package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	monitoringInstanceRetryRate = 60 // seconds
	waitForMonitoringInstance = 15
	taskInfoRetryRate = 1  // seconds
	refreshRate       = 15 // seconds
	secondsBinSize    = 60 // seconds
	imAliveRate       = 15 // seconds
	containerTag      = "gifmachine"
	port              = "8080"
)

var (
	taskEndpoint = os.Getenv("ECS_CONTAINER_METADATA_URI_V4") + "/task"
	containerEndpoint = os.Getenv("ECS_CONTAINER_METADATA_URI_V4") + "/task/stats"
	cpuGauge          = prometheus.NewGauge(prometheus.GaugeOpts{Namespace: "cSidecar", Name: "CPUUtilization", Help: "Container CPU usage"})
	memGauge          = prometheus.NewGauge(prometheus.GaugeOpts{Namespace: "cSidecar", Name: "MemoryUtilization", Help: "Container Memory usage"})
	rxGauge           = prometheus.NewGauge(prometheus.GaugeOpts{Namespace: "cSidecar", Name: "RxTraffic", Help: "Rx traffic"})
	txGauge           = prometheus.NewGauge(prometheus.GaugeOpts{Namespace: "cSidecar", Name: "TxTraffic", Help: "Tx traffic"})
)

// TaskMetadata Structure to unmarshal task metadata endpoint response
type TaskMetadata struct {
	Cluster       string
	TaskARN       string
	Family        string
	Revision      string
	PullStartedAt string
	Limits        struct {
		CPU float64
	}
	Containers []struct {
		DockerID string `json:"DockerId"`
		Networks []struct {
			NetworkMode   string
			IPv4Addresses []string
		}
	}
}

// // TaskInfo Structure to store task information
type TaskInfo struct {
	Cluster     string
	Function    string
	GitBranch   string
	TaskID      string
	LocalIP     string
	PublicIP    string
	DateCreated string
	CPULimit    float64
}

// ContainerStats Structure to store container stats
type ContainerStats struct {
	CPUUtilization    []float64
	MemoryUtilization []float64
	RxTraffic         float64
	TxTraffic         float64
}

func endpointResponse(client *http.Client, endpoint string, respType string) ([]byte, error) {
	resp, err := client.Get(endpoint)
	if err != nil {
		return nil, fmt.Errorf("[%s] unable to get response: %v", respType, err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("[%s] incorrect status code  %d", respType, resp.StatusCode)
	}
	if resp.Body != nil {
		defer resp.Body.Close()
	}
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("[%s] unable to read response body: %v", respType, err)
	}
	return body, nil
}

func getCDepotURL(environment string, company string, awsRegion string) string{
	var awsSession, _ = session.NewSession(&aws.Config{Region: aws.String(awsRegion)})
	var ec2Client = ec2.New(awsSession)

	
	for {
		params := &ec2.DescribeInstancesInput{
			Filters: []*ec2.Filter{
				{
					Name:   aws.String("tag:Name"),
					Values: []*string{aws.String(environment+"-"+company+"-monitoring-instance")},
				},
			},
		}
		ec2Result, _ := ec2Client.DescribeInstances(params)
		if len(ec2Result.Reservations) > 0 {
			fmt.Printf("Found monitoring instance. Giving it %v secs to breath...\n", waitForMonitoringInstance)
			// fmt.Println("Found monitoring instance. Giving it " + str(waitForMonitoringInstance) + "s to breath...")
			time.Sleep(waitForMonitoringInstance * time.Second)
			return  *ec2Result.Reservations[0].Instances[0].NetworkInterfaces[0].PrivateIpAddress
		}
		fmt.Println("Waiting for monitoring instance...")
		time.Sleep(monitoringInstanceRetryRate * time.Second)
	}
}

func getTaskInfo(client *http.Client, taskEndpoint string) (taskInfo TaskInfo) {
	taskMetadata := TaskMetadata{}
	hasTaskInfo := false

	for !hasTaskInfo {
		taskMetadataResponse, err := endpointResponse(client, taskEndpoint, "task")
		if err != nil {
			fmt.Printf("[ERROR] Task endpoint response: %v\n", err)
		} else {
			err := json.Unmarshal(taskMetadataResponse, &taskMetadata)
			if err != nil {
				fmt.Printf("[ERROR] Cannot unmarshal: %s\n", err)
			} else {
				cluster := strings.Split(taskMetadata.Cluster, "/")
				taskInfo.Cluster = cluster[len(cluster)-1]

				taskARN := strings.Split(taskMetadata.TaskARN, "/")
				taskInfo.TaskID = taskARN[len(taskARN)-1]

				taskInfo.LocalIP = taskMetadata.Containers[0].Networks[0].IPv4Addresses[0]

				t, _ := time.Parse(time.RFC3339Nano, taskMetadata.PullStartedAt)
				taskInfo.DateCreated = t.Format("2006-01-02")

				taskInfo.CPULimit = taskMetadata.Limits.CPU

				hasTaskInfo = true
			}
		}
		time.Sleep(taskInfoRetryRate * time.Second)
	}
	return
}

func getContainerStats(client *http.Client, taskInfo TaskInfo, containerStats ContainerStats) ContainerStats {
	var m map[string]interface{}

	containerMetada, err := endpointResponse(client, containerEndpoint, "container")
	if err != nil {
		fmt.Printf("[ERROR] Container endpoint response: %s\n", err)
		cpuGauge.Set(0.0)
		memGauge.Set(0.0)
		rxGauge.Set(0.0)
		txGauge.Set(0.0)
	} else {
		err := json.Unmarshal(containerMetada, &m)
		if err != nil {
			fmt.Printf("[ERROR] Cannot unmarshal: %s\n", err)
		} else {
			for _, value := range m {
				if value != nil {
					if value.(map[string]interface{})["name"] != nil {
						containerName := value.(map[string]interface{})["name"].(string)
						if strings.Contains(containerName, containerTag) {
							// Calculating CPU utilization
							cpuPercent, err := calculateCPUPercent(value, 1/taskInfo.CPULimit)
							if err == nil {
								containerStats.CPUUtilization = append(containerStats.CPUUtilization, cpuPercent)
							}
							// Calculating Memory utilization
							memPercent, err := calculateMemPercent(value)
							if err == nil {
								containerStats.MemoryUtilization = append(containerStats.MemoryUtilization, memPercent)
							}
							// Get RX/TX traffic
							containerStats.RxTraffic = getInterfaceValue(value.(map[string]interface{})["networks"].(map[string]interface{})["eth0"].(map[string]interface{})["rx_bytes"])
							containerStats.TxTraffic = getInterfaceValue(value.(map[string]interface{})["networks"].(map[string]interface{})["eth0"].(map[string]interface{})["tx_bytes"])
						}
					}
				}
			}
		}
	}
	return containerStats
}

func calculateCPUPercent(value interface{}, CPUMultiplicationFactor float64) (cpuPercent float64, err error) {
	preSystemCPUUsage := getInterfaceValue(value.(map[string]interface{})["precpu_stats"].(map[string]interface{})["system_cpu_usage"])
	preTotalUsage := getInterfaceValue(value.(map[string]interface{})["precpu_stats"].(map[string]interface{})["cpu_usage"].(map[string]interface{})["total_usage"])
	systemCPUUsage := getInterfaceValue(value.(map[string]interface{})["cpu_stats"].(map[string]interface{})["system_cpu_usage"])
	totalUsage := getInterfaceValue(value.(map[string]interface{})["cpu_stats"].(map[string]interface{})["cpu_usage"].(map[string]interface{})["total_usage"])
	numCores := getInterfaceValue(value.(map[string]interface{})["cpu_stats"].(map[string]interface{})["online_cpus"])
	if preSystemCPUUsage > 0.0 && preTotalUsage > 0.0 && systemCPUUsage > 0.0 && totalUsage > 0.0 && numCores > 0.0 {
		cpuDelta := totalUsage - preTotalUsage
		systemDelta := systemCPUUsage - preSystemCPUUsage
		cpuPercent = (cpuDelta / systemDelta) * numCores * CPUMultiplicationFactor * 100.0
		return cpuPercent, nil
	}
	return 0.0, fmt.Errorf("[ERROR] Invalid cpu container values")
}

func calculateMemPercent(value interface{}) (memPercent float64, err error) {
	memUsage := getInterfaceValue(value.(map[string]interface{})["memory_stats"].(map[string]interface{})["usage"])
	memLimit := getInterfaceValue(value.(map[string]interface{})["memory_stats"].(map[string]interface{})["limit"])
	if memUsage > 0.0 && memLimit > 0.0 {
		memPercent := (memUsage / memLimit) * 100.0
		return memPercent, nil
	}
	return 0.0, fmt.Errorf("[ERROR] Invalid memory container values")
}

func getInterfaceValue(val interface{}) float64 {
	if val == nil {
		return 0.0
	}
	return val.(float64)
}

func calculateAverage(values []float64) float64 {
	if len(values) > 0 {
		sum := 0.0
		for _, value := range values {
			sum = sum + value
		}
		return sum / float64(len(values))
	}
	return 0.0
}

func main() {
	// Defining vars
	fmt.Println("Getting cDepot URL...")
	environment := os.Getenv("ENVIRONMENT")
	company := os.Getenv("COMPANY")
	awsRegion := os.Getenv("AWS_REGION")
	cDepotURL := "http://"+getCDepotURL(environment, company, awsRegion)+":8002/alive"
	fmt.Println("cDepotURL: " + cDepotURL)
	containerStats := ContainerStats{CPUUtilization: []float64{}, MemoryUtilization: []float64{}}
	savedTime := time.Now()

	// Setup HTTP client (for requests)
	client := &http.Client{
		Timeout: 1 * time.Second,
	}

	// Setup Prometheus metrics
	prometheus.MustRegister(cpuGauge)
	prometheus.MustRegister(memGauge)
	prometheus.MustRegister(rxGauge)
	prometheus.MustRegister(txGauge)

	// Fetching task information
	fmt.Println("Reading task information from metadada endpoint...")
	taskInfo := getTaskInfo(client, taskEndpoint)
	fmt.Println("Task info:", taskInfo)

	// Setup HTTP POST request (for alive pings)
	var imAliveJSON = []byte(`{"cluster":"` + taskInfo.Cluster + `","function":"` + taskInfo.Function + `","gitBranch":"` + taskInfo.GitBranch + `","taskID":"` + taskInfo.TaskID + `","localIP":"` + taskInfo.LocalIP + `:` + port + `","publicIP":"` + taskInfo.PublicIP + `:` + port + `"}`)

	// Refresh container data
	go func(client *http.Client, taskInfo TaskInfo, containerStats ContainerStats) {
		for {
			// Get container data from Fargate endpoint
			containerStats = getContainerStats(client, taskInfo, containerStats)
			// Calculating average per X seconds
			if time.Now().Sub(savedTime).Seconds() > secondsBinSize {
				cpuGauge.Set(calculateAverage(containerStats.CPUUtilization))
				memGauge.Set(calculateAverage(containerStats.MemoryUtilization))
				rxGauge.Set(containerStats.RxTraffic)
				txGauge.Set(containerStats.TxTraffic)
				containerStats.CPUUtilization = nil
				containerStats.MemoryUtilization = nil
				containerStats.RxTraffic = 0
				containerStats.TxTraffic = 0
				savedTime = time.Now()
			}
			time.Sleep(refreshRate * time.Second)
		}
	}(client, taskInfo, containerStats)

	// "I am alive" ping do cDepot
	go func(imAliveJSON []byte) {
		for {
			http.Post(cDepotURL, "application/json", bytes.NewBuffer(imAliveJSON))
			fmt.Println("> heartbeat to "+cDepotURL)
			time.Sleep(imAliveRate * time.Second)
		}
	}(imAliveJSON)

	// Serving endpoints
	fmt.Printf("Listening on port %s\n", port)
	http.Handle("/metrics", promhttp.Handler())
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

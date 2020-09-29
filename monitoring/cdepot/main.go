package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"sync"
	"time"
)

const (
	aliveTimeout              = 30 //seconds
	containerListRefreshRate  = 15 //seconds
	prometheusTargetsFileName = "targets.json"
)

// Container structure
type Container struct {
	Cluster       string    `json:"cluster"`
	Function      string    `json:"function"`
	TaskID        string    `json:"taskID"`
	LocalIP       string    `json:"localIP"`
	PublicIP      string    `json:"publicIP"`
	GitBranch     string    `json:"gitBranch"`
	LastHeartbeat time.Time `json:"lastHeartBeat"`
}

// PrometheusTarget structure
type PrometheusTarget struct {
	Label   PrometheusLabel `json:"labels"`
	Targets []string        `json:"targets"`
}

// PrometheusLabel structure
type PrometheusLabel struct {
	Cluster   string `json:"cluster"`
	Function  string `json:"function"`
	TaskID    string `json:"taskID"`
	GitBranch string `json:"gitBranch"`
}

func convertContainerListToPrometheusTargetList(containerList map[string]Container) string {
	var prometheusTargetList []PrometheusTarget
	var targetIP string
	if len(containerList) > 0 {
		for _, value := range containerList {
			targetIP = value.LocalIP
			prometheusTarget := PrometheusTarget{
				Label: PrometheusLabel{
					Cluster:   value.Cluster,
					Function:  value.Function,
					TaskID:    value.TaskID,
					GitBranch: value.GitBranch,
				},
				Targets: []string{targetIP},
			}
			prometheusTargetList = append(prometheusTargetList, prometheusTarget)
		}
		jsonString, err := json.Marshal(prometheusTargetList)
		if err != nil {
			log.Println(err)
		} else {
			return string(jsonString)
		}
	}
	return "[]"
}

func updatePrometheusTargetsFile(prometheusTargetListJSON string) {
	f, err := os.Create(prometheusTargetsFileName)
	if err != nil {
		fmt.Println("[ERROR] Unable to create/overwrite file:", err)
		f.Close()
	} else {
		_, err = f.WriteString(prometheusTargetListJSON)
		if err != nil {
			fmt.Println("[ERROR] Unable to write file:", err)
		}
	}
}

func main() {
	containerList := make(map[string]Container)
	var mutex = &sync.Mutex{}

	log.Println("cDepot started...")

	go func(containerList map[string]Container) {
		for {
			mutex.Lock()
			for key, value := range containerList {
				if time.Now().Sub(value.LastHeartbeat).Seconds() > aliveTimeout {
					log.Printf("[REMOVE] %s", key)
					delete(containerList, key)
				}
			}
			prometheusTargetListJSON := convertContainerListToPrometheusTargetList(containerList)
			mutex.Unlock()
			updatePrometheusTargetsFile(prometheusTargetListJSON)
			time.Sleep(containerListRefreshRate * time.Second)
		}
	}(containerList)

	http.HandleFunc("/alive", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "POST" {
			var container Container
			reqBody, err := ioutil.ReadAll(r.Body)
			if err != nil {
				panic(err)
			}
			if err := json.Unmarshal(reqBody, &container); err != nil {
				panic(err)
			}
			container.LastHeartbeat = time.Now()
			mutex.Lock()
			containerList[container.LocalIP] = container
			mutex.Unlock()
			fmt.Println(container)
		}
	})
	log.Fatal(http.ListenAndServe(":8002", nil))
}

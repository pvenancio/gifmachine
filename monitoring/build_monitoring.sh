#!/bin/bash

export ENVIRONMENT=$1
export COMPANY=$2
export AWS_REGION=$3

echo "Installing needed software..."
sudo amazon-linux-extras install -y docker
sudo service docker start
sudo yum update -y
sudo yum install -y golang git python3 python3-pip
sudo pip3 install requests
sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

echo "Fetching Golang dependencies..."
go get -v github.com/aws/aws-sdk-go
go get -v github.com/prometheus/client_golang/prometheus
go get -v github.com/prometheus/client_golang/prometheus/promhttp

echo "Fetching monitoring tools source code from S3 bucket..."
aws s3 cp s3://$ENVIRONMENT-$COMPANY-monitoring-source/tools_src.zip . --region $AWS_REGION
unzip -o tools_src.zip

echo "Building cDepot..."
GOOS=linux GOARCH=386 go build -o monitoring/cdepot/cdepot ./monitoring/cdepot/main.go
sudo docker build -t cdepot -f monitoring/cdepot/Dockerfile ./monitoring

printf "Lauching Docker Compose containing\n  - Prometheus\n  - Grafana\n  - cDepot\n"
sudo docker-compose -f monitoring/docker-compose.yml up -d

MONITORING_PUBLIC_IP=`aws ec2 describe-instances \
	--filters Name=tag:Name,Values=$ENVIRONMENT-$COMPANY-monitoring-instance Name=instance-state-name,Values=running \
	--query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region $AWS_REGION`
python3 monitoring/grafana/set_up_grafana.py "http://${MONITORING_PUBLIC_IP}:3000"
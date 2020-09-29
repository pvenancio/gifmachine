#!/bin/bash

export ENVIRONMENT=$1
export COMPANY=$2
export AWS_REGION=$3

echo "Fetching Golang dependencies..."
go get -v github.com/aws/aws-sdk-go
go get -v github.com/prometheus/client_golang/prometheus
go get -v github.com/prometheus/client_golang/prometheus/promhttp

echo "Fetching cSidecar source code from S3 bucket..."
mkdir csidecar
aws s3 cp s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/csidecar/Dockerfile ./csidecar/ --region $AWS_REGION
aws s3 cp s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/csidecar/main.go ./csidecar/ --region $AWS_REGION

echo "Building cSidecar..."
GOOS=linux GOARCH=386 go build -o csidecar/csidecar ./csidecar/main.go
sudo docker build -t csidecar -f csidecar/Dockerfile ./csidecar

echo 'Getting repository URI...'
ECR_REPOSITORY_URI=`aws ecr describe-repositories --region $AWS_REGION --repository-names $ENVIRONMENT-$COMPANY-gifmachine --query 'repositories[0].repositoryUri' --output text`
echo 'Logging into AWS ECR...'
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region $AWS_REGION | sudo docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
echo "Tagging and pushing cSidecar docker image to AWS ECR \"$ENVIRONMENT-$COMPANY-gifmachine\" repository..."
sudo docker tag csidecar $ECR_REPOSITORY_URI:csidecar
sudo docker push $ECR_REPOSITORY_URI:csidecar
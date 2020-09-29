#!/bin/bash

export ENVIRONMENT=$1
export COMPANY=$2
export AWS_REGION=$3

git clone https://github.com/salsify/gifmachine.git

echo "Fetching docker build code from S3 bucket..."
mkdir docker
aws s3 cp s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/docker/Dockerfile ./docker/ --region $AWS_REGION
aws s3 cp s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/docker/build_up.sh ./docker/ --region $AWS_REGION
aws s3 cp s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/docker/start_up.sh ./docker/ --region $AWS_REGION

DOCKER_BUILD_ROLE_ARN=`aws iam get-role --region $AWS_REGION --role-name $ENVIRONMENT-$COMPANY-all-docker-build-role --query 'Role.Arn' --output text`
DOCKER_BUILD_ROLE_KEYS=`aws sts assume-role --region $AWS_REGION --role-arn $DOCKER_BUILD_ROLE_ARN --role-session-name buildImage --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text`
DOCKER_BUILD_ROLE_ACCESS_KEY=$(echo $DOCKER_BUILD_ROLE_KEYS | awk '{print $1}')
DOCKER_BUILD_ROLE_SECRET_ACCESS_KEY=$(echo $DOCKER_BUILD_ROLE_KEYS | awk '{print $2}')
DOCKER_BUILD_ROLE_SESSION_TOKEN=$(echo $DOCKER_BUILD_ROLE_KEYS | awk '{print $3}')

echo "Building gifmachine image..."
sudo docker build -t gifmachine -f docker/Dockerfile \
	--build-arg AWS_DEFAULT_REGION=$AWS_REGION \
	--build-arg AWS_ACCESS_KEY_ID=$DOCKER_BUILD_ROLE_ACCESS_KEY \
	--build-arg AWS_SECRET_ACCESS_KEY=$DOCKER_BUILD_ROLE_SECRET_ACCESS_KEY \
	--build-arg AWS_SESSION_TOKEN=$DOCKER_BUILD_ROLE_SESSION_TOKEN \
	--build-arg ENVIRONMENT=$ENVIRONMENT \
	--build-arg COMPANY=$COMPANY .

echo 'Getting repository URI...'
ECR_REPOSITORY_URI=`aws ecr describe-repositories --region $AWS_REGION --repository-names $ENVIRONMENT-$COMPANY-gifmachine --query 'repositories[0].repositoryUri' --output text`
echo 'Logging into AWS ECR...'
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region $AWS_REGION | sudo docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
echo "Tagging and pushing docker image to AWS ECR \"$ENVIRONMENT-$COMPANY-gifmachine\" repository..."
sudo docker tag gifmachine $ECR_REPOSITORY_URI:gifmachine
sudo docker push $ECR_REPOSITORY_URI:gifmachine

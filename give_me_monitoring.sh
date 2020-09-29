#!/bin/bash

source config/aws-config.txt
export $(cut -d= -f1 config/aws-config.txt)

function banner(){
	echo "+------------------------------------------+"
  	printf "| %-40s |\n" "$1"
  	echo "+------------------------------------------+"
}

banner "MONITORING"

echo "Checking AWS configuration values..."
python3 scripts/check_aws_config_validity.py config/aws-config.txt
if [ $? -ne 0 ]; then
     exit
fi

echo "Checking AWS resources availability for monitoring..."
python3 scripts/check_resources_availability.py 'monitoring'
if [ $? -ne 0 ]; then
     exit
fi

echo "Checking if dependent AWS stacks already exist..."
aws cloudformation describe-stacks --stack-name $ENVIRONMENT-$COMPANY-gifmachine-cf &> /dev/null
if [ $? -ne 0 ]; then
     echo "ERROR: Needed stack '${ENVIRONMENT}-${COMPANY}-gifmachine-cf' does not exist. Please build it first."
     exit
else
	echo "SUCCESS: Needed stack '${ENVIRONMENT}-${COMPANY}-gifmachine-cf' exists!"
fi

printf "Starting creating infrastructure...\n"

# MONITORING
# Comments: Creating montiroing stack via AWS Cloudformation, including
#			grafana, prometheus, and home-made sidecar ecosystem for
# 			monitoring ECS containers.
echo "Creating SSH key for monitoring..."
aws ec2 create-key-pair --key-name $ENVIRONMENT-$COMPANY-monitoring-key --query KeyMaterial --output text --region $AWS_REGION > keys/$ENVIRONMENT-$COMPANY-monitoring-key.pem
chmod 600 keys/$ENVIRONMENT-$COMPANY-monitoring-key.pem
echo "Creating AWS Cloudformation stack... [ETA: `python3 scripts/get_eta.py 4`]"
aws cloudformation create-stack --stack-name $ENVIRONMENT-$COMPANY-monitoring-cf --template-body file://infrastructure/monitoring-cf.yaml --capabilities CAPABILITY_NAMED_IAM \
	--parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT ParameterKey=Company,ParameterValue=$COMPANY --region $AWS_REGION > /dev/null
aws cloudformation wait stack-create-complete --stack-name $ENVIRONMENT-$COMPANY-monitoring-cf
echo "Creating S3 bucket to save monitoring tools source code..."
aws s3api create-bucket --bucket $ENVIRONMENT-$COMPANY-monitoring-source --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION > /dev/null
echo "Zipping and copying monitoring tools source code to S3 bucket..."
zip monitoring/tools_src.zip ./monitoring/cdepot/* ./monitoring/csidecar/* ./monitoring/prometheus/* ./monitoring/grafana/* ./monitoring/docker-compose.yml
aws s3 cp monitoring/tools_src.zip s3://$ENVIRONMENT-$COMPANY-monitoring-source/tools_src.zip --region $AWS_REGION
aws s3 cp monitoring/build_monitoring.sh s3://$ENVIRONMENT-$COMPANY-monitoring-source/build_monitoring.sh --region $AWS_REGION
echo "Waiting 60 secs for monitoring-instance to boot..."
sleep 60
echo "Starting monitoring build in monitoring instance..."
MONITORING_PUBLIC_IP=`aws ec2 describe-instances \
	--filters Name=tag:Name,Values=$ENVIRONMENT-$COMPANY-monitoring-instance Name=instance-state-name,Values=running \
	--query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region $AWS_REGION`
ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i keys/$ENVIRONMENT-$COMPANY-monitoring-key.pem ec2-user@$MONITORING_PUBLIC_IP " \
	export ENVIRONMENT=${ENVIRONMENT}; \
	export COMPANY=${COMPANY}; \
  	export AWS_REGION=${AWS_REGION}; \
  	aws s3 cp s3://$ENVIRONMENT-$COMPANY-monitoring-source/build_monitoring.sh . --region $AWS_REGION; \
	sh build_monitoring.sh $ENVIRONMENT $COMPANY $AWS_REGION"


#!/bin/bash

source config/aws-config.txt
export $(cut -d= -f1 config/aws-config.txt)

function banner(){
	echo "+------------------------------------------+"
  	printf "| %-40s |\n" "$1"
  	echo "+------------------------------------------+"
}

banner "GIFMACHINE"

echo "Checking AWS configuration values..."
python3 scripts/check_aws_config_validity.py config/aws-config.txt
if [ $? -ne 0 ]; then
     exit
fi

echo "Checking AWS resources availability for monitoring..."
python3 scripts/check_resources_availability.py 'gifmachine'
if [ $? -ne 0 ]; then
     exit
fi

# PHASE1: USER INPUT
# Comments: DB and GifMachine authentication credentials are provided 
#           by the user at stack creation.
echo "Please create credentials for database 'gifmachine':"
read -p "> Username (letters only): " DB_USERNAME
while [[ ! $DB_USERNAME =~ ^[A-Za-z] ]]; do
    read -p "Invalid username, try again! `echo $'\n> Username (letters only): '`" DB_USERNAME
done
read -sp "> Password (alphanumeric only, 8 characters minimum): " DB_PASSWORD
while [[ ! $DB_PASSWORD =~ ^[0-9A-Za-z]{8} ]]; do
    read -p "Invalid password, try again: `echo $'\n> Password (alphanumeric only, 8 characters minimum): '`" DB_PASSWORD
done
printf "\n\n"
echo "Please create password for gifmachine API endpoint:"
read -sp "> Password (alphanumeric only): " API_PASSWORD
while [[ ! $API_PASSWORD =~ ^[0-9A-Za-z] ]]; do
    read -p "Invalid password, try again: `echo $'\n> Password (alphanumeric only): '`" API_PASSWORD
done
printf "\n\n"
echo "Creating secrets in AWS Secret Manager..."
aws secretsmanager create-secret --name $ENVIRONMENT-$COMPANY-DB_USERNAME --secret-string $DB_USERNAME --region $AWS_REGION > /dev/null
aws secretsmanager create-secret --name $ENVIRONMENT-$COMPANY-DB_PASSWORD --secret-string $DB_PASSWORD --region $AWS_REGION > /dev/null
aws secretsmanager create-secret --name $ENVIRONMENT-$COMPANY-API_PASSWORD --secret-string $API_PASSWORD --region $AWS_REGION > /dev/null
printf "Access credentials stored. \n
# >>> No user interaction needed anymore! <<<\n
# Starting creating infrastructure...\n"

# PHASE2: VPC, JUMPBOX, and NAT INSTANCE
# Comments: Creating VPC stack via AWS Cloudformation, that includes
#           also the creation of a jumpbox instance to be used as 
#			an entry point to the VPC from the exterior.
echo "Creating folder 'keys' for storing SSH keys locally..."
mkdir keys

echo "Creating private bucket '${ENVIRONMENT}-${COMPANY}-keys' for storing SSH keys in the cloud..."
aws s3api create-bucket --bucket $ENVIRONMENT-$COMPANY-keys --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION > /dev/null

echo "Creating SSH keys for jumpbox and NAT instance..."
aws ec2 create-key-pair --key-name $ENVIRONMENT-$COMPANY-jumpbox-key --query KeyMaterial --output text --region $AWS_REGION > keys/$ENVIRONMENT-$COMPANY-jumpbox-key.pem
aws ec2 create-key-pair --key-name $ENVIRONMENT-$COMPANY-natinstance-key --query KeyMaterial --output text --region $AWS_REGION > keys/$ENVIRONMENT-$COMPANY-natinstance-key.pem
chmod 600 keys/$ENVIRONMENT-$COMPANY-jumpbox-key.pem
chmod 600 keys/$ENVIRONMENT-$COMPANY-natinstance-key.pem

echo "Uploading SSH keys to private bucket..."
aws s3 cp keys/$ENVIRONMENT-$COMPANY-jumpbox-key.pem s3://$ENVIRONMENT-$COMPANY-keys/$ENVIRONMENT-$COMPANY-jumpbox-key.pem
aws s3 cp keys/$ENVIRONMENT-$COMPANY-natinstance-key.pem s3://$ENVIRONMENT-$COMPANY-keys/$ENVIRONMENT-$COMPANY-natinstance-key.pem

echo "Creating AWS Cloudformation stack ${ENVIRONMENT}-${COMPANY}-all-cf... [ETA: `python3 scripts/get_eta.py 4`]"
aws cloudformation create-stack --stack-name $ENVIRONMENT-$COMPANY-all-cf --template-body file://infrastructure/all-cf.yaml --capabilities CAPABILITY_NAMED_IAM \
	--parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT ParameterKey=Company,ParameterValue=$COMPANY --region $AWS_REGION > /dev/null
aws cloudformation wait stack-create-complete --stack-name $ENVIRONMENT-$COMPANY-all-cf
echo "AWS Cloudformation stack ${ENVIRONMENT}-${COMPANY}-all-cf created!"

# PHASE3: DATABASE
# Comments: Creating DB stack via AWS Cloudformation, including
#			booting up Postgres within instance,
echo "Creating SSH key for database instance..."
aws ec2 create-key-pair --key-name $ENVIRONMENT-$COMPANY-dbinstance-key --query KeyMaterial --output text --region $AWS_REGION > keys/$ENVIRONMENT-$COMPANY-dbinstance-key.pem
chmod 600 keys/$ENVIRONMENT-$COMPANY-dbinstance-key.pem

echo "Uploading SSH key to private bucket..."
aws s3 cp keys/$ENVIRONMENT-$COMPANY-dbinstance-key.pem s3://$ENVIRONMENT-$COMPANY-keys/$ENVIRONMENT-$COMPANY-dbinstance-key.pem

echo "Creating AWS Cloudformation stack ${ENVIRONMENT}-${COMPANY}-db-cf... [ETA: `python3 scripts/get_eta.py 4`]"
aws cloudformation create-stack --stack-name $ENVIRONMENT-$COMPANY-db-cf --template-body file://infrastructure/db-cf.yaml --capabilities CAPABILITY_NAMED_IAM \
	--parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT ParameterKey=Company,ParameterValue=$COMPANY \
				 ParameterKey=DBUsername,ParameterValue=$DB_USERNAME ParameterKey=DBPassword,ParameterValue=$DB_PASSWORD \
	--region $AWS_REGION > /dev/null
aws cloudformation wait stack-create-complete --stack-name $ENVIRONMENT-$COMPANY-db-cf
echo "AWS Cloudformation stack ${ENVIRONMENT}-${COMPANY}-db-cf created!"

# PHASE4: GIFMACHINE
# Comments: Creating Gifmachine stack via AWS Cloudformation, including
#			building docker image, registering task definition
#			and launching the service.
echo "Creating SSH key for containers..."
aws ec2 create-key-pair --key-name $ENVIRONMENT-$COMPANY-container-key --query KeyMaterial --output text --region $AWS_REGION > keys/$ENVIRONMENT-$COMPANY-container-key.pem
chmod 600 keys/$ENVIRONMENT-$COMPANY-container-key.pem

echo "Uploading SSH key to private bucket..."
aws s3 cp keys/$ENVIRONMENT-$COMPANY-container-key.pem s3://$ENVIRONMENT-$COMPANY-keys/$ENVIRONMENT-$COMPANY-container-key.pem

echo "Creating ECR repository..."
aws ecr create-repository --repository-name $ENVIRONMENT-$COMPANY-gifmachine --region $AWS_REGION > /dev/null

echo "Creating S3 bucket to save gifmachine deploy configurations..."
aws s3api create-bucket --bucket $ENVIRONMENT-$COMPANY-gifmachine-deploy-configs --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION > /dev/null
aws s3api put-bucket-versioning --bucket $ENVIRONMENT-$COMPANY-gifmachine-deploy-configs --versioning-configuration Status=Enabled

echo "Sending gifmachine configurations and deployment files to S3 bucket..."
aws s3 cp config/gifmachine-config.txt s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/gifmachine-config.txt --region $AWS_REGION
aws s3 cp docker/build_image.sh s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/docker/build_image.sh --region $AWS_REGION
aws s3 cp docker/Dockerfile s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/docker/Dockerfile --region $AWS_REGION
aws s3 cp docker/build_up.sh s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/docker/build_up.sh --region $AWS_REGION
aws s3 cp docker/start_up.sh s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/docker/start_up.sh --region $AWS_REGION

echo "Starting gifmachine image build in Jumpbox..."
JUMPBOX_PUBLIC_IP=`aws ec2 describe-instances \
	--filters Name=tag:Name,Values=$ENVIRONMENT-$COMPANY-all-jumpbox Name=instance-state-name,Values=running \
	--query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region $AWS_REGION`
ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i keys/$ENVIRONMENT-$COMPANY-jumpbox-key.pem ec2-user@$JUMPBOX_PUBLIC_IP " \
	export ENVIRONMENT=${ENVIRONMENT}; \
	export COMPANY=${COMPANY}; \
	export AWS_REGION=${AWS_REGION}; \
	aws s3 cp s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/docker/build_image.sh . --region $AWS_REGION; \
	sh build_image.sh $ENVIRONMENT $COMPANY $AWS_REGION"

echo "Sending cSidecar deployment files to S3 bucket..."
aws s3 cp monitoring/csidecar/Dockerfile s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/csidecar/Dockerfile --region $AWS_REGION
aws s3 cp monitoring/csidecar/main.go s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/csidecar/main.go --region $AWS_REGION
aws s3 cp monitoring/build_csidecar.sh s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/csidecar/build_csidecar.sh --region $AWS_REGION

echo "Starting cSidecar image build in Jumpbox..."
ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i keys/$ENVIRONMENT-$COMPANY-jumpbox-key.pem ec2-user@$JUMPBOX_PUBLIC_IP " \
	export ENVIRONMENT=${ENVIRONMENT}; \
	export COMPANY=${COMPANY}; \
	export AWS_REGION=${AWS_REGION}; \
	aws s3 cp s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/csidecar/build_csidecar.sh . --region $AWS_REGION; \
	sh build_csidecar.sh $ENVIRONMENT $COMPANY $AWS_REGION"

echo "Creating AWS Cloudformation stack ${ENVIRONMENT}-${COMPANY}-gifmachine-cf... [ETA: `python3 scripts/get_eta.py 10`]"
ECR_REPOSITORY_URI=`aws ecr describe-repositories --region $AWS_REGION --repository-names $ENVIRONMENT-$COMPANY-gifmachine --query 'repositories[0].repositoryUri' --output text`
aws cloudformation create-stack --stack-name $ENVIRONMENT-$COMPANY-gifmachine-cf --template-body file://infrastructure/gifmachine-cf.yaml --capabilities CAPABILITY_NAMED_IAM \
	--parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
				 ParameterKey=Company,ParameterValue=$COMPANY \
				 ParameterKey=ContainerImage,ParameterValue=$ECR_REPOSITORY_URI:gifmachine \
				 ParameterKey=cSidecarImage,ParameterValue=$ECR_REPOSITORY_URI:csidecar \
	--region $AWS_REGION > /dev/null
aws cloudformation wait stack-create-complete --stack-name $ENVIRONMENT-$COMPANY-gifmachine-cf
echo "AWS Cloudformation stack ${ENVIRONMENT}-${COMPANY}-gifmachine-cf created!"

LB_URL=`aws elbv2 describe-load-balancers --names $ENVIRONMENT-$COMPANY-gifmachine-lb --query 'LoadBalancers[0].DNSName' --output text`
python3 scripts/test_gifmachine.py "http://${LB_URL}"
echo "GIFMACHINE URL: http://${LB_URL}"


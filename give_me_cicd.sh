#!/bin/bash

source config/aws-config.txt
export $(cut -d= -f1 config/aws-config.txt)

function banner(){
	echo "+------------------------------------------+"
  	printf "| %-40s |\n" "$1"
  	echo "+------------------------------------------+"
}

banner "CICD"

echo "Checking AWS configuration values..."
python3 scripts/check_aws_config_validity.py config/aws-config.txt
if [ $? -ne 0 ]; then
     exit
fi

echo "Checking AWS resources availability for monitoring..."
python3 scripts/check_resources_availability.py 'cicd'
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

# CICD
# Comments: Creating CICD stack via AWS Cloudformation, including
#			build and deploy environments.
echo "Creating private bucket '${ENVIRONMENT}-${COMPANY}-gifmachine-pipeline-artifacts' for storing Code Pipeline artifacts..."
aws s3api create-bucket --bucket $ENVIRONMENT-$COMPANY-gifmachine-pipeline-artifacts --create-bucket-configuration LocationConstraint=$AWS_REGION --region $AWS_REGION > /dev/null

echo "Zipping and sending needed AWS Codepipeline sources files to S3 bucket..."
zip -j cicd/build_src.zip ./cicd/buildspec.yml ./cicd/update_taskdef_template.py ./cicd/appspec.yaml
aws s3 cp cicd/build_src.zip s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/build_src.zip --region $AWS_REGION
aws s3 cp templates/taskdefinition-template.json s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/taskdefinition-template.json --region $AWS_REGION

echo "Creating AWS Cloudformation stack... [ETA: `python3 scripts/get_eta.py 1`]"
aws cloudformation create-stack --stack-name $ENVIRONMENT-$COMPANY-cicd-cf --template-body file://infrastructure/cicd-cf.yaml --capabilities CAPABILITY_NAMED_IAM \
	--parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT ParameterKey=Company,ParameterValue=$COMPANY --region $AWS_REGION > /dev/null
aws cloudformation wait stack-create-complete --stack-name $ENVIRONMENT-$COMPANY-cicd-cf
echo "AWS Cloudformation stack ${ENVIRONMENT}-${COMPANY}-cicd-cf created!"

echo "Creating deployment pipeline..."
python3 cicd/create_pipeline.py $ENVIRONMENT $COMPANY 'gifmachine' $AWS_REGION
echo "CICD pipeline deployed! Deployment starting, go take a look!"
PIPELINE_URL="https://${AWS_REGION}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${ENVIRONMENT}-${COMPANY}-gifmachine-pipeline/view?region=${AWS_REGION}"
echo "PIPELINE URL: ${PIPELINE_URL}"



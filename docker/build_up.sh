#!/bin/bash

apt-get update && apt-get install -y awscli openssh-server vim

aws s3 cp s3://$ENVIRONMENT-$COMPANY-gifmachine-deploy-configs/gifmachine-config.txt .
eval $(cat gifmachine-config.txt | sed 's/^/export /')
rm gifmachine-config.txt

DB_USERNAME=`aws secretsmanager get-secret-value --secret-id $ENVIRONMENT-$COMPANY-DB_USERNAME --query SecretString --output text`
DB_PASSWORD=`aws secretsmanager get-secret-value --secret-id $ENVIRONMENT-$COMPANY-DB_PASSWORD --query SecretString --output text`
DB_ENDPOINT=`aws ec2 describe-instances --region $AWS_DEFAULT_REGION \
	--filters Name=tag:Name,Values=${ENVIRONMENT}-${COMPANY}-db-dbinstance Name=instance-state-name,Values=running \
	--query 'Reservations[0].Instances[0].PrivateIpAddress' --output text`
DATABASE_URL="postgres://${DB_USERNAME}:${DB_PASSWORD}@${DB_ENDPOINT}:5432/gifmachine" 
export DATABASE_URL

GIFMACHINE_PASSWORD=`aws secretsmanager get-secret-value --secret-id $ENVIRONMENT-$COMPANY-API_PASSWORD --query SecretString --output text`
export GIFMACHINE_PASSWORD

gem install bundler #updating to Bundler 2 (required by gifmachine)
echo 'Bundle install...'
bundle install

echo 'Running migrations...'
bundle exec rake db:migrate

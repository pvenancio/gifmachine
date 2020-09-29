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

echo "Preparing and starting ssh..."
aws s3 cp s3://$ENVIRONMENT-$COMPANY-keys/$ENVIRONMENT-$COMPANY-container-key.pem .
chmod 600 $ENVIRONMENT-$COMPANY-container-key.pem
SSH_PUBLIC_KEY=`ssh-keygen -y -f $ENVIRONMENT-$COMPANY-container-key.pem`
mkdir ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo $SSH_PUBLIC_KEY > ~/.ssh/authorized_keys
/etc/init.d/ssh start

echo "Starting gifmachine..."
ruby app.rb

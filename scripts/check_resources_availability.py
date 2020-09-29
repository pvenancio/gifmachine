# CHECK_AWS_RESOURCES_AVAILABILITY
# Functions to evaluate if it is possible to created needed AWS resources,
#  i.e., if resources with same names do not already exist.

import boto3
import sys
from botocore.config import Config

def get_master_aws_config_vars(filename):
	with open(filename, 'r') as configFile:
		for var in configFile:
			if var != '':
				if var.split('=')[0] == 'AWS_REGION': awsRegion = var.split('=')[1].strip()
				if var.split('=')[0] == 'ENVIRONMENT': environment = var.split('=')[1].strip()
				if var.split('=')[0] == 'COMPANY': company = var.split('=')[1].strip()
	return awsRegion, environment, company
				
def check_secret(smClient, secretName):
	try:
		smClient.describe_secret(SecretId=secretName)
		print('  [x] Secret Manager secret "' + secretName + '"')
		return 1
	except:
		print('      Secret Manager secret "' + secretName + '"')
		return 0

def check_key_pair(ec2Client, keyPairName):
	try:
		ec2Client.describe_key_pairs(KeyNames=[keyPairName])
		print('  [x] EC2 key pair "' + keyPairName + '"')
		return 1
	except:
		print('      EC2 key pair "' + keyPairName + '"')
		return 0

def check_stack(cfClient, stackName):
	try:
		cfClient.describe_stacks(StackName=stackName)
		print('  [x] Cloud Formation stack "' + stackName + '"')
		return 1
	except:
		print('      Cloud Formation stack "' + stackName + '"')
		return 0

def check_security_group(ec2Client, sgName):
	try:
		ec2Client.describe_security_groups(Filters=[{'Name': 'group-name','Values': [sgName]}])['SecurityGroups'][0]
		print('  [x] EC2 security group "' + sgName + '"')
		return 1
	except:
		print('      EC2 security group "' + sgName + '"')
		return 0

def check_role(iamClient, roleName):
	try:
		iamClient.get_role(RoleName=roleName)
		print('  [x] IAM role "' + roleName + '"')
		return 1
	except:
		print('      IAM role "' + roleName + '"')
		return 0

def check_instance_profile(iamClient, instanceProfileName):
	try:
		iamClient.get_instance_profile(InstanceProfileName=instanceProfileName)
		print('  [x] IAM instance profile "' + instanceProfileName + '"')
		return 1
	except:
		print('      IAM instance profile "' + instanceProfileName + '"')
		return 0

def check_repository(ecrClient, repositoryName):
	try:
		ecrClient.describe_repositories(repositoryNames=[repositoryName])
		print('  [x] ECR repository "' + repositoryName + '"')
		return 1
	except:
		print('      ECR repository "' + repositoryName + '"')
		return 0

def check_bucket(s3Client, bucketName):
	try:
		s3Client.get_bucket_location(Bucket=bucketName)
		print('  [x] S3 bucket "' + bucketName + '"')
		return 1
	except:
		print('      S3 bucket "' + bucketName + '"')
		return 0

def check_load_balancer(lbv2Client, loadbalancerName):
	try:
		lbv2Client.describe_load_balancers(Names=[loadbalancerName])
		print('  [x] EC2 load balancer "' + loadbalancerName + '"')
		return 1
	except:
		print('      EC2 load balancer "' + loadbalancerName + '"')
		return 0

def check_target_group(lbv2Client, targetGroupName):
	try:
		lbv2Client.describe_target_groups(Names=[targetGroupName])
		print('  [x] EC2 target group "' + targetGroupName + '"')
		return 1
	except:
		print('      EC2 target group "' + targetGroupName + '"')
		return 0

def check_cluster(ecsClient, clusterName):
	clusterList=ecsClient.list_clusters(maxResults=100)
	if len(clusterList['clusterArns']) == 0:
		print('      ECS cluster "' + clusterName + '"')
		return 0
	else:
		for cluster in clusterList['clusterArns']:
			if cluster.split('/')[-1] == clusterName and ecsClient.describe_clusters(clusters=[clusterName])['clusters'][0]['status'] == 'ACTIVE':
				print('  [x] ECS cluster "' + clusterName + '"')
				return 1
	print('      ECS cluster "' + clusterName + '"')
	return 0

def check_service(ecsClient,clusterName, serviceName):
	try:
		serviceList = ecsClient.list_services(cluster=clusterName)
		if len(serviceList['serviceArns']) == 0:
			print('      ECS service "' + serviceName + '"')
			return 0
		else:
			for service in serviceList['serviceArns']:
				if service.split('/')[-1] == serviceName and ecsClient.describe_services(cluster=clusterName,services=[serviceName])['services'][0]['status'] == 'ACTIVE':
					print('  [x] ECS service "' + serviceName + '"')
					return 1
		print('      ECS service "' + serviceName + '"')
		return 0
	except:
		print('      ECS service "' + serviceName + '"')
		return 0

def check_log_group(logsClient, logGroupName):
	try:
		logsClient.describe_log_groups(logGroupNamePrefix=logGroupName)['logGroups'][0]
		print('  [x] CloudWatch log group "' + logGroupName + '"')
		return 1
	except:
		print('      CloudWatch log group "' + logGroupName + '"')
		return 0

def check_codebuild_project(cbClient, cbProjectName):
	try:
		cbClient.batch_get_projects(names=[cbProjectName])['projects'][0]
		print('  [x] CodeBuild project "' + cbProjectName + '"')
		return 1
	except:
		print('      CodeBuild project "' + cbProjectName + '"')
		return 0

def check_codedeploy_application(cdClient, applicationName):
	try:
		cdClient.get_application(applicationName=applicationName)
		print('  [x] CodeDeploy application "' + applicationName + '"')
		return 1
	except:
		print('      CodeDeploy application "' + applicationName + '"')
		return 0

def check_codedeploy_deploymentgroup(cdClient, applicationName, deploymentGroupName):
	try:
		cdClient.batch_get_deployment_groups(applicationName=applicationName, deploymentGroupNames=[deploymentGroupName])
		print('  [x] CodeDeploy deployment group "' + deploymentGroupName + '"')
		return 1
	except:
		print('      CodeDeploy deployment group "' + deploymentGroupName + '"')
		return 0

def check_codepipeline_pipeline(cpClient, pipelineName):
	try:
		cpClient.get_pipeline(name=pipelineName)
		print('  [x] CodePipeline pipeline "' + pipelineName + '"')
		return 1
	except:
		print('      CodePipeline pipeline "' + pipelineName + '"')
		return 0

def resource_validator(section):
	awsRegion, environment, company = get_master_aws_config_vars('config/aws-config.txt')

	clientConfig = Config(region_name = awsRegion)

	smClient = boto3.client('secretsmanager', config=clientConfig)
	ec2Client = boto3.client('ec2', config=clientConfig)
	cfClient = boto3.client('cloudformation', config=clientConfig)
	iamClient = boto3.client('iam', config=clientConfig)
	ecrClient = boto3.client('ecr', config=clientConfig)
	s3Client = boto3.client('s3', config=clientConfig)
	lbv2Client = boto3.client('elbv2', config=clientConfig)
	wafv2Client = boto3.client('wafv2', config=clientConfig)
	ecsClient = boto3.client('ecs', config=clientConfig)
	logsClient = boto3.client('logs', config=clientConfig)
	cbClient = boto3.client('codebuild', config=clientConfig)
	cdClient = boto3.client('codedeploy', config=clientConfig)
	cpClient = boto3.client('codepipeline', config=clientConfig)

	notAvailableResources = 0

	print('Validating AWS resources availability ([x] means NOT available to be created)...')
	if section == 'all' or section == 'gifmachine':
		# #### USER INPUT
		notAvailableResources = notAvailableResources + check_secret(smClient, environment+'-'+company+'-DB_USERNAME')
		notAvailableResources = notAvailableResources + check_secret(smClient, environment+'-'+company+'-DB_PASSWORD')
		notAvailableResources = notAvailableResources + check_secret(smClient, environment+'-'+company+'-API_PASSWORD')

		# #### ALL
		notAvailableResources = notAvailableResources + check_bucket(s3Client, environment+'-'+company+'-keys')
		notAvailableResources = notAvailableResources + check_key_pair(ec2Client, environment+'-'+company+'-jumpbox-key')
		notAvailableResources = notAvailableResources + check_key_pair(ec2Client, environment+'-'+company+'-natinstance-key')
		notAvailableResources = notAvailableResources + check_stack(cfClient, environment+'-'+company+'-all-cf')
		notAvailableResources = notAvailableResources + check_security_group(ec2Client, environment+'-'+company+'-all-jumpbox-sg')
		notAvailableResources = notAvailableResources + check_security_group(ec2Client, environment+'-'+company+'-all-natinstance-sg')
		notAvailableResources = notAvailableResources + check_role(iamClient, environment+'-'+company+'-all-jumpbox-role')
		notAvailableResources = notAvailableResources + check_role(iamClient, environment+'-'+company+'-all-natinstance-role')
		notAvailableResources = notAvailableResources + check_role(iamClient, environment+'-'+company+'-all-docker-build-role')
		notAvailableResources = notAvailableResources + check_instance_profile(iamClient, environment+'-'+company+'-all-jumpbox-iprofile')
		notAvailableResources = notAvailableResources + check_instance_profile(iamClient, environment+'-'+company+'-all-natinstance-iprofile')

		# #### DB
		notAvailableResources = notAvailableResources + check_key_pair(ec2Client, environment+'-'+company+'-dbinstance-key')
		notAvailableResources = notAvailableResources + check_stack(cfClient, environment+'-'+company+'-db-cf')
		notAvailableResources = notAvailableResources + check_security_group(ec2Client, environment+'-'+company+'-db-dbinstance-sg')
		notAvailableResources = notAvailableResources + check_role(iamClient, environment+'-'+company+'-db-dbinstance-role')
		notAvailableResources = notAvailableResources + check_instance_profile(iamClient, environment+'-'+company+'-db-dbinstance-iprofile')

		## GIFMACHINE
		notAvailableResources = notAvailableResources + check_key_pair(ec2Client, environment+'-'+company+'-container-key')
		notAvailableResources = notAvailableResources + check_repository(ecrClient, environment+'-'+company+'-gifmachine')
		notAvailableResources = notAvailableResources + check_bucket(s3Client, environment+'-'+company+'-gifmachine-deploy-configs')
		notAvailableResources = notAvailableResources + check_security_group(ec2Client, environment+'-'+company+'-gifmachine-lb-sg')
		notAvailableResources = notAvailableResources + check_load_balancer(lbv2Client, environment+'-'+company+'-gifmachine-lb')
		notAvailableResources = notAvailableResources + check_target_group(lbv2Client, environment+'-'+company+'-gifmachine-tg-b')
		notAvailableResources = notAvailableResources + check_target_group(lbv2Client, environment+'-'+company+'-gifmachine-tg-g')
		notAvailableResources = notAvailableResources + check_cluster(ecsClient, environment+'-'+company+'-gifmachine-ecs-cluster')
		notAvailableResources = notAvailableResources + check_role(iamClient, environment+'-'+company+'-gifmachine-ecs-taskexecution-role')
		notAvailableResources = notAvailableResources + check_security_group(ec2Client, environment+'-'+company+'-gifmachine-ecs-service-sg')
		notAvailableResources = notAvailableResources + check_log_group(logsClient, '/ecs/'+environment+'-'+company+'-gifmachine-task-log')
		notAvailableResources = notAvailableResources + check_service(ecsClient, environment+'-'+company+'-gifmachine-ecs-cluster',environment+'-'+company+'-gifmachine-ecs-service')

	if section == 'all' or section == 'cicd':
		### CICD
		# notAvailableResources = notAvailableResources + check_bucket(s3Client, environment+'-'+company+'-gifmachine-pipeline-artifacts')
		notAvailableResources = notAvailableResources + check_role(iamClient, environment+'-'+company+'-gifmachine-codebuild-role')
		notAvailableResources = notAvailableResources + check_codebuild_project(cbClient, environment+'-'+company+'-gifmachine-codebuild')
		notAvailableResources = notAvailableResources + check_role(iamClient, environment+'-'+company+'-gifmachine-codedeploy-role')
		notAvailableResources = notAvailableResources + check_codedeploy_application(cdClient, environment+'-'+company+'-gifmachine-codedeploy')
		notAvailableResources = notAvailableResources + check_role(iamClient, environment+'-'+company+'-gifmachine-codepipeline-role')
		notAvailableResources = notAvailableResources + check_codedeploy_deploymentgroup(cdClient, environment+'-'+company+'-gifmachine-codedeploy', environment+'-'+company+'-gifmachine-dg')
		notAvailableResources = notAvailableResources + check_codepipeline_pipeline(cpClient, environment+'-'+company+'-gifmachine-pipeline')


	if section == 'all' or section == 'monitoring':
		### MONITORING
		notAvailableResources = notAvailableResources + check_key_pair(ec2Client, environment+'-'+company+'-monitoring-key')
		notAvailableResources = notAvailableResources + check_bucket(s3Client, environment+'-'+company+'-monitoring-source')
		notAvailableResources = notAvailableResources + check_stack(cfClient, environment+'-'+company+'-monitoring-cf')
	
	if notAvailableResources==0:
		print('SUCCESS! Resources for ' + section + ' can be created on your AWS account in region '+awsRegion+'!')
	else:
		print('\nERROR: ' +str(notAvailableResources)+ ' resources cannot be created since resources with same name already exist in AWS Region '+awsRegion+""":
To solve this problem please do one of two things:
  - Delete existing resources mentioned above;
  - Change master config variables "ENVIRONMENT" or "COMPANY" in config/aws-config.txt file to different values.""")
		sys.exit(1)

def main(section):
	resource_validator(section)

if __name__ == '__main__':
    main(*sys.argv[1:])

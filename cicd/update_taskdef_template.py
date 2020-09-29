import sys
import boto3
import json
from botocore.config import Config

def update_taskdef_template(environment, company, awsRegion):
	clientConfig = Config(region_name = awsRegion)
	stsClient = boto3.client('sts', config=clientConfig)
	s3Client = boto3.client('s3', config=clientConfig)

	bucketName = environment+'-'+company+'-gifmachine-deploy-configs'
	accountId = stsClient.get_caller_identity()['Account']
	roleArn='arn:aws:iam::'+accountId+':role/'+environment+'-'+company+'-gifmachine-ecs-taskexecution-role'
	containerImage = accountId+'.dkr.ecr.'+awsRegion+'.amazonaws.com/'+environment+'-'+company+'-gifmachine:gifmachine'
	csidecarImage = accountId+'.dkr.ecr.'+awsRegion+'.amazonaws.com/'+environment+'-'+company+'-gifmachine:csidecar'
	envVarsFilename = "gifmachine-config.txt"
	taskDefFilename = "taskdefinition-template.json"

	# Downloading data from S3
	taskDefFile = s3Client.get_object(Bucket = bucketName, Key = taskDefFilename) 
	taskDef = json.loads(taskDefFile['Body'].read())

	# Personalizing task def template
	taskDef["family"]=environment+'-'+company+'-gifmachine-taskdefinition'
	taskDef["executionRoleArn"]=roleArn
	taskDef["taskRoleArn"]=roleArn
	taskDef["containerDefinitions"][0]["image"] = containerImage
	taskDef["containerDefinitions"][1]["image"] = csidecarImage
	for container in taskDef["containerDefinitions"]:
		container["logConfiguration"]["options"]["awslogs-group"]='/ecs/'+environment+'-'+company+'-gifmachine-task-log'
		container["logConfiguration"]["options"]["awslogs-region"]=awsRegion
		container["environment"]=[{'name': 'ENVIRONMENT', 'value': environment},{'name': 'COMPANY', 'value': company},{'name': 'AWS_REGION', 'value': awsRegion}]
	f = open('taskdef.json', "w")
	f.write(json.dumps(taskDef))
	f.close()

def main(environment, company, awsRegion):
	update_taskdef_template(environment, company, awsRegion)

if __name__ == '__main__':
    main(*sys.argv[1:])

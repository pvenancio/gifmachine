import boto3
import sys
from botocore.config import Config
import json

def create_deployment_group(environment,company,service,awsRegion):
    clientConfig = Config(region_name = awsRegion)
    cdClient = boto3.client('codedeploy',config=clientConfig)
    elbClient = boto3.client('elbv2',config=clientConfig)
    iamClient = boto3.client('iam',config=clientConfig)

    lbArn = elbClient.describe_load_balancers(Names=[environment+'-'+company+'-'+service+'-lb'])['LoadBalancers'][0]['LoadBalancerArn']
    listenersList = elbClient.describe_listeners(LoadBalancerArn=lbArn)['Listeners']
    for listener in listenersList:
    	if listener['Port'] == 80: listenerArn = listener['ListenerArn']
    	if listener['Port'] == 8080: testListenerArn = listener['ListenerArn']
    codeDeployRoleArn = iamClient.get_role(RoleName=environment + '-'+company+'-'+service+'-codedeploy-role')['Role']['Arn']

    cdClient.create_deployment_group(
        applicationName = environment+'-'+company+'-'+service+'-codedeploy',
        deploymentGroupName = environment+'-'+company+'-'+service+'-dg',
        deploymentConfigName='CodeDeployDefault.ECSAllAtOnce',
        serviceRoleArn=codeDeployRoleArn,
        deploymentStyle={'deploymentType': 'BLUE_GREEN','deploymentOption': 'WITH_TRAFFIC_CONTROL'},
        blueGreenDeploymentConfiguration={
            'terminateBlueInstancesOnDeploymentSuccess': {'action': 'TERMINATE','terminationWaitTimeInMinutes': 5},
            'deploymentReadyOption': {'actionOnTimeout': 'CONTINUE_DEPLOYMENT'}
        },
        loadBalancerInfo={
            'targetGroupPairInfoList': [{
                'targetGroups': [{'name': environment+'-'+company+'-'+service+'-tg-b'},{'name': environment+'-'+company+'-'+service+'-tg-g'}],
                'prodTrafficRoute': {'listenerArns': [listenerArn]},
                'testTrafficRoute': {'listenerArns': [testListenerArn]}
            }]
        },
        ecsServices=[{
            'serviceName': environment+'-'+company+'-'+service+'-ecs-service',
            'clusterName': environment+'-'+company+'-'+service+'-ecs-cluster',
        }]
    )

def create_pipeline(environment,company,service,awsRegion):
    clientConfig = Config(region_name = awsRegion)
    cpClient = boto3.client('codepipeline',config=clientConfig)
    iamClient = boto3.client('iam',config=clientConfig)

    with open('templates/pipeline-template.json', "r") as pipelineTemplateFile:
        pipeline = json.load(pipelineTemplateFile)['pipeline']
        pipeline['name']=environment+'-'+company+'-'+service+'-pipeline'
        codePipelineRoleArn = iamClient.get_role(RoleName=environment + '-'+company+'-'+service+'-codepipeline-role')['Role']['Arn']
        pipeline['roleArn']=codePipelineRoleArn
        pipeline['artifactStore']['location']=environment + '-'+company+'-'+service+'-pipeline-artifacts'
        pipeline['stages'][0]['actions'][0]['configuration']['S3Bucket']=environment + '-'+company+'-'+service+'-deploy-configs'
        pipeline['stages'][0]['actions'][0]['region']=awsRegion
        pipeline['stages'][1]['actions'][0]['configuration']['EnvironmentVariables']= \
            '[{"name":"ENVIRONMENT","value":"'+environment+'","type":"PLAINTEXT"},\
              {"name":"COMPANY","value":"'+company+'","type":"PLAINTEXT"},\
              {"name":"AWS_REGION","value":"'+awsRegion+'","type":"PLAINTEXT"}]'
        pipeline['stages'][1]['actions'][0]['configuration']['ProjectName']=environment + '-'+company+'-'+service+'-codebuild'
        pipeline['stages'][1]['actions'][0]['region']=awsRegion
        pipeline['stages'][2]['actions'][0]['configuration']['ApplicationName']=environment + '-'+company+'-'+service+'-codedeploy'
        pipeline['stages'][2]['actions'][0]['configuration']['DeploymentGroupName']=environment + '-'+company+'-'+service+'-dg'
        pipeline['stages'][2]['actions'][0]['region']=awsRegion
        cpClient.create_pipeline(pipeline=pipeline)

def main(environment,company,service,awsRegion):
    create_deployment_group(environment,company,service,awsRegion)
    create_pipeline(environment,company,service,awsRegion)

if __name__ == '__main__':
    main(*sys.argv[1:])

# gifmachine-on-aws

Within gifmachine-on-aws it can be found a set of scripts and templates to automatically deploy the [Gifmachine](https://github.com/salsify/gifmachine) application in the AWS ecosystem, including all the resources for it to proper function in an internet opened, ready for user traffic, cloud environment. Also, as a bonus, procedures for automatically launching a monitoring solution and CICD pipeline can be found here. 

All is done through AWS CLI version 2 (infrastructure-as-code via AWS Cloudformation), and AWS Python and Go SDKs.

## Requirements

The following dependencies must be installed beforehand:
* [AWS CLI version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-mac.html);
* [Python3](https://realpython.com/installing-python/) and its following packages (installed via [pip3](https://vgkits.org/blog/pip3-macos-howto/)):
  - [Boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/quickstart.html#installation) (AWS Python SDK);
  - [requests](https://requests.readthedocs.io/en/master/).

For the time being, an AWS user with AdministratorAccess IAM policy attach is needed and configured on the local machine (via ``aws configure``) to run these scripts. On subsequent versions of gifmachine-on-aws a more fine-grained IAM policy list will be detailed. 

Note: no delete/remove AWS CLI/SDK commands are present in these scripts so do not worry to accidentally delete anything when running gifmachine-on-aws.

## Configuration

Use the config/aws-config.txt file to setup the resources name tags ``ENVIRONMENT`` and ``COMPANY``, and the ``AWS_REGION`` where to build the infrastructure (only eu-west-1 and us-east-1 valid for now). 

The name tags, besides of identifying the resources related to gifmachine-on-aws on you AWS account, are used to guarantee that there is no name conflict between the resources already present in your account and the ones created here.

Default values are:

```bash
AWS_REGION=eu-west-1
ENVIRONMENT=prod
COMPANY=dundermiff
```

Note: due to the name length limitation of some AWS resources (namely EC2 Target Groups), the number o characters of ``ENVIRONMENT``+``COMPANY`` cannot be greater than 15.

## Usage
### Gifmachine
To deploy Gifmachine on AWS, simply run:
```bash
sh give_me_gifs.sh
```
A prompt will appear to choose the credentials for the PostgreSQL database that will be created and to choose the password for the gifmachine /gif endpoint. After this no more user interaction is needed. After 20 minutes (more or less, so you can grab a cup of coffee!) the deployment will be finished and the gifmachine url will appear.

### Monitoring

After the main gifmachine stack is created, a monitoring stack can also be deployed enabling a Prometheus/Grafana setup that collects gifmachine containers metrics (more on that in the [Documentation](#Documentation) section below).

To deploy the monitoring system just run:
```bash
sh give_me_monitoring.sh
```
No interaction is needed, and after 10 minutes the url for the Grafana dashboard will appear (wait a minute or two to start seeing metrics in the dashboard).

### CICD Pipeline

Also, and again after the main gifmachine stack is created, a CICD stack can be deployed that creates an AWS CodePipeline pipeline enabling an automated build and deploy of a new version of the Gifmachine application.

To create the pipeline, run:
```bash
sh give_me_cicd.sh
```
No interaction is needed and after a minute the pipeline url will appear. Note that when you create this stack, the pipeline will automatically start.

## Architecture
This infrastructure solution for gifmachine-on-aws is composed of multiple AWS services:
* ECS Fargate to handle the containerized gifmachine application;
* EC2 Network Load Balancer to receive external requests and distribute them among the running gifmachine containers;
* EC2 Instances to act as a host for:
  - Jumpbox (to enable access to the resources in the private subnets from outside the VPC);
  - PostgreSQL database;
  - NAT Gateway (for internet connection from the the private subnets);
  - Monitoring solution.
* Secrets Manager to store credentials;
* CodeBuild, CodeDeploy, and CodePipeline for CICD;
* ECR for gifmachine container image repository;
* S3 to store gifmachine configurations, keys, and pipelines;
* IAM Roles for enabling accessibility between services;
* VPC (and all its subnets, security groups, routing tables, etc);
* AWS Cloudformation to deploy all of the above.

A detailed design of the architecture can be seen below:

![architecture](/documentation/aws_architecture.png)

Architecture notes:
* AWS Fargate was chosen over other solutions (non-AWS managed ones) due to it's high reliability and availability (since it's a managed service);
* An EC2 Instance was used for hosting the PostgreSQL and the NAT gateway in this setup due to its quick launch time. For a 'real' production environment AWS RDS and AWS NAT Gateway managed services are recommended;
* Currently AWS ECS Fargate dos not have an easy way to share its underlining infrastructure metrics (the way AWS suggests involves AWS Cloudwatch Logs plus AWS Athena and is not very Prometheus/Grafana user-friendly), thus the need for the sidecar setup;
* Also, AWS ECS Fargate does not provide access to the inside of the container (like what EC2 instances do), so an OpenSSH server is started within it for ease of internal access (not the most recommended solution, [I know](https://jpetazzo.github.io/2014/06/23/docker-ssh-considered-evil/)); 
* The AWS CodePipeline and its siblings was chosen over other CICD services due to its higher integration with the AWS ecosystem. 

## Details
### Gifmachine
The Gifmachine build procedure is divided into 4 phases:

```bash
# PHASE1: USER INPUT
# (...)

# PHASE2: VPC, JUMPBOX, and NAT INSTANCE
# (...)

# PHASE3: DATABASE
# (...)

# PHASE4: GIFMACHINE
# (...)
```

In Phase 1, it starts by asking the user to create PostgreSQL database credentials and Gifmachine API password and then stores them in AWS Secret Manager for later use.

In Phase 2, SSH keys for connecting to the EC2 Instances (Jumpbox and NAT Instance) are created and stored (locally in the /keys folder, an remotely in an also created S3 bucket).

Then the Cloudformation stack "```ENVIRONMENT```-```COMPANY```-all-cf", that encompasses the VPC, Subnets, Routing Tables, Gateways, EC2 Instances, etc., that will be used by all the remaining stacks is built.

In Phase 3 the process is similar, since an SSH key for the database EC2 Instance is also created and stored, and then a Cloudformation stack (named "```ENVIRONMENT```-```COMPANY```-db-cf") starts to be built as well. This one will include all database related resources, i.e., EC2 Instance, Private Subnet, Security Group, etc.). A boot script is included in the EC2 Instance that will install and setup PostgreSQL automatically on start-up.

Phase 4 is where Gifmachine infrastructure is built. SSH key that will enable direct connection to the containers are created and stored, an ECR repository and S3 bucket are created to store the built container images and deployment configuration files, respectively.

Gifmachine configuration files are uploaded to the created S3 bucket, and the container image built is launched within the jumpbox via an SSH command. This image build process basically clones the gifmachine git repository, builds it, includes in it the relevant environment variables, and uploads the result to ECR.

The same is done for the container sidecar application.

Finally, the Cloudformation stack "```ENVIRONMENT```-```COMPANY```-gifmachine-cf" is created (Public/Private Subnets, Network Load Balancer, ECS Cluster and Service, IAM roles, etc.), then a simple set of test are run to validate that the Gifmachine is working, and then its url is showed and ready to be used.

### Monitoring
The Monitoring procedure starts buy creating SSH key and storing it, and then launches the Cloudformation stack "```ENVIRONMENT```-```COMPANY```-monitoring-cf" (EC2 Instance to build and deploy the monitoring apps, and the usual Subnets, Security Groups, etc.).

This Monitoring solution is based on a Prometheus/Grafana usual set up, with an addition of a simple Go application that serves as an endpoint for the containers sidecars to send their "hearbeats" to, cDepot (container Depot). At each minute, cDepot will evaluate which containers it has heartbeats from and then updates the target file where Prometheus will read the IPs to search for metrics.

All containers run via docker-compose within the EC2 instance.

### CICD
The CICD build procedure starts by creating an S3 bucket, where CodePipeline will store its pipeline artefacts (files shared between pipeline stages). 

The needed files for CodeBuild and CodeDeploy are zipped and sent to this S3 bucket, as well as the task definition template to be used by CodeDeploy.

The CICD Cloudformation stack is created, including a CodeBuild project, a CodeDeploy application, and the needed IAM roles.

After the creation of the stack, a CodeDeploy deployment group is created (can only be done after the stack since Cloudformation does not support it yet), and then finally the CodePipeline pipeline (that will automatically initiate the pipeline after its creation).

The CodePipeline pipeline starts by fetching the build procedure from an S3 bucket. Then this build procedure clones the gifmachine git repository, builds a docker image from it, and pushes it to AWS ECR. To conclude the build process, the task definition template is updated with relevant data (e.g. ECR docker image uri, environment variables, etc.) and it is sent to CodeDeploy.

In CodeDeploy, a Blue/Green type of deployment is set up, guaranteeing zero-downtime solution when deploying a new version of gifmachine. After the new version passes the Load Balancer health check (one or two minutes), the deployment finishes and is marked with success.

## Cost
The cost of running gifmachine-on-aws, split by its AWS resource is (values for AWS region eu-west-1):
* 2 EC2 Instance (t3a.nano) = 2 x $0.0047/hour = $0.0094/hour = $0.225/day
* 2 EC2 Instance (t3a.micro) = 2 x $0.0094/hour = $0.0188/hour = $0.45/day
* 1 EC2 NW Load Balancer = 1 x $0.0252/hour = $0.60/day
* 0.256 Fargate vCPUs = 0.256 x $0.04048/hour = $0.01/hour = $0.24/day
* 0.512 Fargate GBs = 0.512 x $0.00444/hour = $0.0022/hour = $0.05/day
* 3 Secret Manager secrets = 3 x $0.4/month = $0.038/day

Taking this into consideration, the overall cost of gifmachine-on-aws is $1.6/day, or $50/month.

Note: this value is an approximation, it can be lowered when used a Free Tier AWS account and will increase with traffic growth (due to LB cost per usage) and number of builds/deploys (also due to CodeBuild/CodeDeploy cost per usage). 

## Documentation
The documentation used to build gifmachine-on-aws was:
* AWS Documentation: [docs.aws.amazon.com](https://docs.aws.amazon.com)
* AWS CLI Reference: [docs.aws.amazon.com/cli/latest/reference](https://docs.aws.amazon.com/cli/latest/reference/)
* Python Boto3 Documentation: [boto3.amazonaws.com/v1/documentation/api/latest/index.html](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html) 
* AWS Go SDK Reference: [docs.aws.amazon.com/sdk-for-go/api](https://docs.aws.amazon.com/sdk-for-go/api/)
* Prometheus Go SDK: [prometheus.io/docs/guides/go-application](https://prometheus.io/docs/guides/go-application/)
* Grafana HTTP API Reference: [grafana.com/docs/grafana/latest/http_api](https://grafana.com/docs/grafana/latest/http_api/)

## Folder structure
The folder structure of gifmachine-on-aws repository is defined as follows:

```bash
.
├── cicd                   # files needed for CodeBuild, CodeDeploy, and CodePipeline
├── config                 # configuration files for both AWS and gifmachine
├── docker                 # dockerfile, and build and image entrypoint scripts
├── documentation          # architecture diagram (Draw.io) and image
├── infrastructure         # cloudformation files
├── monitoring             # monitoring stack and build scripts 
│   ├── cdepot             # cDepot source
│   ├── csidecar           # cSidecar source
│   ├── grafana            # grafana configurations
│   └── prometheus         # prometheus configurations
├── scripts                # auxiliar scripts
└── templates              # pipeline and task definition templates
```
## Roadmap

Although being functional, there is still room for improvement in gifmachine-on-aws, namely:
* Implement auto-scaling in AWS ECS Fargate, that automatically launches more containers based on CPU utlization of the overall service;
* Change the EC2 Network Load Balancer to an EC2 Application Load Balancer to take advantage of the layer 7 balancing functionalities of it (and the possiblitiy to attach an AWS WAF - Web Application Firewall);
* Create the procedure to delete all gifmachine-on-aws created resources (currently, due to Cloudformation limitations, some resources needed to be created via the AWS CLI, thus not beeing removed if the Cloudformation stack is deleted);
* Improve monitoring with a ELK stack to ingest gifmachine logs (and analyse, e.g., endpoints usage, most seen gifs, etc.);
* Create an AWS Lambda function to do an higher application validation within the Blue/Green CodeDeploy deployment;
* Enable a more secure way to interact with and debug the running processes within the container;
* Enable deployment on other AWS Regions.

## License
Open source project under [MIT](https://choosealicense.com/licenses/mit/) license.

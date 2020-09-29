# CHECK_AWS_CONFIG_VALIDITY
# Function to evaluate if master AWS configuration is valid

import sys

def get_master_aws_config_vars(filename):
	with open(filename, 'r') as configFile:
		for var in configFile:
			if var != '':
				if var.split('=')[0] == 'ENVIRONMENT': environment = var.split('=')[1].strip()
				if var.split('=')[0] == 'COMPANY': company = var.split('=')[1].strip()
				if var.split('=')[0] == 'AWS_REGION': awsRegion = var.split('=')[1].strip()
	configLength = len(environment)+len(company)
	if awsRegion != 'eu-west-1' and awsRegion != 'us-east-1':
		print("ERROR: Invalid AWS Region. Available values are 'eu-west-1' or 'us-east-1'")
		sys.exit(1)
	elif configLength > 15:
		print("ERROR: Length of ENVIRONMENT and COMPANY configuration values too long. Sum of both values must be below of 16 characters (currently " + str(configLength) + ").")
		sys.exit(1)
	else:
		print('VALID!')

def main(filename):
	get_master_aws_config_vars(filename)

if __name__ == '__main__':
    main(*sys.argv[1:])

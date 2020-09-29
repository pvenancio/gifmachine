# CHECK_GIFMACHINE
# Batch of tests to all gif machine's endpoints to check
#  everything is online.

import sys
import requests
import time
from requests.adapters import HTTPAdapter

def test_gifmachine(gifmachineUrl):
	historyEndpoint='/history'
	searchEndpoint='/search?query='
	
	headers = {"Accept": "application/json",
	           "Content-Type": "application/json"}

	print('Waiting for Gif Machine to be ready...')
	if check_if_ready(gifmachineUrl,2,1,1):
		print('Gif Machine ready! Testing...')
		test_endpoint("/",gifmachineUrl)
		test_endpoint("/history",gifmachineUrl+historyEndpoint)
		test_endpoint("/search",gifmachineUrl+searchEndpoint)

def test_endpoint(endpointName, endpointUrl):
	r=requests.get(endpointUrl)
	if r.status_code == 200:
		print("> Endpoint " + endpointName + " OK!")
	else:
		print("> Endpoint " + endpointName + " NOT OK!")

def check_if_ready(gifmachineUrl, retryIn, timeout, maxRetries):
	adapter = HTTPAdapter(max_retries=maxRetries)
	session = requests.Session()
	session.mount(gifmachineUrl, adapter)
	while True:
		try:
			session.get(gifmachineUrl,timeout=timeout)
			return True
		except:
			time.sleep(retryIn)

def main(gifmachineUrl):
	test_gifmachine(gifmachineUrl)

if __name__ == '__main__':
    main(*sys.argv[1:])

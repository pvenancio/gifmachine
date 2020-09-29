import sys
import requests
import json
import time
from requests.adapters import HTTPAdapter

def set_up_grafana(grafanaUrl):
	dashboardName = 'gifmachines'
	dashboardTemplateFilename = 'monitoring/grafana/dashboard.json'
	sourceApiEndpoint='/api/datasources'
	createDashboardApiEndpoint='/api/dashboards/db'
	searchApiEndpoint='/api/search/'
	headers = {"Accept": "application/json",
	           "Content-Type": "application/json"}
		
	print('Waiting for Grafana to be ready...')
	if check_if_ready(grafanaUrl,2,1,1):
		print('Grafana ready!')
		
		print('Adding Prometheus source...')
		sourceConfig = {'name':'Prometheus','type':'prometheus','url':'prometheus:9090','access':'proxy','basicAuth':False}
		requests.post(grafanaUrl+sourceApiEndpoint, headers=headers, json=sourceConfig)
		
		print('Creating dashboard...')
		with open(dashboardTemplateFilename) as jsonFile:
			dashboard = json.load(jsonFile)
			dashboard['dashboard']['title']=dashboardName
			r=requests.post(grafanaUrl+createDashboardApiEndpoint, headers=headers, json=dashboard)

		print('Getting dashboard...')
		r = requests.get(grafanaUrl+searchApiEndpoint, headers=headers)
		searchResult = json.loads(r.text)
		for item in searchResult:
			if dashboardName in item['title']:
				dashboardUrl=item['url']
				break
		print("DASHBOARD URL: "+grafanaUrl+dashboardUrl)


def check_if_ready(grafanaUrl, retryIn, timeout, maxRetries):
	adapter = HTTPAdapter(max_retries=maxRetries)
	session = requests.Session()
	session.mount(grafanaUrl, adapter)
	while True:
		try:
			session.get(grafanaUrl,timeout=timeout)
			return True
		except:
			time.sleep(retryIn)


def main(grafanaUrl):
	set_up_grafana(grafanaUrl)

if __name__ == '__main__':
    main(*sys.argv[1:])

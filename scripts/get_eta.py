import sys
from datetime import datetime, timedelta

def get_eta(timeDuration):
	eta=datetime.now()+timedelta(minutes = int(timeDuration))
	print(eta.strftime("%H:%M"))

def main(timeDuration):
	get_eta(timeDuration)

if __name__ == '__main__':
    main(*sys.argv[1:])

info:
	@echo "build	build the privacyidea image"
	@echo "push		push the image to the docker hub"

LOCAL_DATA_VOLUME=/tmp/privacyidea-data

build:
	docker build -t michimau/privacyidea .

push:
	docker push michimau/privacyidea

run: $(LOCAL_DATA_VOLUME) secretkey pipepper
	#docker run -v $(LOCAL_DATA_VOLUME):/data/privacyidea -p 80:80 -ti --env-file=secretkey --env-file=pipepper michimau/privacyidea
	docker run -p 80:80 -ti --env-file=secretkey --env-file=pipepper michimau/privacyidea


$(LOCAL_DATA_VOLUME):
	mkdir $(LOCAL_DATA_VOLUME)

secretkey:
	@echo Creating secretkey
	@echo SECRET_KEY=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) > secretkey

pipepper:
	@echo Creating pipepper
	@echo PI_PEPPER=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) > pipepper

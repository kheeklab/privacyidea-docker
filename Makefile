info:
	@echo "build	build the privacyidea image"
	@echo "push		push the image to the docker hub"

LOCAL_DATA_VOLUME=/tmp/privacyidea-data

build:
	docker build -t khalibre/privacyidea:dev .

push:
	docker push michimau/privacyidea

run: cleanup create_volume secretkey pipepper
	docker run -v $(LOCAL_DATA_VOLUME):/data/privacyidea -p 80:80 -ti --name=privacyidea-dev --env-file=secretkey --env-file=pipepper khalibre/privacyidea:dev

create_volume:
	mkdir $(LOCAL_DATA_VOLUME)

secretkey:
	@echo Creating secretkey
	@echo SECRET_KEY=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) > secretkey

pipepper:
	@echo Creating pipepper
	@echo PI_PEPPER=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) > pipepper

cleanup:
	docker stop privacyidea-dev || true
	docker rm privacyidea-dev || true
	sudo rm -rf $(LOCAL_DATA_VOLUME)

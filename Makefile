LOCAL_DATA_VOLUME=/tmp/privacyidea-data

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-30s %s\n", $$1, $$2}' | sort

build: ## Build image
	docker build -t khalibre/privacyidea:dev .

push: ## Push image
	docker push khalibre/privacyidea:dev

run: cleanup create_volume secretkey pipepper ## Run test
	docker run -p 80:80 -p 443:443 -ti --name=privacyidea-dev --env-file=secretkey --env-file=pipepper khalibre/privacyidea:dev

create_volume:
	mkdir $(LOCAL_DATA_VOLUME)

secretkey:
	@echo Creating secretkey
	@echo SECRET_KEY=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) > secretkey

pipepper:
	@echo Creating pipepper
	@echo PI_PEPPER=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) > pipepper

cleanup:
	@if docker ps -a | grep -q privacyidea-dev; then docker stop privacyidea-dev || true; fi
	@if docker ps -a | grep -q privacyidea-dev; then docker rm privacyidea-dev || true; fi
	@if [ -d $(LOCAL_DATA_VOLUME) ]; then sudo rm -rf $(LOCAL_DATA_VOLUME); fi

test:
	container-structure-test test --image khalibre/privacyidea:dev --config structure-tests.yaml

.DEFAULT_GOAL := help

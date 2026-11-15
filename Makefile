LOCAL_DATA_VOLUME=/tmp/privacyidea-data
REPOSITORY_OWNER := $(shell git remote get-url origin 2>/dev/null | sed -nE '/github\.com[:/]/ { s@^.*github\.com[:/]@@; s@/.*@@; p; }' | tr '[:upper:]' '[:lower:]')
IMAGE ?= $(if $(REPOSITORY_OWNER),$(REPOSITORY_OWNER)/privacyidea,privacyidea)
IMAGE_TAG ?= dev

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-30s %s\n", $$1, $$2}' | sort

build: ## Build image
	docker build -t $(IMAGE):$(IMAGE_TAG) .

push: ## Push image
	docker push $(IMAGE):$(IMAGE_TAG)

run: cleanup create_volume secretkey pipepper ## Run test
	docker run -p 8080:8080 -ti --name=privacyidea-dev --env-file=secretkey --env-file=pipepper $(IMAGE):$(IMAGE_TAG)

create_volume:
	mkdir $(LOCAL_DATA_VOLUME)

secretkey:
	@echo Creating secretkey
	@echo PI_SECRET_KEY=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) > secretkey

pipepper:
	@echo Creating pipepper
	@echo PI_PEPPER=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) > pipepper

cleanup:
	@if docker ps -a | grep -q privacyidea-dev; then docker stop privacyidea-dev || true; fi
	@if docker ps -a | grep -q privacyidea-dev; then docker rm privacyidea-dev || true; fi
	@if [ -d $(LOCAL_DATA_VOLUME) ]; then sudo rm -rf $(LOCAL_DATA_VOLUME); fi

test:
	container-structure-test test --image $(IMAGE):$(IMAGE_TAG) --config structure-tests.yaml

.DEFAULT_GOAL := help

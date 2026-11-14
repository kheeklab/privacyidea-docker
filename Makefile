REPOSITORY_OWNER := $(shell git remote get-url origin 2>/dev/null | sed -nE '/github\.com[:/]/ { s@^.*github\.com[:/]@@; s@/.*@@; p; }' | tr '[:upper:]' '[:lower:]')
IMAGE ?= $(if $(REPOSITORY_OWNER),$(REPOSITORY_OWNER)/privacyidea,privacyidea)
IMAGE_TAG ?= dev
export IMAGE IMAGE_TAG

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-30s %s\n", $$1, $$2}' | sort

build: ## Build image
	docker build -t $(IMAGE):$(IMAGE_TAG) .

push: ## Push image
	docker push $(IMAGE):$(IMAGE_TAG)

credentials: ## Generate local credentials; does not provision a usable service
	python3 scripts/create-demo-env.py

cleanup:
	docker compose down

test:
	container-structure-test test --image $(IMAGE):$(IMAGE_TAG) --config structure-tests.yaml

.DEFAULT_GOAL := help

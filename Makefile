HELM_BIN := $(shell which helm)
HELM_DATA_HOME ?= $(shell ${HELM_BIN} env | grep HELM_DATA_HOME | cut -d'=' -f2 | tr -d '"')
HELM_TEMPLATE=default
HELM_TEMPLATE_PATH= ${HELM_DATA_HOME}/starters/${HELM_TEMPLATE}
HELM_CHART_DIR=charts
APP_NAME=
APP_PATH=$(HELM_CHART_DIR)/$(APP_NAME)
USE_STARTER=true



.PHONY: checks
checks: ## Check if helm is installed
	@echo "Checking if helm is installed"
	@if [ -z $(HELM_BIN) ]; then \
		echo "Helm is not installed. Please install helm"; \
		exit 1; \
	fi

	@echo "Checking if helm data home is set"
	@if [ -z $(HELM_DATA_HOME) ]; then \
		echo "HELM_DATA_HOME is not set. Please set HELM_DATA_HOME"; \
		exit 1; \
	fi

	@echo "Checking if APP_NAME is set"
	@if [ -z $(APP_NAME) ]; then \
		echo "APP_NAME is not set. Please set APP_NAME"; \
		exit 1; \
	fi

.PHONY: prepare-dev
prepare-dev: ## Prepare the development environment
	@echo "Copying helm template to HELM_DATA_HOME"
	mkdir -p ${HELM_TEMPLATE_PATH}
	cp -r templates/default/* $(HELM_TEMPLATE_PATH)


.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: lint
lint: ## Lint the helm chart
	@echo "Linting helm chart"
	$(HELM_BIN) lint $(HELM_CHART_DIR)/*

.PHONY: create_app
create_app: checks ## Create a new project
	@if [ $(USE_STARTER) = true ]; then \
		echo "Creating a new project using starter"; \
		$(HELM_BIN) create $(APP_PATH) --starter $(HELM_TEMPLATE); \
	else \
		echo "Creating a new project"; \
		$(HELM_BIN) create $(APP_PATH); \
	fi

.PHONY: test_charts
test_charts: ## Test the helm chart
	@echo "Testing helm chart"
	@for chart in $(HELM_CHART_DIR)/*; do \
		echo "Testing $$chart"; \
		$(HELM_BIN) template $$chart; \
	done

.PHONY: build_dependencies
build_dependencies: ## Build the dependencies
	@echo "Building dependencies"
	@for chart in $(HELM_CHART_DIR)/*; do \
		echo "Building dependencies for $$chart"; \
		$(HELM_BIN) dependency update $$chart; \
	done



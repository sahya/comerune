SHELL := /bin/bash

# Environment setup
ANDROID_HOME := $(HOME)/android-sdk
FLUTTER_BIN  := $(HOME)/tools/flutter/bin
MISE_BIN     := $(HOME)/.local/bin/mise
# Activate mise if available, otherwise skip
MISE_ACTIVATE := $(if $(wildcard $(MISE_BIN)),eval "$$($(MISE_BIN) activate bash)",true)
ENV := $(MISE_ACTIVATE) && \
       export ANDROID_HOME=$(ANDROID_HOME) && \
       export PATH=$(FLUTTER_BIN):$(ANDROID_HOME)/cmdline-tools/latest/bin:$(ANDROID_HOME)/platform-tools:$$PATH

.PHONY: help doctor clean build build-release build-clean test pub-get analyze format check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

doctor: ## Run flutter doctor
	$(ENV) && flutter doctor -v

clean: ## Run flutter clean
	$(ENV) && flutter clean

build: ## Build debug APK
	$(ENV) && flutter build apk --debug

build-release: ## Build release APK
	$(ENV) && flutter build apk --release

build-clean: clean build ## Clean + build debug APK

test: ## Run tests
	$(ENV) && flutter test

pub-get: ## Resolve dependencies
	$(ENV) && flutter pub get

analyze: ## Run static analysis
	$(ENV) && flutter analyze

format: ## Run code formatter
	$(ENV) && dart format .

check: analyze format test ## Run all checks (analyze → format → test)

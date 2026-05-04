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

# OAuth + App Links + BFF build-time defines.
# android/oauth_bff.env is gitignored (see android/oauth_bff.env.example).
# When present the file's KEY=VALUE entries are injected as Dart compile-time
# constants via --dart-define-from-file; when absent the flag is omitted so
# build still succeeds and OAuthBffConfig.isFullyConfigured returns false at
# runtime (UI hides the OAuth login entry point).
OAUTH_BFF_ENV_FILE := android/oauth_bff.env
DART_DEFINE_OAUTH_BFF := $(if $(wildcard $(OAUTH_BFF_ENV_FILE)),--dart-define-from-file=$(OAUTH_BFF_ENV_FILE),)

.PHONY: help doctor clean build build-release build-release-aab build-adi-verification build-clean test pub-get analyze format format-all check setup-libs ext-gen

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-38s\033[0m %s\n", $$1, $$2}'

doctor: ## Run flutter doctor
	$(ENV) && flutter doctor -v

clean: ## Run flutter clean
	$(ENV) && flutter clean

setup-libs: ## Download VOICEVOX native libraries if missing
	@bash scripts/setup-voicevox-libs.sh

build: setup-libs ## Build debug APK
	$(ENV) && flutter build apk --debug $(DART_DEFINE_OAUTH_BFF)

build-release: setup-libs ## Build release APK
	$(ENV) && bash scripts/guard-no-adi-registration-asset.sh && bash scripts/verify-release-keystore.sh && flutter build apk --release --obfuscate --split-debug-info=build/debug-info $(DART_DEFINE_OAUTH_BFF)

# AAB は本来複数 ABI 同梱が強みだが、現状は arm64-v8a のみ（android/app/build.gradle.kts の release abiFilters による）。
build-release-aab: setup-libs ## Build release AAB (arm64-v8a only — for Google Play upload)
	$(ENV) && bash scripts/guard-no-adi-registration-asset.sh && bash scripts/verify-release-keystore.sh && flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info $(DART_DEFINE_OAUTH_BFF)

build-adi-verification: setup-libs ## Build Android Developer Verification APK (requires ANDROID_ADI_REGISTRATION_PUBLIC_CONTENT_FILE)
	$(ENV) && bash scripts/build-android-developer-verification-apk.sh

build-clean: clean build ## Clean + build debug APK

test: ## Run tests
	$(ENV) && flutter test

pub-get: ## Resolve dependencies
	$(ENV) && flutter pub get

analyze: ## Run static analysis
	$(ENV) && flutter analyze

format: ## Run code formatter and restore out-of-scope tracked changes
	$(ENV) && bash scripts/format-safely.sh

format-all: ## Run code formatter for the whole repository (use in dedicated PRs)
	$(ENV) && dart format .

check: analyze format test ## Run all checks (analyze → format → test)

ext-gen: ## Regenerate optional integration overrides + registry from integrations/
	$(ENV) && dart run scripts/gen_extension_overrides.dart && dart run scripts/gen_extension_registry.dart

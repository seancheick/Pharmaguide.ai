# PharmaGuide Flutter — Build & Run Commands
# Usage: make <target>
# Requires: .env file with SUPABASE_URL and SUPABASE_ANON_KEY set

include .env
export

FLUTTER := $(HOME)/Development/flutter/bin/flutter

DART_DEFINES := \
	--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
	--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) \
	--dart-define=GEMINI_API_KEY=$(GEMINI_API_KEY) \
	--dart-define=SENTRY_DSN=$(SENTRY_DSN) \
	--dart-define=SENTRY_ENVIRONMENT=$(SENTRY_ENVIRONMENT) \
	--dart-define=SENTRY_RELEASE=$(SENTRY_RELEASE)

# ─── Development ──────────────────────────────────────────────────────────────

.PHONY: run
run: ## Run app on connected device (debug)
	$(FLUTTER) run $(DART_DEFINES)

.PHONY: run-ios
run-ios: ## Run on iOS simulator
	$(FLUTTER) run $(DART_DEFINES) -d iPhone

.PHONY: run-android
run-android: ## Run on Android emulator
	$(FLUTTER) run $(DART_DEFINES) -d android

# ─── Build ────────────────────────────────────────────────────────────────────

.PHONY: build-ios
build-ios: ## Build iOS release IPA
	$(FLUTTER) build ipa $(DART_DEFINES) --release

.PHONY: build-android
build-android: ## Build Android release AAB
	$(FLUTTER) build appbundle $(DART_DEFINES) --release

# ─── Testing & Quality ────────────────────────────────────────────────────────

.PHONY: test
test: ## Run all tests
	$(FLUTTER) test

.PHONY: analyze
analyze: ## Run flutter analyze
	$(FLUTTER) analyze

.PHONY: format
format: ## Format all Dart files
	dart format lib/ test/

.PHONY: check
check: analyze test ## Run analyze + tests (CI gate)

# ─── Code Generation ──────────────────────────────────────────────────────────

.PHONY: gen
gen: ## Regenerate Drift + JSON code
	dart run build_runner build --delete-conflicting-outputs

.PHONY: gen-watch
gen-watch: ## Watch and regenerate on change
	dart run build_runner watch --delete-conflicting-outputs

# ─── Supabase ─────────────────────────────────────────────────────────────────

.PHONY: verify-supabase
verify-supabase: ## Verify Supabase anon key is valid
	@echo "Testing Supabase connection..."
	@STATUS=$$(curl -s -o /dev/null -w "%{http_code}" \
		"$(SUPABASE_URL)/auth/v1/settings" \
		-H "apikey: $(SUPABASE_ANON_KEY)"); \
	if [ "$$STATUS" = "200" ]; then \
		echo "✓ Supabase connected (HTTP $$STATUS)"; \
	else \
		echo "✗ Supabase check failed (HTTP $$STATUS)"; exit 1; \
	fi

# ─── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

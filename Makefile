# PharmaGuide Flutter — Build & Run Commands
# Usage: make <target>
# Requires: .env file with SUPABASE_URL and SUPABASE_ANON_KEY set

include .env
export

# Force UTF-8 for every tool we shell out to. CocoaPods (Ruby) crashes
# with `Encoding::CompatibilityError: ASCII-8BIT` when the project path
# contains non-ASCII characters or spaces (this repo's path has a space:
# "PharmaGuide ai/"). Setting LANG/LC_ALL here means every make target
# — including the ones that invoke `pod install` transitively via
# Flutter — picks the right encoding without per-shell tricks.
export LANG := en_US.UTF-8
export LC_ALL := en_US.UTF-8

FLUTTER := $(HOME)/Development/flutter/bin/flutter

DART_DEFINES := \
	--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
	--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) \
	--dart-define=GEMINI_API_KEY=$(GEMINI_API_KEY) \
	--dart-define=SENTRY_DSN=$(SENTRY_DSN) \
	--dart-define=SENTRY_ENVIRONMENT=$(SENTRY_ENVIRONMENT) \
	--dart-define=SENTRY_RELEASE=$(SENTRY_RELEASE) \
	--dart-define=GOOGLE_WEB_CLIENT_ID=$(GOOGLE_WEB_CLIENT_ID) \
	--dart-define=GOOGLE_IOS_CLIENT_ID=$(GOOGLE_IOS_CLIENT_ID)

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

# ─── v2 design system previews ────────────────────────────────────────────────
# DEV_ROUTE skips the splash → onboarding/home flow and launches directly
# at the named route. Useful for reviewing v2 prototypes during the
# design/v2-mobile-polish branch.

.PHONY: run-v2
run-v2: ## Boot straight into the v2 component gallery
	$(FLUTTER) run $(DART_DEFINES) --dart-define=DEV_ROUTE=/dev/v2

.PHONY: run-v2-ios
run-v2-ios: ## v2 gallery on iOS simulator
	$(FLUTTER) run $(DART_DEFINES) --dart-define=DEV_ROUTE=/dev/v2 -d iPhone

.PHONY: run-v2-android
run-v2-android: ## v2 gallery on Android emulator
	$(FLUTTER) run $(DART_DEFINES) --dart-define=DEV_ROUTE=/dev/v2 -d android

.PHONY: v2-audit
v2-audit: ## Run the v2 design-system governance audit (hex / serif / TextStyle)
	@bash scripts/v2_audit.sh

# ─── Phase 11.7g.3 staged route swap ──────────────────────────────────────────
# `run-v2pd` boots the app with the production /product/:dsldId route flipped
# to the v2 ConnectedScreen. Legacy widget stays imported — set
# USE_V2_PRODUCT_DETAIL=false (or omit the flag) to fall back instantly.

.PHONY: run-v2pd
run-v2pd: ## Run with /product route swapped to v2 (TestFlight preview mode)
	$(FLUTTER) run $(DART_DEFINES) --dart-define=USE_V2_PRODUCT_DETAIL=true

.PHONY: run-v2pd-ios
run-v2pd-ios: ## v2 product detail on iOS simulator
	$(FLUTTER) run $(DART_DEFINES) --dart-define=USE_V2_PRODUCT_DETAIL=true -d iPhone

.PHONY: build-ipa-v2pd
build-ipa-v2pd: ## Build TestFlight IPA with v2 product detail enabled
	$(FLUTTER) build ipa $(DART_DEFINES) --dart-define=USE_V2_PRODUCT_DETAIL=true --release

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

# ─── iOS native (CocoaPods) ───────────────────────────────────────────────────

.PHONY: pod-install
pod-install: ## Reinstall iOS CocoaPods (use after iOS plugin upgrades)
	cd ios && pod install --repo-update

.PHONY: ios-clean
ios-clean: ## Wipe iOS Pods + lockfile (forces fresh install on next build)
	rm -rf ios/Pods ios/Podfile.lock

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

.PHONY: verify-bundle
verify-bundle: ## Verify bundled DB matches Supabase storage (P4 release-safety)
	@$(FLUTTER) pub run scripts/verify_bundle.dart \
		--manifest assets/db/export_manifest.json \
		--db assets/db/pharmaguide_core.db \
		--supabase-url "$(SUPABASE_URL)" \
		--anon-key "$(SUPABASE_ANON_KEY)" \
		--sample-size 20

# ─── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

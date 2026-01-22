.PHONY: clean apk gen init analyze format in g codegen ci-flutter-git-setup ci-flutter-deps ci-build-darwin ci-build-macos ci-build-ios ci-build-windows ci-build-msix fg clean-build-env dcm-analyze release-android

# Default flavor
FLAVOR ?= dev

# Use FVM or regular Flutter
USE_FVM ?= true

ifeq ($(USE_FVM),true)
FVM_BIN := $(shell command -v fvm 2>/dev/null)
ifeq ($(FVM_BIN),)
$(warning USE_FVM=true, but "fvm" was not found in PATH. Falling back to system flutter/dart.)
FLUTTER_CMD := flutter
DART_CMD    := dart
else
	FLUTTER_CMD := fvm flutter
	DART_CMD    := fvm dart
endif
else
	FLUTTER_CMD := flutter
	DART_CMD    := dart
endif

LOG_FILE ?= test_results.log

# Validate FLAVOR. Flavors are used for iOS, Android, macOS and Windows builds
VALID_FLAVORS := dev prod stage
ifneq ($(filter $(FLAVOR),$(VALID_FLAVORS)), $(FLAVOR))
$(error Invalid FLAVOR: $(FLAVOR). Must be one of $(VALID_FLAVORS))
endif

ifdef BUILD_NUMBER
	BUILD_NUM_VALUE := $(BUILD_NUMBER)
	BUILD_NUMBER_ARG := --build-number=$(BUILD_NUM_VALUE)
else
	BUILD_NUM_VALUE := $(shell grep '^version:' pubspec.yaml | cut -d '+' -f 2)
	BUILD_NUMBER_ARG :=
endif

# Dependency loading 
.dart_tool/package_config.json: ../pubspec.yaml pubspec.lock
	@echo "* Resolving dependencies... *"
	$(FLUTTER_CMD) pub get --no-example
	@echo "* Dependencies resolved. *"

# Code generation
.dart_tool/build/entrypoint/build.dart:
	@echo "* Resolving dependencies... *"
	$(FLUTTER_CMD) pub get
	@echo "* Starting code generation... *"
	$(DART_CMD) run build_runner build --delete-conflicting-outputs
	@echo "* Code generation successful *"

# Linter check (runs after code generation)
.dart_tool/analyze_passed: .dart_tool/build/entrypoint/build.dart
	@echo "* Running linter check... *"
	$(FLUTTER_CMD) analyze --fatal-warnings --fatal-infos --no-pub . || (echo "Error or linter hint in project"; exit 1)
	@touch $@
	@echo "* Linter check passed. *"

# Configure Android once (stamp file)
build/.android_configured: .dart_tool/package_config.json
	@echo "* Configuring Android project (no build)... *"
	@mkdir -p $(dir $@)
	$(FLUTTER_CMD) build apk -t 'lib/main.dart' \
		--config-only
	@touch $@
	@echo "* Android config complete. *"

# Release Android build
build/app/outputs/flutter-apk/app-release.apk: .dart_tool/analyze_passed build/.android_configured
	@echo "* Building APK... *"
	$(FLUTTER_CMD) build apk -t 'lib/main.dart' $(BUILD_NUMBER_ARG) \
		--no-pub \
		--target-platform=android-arm64 \
		--split-per-abi
	@echo "* APK release build finished. *"

build/app/outputs/bundle/release/app-release.aab: .dart_tool/analyze_passed build/.android_configured
	@echo "* Building AAB... *"
	$(FLUTTER_CMD) build appbundle -t 'lib/main.dart' $(BUILD_NUMBER_ARG) \
		--no-pub
	@echo "* AAB release build finished. *"

### Human-readable aliases
# Clean project
clean:
	@echo "* Cleaning project... *"
	$(FLUTTER_CMD) clean
	@rm -f .dart_tool/analyze_passed
	@echo "* Project cleaned. *"

# Code analysis
analyze:
	@echo "* Analyzing code... *"
	$(FLUTTER_CMD) analyze --fatal-warnings --fatal-infos --no-pub . || (echo "Error or linter hint in project"; exit 1)
	@echo "* Code analysis complete. *"

# DCM analysis
dcm-analyze:
	@echo "* Running DCM analysis... *"
	@if command -v dcm >/dev/null 2>&1; then \
		dcm analyze .; \
	else \
		$(DART_CMD) run dart_code_metrics:metrics analyze .; \
	fi || (echo "DCM analysis failed"; exit 1)
	@echo "* DCM analysis complete. *"
	
release-android: .dart_tool/build/entrypoint/build.dart build/app/outputs/flutter-apk/app-release.apk
ifeq ($(BUILD_AAB),1)
	@$(MAKE) build/app/outputs/bundle/release/app-release.aab
endif
	@echo "* RELEASE android app build finished *"

# APK build 
apk: build/app/outputs/flutter-apk/app-release.apk

# Run build_runner 
gen: .dart_tool/build/entrypoint/build.dart

# Initialize project 
init: clean gen

# Validate formatting issues
format: 
	#@dart format -o none --set-exit-if-changed ./lib --line-length=120

# Initialize project
in:
	@echo "* Getting latest dependencies *"
	$(FLUTTER_CMD) pub get --no-example
	@echo "* Running build runner *"
	$(DART_CMD) run build_runner build --delete-conflicting-outputs

# Code generation
g:
	@echo "* Starting code generation... *"
	$(DART_CMD) run build_runner build --delete-conflicting-outputs
	@echo "* Code generation successfull *"

codegen: gen
	@echo "* Code generation completed. *"

ci-flutter-git-setup:
	@echo "* Checking for Flutter version... *"
	@if [ -n "$(CI_FLUTTER_VERSION)" ]; then \
		FLUTTER_VERSION="$(CI_FLUTTER_VERSION)"; \
	elif [ -f .ci-flutter-version ]; then \
		FLUTTER_VERSION=$$(cat .ci-flutter-version); \
	elif [ -f ../.ci-flutter-version ]; then \
		FLUTTER_VERSION=$$(cat ../.ci-flutter-version); \
	else \
		echo "Error: CI_FLUTTER_VERSION not set and .ci-flutter-version not found"; \
		exit 1; \
	fi; \
	echo "* Cloning Flutter version $$FLUTTER_VERSION... *"; \
	git clone https://github.com/flutter/flutter.git --branch $$FLUTTER_VERSION --depth 1 $$HOME/flutter; \
	export PATH="$$PATH:$$HOME/flutter/bin"; \
	echo "* Flutter cloned and added to PATH. *"

ci-flutter-deps:
	@echo "* Installing Flutter dependencies for PLATFORM=$(PLATFORM)... *"
	@if [ -z "$(PLATFORM)" ]; then \
		echo "Error: PLATFORM variable is not set. Please specify PLATFORM=ios or PLATFORM=macos."; \
		exit 1; \
	fi
	$(FLUTTER_CMD) precache --$(PLATFORM)
	$(FLUTTER_CMD) pub get --no-example
	@echo "* Flutter dependencies installed for $(PLATFORM). *"

ci-build-darwin: .dart_tool/analyze_passed
	@echo "* Building $(PLATFORM) app... *"
	@if [ -z "$(PLATFORM)" ]; then \
		echo "Error: PLATFORM variable is not set. Please specify PLATFORM=ios or PLATFORM=macos."; \
		exit 1; \
	fi
	$(FLUTTER_CMD) build $(PLATFORM) --config-only --no-pub $(BUILD_NUMBER_ARG)
	@echo "$(PLATFORM) build completed successfully."

ci-build-macos:
	@make ci-build-darwin PLATFORM=macos BUILD_NUMBER=$(BUILD_NUMBER)

ci-build-ios:
	@make ci-build-darwin PLATFORM=ios BUILD_NUMBER=$(BUILD_NUMBER)

ci-build-windows: .dart_tool/analyze_passed
	@echo "* Building Windows app... *"
	$(FLUTTER_CMD) build windows -t 'lib/main.dart' $(BUILD_NUMBER_ARG) --no-pub
	@echo "* Windows build completed successfully. *"

ci-build-msix:
	@echo "* Generating Windows-style version... *"
	$(eval WINDOWS_STYLE_VERSION := $(shell $(DART_CMD) run scripts/print_windows_style_version.dart --build-number $(BUILD_NUM_VALUE)))
	@echo "* Building msix... *"
	$(DART_CMD) run msix:create --windows-build-args ' $(BUILD_NUMBER_ARG) --no-pub ' --version $(WINDOWS_STYLE_VERSION)

# Code generation
fg:
	@echo "* Starting code generation... *"
	$(DART_CMD) run build_runner build --delete-conflicting-outputs
	@echo "* Code generation successful *"

# Cleans build environment and gets dependencies.
clean-build-env:
	@echo "* Getting dependencies. *"
	@$(FLUTTER_CMD) pub get --no-example > /dev/null 2>&1
	@$(DART_CMD) run build_runner clean > /dev/null 2>&1
	@$(DART_CMD) run build_runner build --delete-conflicting-outputs > /dev/null 2>&1

# Make targets used by CI: GitHub Actions workflows and CI images.
#
# The `gha-*` targets are used by the GitHub Actions workflows and always call
# the system `flutter`/`dart` (CI images do not ship fvm). They operate on the
# example app, so they must be included from `example/Makefile`.
#
# The legacy `ci-*` targets are kept for backward compatibility.

.PHONY: ci-flutter-git-setup ci-flutter-deps ci-build-darwin ci-build-macos \
	ci-build-ios ci-build-windows ci-build-msix \
	gha-prepare gha-build-android-apk gha-build-ios gha-build-macos \
	gha-build-windows gha-build-msix

### Legacy CI targets

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

### GHA targets (used by GitHub Actions workflows)

# Shared build arguments. BUILD_NAME / BUILD_NUMBER are passed on the command
# line by the workflows.
GHA_BUILD_NAME_ARG := $(if $(BUILD_NAME),--build-name=$(BUILD_NAME),)
GHA_BUILD_NUMBER_ARG := $(if $(BUILD_NUMBER),--build-number=$(BUILD_NUMBER),)

# Dependency resolution and code generation for the example app.
gha-prepare:
	@echo "*  Resolving dependencies... *"
	flutter pub get
	@echo "*  Running code generation... *"
	dart run build_runner build --delete-conflicting-outputs
	@echo "*  Project prepared. *"

gha-build-android-apk:
	@echo "*  Building Android APK... *"
	flutter build apk --release $(GHA_BUILD_NAME_ARG) $(GHA_BUILD_NUMBER_ARG) --no-pub
	@echo "*  Android APK build complete. *"

gha-build-ios:
	@echo "*  Building iOS app... *"
	flutter build ios --release --no-codesign $(GHA_BUILD_NAME_ARG) $(GHA_BUILD_NUMBER_ARG) --no-pub
	@echo "*  iOS build complete. *"

gha-build-macos:
	@echo "*  Building macOS app... *"
	flutter build macos --release --no-codesign $(GHA_BUILD_NAME_ARG) $(GHA_BUILD_NUMBER_ARG) --no-pub
	@echo "*  macOS build complete. *"

gha-build-windows:
	@echo "*  Building Windows app... *"
	flutter build windows --release $(GHA_BUILD_NAME_ARG) $(GHA_BUILD_NUMBER_ARG) --no-pub
	@echo "*  Windows build complete. *"

gha-build-msix:
	@echo "*  Building msix... *"
	windows_version="$$(dart run scripts/print_windows_style_version.dart --build-number $(BUILD_NUMBER))"
	dart run msix:create --build-windows false --version "$$windows_version"
	@echo "*  Msix build complete. *"

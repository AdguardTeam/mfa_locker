# Proxy Makefile that delegates all targets to example/Makefile
# This allows CI/CD to work with Makefile in the root while the actual build happens in example/

# Get all targets from example/Makefile (except special ones)
EXAMPLE_DIR := example

# Read .ci-flutter-version from root and export it for example/Makefile
CI_FLUTTER_VERSION_FILE := .ci-flutter-version
ifneq ($(wildcard $(CI_FLUTTER_VERSION_FILE)),)
	export CI_FLUTTER_VERSION := $(shell cat $(CI_FLUTTER_VERSION_FILE))
endif

# Special variable to detect if we're being called from the proxy
export FROM_PROXY := 1

# Default target
.DEFAULT_GOAL := help

# Catch-all target that forwards everything to example/Makefile
%:
	@$(MAKE) -C $(EXAMPLE_DIR) $@ $(MAKEFLAGS)

# Special targets that need explicit forwarding
.PHONY: help
help:
	@echo "Proxy Makefile - all targets are forwarded to $(EXAMPLE_DIR)/Makefile"
	@echo ""
	@$(MAKE) -C $(EXAMPLE_DIR) help 2>/dev/null || echo "Run 'make <target>' to execute targets in $(EXAMPLE_DIR)/"

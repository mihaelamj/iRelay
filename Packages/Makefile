# Makefile for SwiftClaw
# Apple-native AI Assistant

# Configuration
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
BUILD_DIR = .build
SWIFT = xcrun swift
INSTALL = install

# Get the absolute path to this Makefile's directory
MAKEFILE_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
PROJECT_DIR := $(MAKEFILE_DIR)

# Build configuration
SWIFT_BUILD_FLAGS = -c release
PRODUCT_NAME_CLI = swiftclaw

# Detect architecture
ARCH := $(shell uname -m)
ifeq ($(ARCH),arm64)
    SWIFT_ARCH = arm64-apple-macosx
else
    SWIFT_ARCH = x86_64-apple-macosx
endif

# Colors for output
BOLD := $(shell tput bold)
GREEN := $(shell tput setaf 2)
YELLOW := $(shell tput setaf 3)
RESET := $(shell tput sgr0)

.PHONY: all build build-debug build-release install install-symlinks uninstall update test clean help

# Default target
all: build

## help: Show this help message
help:
	@echo "$(BOLD)SwiftClaw - Makefile Help$(RESET)"
	@echo ""
	@echo "$(BOLD)Available targets:$(RESET)"
	@echo "  $(GREEN)make build$(RESET)         - Build executable (release mode)"
	@echo "  $(GREEN)make build-debug$(RESET)   - Build executable (debug mode)"
	@echo "  $(GREEN)make build-release$(RESET) - Build executable (release mode, optimized)"
	@echo "  $(GREEN)make install$(RESET)       - Install executable to $(BINDIR)"
	@echo "  $(GREEN)make install-symlinks$(RESET) - Install with symlinks"
	@echo "  $(GREEN)make update$(RESET)        - Rebuild and reinstall"
	@echo "  $(GREEN)make uninstall$(RESET)     - Remove installed executable"
	@echo "  $(GREEN)make test$(RESET)          - Run all tests"
	@echo "  $(GREEN)make test-unit$(RESET)     - Run unit tests only"
	@echo "  $(GREEN)make clean$(RESET)         - Clean build artifacts"
	@echo "  $(GREEN)make distclean$(RESET)     - Clean everything including Package.resolved"
	@echo "  $(GREEN)make format$(RESET)        - Format Swift code"
	@echo "  $(GREEN)make lint$(RESET)          - Lint Swift code"
	@echo ""
	@echo "$(BOLD)Configuration:$(RESET)"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  BINDIR=$(BINDIR)"
	@echo "  ARCH=$(ARCH)"

## build: Build executable (release mode)
build: build-release

## build-debug: Build in debug mode
build-debug:
	@echo "$(BOLD)$(GREEN)Building SwiftClaw (debug)...$(RESET)"
	$(SWIFT) build --product $(PRODUCT_NAME_CLI)
	@echo "$(GREEN)✓ Build complete$(RESET)"
	@echo "  CLI: $(BUILD_DIR)/debug/$(PRODUCT_NAME_CLI)"

## build-release: Build in release mode (optimized)
build-release:
	@echo "$(BOLD)$(GREEN)Building SwiftClaw (release)...$(RESET)"
	$(SWIFT) build $(SWIFT_BUILD_FLAGS) --product $(PRODUCT_NAME_CLI)
	@echo "$(GREEN)✓ Build complete$(RESET)"
	@echo "  CLI: $(BUILD_DIR)/release/$(PRODUCT_NAME_CLI)"

## install: Install executable to PREFIX/bin (copy)
install:
	@if [ ! -f "$(PROJECT_DIR)/$(BUILD_DIR)/release/$(PRODUCT_NAME_CLI)" ]; then \
		echo "$(YELLOW)⚠ Release binary not found. Please build first:$(RESET)"; \
		echo "$(YELLOW)  make build$(RESET)"; \
		exit 1; \
	fi
	@echo "$(BOLD)$(GREEN)Installing to $(BINDIR)...$(RESET)"
	@mkdir -p $(BINDIR)
	$(INSTALL) -m 755 $(PROJECT_DIR)/$(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) $(BINDIR)/$(PRODUCT_NAME_CLI)
	@echo "$(GREEN)✓ Installation complete$(RESET)"
	@echo "  Installed: $(BINDIR)/$(PRODUCT_NAME_CLI)"

## install-symlinks: Install with symlinks
install-symlinks:
	@if [ ! -f "$(PROJECT_DIR)/$(BUILD_DIR)/release/$(PRODUCT_NAME_CLI)" ]; then \
		echo "$(YELLOW)⚠ Release binary not found. Please build first:$(RESET)"; \
		echo "$(YELLOW)  make build$(RESET)"; \
		exit 1; \
	fi
	@echo "$(BOLD)$(GREEN)Installing to $(BINDIR) (symlinks)...$(RESET)"
	@mkdir -p $(BINDIR)
	@ln -sf "$(PROJECT_DIR)/$(BUILD_DIR)/release/$(PRODUCT_NAME_CLI)" $(BINDIR)/$(PRODUCT_NAME_CLI)
	@echo "$(GREEN)✓ Installation complete (symlinks)$(RESET)"
	@echo "  Symlinked: $(BINDIR)/$(PRODUCT_NAME_CLI) -> $(PROJECT_DIR)/$(BUILD_DIR)/release/$(PRODUCT_NAME_CLI)"

## update: Rebuild and reinstall
update: build-release
	@if [ -L "$(BINDIR)/$(PRODUCT_NAME_CLI)" ]; then \
		echo "$(GREEN)✓ Update complete! Symlinks automatically use new build.$(RESET)"; \
	else \
		$(MAKE) install; \
		echo "$(GREEN)✓ Update complete! Binary reinstalled.$(RESET)"; \
	fi

## uninstall: Remove installed executable
uninstall:
	@echo "$(BOLD)$(YELLOW)Uninstalling from $(BINDIR)...$(RESET)"
	rm -f $(BINDIR)/$(PRODUCT_NAME_CLI)
	@echo "$(GREEN)✓ Uninstall complete$(RESET)"

## test: Run all tests
test:
	@echo "$(BOLD)$(GREEN)Running all tests...$(RESET)"
	$(SWIFT) test
	@echo "$(GREEN)✓ All tests passed$(RESET)"

## test-unit: Run unit tests only
test-unit:
	@echo "$(BOLD)$(GREEN)Running unit tests...$(RESET)"
	$(SWIFT) test
	@echo "$(GREEN)✓ Unit tests passed$(RESET)"

## clean: Clean build artifacts
clean:
	@echo "$(BOLD)$(YELLOW)Cleaning build artifacts...$(RESET)"
	$(SWIFT) package clean
	rm -rf $(BUILD_DIR)
	@echo "$(GREEN)✓ Clean complete$(RESET)"

## distclean: Clean everything including Package.resolved
distclean: clean
	@echo "$(BOLD)$(YELLOW)Removing Package.resolved...$(RESET)"
	rm -f Package.resolved
	@echo "$(GREEN)✓ Distclean complete$(RESET)"

## format: Format Swift code
format:
	@if command -v swift-format >/dev/null 2>&1; then \
		echo "$(BOLD)$(GREEN)Formatting Swift code...$(RESET)"; \
		find Sources Tests -name "*.swift" -exec swift-format -i {} \;; \
		echo "$(GREEN)✓ Format complete$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ swift-format not found. Install: brew install swift-format$(RESET)"; \
		exit 1; \
	fi

## lint: Lint Swift code
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		echo "$(BOLD)$(GREEN)Linting Swift code...$(RESET)"; \
		swiftlint; \
		echo "$(GREEN)✓ Lint complete$(RESET)"; \
	else \
		echo "$(YELLOW)⚠ SwiftLint not found. Install: brew install swiftlint$(RESET)"; \
		exit 1; \
	fi

# Development helpers
.PHONY: dev run-cli watch

## dev: Quick development build
dev:
	@$(SWIFT) build

## run-cli: Run CLI in debug mode (pass args with ARGS="...")
run-cli: build-debug
	@echo "$(BOLD)$(GREEN)Running $(PRODUCT_NAME_CLI)...$(RESET)"
	$(BUILD_DIR)/debug/$(PRODUCT_NAME_CLI) $(ARGS)

## watch: Watch for changes and rebuild
watch:
	@if command -v fswatch >/dev/null 2>&1; then \
		echo "$(BOLD)$(GREEN)Watching for changes...$(RESET)"; \
		fswatch -o Sources Tests | xargs -n1 -I{} make build-debug; \
	else \
		echo "$(YELLOW)⚠ fswatch not found. Install: brew install fswatch$(RESET)"; \
		exit 1; \
	fi

# Version information
.PHONY: version

## version: Show version information
version:
	@echo "$(BOLD)SwiftClaw Version Information$(RESET)"
	@if [ -f $(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) ]; then \
		echo "  CLI: $$($(BUILD_DIR)/release/$(PRODUCT_NAME_CLI) --version)"; \
	elif [ -f $(BUILD_DIR)/debug/$(PRODUCT_NAME_CLI) ]; then \
		echo "  CLI: $$($(BUILD_DIR)/debug/$(PRODUCT_NAME_CLI) --version)"; \
	else \
		echo "  $(YELLOW)Not built yet. Run: make build$(RESET)"; \
	fi
	@echo "  Swift: $$($(SWIFT) --version | head -1)"
	@echo "  Architecture: $(ARCH)"

# Shortcuts
.PHONY: b i u t c

b: build
i: install
u: uninstall
t: test
c: clean

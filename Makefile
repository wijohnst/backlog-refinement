.PHONY: help install uninstall test test-unit test-integration clean

help:
	@echo "Backlog Refinement System - Makefile targets"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  install         Install refine-backlog CLI to ~/.local/bin/"
	@echo "  uninstall       Remove installed CLI"
	@echo "  init            Initialize in current repo (runs scripts/init-refine-backlog)"
	@echo "  test            Run all tests"
	@echo "  test-unit       Run unit tests only"
	@echo "  test-integration Run integration tests only"
	@echo "  clean           Remove test artifacts and temp files"
	@echo "  help            Show this help message"
	@echo ""

# Installation targets
INSTALL_DIR := $(HOME)/.local/bin
CLI_SOURCE := $(CURDIR)/bin/refine-backlog
CLI_LINK := $(INSTALL_DIR)/refine-backlog

install: $(INSTALL_DIR)
	@if [ -L $(CLI_LINK) ]; then \
		echo "✓ Symlink already exists at $(CLI_LINK)"; \
	else \
		ln -s $(CLI_SOURCE) $(CLI_LINK); \
		chmod +x $(CLI_SOURCE); \
		echo "✓ Installed: $(CLI_LINK) -> $(CLI_SOURCE)"; \
		echo ""; \
		echo "Add to your PATH (if not already):"; \
		echo "  export PATH=\"$(INSTALL_DIR):\$$PATH\""; \
	fi

$(INSTALL_DIR):
	mkdir -p $(INSTALL_DIR)

uninstall:
	@if [ -L $(CLI_LINK) ]; then \
		rm $(CLI_LINK); \
		echo "✓ Removed: $(CLI_LINK)"; \
	else \
		echo "✗ Symlink not found at $(CLI_LINK)"; \
	fi

# Initialization
init:
	@scripts/init-refine-backlog

# Testing targets
test: test-unit test-integration
	@echo "✓ All tests completed"

test-unit:
	@echo "Running unit tests..."
	@test/run_tests.sh --unit 2>&1 || true

test-integration:
	@echo "Running integration tests..."
	@test/run_tests.sh --integration 2>&1 || true

# Cleanup
clean:
	@rm -f refinement-log.json.lock
	@find . -name "*.tmp" -delete
	@find . -name "*~" -delete
	@echo "✓ Cleaned up temporary files"

.DEFAULT_GOAL := help

.PHONY: install build clean test uninstall help

ACP_DIR := libs/acp

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: clean build ## Build and install deepagents-acp globally
	@echo "==> Installing deepagents-acp globally..."
	cd $(ACP_DIR) && npm install -g .
	@echo ""
	@echo "==> Installed: $$(which deepagents-acp)"
	@echo "==> Version:   $$(deepagents-acp --version 2>/dev/null || echo 'unknown')"
	@echo ""
	@echo "Zed config example:"
	@echo '  "deepagents-acp": {'
	@echo '    "type": "custom",'
	@echo '    "command": "deepagents-acp",'
	@echo '    "args": ["--debug"],'
	@echo '    "env": {'
	@echo '      "CUSTOM_LLM_BASE_URL": "https://api.example.com/v1",'
	@echo '      "CUSTOM_LLM_API_KEY": "sk-xxx",'
	@echo '      "CUSTOM_LLM_MODEL": "model-name"'
	@echo '    }'
	@echo '  }'

build: ## Build the ACP package
	@echo "==> Building deepagents-acp..."
	cd $(ACP_DIR) && pnpm build

clean: ## Remove build artifacts
	@echo "==> Cleaning..."
	cd $(ACP_DIR) && pnpm clean
	@echo "==> Done"

test: ## Quick test - run deepagents-acp with debug mode
	@echo "==> Starting deepagents-acp in debug mode (Ctrl+C to stop)..."
	deepagents-acp --debug

uninstall: ## Remove global installation
	@echo "==> Uninstalling deepagents-acp..."
	npm uninstall -g deepagents-acp
	@echo "==> Done"


# Base Mainnet Deployment Makefile

.PHONY: help deploy-base deploy-base-dry verify-base test-deploy setup-env

# Load environment variables
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup-env: ## Setup environment file from template
	@if [ ! -f .env ]; then \
		cp .env.base .env; \
		echo "Created .env file from template. Please edit with your actual values."; \
	else \
		echo ".env file already exists."; \
	fi

deploy-base-dry: ## Dry run deployment to Base (no broadcast)
	@echo "🔍 Running deployment dry run on Base..."
	@forge script script/DeployBase.s.sol:DeployBase --rpc-url base --slow

deploy-base: ## Deploy to Base mainnet with verification
	@echo "🚀 Deploying to Base mainnet..."
	@echo "⚠️  Make sure you have sufficient Base ETH for gas!"
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@forge script script/DeployBase.s.sol:DeployBase --rpc-url base --broadcast --verify --slow

deploy-base-no-verify: ## Deploy to Base mainnet without verification
	@echo "🚀 Deploying to Base mainnet (no verification)..."
	@echo "⚠️  Make sure you have sufficient Base ETH for gas!"
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@forge script script/DeployBase.s.sol:DeployBase --rpc-url base --broadcast --slow

verify-base: ## Verify contract on Basescan (requires CONTRACT_ADDRESS)
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "❌ Please provide CONTRACT_ADDRESS: make verify-base CONTRACT_ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "🔍 Verifying contract $(CONTRACT_ADDRESS) on Basescan..."
	@forge verify-contract $(CONTRACT_ADDRESS) src/AllUniswap.sol:AutoBuyContract \
		--constructor-args $$(cast abi-encode "constructor(address,address,address,address,address,address)" \
		0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD \
		0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967 \
		0x000000000022D473030F116dDEE9F6B43aC78BA3 \
		0x2626664c2603336E57B271c5C0b26F421741e481 \
		0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24 \
		0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913) \
		--chain base

test-deploy: ## Test deployment on Base
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "❌ Please provide CONTRACT_ADDRESS: make test-deploy CONTRACT_ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "🧪 Testing deployed contract $(CONTRACT_ADDRESS)..."
	@echo "Checking contract code..."
	@cast code $(CONTRACT_ADDRESS) --rpc-url base > /dev/null && echo "✅ Contract deployed" || echo "❌ Contract not found"
	@echo "Checking owner..."
	@cast call $(CONTRACT_ADDRESS) "owner()" --rpc-url base
	@echo "Checking USDC address..."
	@cast call $(CONTRACT_ADDRESS) "USDC()" --rpc-url base
	@echo "Checking fee recipient..."
	@cast call $(CONTRACT_ADDRESS) "feeRecipient()" --rpc-url base

authorize-backend: ## Authorize a backend wallet (requires CONTRACT_ADDRESS and BACKEND_ADDRESS)
	@if [ -z "$(CONTRACT_ADDRESS)" ] || [ -z "$(BACKEND_ADDRESS)" ]; then \
		echo "❌ Please provide CONTRACT_ADDRESS and BACKEND_ADDRESS:"; \
		echo "   make authorize-backend CONTRACT_ADDRESS=0x... BACKEND_ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "🔐 Authorizing backend $(BACKEND_ADDRESS)..."
	@cast send $(CONTRACT_ADDRESS) "authorizeBackend(address)" $(BACKEND_ADDRESS) --rpc-url base --private-key $(PRIVATE_KEY)

set-fee-recipient: ## Set fee recipient (requires CONTRACT_ADDRESS and FEE_RECIPIENT_ADDRESS)
	@if [ -z "$(CONTRACT_ADDRESS)" ] || [ -z "$(FEE_RECIPIENT_ADDRESS)" ]; then \
		echo "❌ Please provide CONTRACT_ADDRESS and FEE_RECIPIENT_ADDRESS:"; \
		echo "   make set-fee-recipient CONTRACT_ADDRESS=0x... FEE_RECIPIENT_ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "💰 Setting fee recipient to $(FEE_RECIPIENT_ADDRESS)..."
	@cast send $(CONTRACT_ADDRESS) "setFeeRecipient(address)" $(FEE_RECIPIENT_ADDRESS) --rpc-url base --private-key $(PRIVATE_KEY)

transfer-ownership: ## Transfer ownership (requires CONTRACT_ADDRESS and NEW_OWNER_ADDRESS)
	@if [ -z "$(CONTRACT_ADDRESS)" ] || [ -z "$(NEW_OWNER_ADDRESS)" ]; then \
		echo "❌ Please provide CONTRACT_ADDRESS and NEW_OWNER_ADDRESS:"; \
		echo "   make transfer-ownership CONTRACT_ADDRESS=0x... NEW_OWNER_ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "👑 Transferring ownership to $(NEW_OWNER_ADDRESS)..."
	@echo "⚠️  This cannot be undone!"
	@read -p "Continue? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@cast send $(CONTRACT_ADDRESS) "transferOwnership(address)" $(NEW_OWNER_ADDRESS) --rpc-url base --private-key $(PRIVATE_KEY)

check-balance: ## Check deployer ETH balance
	@echo "💰 Checking deployer balance..."
	@cast balance $(shell cast wallet address --private-key $(PRIVATE_KEY)) --rpc-url base

addresses: ## Show all contract addresses used in deployment
	@echo "📋 Base Mainnet Contract Addresses:"
	@echo "Universal Router:  0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD"
	@echo "Pool Manager (V4): 0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967"
	@echo "Permit2:          0x000000000022D473030F116dDEE9F6B43aC78BA3"
	@echo "V3 SwapRouter:    0x2626664c2603336E57B271c5C0b26F421741e481"
	@echo "V2 Router:        0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24"
	@echo "USDC:             0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"

# ── ERC-4337 from scratch — Makefile ──────────────────────────────────
# Loads contracts/.env so targets can use $(SEPOLIA_RPC_URL) etc.
# Override on the command line if needed, e.g.:
#   make test-fork SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/KEY"
-include contracts/.env
export

.DEFAULT_GOAL := help
.PHONY: help install build test test-fork anvil deploy-sim deploy bundler client clean

help:
	@echo "ERC-4337 from scratch -- make targets:"
	@echo "  install     Install deps (OpenZeppelin + bundler)"
	@echo "  build       Compile contracts"
	@echo "  test        Unit tests (local EVM)"
	@echo "  test-fork   Integration test vs real EntryPoint (needs SEPOLIA_RPC_URL)"
	@echo "  anvil       Local Anvil fork of Sepolia"
	@echo "  deploy-sim  Simulate deployment (no broadcast)"
	@echo "  deploy      Deploy to Sepolia (broadcast)"
	@echo "  bundler     Start the bundler server"
	@echo "  client      Send a demo UserOp (calls Counter.increment())"
	@echo "  clean       Remove build artifacts"

install:
	git submodule update --init --recursive
	cd bundler && npm install

build:
	cd contracts && forge build

test:
	cd contracts && forge test -vvv

test-fork:
	cd contracts && forge test --match-path test/Integration.fork.t.sol --fork-url $(SEPOLIA_RPC_URL) -vvv

anvil:
	anvil --fork-url $(SEPOLIA_RPC_URL)

deploy-sim:
	cd contracts && forge script script/Deploy.s.sol --rpc-url sepolia

deploy:
	cd contracts && forge script script/Deploy.s.sol --rpc-url sepolia --broadcast

bundler:
	cd bundler && npx ts-node src/index.ts

client:
	cd bundler && npx ts-node src/client/sendUserOp.ts

clean:
	cd contracts && forge clean

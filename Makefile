# ── ERC-4337 from scratch — Makefile ──────────────────────────────────
# Loads contracts/.env so targets can use $(SEPOLIA_RPC_URL) etc.
# Override on the command line if needed, e.g.:
#   make test-fork SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/KEY"
-include contracts/.env
export

.DEFAULT_GOAL := help
.PHONY: help install build test test-fork anvil deploy-sim deploy deploy-v3-sim deploy-v3 deploy-v3-local vector bundler client front clean

help:
	@echo "ERC-4337 from scratch -- make targets:"
	@echo "  install     Install deps (OpenZeppelin + bundler + frontend)"
	@echo "  build       Compile contracts"
	@echo "  test        Unit tests (local EVM)"
	@echo "  test-fork   Integration test vs real EntryPoint (needs SEPOLIA_RPC_URL)"
	@echo "  anvil       Local Anvil fork of Sepolia"
	@echo "  deploy-sim  Simulate V1 deployment (no broadcast)"
	@echo "  deploy      Deploy V1 to Sepolia (broadcast)"
	@echo "  deploy-v3-sim  Simulate V3 deployment (Factory + Paymaster + Counter, no broadcast)"
	@echo "  deploy-v3   Deploy V3 to Sepolia (AccountFactory + Paymaster + Counter, broadcast)"
	@echo "  deploy-v3-local Deploy V3 to a local Anvil fork (127.0.0.1:8545)"
	@echo "  vector      Regenerate the locked WebAuthn P-256 test vector"
	@echo "  bundler     Start the bundler server"
	@echo "  client      Send a demo UserOp (V1 CLI client)"
	@echo "  front       Start the V3 frontend (Vite dev server)"
	@echo "  clean       Remove build artifacts"

install:
	git submodule update --init --recursive
	cd bundler && npm install
	cd frontend && npm install

build:
	cd contracts && forge build

test:
	cd contracts && forge test -vvv

test-fork:
	cd contracts && forge test --match-path test/Integration.fork.t.sol --fork-url $(SEPOLIA_RPC_URL) -vvv

anvil:
	anvil --fork-url $(SEPOLIA_RPC_URL) --chain-id 11155111

deploy-sim:
	cd contracts && forge script script/Deploy.s.sol --rpc-url sepolia

deploy:
	cd contracts && forge script script/Deploy.s.sol --rpc-url sepolia --broadcast

deploy-v3-sim:
	cd contracts && forge script script/DeployPasskey.s.sol --rpc-url sepolia

deploy-v3:
	cd contracts && forge script script/DeployPasskey.s.sol --rpc-url sepolia --broadcast --verify

deploy-v3-local:
	cd contracts && forge script script/DeployPasskey.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

vector:
	cd frontend && npm run gen:vector

bundler:
	cd bundler && npx ts-node src/index.ts

client:
	cd bundler && npx ts-node src/client/sendUserOp.ts

front:
	cd frontend && npm run dev

clean:
	cd contracts && forge clean

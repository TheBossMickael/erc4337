# CLAUDE.md

Guidance for AI assistants and contributors working in this repository.

## Project

ERC-4337 account abstraction implemented from scratch, for learning, deployed on Sepolia
(testnet, no real funds). Three components are built here:

- **SmartAccount** (Solidity) — smart wallet with custom validation logic (`validateUserOp`);
  replaces an EOA.
- **Paymaster** (Solidity) — sponsors the gas on behalf of the user.
- **Bundler** (Node.js / TypeScript) — JSON-RPC server that collects UserOperations and submits
  them to the EntryPoint via `handleOps`.

The **EntryPoint** is intentionally NOT implemented — it is the canonical singleton deployed by
the Ethereum Foundation (`0x4337084d9e255ff0702461cf8895ce9e3b5ff108`, v0.8, on Sepolia).

V1 scope and deliberate simplifications: see [docs/limitations-v1.md](docs/limitations-v1.md).

## Repo structure

```
contracts/   Foundry — SmartAccount, Paymaster, Counter, interfaces, tests, deploy script
bundler/     Node.js — JSON-RPC bundler server + test client
docs/        Architecture & technical documentation
frontend/    Reserved for V2
Makefile     Common commands
```

## Conventions

**Solidity** — `pragma ^0.8.24`; NatSpec + checks-effects-interactions; naming: `_param`
(function params), `s_variable` (storage), `i_variable` (immutable), `CONSTANT`; emit events on
important state changes; never `tx.origin`; always check `msg.sender == entryPoint` in
`validateUserOp` / `validatePaymasterUserOp`.

**TypeScript** — strict mode; `async/await` only (no `.then()`); explicit types, no `any`; one
responsibility per file.

**Git** — commits `type: description` (feat, fix, chore, docs, test); one feature = one branch =
one PR.

## Commands

Via the root Makefile:

```
make build                                # compile contracts
make test                                 # unit tests (local EVM)
make test-fork SEPOLIA_RPC_URL="<rpc>"    # integration test vs the real EntryPoint
make deploy                               # deploy to Sepolia
make bundler                              # start the bundler server
make client                               # send a demo UserOp
```

Full setup & deployment guide: [docs/deployment.md](docs/deployment.md).

## Configuration

Two `.env` files (one per service): `contracts/.env` (Foundry) and `bundler/.env` (bundler).
Copy each from the `.env.example` next to it. Never commit real `.env` files.

## Key references

- ERC-4337 spec — https://eips.ethereum.org/EIPS/eip-4337
- Reference implementation (eth-infinitism) — https://github.com/eth-infinitism/account-abstraction
- viem — https://viem.sh

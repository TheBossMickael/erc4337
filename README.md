# ERC-4337 Account Abstraction — from scratch

> The three ERC-4337 components — **smart account**, **paymaster**, and a **minimal bundler** —
> implemented from scratch (no SDK) to understand account abstraction end to end. Deployed and
> verified on Sepolia.

**Status:** V1 — complete, fully tested, and **deployed + verified on Sepolia**.

## What this is

A hands-on implementation of [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) (account
abstraction). Instead of relying on an SDK (Pimlico, Alchemy, permissionless.js…), each piece is
implemented by hand to understand the full machinery: how a smart account **validates** a
`UserOperation`, how a paymaster **sponsors gas**, and how a bundler turns UserOperations into a
real `handleOps` transaction.

**This is V1** — the foundation: a single-owner account with standard **ECDSA** signature
validation. It is the first milestone of an evolving project: V2 and V3 keep the same architecture
but progressively swap the *validation logic* for richer authentication (a secret question, then
passkeys / Face ID). See the [roadmap](#roadmap).

The **EntryPoint** is the only piece not written here — it is the canonical singleton deployed by
the Ethereum Foundation (`0x4337084d9e255ff0702461cf8895ce9e3b5ff108` on Sepolia).

## Demo

A `UserOperation` that calls `Counter.increment()` on a contract — gas sponsored by the Paymaster,
so the user signs **no Ethereum transaction** and pays **no gas**:

```
$ make client
Counter before: 0
UserOpHash    : 0x0620…7066
Signed by     : 0x2045…49A8   (the account owner)
Counter after : 1  (0 -> 1)
```

→ This exact UserOp on Sepolia:
[Etherscan tx](https://sepolia.etherscan.io/tx/0xd4eafb0fa4355a0455565c5d64b565d8c32fdd9cfcb88bfad18b542bf9198fd7)
(a gasless `handleOps` — the user signs nothing on-chain, the Paymaster covers the gas).

## Scope & philosophy

This is a **deliberately minimal, pedagogical** implementation. Production-grade ERC-4337 stacks
exist and are far more complex — matching them was not the goal. The point was to build and
understand the mechanics myself.

| Focused on (the core) | Deliberately simplified |
|---|---|
| SmartAccount validation logic (how a signature is accepted) | No account factory (CREATE2) — accounts are pre-deployed |
| The full end-to-end flow (client → bundler → EntryPoint → account) | Unconditional paymaster (sponsors everything) |
| Integration with the **real** EntryPoint (fork test vs the live v0.8 contract) | Minimal bundler: 1 UserOp/bundle, no gas estimation, no ERC-7562 |

Reference / production implementations (for comparison):
- eth-infinitism — [account-abstraction](https://github.com/eth-infinitism/account-abstraction) (contracts) · [bundler](https://github.com/eth-infinitism/bundler)
- Production tooling — [Pimlico](https://pimlico.io), [Alchemy Account Kit](https://www.alchemy.com/account-kit), [Stackup](https://www.stackup.sh)

Full list of trade-offs: [docs/limitations-v1.md](docs/limitations-v1.md).

## Architecture

```
User (client) ──signs UserOp──▶ Bundler ──handleOps tx──▶ EntryPoint ──▶ SmartAccount.validate()
                                                                     └──▶ SmartAccount.execute() ──▶ Counter
                                                          (gas sponsored by the Paymaster's deposit)
```

Detailed walkthrough — who signs, who pays, the two verification/execution loops:
[docs/architecture.md](docs/architecture.md).

## Tech stack

- **Solidity + Foundry** — contracts, tests, deployment
- **TypeScript + Node.js + [viem](https://viem.sh)** — bundler
- **OpenZeppelin** — ECDSA signature recovery
- **Sepolia** testnet

## Project structure

```
contracts/   Foundry — SmartAccount, Paymaster, Counter, interfaces, tests, deploy script
bundler/     Node.js — JSON-RPC bundler server + test client
docs/        Architecture & technical documentation
Makefile     Common commands (build, test, deploy, run)
```

## Getting started

Prerequisites: [Foundry](https://book.getfoundry.sh/), Node.js ≥ 18.

```bash
git clone --recursive <repo-url>   # forge-std + OpenZeppelin are git submodules
cd <repo>

make install     # fetch submodules + install bundler dependencies
make build       # compile the contracts
make test        # 19 unit tests (local EVM)
make test-fork SEPOLIA_RPC_URL="<your RPC>"   # integration test vs the real EntryPoint
```

### Run it yourself (end-to-end)

You can run the whole flow two ways:

- **Locally, without spending any ETH** — fork Sepolia with Anvil and run everything against it.
- **On real Sepolia** — deploy and run against the live network.

Both are documented step by step (terminals, `.env` setup) in
[docs/deployment.md](docs/deployment.md). The short version, once the `.env` files are filled:

```bash
make deploy      # deploy SmartAccount + Paymaster + Counter, fund the Paymaster
make bundler     # start the bundler (separate terminal)
make client      # send a gasless UserOp → Counter: 0 -> 1
```

This flow was validated end-to-end both on a Sepolia fork and on **live Sepolia** (see the
transaction above).

## Testing

- **19 unit tests** (local EVM, mocked EntryPoint) — signature validation, access control,
  execution, paymaster, deposits.
- **1 integration test** against the **real** EntryPoint v0.8, run on a Sepolia fork — exercises
  the actual `handleOps` flow (hash format, packing, prefund/paymaster) without spending sETH.

## Deployed on Sepolia (V1)

| Contract | Address (verified on Etherscan) |
|---|---|
| SmartAccount | [`0x6f12…Aa87`](https://sepolia.etherscan.io/address/0x6f129556388aA38C1a627ce857c6553F0873Aa87) |
| Paymaster | [`0x317E…9e2c`](https://sepolia.etherscan.io/address/0x317Eda62C69fbE81ed45aC503a06966244239e2c) |
| Counter | [`0x12dF…d81d`](https://sepolia.etherscan.io/address/0x12dF2717B653E9ad32a0d476998D82CBA378d81d) |

## Documentation

- [Architecture](docs/architecture.md) — the full path of a transaction, who pays the gas
- [Contracts](docs/contracts.md) — SmartAccount, Paymaster, signature convention
- [Bundler](docs/bundler.md) — JSON-RPC server, userOpHash, serialization
- [Deployment](docs/deployment.md) — setup, `.env`, commands, end-to-end test
- [V1 limitations](docs/limitations-v1.md) — deliberate simplifications

## Roadmap

- **V1** (this repo) — ECDSA validation, gasless via paymaster, minimal bundler ✅
- **V2** — custom auth: answering a secret question derives the signing key (local frontend)
- **V3** — passkeys / Face ID (WebAuthn / P-256), web frontend deployed on Vercel

## License

MIT — see [LICENSE](LICENSE).

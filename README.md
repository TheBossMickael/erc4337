# ERC-4337 Account Abstraction — from scratch

> The three ERC-4337 components — **smart account**, **paymaster**, and a **minimal bundler** —
> implemented from scratch (no SDK) to understand account abstraction end to end. **V3** adds
> **passkeys**: tap a button, approve Face ID / Touch ID / Windows Hello, and a real gasless
> transaction happens on Sepolia — no wallet extension, no seed phrase, no gas. The account even
> **deploys itself** on first use.

**Status:** V3 — shipped, deployed + verified on Sepolia, and **hosted live**.

## ▶ Live demo

**[erc4337.onrender.com](https://erc4337.onrender.com)** — open it, tap *Increment the counter*, and
approve your device's biometric prompt. The **first** tap registers a passkey and prompts twice
(register, then sign); later taps prompt once. You sign **no Ethereum transaction**, install **no
wallet**, and pay **no gas** — that is the whole point of ERC-4337 account abstraction.

> Needs a device with a passkey authenticator (Face ID, Touch ID, Windows Hello, or a security
> key). Works in every major desktop browser; **on iPhone/iPad it only works in Safari**.
> Hosted on Render's free tier — the first visit may take ~30-50s to wake the server.

## What this is

A from-scratch implementation of [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) — no SDK
(Pimlico, Alchemy, permissionless.js…): every piece built by hand to understand how account
abstraction actually works. The core idea: **your account is a smart contract that decides what
a valid signature is**. Each version of this project swaps that auth scheme, and nothing else:

- **V1** — a classic **ECDSA** private key (you *hold* a key)
- **V2** — **secret questions** (you *know* the answers)
- **V3** (current) — **passkeys**: your device's biometrics sign, via WebAuthn P-256 (you *are*
  the key — no wallet, no seed phrase)

The only piece not written here is the **EntryPoint** — the canonical contract deployed by the
Ethereum Foundation, which orchestrates everything.

## How the demo works

One tap = one `UserOperation`: your **passkey** signs it (the private key never leaves your
device), the **bundler** wraps it into a single real Ethereum transaction, the **EntryPoint**
verifies the P-256 signature on-chain and runs the action, and the **Paymaster** pays the gas.
On the very first tap, that same transaction also **deploys your smart account** (CREATE2
factory) — the account doesn't exist until you use it.

You never sign an Ethereum transaction and never touch ETH. Full flow:
[docs/architecture.md](docs/architecture.md) · passkeys deep dive:
[docs/v3-passkeys-factory.md](docs/v3-passkeys-factory.md).

## Contracts

One abstract `BaseAccount` owns the whole ERC-4337 lifecycle; each version only swaps the
signature check:

```
BaseAccount (abstract)          the ERC-4337 lifecycle  +  one hook: _validateSignature
 ├─ SmartAccount (V1)           ECDSA — a classic private key
 ├─ SecretQuestionAccount (V2)  ECDSA — key derived from secret answers
 └─ PasskeyAccount (V3)         WebAuthn P-256 — the device's authenticator signs

AccountFactory (V3)             CREATE2 — deploys accounts inside their first UserOp
```

## Tech stack

- **Solidity + Foundry** — contracts, tests, deployment
- **TypeScript + Node.js + [viem](https://viem.sh)** — bundler + counterfactual UserOp flow
- **React + Vite** — frontend (single fused passkey button)
- **OpenZeppelin** — `WebAuthn` + `P256` (V3), ECDSA (V1/V2), Create2
- **[@noble/curves](https://github.com/paulmillr/noble-curves)** — off-chain DER/low-s parsing
- **WebAuthn** (`navigator.credentials`) — passkey registration & signing
- **Sepolia** testnet · **Render** hosting

## Project structure

```
contracts/   Foundry — BaseAccount, SmartAccount, SecretQuestionAccount, PasskeyAccount, AccountFactory, Paymaster, Counter, tests
bundler/     Node.js — JSON-RPC bundler (/rpc) + serves the frontend build
frontend/    React + Vite — passkey wallet (single fused button) + WebAuthn library
docs/        Architecture & technical documentation
render.yaml  Single-service hosting (bundler serves the frontend)
Makefile     Common commands (build, test, deploy-v3, vector, bundler, front)
```

## Getting started

Prerequisites: [Foundry](https://book.getfoundry.sh/), Node.js ≥ 18.

```bash
git clone --recursive https://github.com/TheBossMickael/erc4337.git   # forge-std + OpenZeppelin are git submodules
cd erc4337

make install     # submodules + bundler & frontend dependencies
make build       # compile the contracts
make test        # Solidity unit tests (local EVM)
make test-fork SEPOLIA_RPC_URL="<your RPC>"   # integration test vs the real EntryPoint (+ P-256 precompile)
```

## Testing

- **Solidity unit tests** (local EVM): validation, access control, execution, paymaster, factory —
  every account version.
- **Fork tests** against the **real** EntryPoint v0.8 (and V3's P-256 precompile) on a Sepolia fork.
- **Locked WebAuthn vector**, asserted on both sides (Solidity + TS) — Foundry cannot sign P-256,
  so the vector is generated once (`make vector`); if the signature format drifts, both worlds break.
- **Frontend Vitest**: the WebAuthn parsing/encoding helpers.

## Deployed on Sepolia

### V3 (current)

| Contract | Address (verified on Etherscan) |
|---|---|
| AccountFactory | [`0x28d7…Ac1a`](https://sepolia.etherscan.io/address/0x28d7291A4D81A2372b923b2aCb87B3e93C84Ac1a) |
| Paymaster | [`0x93ba…d314`](https://sepolia.etherscan.io/address/0x93ba5Cec8f2E500FF54d007c98AE53eEd7a1d314) |
| Counter | [`0x3921…b48d`](https://sepolia.etherscan.io/address/0x3921D645a40d7e1E155d7f58207193976EbAb48d) |

PasskeyAccounts are **counterfactual** — each is created lazily inside its owner's first UserOp, so
there is no single "demo account" address (one passkey = one account).

### V2 — auth by knowledge

| Contract | Address (verified on Etherscan) |
|---|---|
| SecretQuestionAccount (demo) | [`0xE4c8…324C`](https://sepolia.etherscan.io/address/0xE4c8C009A84E1d279fd5b0e4fB597374d332324C) |
| Paymaster | [`0x73B4…C57D`](https://sepolia.etherscan.io/address/0x73B4f9E64A36a82bcCbAE8c44a098446c444C57D) |
| Counter | [`0xb73D…5F1D`](https://sepolia.etherscan.io/address/0xb73D44DeaceAdCBf060A11c9f5A22AE9dccb5F1D) |

### V1 — single-owner ECDSA

| Contract | Address (verified on Etherscan) |
|---|---|
| SmartAccount | [`0x6f12…Aa87`](https://sepolia.etherscan.io/address/0x6f129556388aA38C1a627ce857c6553F0873Aa87) |
| Paymaster | [`0x317E…9e2c`](https://sepolia.etherscan.io/address/0x317Eda62C69fbE81ed45aC503a06966244239e2c) |
| Counter | [`0x12dF…d81d`](https://sepolia.etherscan.io/address/0x12dF2717B653E9ad32a0d476998D82CBA378d81d) |

## Hosting

Hosted live on **Render** as a single web service — [erc4337.onrender.com](https://erc4337.onrender.com).
Config: [render.yaml](render.yaml). WebAuthn requires HTTPS, which the Render URL provides.

## Documentation

Recommended reading order — each builds on the previous one:

1. [Architecture](docs/architecture.md) — the full path of a transaction, who pays the gas
2. [Contracts](docs/contracts.md) — BaseAccount, the account hierarchy, signature convention
3. [Bundler](docs/bundler.md) — JSON-RPC server, simulation, userOpHash, serialized submission
4. [V3 — passkeys + factory](docs/v3-passkeys-factory.md) — WebAuthn/P-256, counterfactual deployment
5. [Limitations](docs/limitations.md) — deliberate simplifications (V1, V2 & V3)

V2's write-up (key derivation from secret answers) lives with its release, at tag
[`v2.0.0`](https://github.com/TheBossMickael/erc4337/blob/v2.0.0/docs/v2-auth-by-knowledge.md).

## Roadmap

- **V1** — ECDSA validation, gasless via paymaster, minimal bundler ✅
- **V2** — auth by knowledge (secret questions), React frontend, deployed + hosted ✅
- **V3** (current) — passkeys / WebAuthn (P-256) + counterfactual factory, **deployed + hosted** ✅

## License

MIT — see [LICENSE](LICENSE).

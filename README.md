# ERC-4337 Account Abstraction — from scratch

> The three ERC-4337 components — **smart account**, **paymaster**, and a **minimal bundler** —
> implemented from scratch (no SDK) to understand account abstraction end to end. **V3** adds
> **passkeys**: tap a button, approve Face ID / Touch ID / Windows Hello, and a real gasless
> transaction happens on Sepolia — no wallet extension, no seed phrase, no gas. The account even
> **deploys itself** on first use (counterfactual factory + `initCode`).

**Status:** V3 — shipped, deployed + verified on Sepolia, and **hosted live**.

## ▶ Live demo

**[erc4337.onrender.com](https://erc4337.onrender.com)** — open it, tap *Increment the counter*, and
approve your device's biometric prompt. The **first** tap registers a passkey and prompts twice
(register, then sign); later taps prompt once. You sign **no Ethereum transaction**, install **no
wallet**, and pay **no gas** — that is the whole point of ERC-4337 account abstraction.

> Requires a browser/device with a passkey authenticator (Face ID, Touch ID, Windows Hello, or a
> security key) and a secure (HTTPS) context. Works in Chrome, Edge, Firefox and Safari on desktop,
> and in Safari on iOS. **On iPhone/iPad, use Safari** — Apple restricts passkey access to Safari
> there, so third-party iOS browsers (Chrome, Firefox, Edge) return a permission error.
> Hosted on Render's free tier — the first visit after a while may take ~30-50s to wake the server.

## What this is

A hands-on implementation of [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337). Instead of an SDK
(Pimlico, Alchemy, permissionless.js…), each piece is built by hand to understand the full
machinery: how a smart account **validates** a `UserOperation`, how a paymaster **sponsors gas**, how
a bundler turns UserOperations into a real `handleOps` transaction, and how a factory **deploys the
account on the fly**.

The project evolves in milestones that keep the **same architecture** (a `BaseAccount` Template
Method) and swap only the *validation logic*:

- **V1** — single-owner **ECDSA** account (auth by *possession*: you hold a key).
- **V2** — **auth by knowledge**: 3 secret questions derive the signing key in the browser; the
  account stores only the derived address.
- **V3** (current) — **passkeys / WebAuthn (P-256)**: the device's authenticator signs; the account
  stores only the public key `(x, y)`. Plus a **CREATE2 factory** for counterfactual deployment.

The **EntryPoint** is the only piece not written here — the canonical singleton deployed by the
Ethereum Foundation (`0x4337084d9e255ff0702461cf8895ce9e3b5ff108` on Sepolia).

## V3 — Passkeys + counterfactual factory

Two additions, both proving the `BaseAccount` refactor holds — a new scheme touches only two hooks:

1. **`PasskeyAccount`** — validated by a **WebAuthn passkey** (P-256 / secp256r1). The private key is
   generated and held by the authenticator (Secure Enclave / TPM / security key) and **never leaves
   the device**. On-chain verification uses OpenZeppelin's audited `WebAuthn` + `P256` libraries
   (EIP-7951 precompile at `0x100`, with a Solidity fallback).
2. **`AccountFactory`** — CREATE2, **idempotent**. The account address is computed off-chain
   (`factory.getAddress`) before it exists, and the real deployment is bundled into the account's
   **first UserOp** via `initCode`. This removed V2's `/deploy` endpoint and its server-side deployer
   key: deployment is now paid out of the normal `handleOps` flow.

```
Browser (passkey signs userOpHash with Face ID / Touch ID / Windows Hello)
   │  POST /rpc (eth_sendUserOperation) — first op carries initCode (factory + createAccount)
   ▼
Bundler ──simulate (eth_call), then handleOps tx──▶ EntryPoint
                                        ├─(first op)─▶ AccountFactory.createAccount (CREATE2 deploy)
                                        ├──────────▶ PasskeyAccount.validate()  (WebAuthn + P-256)
                                        └──────────▶ PasskeyAccount.execute() ──▶ Counter
                                        (gas sponsored by the Paymaster's deposit)
```

The user never signs an Ethereum transaction — the **bundler** does that (and pays), reimbursed by
the **Paymaster**. Deep dive: [docs/v3-passkeys-factory.md](docs/v3-passkeys-factory.md).

## Contracts

A **Template Method** hierarchy isolates the one thing that changes between auth schemes:

```
BaseAccount (abstract)          validateUserOp / execute / prefund / deposit  +  _validateSignature (hook)
 ├─ SmartAccount (V1)           secp256k1 · _validateSignature = ECDSA recover == s_owner
 ├─ SecretQuestionAccount (V2)  secp256k1 · _validateSignature = ECDSA recover == s_signerAddress
 └─ PasskeyAccount (V3)         secp256r1 · _validateSignature = WebAuthn.verify(userOpHash, (x, y))

AccountFactory (V3)  CREATE2, idempotent — counterfactual deployment via initCode
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

- **Solidity unit tests** (local EVM, mocked EntryPoint): signature validation, access control,
  execution, paymaster, deposits — for `SmartAccount`, `SecretQuestionAccount`, `PasskeyAccount`,
  plus `AccountFactory` (idempotence, CREATE2 determinism).
- **Fork tests** against the **real** EntryPoint v0.8 on a Sepolia fork (V1, V2, and V3's real P-256
  precompile at `0x100`) — the actual `handleOps` flow without spending sETH.
- **Locked WebAuthn vector** cross-checked on both sides: the same P-256 assertion is asserted
  on-chain ([WebAuthnVector.sol](contracts/test/fixtures/WebAuthnVector.sol)) and off-chain
  ([webauthn.test.ts](frontend/src/lib/webauthn.test.ts)). Foundry has no P-256 signing cheatcode, so
  the vector is generated once by `make vector` and locked — if the format changes, both worlds break.
- **Frontend Vitest**: SPKI→(x,y), DER→(r,s) with low-s normalization, and the naked-tuple signature
  encoding.

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
3. [Bundler](docs/bundler.md) — JSON-RPC server, simulation, userOpHash, serialization
4. [V2 — auth by knowledge](docs/v2-auth-by-knowledge.md) — key derivation from answers
5. [V3 — passkeys + factory](docs/v3-passkeys-factory.md) — WebAuthn/P-256, counterfactual deployment
6. [Limitations](docs/limitations.md) — deliberate simplifications (V1, V2 & V3)

## Roadmap

- **V1** — ECDSA validation, gasless via paymaster, minimal bundler ✅
- **V2** — auth by knowledge (secret questions), React frontend, deployed + hosted ✅
- **V3** (current) — passkeys / WebAuthn (P-256) + counterfactual factory, **deployed + hosted** ✅

## License

MIT — see [LICENSE](LICENSE).

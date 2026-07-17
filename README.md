# ERC-4337 Account Abstraction — from scratch

> The three ERC-4337 components — **smart account**, **paymaster**, and a **minimal bundler** —
> implemented from scratch (no SDK) to understand account abstraction end to end. **V2** adds
> authentication **by knowledge**: answer 3 secret questions and a real gasless transaction happens
> on Sepolia — no wallet extension, no seed phrase, no gas.

**Status:** V2 — shipped, deployed + verified on Sepolia. No longer hosted live (see below).

## ▶ Live demo

**No longer hosted.** [erc4337.onrender.com](https://erc4337.onrender.com) now serves **V3**
(WebAuthn passkeys) — the same Render service was reused for the newer milestone instead of
running a second one. The V2 contracts are still deployed and verified on Sepolia (see
[Deployed on Sepolia](#deployed-on-sepolia)); there is just no public URL running this V2
frontend anymore. For the current live demo, see the
[main branch](https://github.com/TheBossMickael/erc4337).

## What this is

A hands-on implementation of [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337). Instead of an SDK
(Pimlico, Alchemy, permissionless.js…), each piece is built by hand to understand the full
machinery: how a smart account **validates** a `UserOperation`, how a paymaster **sponsors gas**,
and how a bundler turns UserOperations into a real `handleOps` transaction.

The project evolves in milestones that keep the **same architecture** and swap only the
*validation logic*:

- **V1** — single-owner **ECDSA** account (auth by *possession*: you hold a key).
- **V2** (current) — **auth by knowledge**: 3 secret questions derive the signing key in the
  browser; the account stores only the derived address.
- **V3** — passkeys / Face ID (WebAuthn / P-256).

The **EntryPoint** is the only piece not written here — the canonical singleton deployed by the
Ethereum Foundation (`0x4337084d9e255ff0702461cf8895ce9e3b5ff108` on Sepolia).

## V2 — Authentication by knowledge (secret questions)

The V1→V2 jump is **not** a change of curve (still ECDSA secp256k1) — it is a change of **auth
model**: from *possession* (I hold a private key) to *knowledge* (I know the answers).

```
answers ──KDF(salt || answers)──▶ private key ──▶ address
                                                    │
                     stored on-chain as s_signerAddress — never the answers themselves
```

- The browser derives the key from the answers and **signs the `userOpHash`**; the contract checks
  `recover(hash, sig) == s_signerAddress`. Correctness is never compared in clear text — it is
  **proven by the signature**.
- Two screens:
  - **USE** — answer the questions on the shared demo account → gasless `Counter.increment()`.
  - **SETUP** — pick *your own* secret answers → a backend endpoint deploys a fresh
    `SecretQuestionAccount` for the derived address (the deployer key stays server-side,
    *deployer ≠ signer*).
- The bundler **simulates** each UserOp (`eth_call`) before submitting, so a wrong answer is
  rejected for free — no gas spent, no failed transaction.

Deep dive: [docs/v2-auth-by-knowledge.md](docs/v2-auth-by-knowledge.md).

### Security model — read this

This is a **brain wallet**: *the answers ARE the private key.* Public or weak answers ⇒ the account
is drainable by anyone who guesses them. This demo uses **public answers on purpose**
(`rex` / `paris` / `inception`) so the demo is reproducible — they are **intentionally insecure**.

A real deployment would harden this with:
- **secret, high-entropy answers** chosen by each user (never published);
- a **slow KDF** (scrypt / Argon2) instead of `keccak256`, to resist brute force;
- a per-user **salt**.

The design already supports secret answers (SETUP lets each user choose their own). Being honest
about the insecurity of the *public* demo is the point — not pretending it is safe.

## Architecture

```
Browser (derives key from answers, signs userOpHash)
   │  POST /rpc (eth_sendUserOperation)
   ▼
Bundler ──simulate (eth_call), then handleOps tx──▶ EntryPoint ──▶ SecretQuestionAccount.validate()
                                                              └──▶ SecretQuestionAccount.execute() ──▶ Counter
                                                   (gas sponsored by the Paymaster's deposit)
```

The signature over the canonical `userOpHash` is what proves knowledge of the answers. The user
never signs an Ethereum transaction — the **bundler** does that (and pays), reimbursed by the
**Paymaster**. Detailed walkthrough: [docs/architecture.md](docs/architecture.md).

## Contracts

A small **Template Method** hierarchy isolates the one thing that changes between auth schemes:

```
BaseAccount (abstract)          validateUserOp / execute / prefund / deposit  +  _validateSignature (hook)
 ├─ SmartAccount (V1)           _validateSignature = ECDSA recover == s_owner
 └─ SecretQuestionAccount (V2)  _validateSignature = ECDSA recover == s_signerAddress
```

A future `PasskeyAccount` (V3) will just override `_validateSignature` with a P-256/WebAuthn check.

## Tech stack

- **Solidity + Foundry** — contracts, tests, deployment
- **TypeScript + Node.js + [viem](https://viem.sh)** — bundler + key derivation
- **React + Vite** — frontend (USE / SETUP)
- **OpenZeppelin** — ECDSA signature recovery
- **Sepolia** testnet · **Render** hosting

## Project structure

```
contracts/   Foundry — BaseAccount, SmartAccount, SecretQuestionAccount, Paymaster, Counter, tests, deploy scripts
bundler/     Node.js — JSON-RPC bundler (/rpc) + SETUP deploy endpoint (/deploy) + serves the frontend build
frontend/    React + Vite — secret-question wallet (USE / SETUP), key derivation library
docs/        Architecture & technical documentation
render.yaml  Single-service hosting (bundler serves the frontend)
Makefile     Common commands (build, test, deploy, run, front)
```

## Getting started

Prerequisites: [Foundry](https://book.getfoundry.sh/), Node.js ≥ 18.

```bash
git clone --recursive https://github.com/TheBossMickael/erc4337.git   # forge-std + OpenZeppelin are git submodules
cd erc4337

make install     # submodules + bundler & frontend dependencies
make build       # compile the contracts
make test        # Solidity unit tests (local EVM)
make test-fork SEPOLIA_RPC_URL="<your RPC>"   # integration test vs the real EntryPoint
```

## Testing

- **Solidity — 32 unit tests** (local EVM, mocked EntryPoint): signature validation, access
  control, execution, paymaster, deposits, for both `SmartAccount` and `SecretQuestionAccount`.
- **2 integration tests** against the **real** EntryPoint v0.8 on a Sepolia fork (V1 + V2) —
  exercises the actual `handleOps` flow without spending sETH.
- **TS ↔ Solidity cross-check**: the key/address derived by the frontend
  ([`derive.ts`](frontend/src/lib/derive.ts)) is asserted on-chain (a Solidity test signs with the
  frontend-derived key and expects `validateUserOp == 0`). If the derivation changes, both worlds
  break together.
- **Frontend — 6 Vitest tests** on the derivation (determinism, normalization, locked demo vector).

## Deployed on Sepolia

### V2 (current)

| Contract | Address (verified on Etherscan) |
|---|---|
| SecretQuestionAccount (demo) | [`0xE4c8…324C`](https://sepolia.etherscan.io/address/0xE4c8C009A84E1d279fd5b0e4fB597374d332324C) |
| Paymaster | [`0x73B4…C57D`](https://sepolia.etherscan.io/address/0x73B4f9E64A36a82bcCbAE8c44a098446c444C57D) |
| Counter | [`0xb73D…5F1D`](https://sepolia.etherscan.io/address/0xb73D44DeaceAdCBf060A11c9f5A22AE9dccb5F1D) |

Demo signer derived from `rex` / `paris` / `inception`: `0x6791C67E22f99Cf7D019f6e5D4009E9BDB853ACa`.

### V1

| Contract | Address (verified on Etherscan) |
|---|---|
| SmartAccount | [`0x6f12…Aa87`](https://sepolia.etherscan.io/address/0x6f129556388aA38C1a627ce857c6553F0873Aa87) |
| Paymaster | [`0x317E…9e2c`](https://sepolia.etherscan.io/address/0x317Eda62C69fbE81ed45aC503a06966244239e2c) |
| Counter | [`0x12dF…d81d`](https://sepolia.etherscan.io/address/0x12dF2717B653E9ad32a0d476998D82CBA378d81d) |

## Hosting

No longer hosted live — [erc4337.onrender.com](https://erc4337.onrender.com) now serves **V3**
(same Render service, reused rather than duplicated). Config for this V2 service was
[render.yaml](render.yaml); the contracts above remain deployed and verified on Sepolia.

## Documentation

Recommended reading order — each builds on the previous one:

1. [Architecture](docs/architecture.md) — the full path of a transaction, who pays the gas
2. [Contracts](docs/contracts.md) — BaseAccount, SecretQuestionAccount, Paymaster, signature convention
3. [Bundler](docs/bundler.md) — JSON-RPC server, `/deploy`, simulation, userOpHash, serialization
4. [V2 — auth by knowledge](docs/v2-auth-by-knowledge.md) — derivation, the two screens, hosting, pitfalls
5. [Limitations](docs/limitations.md) — deliberate simplifications (V1 & V2)

## Roadmap

- **V1** — ECDSA validation, gasless via paymaster, minimal bundler ✅
- **V2** (current) — auth by knowledge (secret questions), React frontend, **deployed + hosted** ✅
- **V3** — passkeys / Face ID (WebAuthn / P-256)

## License

MIT — see [LICENSE](LICENSE).

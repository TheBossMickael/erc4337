# ERC-4337 Architecture — The full path of a transaction

> Goal: describe **exactly** the journey of a user action, from the client to on-chain
> execution, and clarify **who pays the gas and with which ETH** at each step.

---

## 0. Recap — the path of a classic Ethereum transaction (EOA)

To understand what ERC-4337 changes, you first need the "normal" path of a transaction sent
from an EOA (the case of a MetaMask-style wallet).

```
┌──────────┐   signs with its    ┌──────────────┐   includes the tx ┌─────────┐
│   EOA    │   private key       │  P2P network │   in a block      │ Miner/  │
│  (user)  │ ──── secp256k1 ───▶ │  (mempool)   │ ────────────────▶ │ Valid.  │
└──────────┘                     └──────────────┘                   └─────────┘
     │                                                                    │
     │  the tx already contains: from, to, value, data, gas, nonce, sig   │
     └──────────── the sender pays the gas IN ETH, themselves ───────────┘
```

In this model: the EOA **is** the account (a key pair, no code); the only authorization the
protocol can verify is the secp256k1 signature; and **`from` = the one who signs = the one who
pays, in ETH, from their own balance** — no ETH, no action. It is this rigid fusion that
ERC-4337 decouples.

---

## 1. The core idea: decouple 3 roles that used to be fused

| Question | Classic EOA | ERC-4337 |
|---|---|---|
| **Who decides if the action is authorized?** | The protocol (secp256k1 check) | The **account** (custom Solidity code) |
| **Who sends the tx to the network?** | The sending EOA | The **Bundler** (a third-party EOA) |
| **Who pays the gas in native ETH?** | The sender | The sender **OR a Paymaster** |

ERC-4337 **does not bypass** Ethereum's cryptography: a *real* secp256k1-signed transaction is
still what reaches the network — the **Bundler**'s. What moves is the decision "is this action
authorized?", from the protocol into a **smart contract** — which can then accept other schemes.
V3 does exactly that with WebAuthn P-256 passkeys; multisig or session keys would slot in the
same way.

---

## 2. The full path of a UserOperation (ERC-4337)

```
   OFF-CHAIN                                      ON-CHAIN (Sepolia)
 ───────────────────────────────          ──────────────────────────────────────

 ┌─────────────┐
 │    User     │  1. creates a UserOperation (intent)
 │  (client)   │  2. SIGNS it (scheme depends on the version — see note *)
 └──────┬──────┘
        │ 3. eth_sendUserOperation (HTTP JSON-RPC)
        ▼
 ┌─────────────┐
 │   BUNDLER   │  4. basic validation of the UserOp
 │  (Node.js,  │  5. builds ONE real Ethereum tx:
 │   an EOA)   │     handleOps([userOp], beneficiary)
 └──────┬──────┘  6. signs it with ITS OWN key + pays the network gas IN ETH
        │
        │ 7. tx sent to the network ─────────────────┐
        │                                            ▼
        │                                   ┌───────────────────┐
        │                                   │    ENTRYPOINT     │  (deployed by the EF,
        │                                   │   (singleton)     │   not by us)
        │                                   └─────────┬─────────┘
        │                                             │
        │             ╔═══════ VERIFICATION LOOP ═════╪═══════════════════╗
        │             ║                               ▼                   ║
        │             ║   8a. validateUserOp() ──▶ ┌──────────────┐       ║
        │             ║       (signature check)    │   ACCOUNT *  │       ║
        │             ║                            └──────────────┘       ║
        │             ║   8b. validatePaymasterUserOp() ──▶ ┌──────────┐  ║
        │             ║       (does the paymaster accept?)  │ PAYMASTER│  ║
        │             ║                                     └──────────┘  ║
        │             ║   8c. checks the deposits cover the max cost      ║
        │             ╚═══════════════════════════════════════════════════╝
        │                                             │
        │             ╔═══════ EXECUTION LOOP ════════╪═══════════════════╗
        │             ║                               ▼                   ║
        │             ║   9a. runs the callData ───▶ ┌──────────────┐     ║
        │             ║       (the real action)      │  ACCOUNT *   │     ║
        │             ║                              │  .execute()  │     ║
        │             ║                              └──────────────┘     ║
        │             ║   9b. postOp() ──▶ ┌──────────┐ (reconcile cost)  ║
        │             ║                    │ PAYMASTER│                   ║
        │             ║                    └──────────┘                   ║
        │             ║   9c. refunds the surplus, pays the BENEFICIARY   ║
        │             ║       (= the bundler, in ETH) ◀───────────────────╫───┐
        │             ╚═══════════════════════════════════════════════════╝   │
        └─────────────────── the bundler recovers its advanced ETH ───────────┘
```

> \* **"ACCOUNT"** is generic here: `SmartAccount` in V1 (ECDSA, the owner holds the key),
> `SecretQuestionAccount` in V2 (ECDSA, key derived client-side from secret answers) or
> `PasskeyAccount` in V3 (WebAuthn — the device's P-256 authenticator signs). All extend the same
> abstract `BaseAccount` — only the signature *check* differs (`_validateSignature`). Details:
> [contracts.md](./contracts.md).

### Three key points of the flow

1. **The account is passive.** It sends nothing on its own: the **Bundler** sends the
   `handleOps()` transaction; the account only *responds* when the EntryPoint calls it.

2. **The EntryPoint calls the account TWICE, separately**: first `validateUserOp()` ("is this
   signature valid?"), then — after validating the Paymaster and checking the funds — the
   execution of the `callData`. Hence the two loops: validate everything first, execute next.

3. **The account may not even exist yet (V3).** If `sender` has no code and the UserOp carries
   an `initCode`, the EntryPoint first calls the **AccountFactory** (CREATE2) to deploy it —
   inside the same `handleOps`, just before step 8a. Deployment is simply one more sponsored
   step of the first UserOp. Details: [v3-passkeys-factory.md](./v3-passkeys-factory.md).

---

## 3. Why two separate loops? (verification then execution)

An **economic protection for the bundler**. The bundler spends its own ETH on `handleOps()` and
needs the guarantee of being reimbursed. By **validating everything first** (and checking the
deposits cover the max cost of the *whole* bundle), the EntryPoint guarantees the bundle is
profitable *before* spending the expensive execution gas — otherwise a late UserOp could
invalidate the earlier ones after their gas was already burned.

---

## 4. Who pays the gas, and with which ETH?

The most common source of confusion — there are **two distinct "gas" levels**.

**Level 1 — the network gas.** `handleOps()` is a real Ethereum transaction: like any tx,
someone must sign it and advance the ETH — the **Bundler**. It must always hold native ETH.

**Level 2 — the bundler's reimbursement.** At the end of `handleOps()`, the EntryPoint
reimburses the bundler (the `beneficiary`). With whose ETH? Two cases:

- **Case A — without a Paymaster: the account pays.** The account must hold an ETH deposit on
  the EntryPoint; `_payPrefund()` (in `BaseAccount.sol`, shared by every account version) tops
  up the missing difference. The need for ETH has not disappeared — only the "sign" (owner) and
  "send" (bundler) roles were decoupled.
- **Case B — with a Paymaster: a third party pays.** With a non-empty `paymasterAndData`, the
  account sends nothing and the **Paymaster's deposit** covers the cost — after the EntryPoint
  asked it via `validatePaymasterUserOp()` (ours accepts everything; a real one would filter).
  **The user needs NO ETH** — this is "gasless": the user signs, a third party pays.

### Summary table "who needs ETH?"

| Actor | Needs native ETH? | Why |
|---|---|---|
| **User (owner/signer)** | ❌ with Paymaster / ✅ without | Without a Paymaster, their account funds the prefund |
| **Account** | ✅ without Paymaster / ❌ with | Source of the reimbursement when there is no sponsor |
| **Bundler** | ✅ **always** | Signs and advances the gas of the real `handleOps()` tx |
| **Paymaster** | ✅ if used | Reimburses the bundler instead of the user |
| **EntryPoint** | ❌ | It only keeps the deposit accounting |

In practice on a testnet you must fund the **Bundler** (always) and, depending on the mode,
either the account or the **Paymaster**.

---

## 5. Components recap

| Component | Nature | Built in this project? | Role in one sentence |
|---|---|---|---|
| `PackedUserOperation` | struct | ✅ (interface) | The user's signed intent — what these docs informally call "the UserOp" |
| `BaseAccount` | abstract Solidity contract | ✅ | Shared validate/execute/prefund logic; `_validateSignature` is the hook |
| `SmartAccount` (V1) | Solidity contract | ✅ | `BaseAccount` + ECDSA against a fixed `s_owner` |
| `SecretQuestionAccount` (V2) | Solidity contract | ✅ | `BaseAccount` + ECDSA against a KDF-derived `s_signerAddress` |
| `PasskeyAccount` (V3) | Solidity contract | ✅ | `BaseAccount` + WebAuthn P-256 against a stored public key `(x, y)` |
| `AccountFactory` (V3) | Solidity contract | ✅ | CREATE2 factory — counterfactual deployment via `initCode` |
| `Paymaster` | Solidity contract | ✅ | Sponsors the gas for the user |
| `Counter` | Solidity contract | ✅ | Demo witness contract (UserOps target) |
| `Bundler` | Node.js server | ✅ | Collects UserOps, simulates, sends `handleOps` one at a time |
| `EntryPoint` | Singleton contract | ❌ (deployed by the EF) | Orchestrates validation + execution |

---

## 6. Going further

- Contract details (validation, signature, factory): [contracts.md](./contracts.md)
- Bundler details (JSON-RPC, simulation, serialized submission): [bundler.md](./bundler.md)
- V2 auth-by-knowledge specifics: the V2 doc at tag [`v2.0.0`](https://github.com/TheBossMickael/erc4337/blob/v2.0.0/docs/v2-auth-by-knowledge.md)
- V3 passkeys + counterfactual factory: [v3-passkeys-factory.md](./v3-passkeys-factory.md)
- Deliberate simplifications (V1–V3): [limitations.md](./limitations.md)

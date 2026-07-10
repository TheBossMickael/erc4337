# Limitations — deliberate simplifications (V1, V2 & V3)

> These choices are **intentional** (pedagogical project, one trusted account, testnet).
> They are NOT bugs. This document exists so they are not mistaken for errors, and lists what
> a production version would need to fix.
>
> **Scope.** The **bundler** and **paymaster** are shared infrastructure across V1/V2/V3 — most of
> what follows applies to all three (V3 removed the bundler's `/deploy` endpoint; the relay +
> simulate core is otherwise unchanged). Only the *account* differs (validation logic), covered in
> [contracts.md](contracts.md), [v2-auth-by-knowledge.md](v2-auth-by-knowledge.md) and
> [v3-passkeys-factory.md](v3-passkeys-factory.md).

## Caveats / simplifications

> Severity legend: 🔴 pitfall to get right (not really a "limitation") · 🟠 structural
> simplification with real consequences · 🟡 moderate, worth knowing · 🟢 minor / cosmetic.

### 🔴 a. Signed hash — the #1 source of bugs (not a limitation, a pitfall)
In v0.8, the `userOpHash` follows an EIP-712 scheme (domain = EntryPoint + chainId). Absolute
invariant: **what the client signs == what `validateUserOp` expects**. The safeguard in place:
the client fetches the hash via `getUserOpHash` then signs with `personal_sign`; the contract
applies `MessageHashUtils.toEthSignedMessageHash`. Symptom if it breaks: `validateUserOp` always
returns `1` (and `handleOps` reverts with `AA24 signature error`).

### 🟢 b. No factory (CREATE2) — RESOLVED in V3
In V1/V2 the account had to be **deployed BEFORE** any UserOp (V1 pre-deployed; V2 via the
`/deploy` endpoint — a distinct on-chain step with a server-side deployer key, not `initCode`).
**V3 closes this**: an `AccountFactory` (CREATE2, idempotent) lets the account address be computed
off-chain (`factory.getAddress`) and the real deployment be bundled into the account's first UserOp
via `initCode`. This removed the `/deploy` endpoint and the deployer key entirely — deployment is now
paid out of the normal `handleOps` flow. See [v3-passkeys-factory.md](v3-passkeys-factory.md).

### 🟠 c. Funding = revert risk
The EntryPoint requires the deposit (Paymaster or account) to cover
`maxCost = (verifGas + callGas + preVerifGas + pmVerifGas + pmPostOpGas) × maxFeePerGas`.
Safeguard: large deposit (≥ 0.05 sETH) + generous gas limits. Symptom if insufficient:
`handleOps` reverts (`AA31 paymaster deposit too low`).

### 🟡 d. No gas estimation
No implementation of `eth_estimateUserOperationGas`. The limits (`verificationGasLimit`,
`callGasLimit`, `preVerificationGas`) are **hardcoded generous** on the client side.
Consequence: we "overpay" on the limit (the surplus is refunded), but a too-expensive UserOp
could fail for lack of limit. To be implemented for arbitrary UserOps.

### 🟡 e. No ERC-7562 rules (mempool validation)
Real bundlers reject UserOps that use forbidden opcodes during validation (`TIMESTAMP`,
`BLOCKHASH`, `NUMBER`, out-of-bounds storage access, etc.) to protect against UserOps that would
pass simulation then fail at inclusion (mempool DoS). Our single-UserOp bundler, with a trusted
account, performs **none** of these checks. V2 added an `eth_call` **dry-run** of `handleOps`
before submission (see [bundler.md](bundler.md), section "The `eth_call` dry-run before
submission"): it catches UserOps that would revert (bad signature, underfunded paymaster) and
avoids wasting gas on them, but this is **not** ERC-7562 opcode-level validation — an op that
passes simulation could still behave differently at inclusion time.

### 🟢 f. Hand-rolled binary packing
`accountGasLimits`, `gasFees`, `paymasterAndData` are packed by hand (bit shifts). Encapsulated
in tested helpers, but a mistake here is silent (no compile error).

### 🟢 g. Unconditional Paymaster
The Paymaster sponsors **everything** with no filter → in production, anyone can drain its
deposit. Intentional. Production: whitelist, off-chain sponsor signature, quota, or ERC-20
payment reconciled in `postOp`.

## Other simplifications

- **1 UserOp per bundle**: no aggregation or profitability sorting.
- **Synchronous submission**: the handler waits for the receipt before responding (a real
  bundler returns the `userOpHash` immediately and includes in the background).
- **Immutable owner/signer/pubkey**: no owner change or social recovery, in any version.
- **Two curves**: V1 (possession) and V2 (knowledge) use secp256k1; **V3 adds secp256r1 (P-256)**
  via WebAuthn passkeys (`PasskeyAccount`), verified with OpenZeppelin's `P256`/`WebAuthn` libraries
  (EIP-7951 precompile at `0x100`, with a Solidity fallback).
- **No active `postOp`**: the Paymaster reconciles nothing (empty context).

### 🟠 h. One browser = one account (V3 passkeys)
V3 tracks which passkey/account belongs to a visitor purely in `localStorage` (no backend store):
Render's free plan has an **ephemeral filesystem** (a SQLite file would not survive a redeploy), and
cross-device continuity is out of scope for this demo. Consequences, both accepted: a passkey is
bound to its device/browser — clearing storage or switching devices means registering a new passkey
(a new counterfactual account); and there is **no shared "try it with public answers" account** like
V2 had — every visitor goes through a real WebAuthn registration.

## Shipped in V3
WebAuthn / passkeys (P-256, `PasskeyAccount`) · factory + `initCode` (counterfactual deployment,
closing 🟢 b above). Full breakdown: [v3-passkeys-factory.md](v3-passkeys-factory.md).

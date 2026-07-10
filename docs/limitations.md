# Limitations — deliberate simplifications (V1 & V2)

> These choices are **intentional** (pedagogical project, one trusted account, testnet).
> They are NOT bugs. This document exists so they are not mistaken for errors, and lists what
> a production version would need to fix.
>
> **Scope.** The **bundler** and **paymaster** are shared, unchanged infrastructure across V1 and
> V2 — everything below applies to both. Only the *account* differs (validation logic), covered
> separately in [contracts.md](contracts.md) and [v2-auth-by-knowledge.md](v2-auth-by-knowledge.md).

## Caveats / simplifications

> Severity legend: 🔴 pitfall to get right (not really a "limitation") · 🟠 structural
> simplification with real consequences · 🟡 moderate, worth knowing · 🟢 minor / cosmetic.

### 🔴 a. Signed hash — the #1 source of bugs (not a limitation, a pitfall)
In v0.8, the `userOpHash` follows an EIP-712 scheme (domain = EntryPoint + chainId). Absolute
invariant: **what the client signs == what `validateUserOp` expects**. The safeguard in place:
the client fetches the hash via `getUserOpHash` then signs with `personal_sign`; the contract
applies `MessageHashUtils.toEthSignedMessageHash`. Symptom if it breaks: `validateUserOp` always
returns `1` (and `handleOps` reverts with `AA24 signature error`).

### 🟠 b. No factory (CREATE2)
The account must be **deployed BEFORE** sending a UserOp — true for both V1's `SmartAccount`
(pre-deployed) and V2's `SecretQuestionAccount` (deployed via the `/deploy` endpoint on SETUP,
which is still a distinct on-chain deployment step, not `initCode`). `initCode` is always empty,
`sender` = the already-deployed address. A real ERC-4337 stack deploys the account "on the fly"
on the first UserOp via a factory + `initCode`.

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
- **Immutable owner/signer**: no owner change or social recovery, in either version.
- **ECDSA validation only**: V1 and V2 both use secp256k1 — V2 changes *how* the key is obtained
  (derived from secret answers instead of held directly), not the curve. P-256/WebAuthn is
  planned for **V3**.
- **No active `postOp`**: the Paymaster reconciles nothing (empty context).

## Planned evolutions (out of scope for V1/V2)
**V3**: WebAuthn/Passkeys (P-256) · factory + `initCode` (counterfactual deployment).

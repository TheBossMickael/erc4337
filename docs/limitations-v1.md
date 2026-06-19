# V1 limitations — deliberate simplifications

> These choices are **intentional** (pedagogical project, one trusted account, testnet).
> They are NOT bugs. This document exists so they are not mistaken for errors, and lists what
> a production version would need to fix.

## Caveats / simplifications

### 🔴 a. Signed hash — the #1 source of bugs (not a limitation, a pitfall)
In v0.8, the `userOpHash` follows an EIP-712 scheme (domain = EntryPoint + chainId). Absolute
invariant: **what the client signs == what `validateUserOp` expects**. The safeguard in place:
the client fetches the hash via `getUserOpHash` then signs with `personal_sign`; the contract
applies `MessageHashUtils.toEthSignedMessageHash`. Symptom if it breaks: `validateUserOp` always
returns `1` (and `handleOps` reverts with `AA24 signature error`).

### 🟠 b. No factory (CREATE2)
The SmartAccount must be **deployed BEFORE** sending a UserOp. `initCode` is always empty,
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
account, performs **none** of these checks.

### 🟢 f. Hand-rolled binary packing
`accountGasLimits`, `gasFees`, `paymasterAndData` are packed by hand (bit shifts). Encapsulated
in tested helpers, but a mistake here is silent (no compile error).

### 🟢 g. Unconditional Paymaster
The Paymaster sponsors **everything** with no filter → in production, anyone can drain its
deposit. Intentional in V1. Production: whitelist, off-chain sponsor signature, quota, or ERC-20
payment reconciled in `postOp`.

## Other simplifications

- **1 UserOp per bundle**: no aggregation or profitability sorting.
- **Synchronous submission**: the handler waits for the receipt before responding (a real
  bundler returns the `userOpHash` immediately and includes in the background).
- **Immutable owner**: no owner change or social recovery.
- **ECDSA validation only**: no P-256/WebAuthn or ZKP yet (V2).
- **No active `postOp`**: the Paymaster reconciles nothing (empty context).

## Planned evolutions (out of V1 scope)
Session keys · WebAuthn/Passkeys (P-256, requires a frontend) · social recovery · multi-UserOp
bundling · gas estimation · ERC-7562 validation · factory + `initCode`.

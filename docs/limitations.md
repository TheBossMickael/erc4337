# Limitations — deliberate simplifications (V1, V2 & V3)

> These choices are **intentional** (pedagogical project, testnet, no real funds). They are NOT
> bugs. This document exists so they are not mistaken for errors, and says what a production
> version would fix. The **bundler** and **paymaster** are shared across V1/V2/V3; the *account*
> (what differs per version) is covered in [contracts.md](contracts.md) and
> [v3-passkeys-factory.md](v3-passkeys-factory.md) (V2's write-up lives at tag
> [`v2.0.0`](https://github.com/TheBossMickael/erc4337/blob/v2.0.0/docs/v2-auth-by-knowledge.md)).
>
> Severity legend: 🔴 pitfall to get right (not really a "limitation") · 🟠 structural
> simplification with real consequences · 🟡 moderate, worth knowing · 🟢 minor / cosmetic.

### 🔴 a. Signed hash — the #1 source of bugs (a pitfall, not a limitation)
Absolute invariant: **what the client signs == what `validateUserOp` expects**. Safeguard in
place: the client always fetches the canonical hash via `getUserOpHash`, then signs it
(`personal_sign` in V1/V2, WebAuthn challenge in V3). Symptom if it breaks: `validateUserOp`
always returns `1` and `handleOps` reverts with `AA24 signature error`.

### 🟢 b. No factory (CREATE2) — RESOLVED in V3
In V1/V2 the account had to be deployed **before** any UserOp (V1 by script, V2 via a `/deploy`
endpoint). V3's `AccountFactory` closed this: the address is known in advance and the deployment
rides in the first UserOp's `initCode` — which also removed `/deploy` and the server-side
deployer key. See [v3-passkeys-factory.md](v3-passkeys-factory.md).

### 🟠 c. Funding = revert risk
The EntryPoint requires the deposit (Paymaster or account) to cover the **max** cost of the
bundle. Safeguard: large deposit + generous gas limits. Symptom if insufficient: `handleOps`
reverts (`AA31 paymaster deposit too low`).

### 🟡 d. No gas estimation
No `eth_estimateUserOperationGas`: the client hardcodes generous limits. We "overpay" on the
limit (the surplus is refunded), but an unusually expensive UserOp could fail for lack of limit.

### 🟡 e. No ERC-7562 rules (mempool validation)
Real bundlers enforce opcode rules during validation to protect a **public** mempool from DoS.
Ours performs none of them. The `eth_call` **dry-run** before submission ([bundler.md](bundler.md))
does catch any op that would revert — so no gas is ever wasted on one — but that is not
opcode-level validation.

### 🟢 f. Hand-rolled binary packing
`accountGasLimits`, `gasFees`, `paymasterAndData` are bit-packed by hand. Encapsulated in tested
helpers, but a mistake here is silent (no compile error).

### 🟢 g. Unconditional Paymaster
Sponsors **everything**, no filter, empty context (so `postOp` never runs) → in production anyone
could drain the deposit. A real version would filter: whitelist, off-chain sponsor signature,
quota, or ERC-20 payment reconciled in `postOp`.

### 🟠 h. One browser = one account (V3 passkeys)
The passkey↔account mapping lives in `localStorage` only (no backend store — Render's free tier
has an ephemeral filesystem). A passkey is bound to its device/browser: clearing storage or
switching devices = a new counterfactual account; and there is no shared demo account like V2 —
every visitor registers a real passkey.

### 🟡 i. One UserOp at a time
One op per bundle (no aggregation), submitted **synchronously** (the HTTP response waits for the
receipt) and **serialized** — an in-process queue in `bundler/src/handler.ts`, because two
concurrent ops would race for the bundler EOA's tx nonce and one tx would fail. Consequences:
one op per ~block, an unbounded queue, and a guarantee that only covers a single bundler process.
A production bundler batches ops, manages its nonces explicitly, and responds before inclusion.

### 🟢 j. Immutable authority
No owner/signer/pubkey rotation and no social recovery, in any version: losing the key / the
answers / the passkey device means losing the account.

## Shipped in V3
WebAuthn passkeys (P-256, `PasskeyAccount`) · factory + `initCode` (closes 🟢 b) · serialized
bundler submission (🟡 i). Details: [v3-passkeys-factory.md](v3-passkeys-factory.md).

# Contracts — BaseAccount, SecretQuestionAccount & Paymaster

> Technical detail of the project's Solidity contracts (V2). For the overall flow, see
> [architecture.md](./architecture.md). For the simplifications, see
> [limitations.md](./limitations.md).

## File overview

```
contracts/src/
├── interfaces/
│   ├── IAccount.sol             ← PackedUserOperation struct + IAccount interface
│   ├── IPaymaster.sol           ← IPaymaster interface + PostOpMode enum
│   └── IEntryPoint.sol          ← MINIMAL EntryPoint interface (what we call)
├── BaseAccount.sol              ← abstract account: validate/execute/prefund/deposit
├── SecretQuestionAccount.sol    ← auth by KNOWLEDGE (ECDSA against a KDF-derived s_signerAddress)
├── SmartAccount.sol             ← V1, superseded — not detailed here
├── Paymaster.sol                ← the gas sponsor
└── Counter.sol                  ← demo witness contract (UserOps target: increment())
```

## BaseAccount → SecretQuestionAccount

`SecretQuestionAccount` extends the abstract `BaseAccount`, which owns the whole ERC-4337
lifecycle (Template Method pattern) and leaves only the signature check as an overridable hook:

```
BaseAccount (abstract)
 ├─ validateUserOp()   final template: _validateSignature() then _payPrefund()
 ├─ execute() / executeBatch()
 ├─ _payPrefund(), addDeposit(), getDeposit()
 ├─ _validateSignature()  ← hook, overridden below
 └─ _authorizedAdmin()    ← hook, overridden below
      │
      └─ SecretQuestionAccount   _validateSignature: recover == s_signerAddress
```

`SecretQuestionAccount` stores only `s_signerAddress` — the address derived off-chain from the
secret answers (never the answers, never the key). It implements exactly two hooks:
`_validateSignature` (below) and `_authorizedAdmin` (returns `s_signerAddress`, letting that
address drive `execute()`/`executeBatch()` directly, besides the EntryPoint). Full derivation
chain, the two frontend screens, and the security model:
[v2-auth-by-knowledge.md](./v2-auth-by-knowledge.md). Deployment is per-user, via the bundler's
`POST /deploy` (deployer key ≠ signer key) — not a one-time script.

### Signature validation — the hash convention (critical point)

```
userOpHash (computed by the EntryPoint)
        │
        ▼
toEthSignedMessageHash(userOpHash)        ← EIP-191 "personal_sign" prefix
        │   = keccak256("\x19Ethereum Signed Message:\n32" || userOpHash)
        ▼
ECDSA.tryRecover(hash, signature) ── recovered address
        │
        ▼
recovered == s_signerAddress ?  → 0 (success)  else → 1 (failure)
```

**Absolute invariant**: the client must sign **exactly this prefixed hash**. The browser applies
it via viem's `signMessage({ message: { raw: userOpHash } })`; the contract applies
`MessageHashUtils.toEthSignedMessageHash`. If the two sides disagree, `ecrecover` returns a wrong
address → `validateUserOp` always returns `1`. **This is the #1 source of bugs.**

`ECDSA.tryRecover` (OpenZeppelin) rather than raw `ecrecover`: rejects the malleable high-`s`
signature variant, and returns a `RecoverError` instead of reverting on a malformed signature —
required, since `validateUserOp` must never revert on a bad signature.

> **Convention vs the reference.** We apply the EIP-191 `personal_sign` prefix (the v0.6/v0.7
> `SimpleAccount` style) rather than the v0.8 reference's raw EIP-712 hash. Both are valid — the
> only hard requirement is that client and contract agree on the scheme.

### validationData, prefund, execution — all in `BaseAccount`

- **`validationData`** is a packed `uint256`, not a boolean (`SIG_VALIDATION_SUCCESS = 0` /
  `SIG_VALIDATION_FAILED = 1` here; bits 160+ would encode `validUntil`/`validAfter` for
  **session keys** — a temporary, scope-limited key authorized for a time window — unused today).
- **`_payPrefund`**: if no Paymaster sponsors, advances `missingAccountFunds` (= max cost minus
  current deposit) to the EntryPoint. With a Paymaster this is `0` and the call is a no-op.
- **`execute`/`executeBatch`**: runs the UserOp's `callData`. Access control via
  `requireFromEntryPointOrOwner` — the EntryPoint (normal flow) or `_authorizedAdmin()` (direct
  control). Sub-call failures bubble up via `BaseAccount__ExecuteFailed`.

### Security

- `msg.sender == i_entryPoint` is checked on every validation (modifier, in `BaseAccount`) —
  without it, anyone could trigger validations.
- `s_signerAddress` has no setter → effectively immutable authority (no takeover risk).
- **Why not a plaintext "secret question"?** The `signature` field is free `bytes`, so one could
  put an answer in it directly — but a UserOp travels in cleartext through the mempool, exposing
  and replaying the secret for **any** action. A signature reveals nothing and is bound to the
  specific `userOpHash` (non-replayable). That's exactly what happens here: the answers never
  appear on-chain or in the mempool, only a signature from the KDF-derived key.

---

## Counter (demo witness contract)

No ERC-4337 role: a **target** proving a UserOp can call a function on another contract, not just
transfer ETH. `increment()` adds 1 and emits an event; `count()` reads it. During the demo, the
`msg.sender` the Counter sees is the **account's address**, not the user's EOA — the concrete
demonstration of account abstraction.

---

## Paymaster

Sponsors the gas. **Not an EOA**: it holds an accounting deposit on the EntryPoint (`depositTo`),
which the EntryPoint draws from to reimburse the bundler.

| Function | Role |
|---|---|
| `validatePaymasterUserOp` | Checks the caller, returns `("", 0)` → accepts everything |
| `postOp` | No-op (never called — context is empty) |
| `deposit` / `withdrawTo` / `getDeposit` | Fund / withdraw / read the EntryPoint deposit |

`context = ""` → no `postOp` call, nothing to reconcile. ⚠️ **Unconditional sponsoring is
insecure in production** (anyone can drain the deposit) — deliberate here. A real version would
filter (whitelist, off-chain sponsor signature, quota, ERC-20 payment in `postOp`).

---

## Interfaces

- **`IAccount`**: `validateUserOp(...)` + the `PackedUserOperation` struct (the "packed" fields:
  `accountGasLimits`, `gasFees`).
- **`IPaymaster`**: `validatePaymasterUserOp`, `postOp`, `PostOpMode` enum.
- **`IEntryPoint`**: minimal subset of the real EntryPoint — only what we call.

---

## Tests

- `test/SecretQuestionAccount.t.sol` — signature validation, access control, execute, batch,
  prefund, deposit, plus `test_demoVector_crossChecksFrontendDerivation`: signs with the
  frontend-derived demo key and asserts `validateUserOp == 0`, keeping the TS KDF and the
  Solidity check in sync.
- `test/Paymaster.t.sol` — accept, access control, deposit/withdraw.
- `test/Integration.fork.t.sol` — end-to-end against the **real** EntryPoint on a Sepolia fork.
  Skipped without `--fork-url`.

Commands: `forge build`, `forge test -vvv` (see README.md).

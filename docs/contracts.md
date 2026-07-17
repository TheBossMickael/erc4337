# Contracts — the account hierarchy, AccountFactory & Paymaster

> Technical detail of the project's Solidity contracts (V1 → V3). For the overall flow, see
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
├── SmartAccount.sol             ← V1 — auth by POSSESSION (ECDSA against a fixed s_owner)
├── SecretQuestionAccount.sol    ← V2 — auth by KNOWLEDGE (ECDSA against a KDF-derived signer)
├── PasskeyAccount.sol           ← V3 — auth by DEVICE (WebAuthn P-256 against a stored pubkey)
├── AccountFactory.sol           ← V3 — CREATE2 factory, counterfactual deployment via initCode
├── Paymaster.sol                ← the gas sponsor
└── Counter.sol                  ← demo witness contract (UserOps target: increment())
```

## The BaseAccount hierarchy (Template Method)

The abstract `BaseAccount` owns the whole ERC-4337 account lifecycle and leaves exactly **two
hooks** for concrete schemes:

```
BaseAccount (abstract)
 ├─ validateUserOp()   final template: _validateSignature() then _payPrefund()
 ├─ execute() / executeBatch()
 ├─ _payPrefund(), addDeposit(), getDeposit()
 ├─ _validateSignature()  ← hook 1: is this UserOp signature valid?
 └─ _authorizedAdmin()    ← hook 2: who may call execute() directly, besides the EntryPoint?
      │
      ├─ SmartAccount (V1)           ECDSA recover == s_owner          · admin = s_owner
      ├─ SecretQuestionAccount (V2)  ECDSA recover == s_signerAddress  · admin = s_signerAddress
      └─ PasskeyAccount (V3)         WebAuthn.verify against (x, y)    · admin = address(0)
```

Adding an auth scheme must not touch the security-critical lifecycle — V3 is the proof: it
overrides the two hooks and nothing else. Deployment also differs per version: V1 once by
script, V2 per-user via the bundler's `/deploy` (removed in V3), V3 lazily via the
[AccountFactory](#accountfactory-v3--counterfactual-deployment).

## Signature validation

### secp256k1 accounts (V1 & V2) — ECDSA + EIP-191

```
userOpHash (computed by the EntryPoint)
        │
        ▼
toEthSignedMessageHash(userOpHash)        ← EIP-191 "personal_sign" prefix
        │
        ▼
ECDSA.tryRecover(hash, signature) == stored signer ?  → 0 (success)  else → 1
                                     (s_owner in V1, s_signerAddress in V2)
```

**Absolute invariant**: the client must sign **exactly this prefixed hash** (viem:
`signMessage({ message: { raw: userOpHash } })`). If the two sides disagree, `validateUserOp`
always returns `1`. **This is the #1 source of bugs.** OpenZeppelin's `tryRecover` (not raw
`ecrecover`) rejects malleable signatures and never reverts on malformed input — required, since
`validateUserOp` must return `1`, not revert.

> We use the EIP-191 `personal_sign` convention (v0.6/v0.7 `SimpleAccount` style) rather than the
> v0.8 reference's raw EIP-712 hash. Both are valid — client and contract just have to agree.

V2's specificity (the key is *derived in the browser* from secret answers; the contract sees a
normal ECDSA signature): the V2 doc at tag
[`v2.0.0`](https://github.com/TheBossMickael/erc4337/blob/v2.0.0/docs/v2-auth-by-knowledge.md).

### PasskeyAccount (V3) — WebAuthn / P-256

A different signature, same lifecycle: the account stores the P-256 public key `(x, y)`, and
`_validateSignature` hands the WebAuthn assertion to OpenZeppelin's `WebAuthn`/`P256` libraries.
`_authorizedAdmin()` is `address(0)` — a P-256 key has no EVM address, so everything goes through
UserOps. Details (how WebAuthn signing works, the precompile, the encoding trap):
[v3-passkeys-factory.md](./v3-passkeys-factory.md).

### validationData, prefund, execution — all in `BaseAccount`

- **`validationData`** is a packed `uint256`, not a boolean (`0` = success, `1` = failure; bits
  160+ would encode a validity time window for session keys — unused here).
- **`_payPrefund`**: if no Paymaster sponsors, advances `missingAccountFunds` to the EntryPoint.
  With a Paymaster this is `0` and the call is a no-op.
- **`execute`/`executeBatch`**: runs the UserOp's `callData`. Access control:
  `requireFromEntryPointOrOwner` — the EntryPoint (normal flow) or `_authorizedAdmin()`.

### Security

- `msg.sender == i_entryPoint` is checked on every validation — without it, anyone could trigger
  validations.
- The authority is immutable in every version (no setter for `s_owner`/`s_signerAddress`,
  immutable `(x, y)`) → no takeover risk, but no rotation or recovery either
  ([limitations.md](./limitations.md)).
- **Why sign instead of sending a secret?** A UserOp travels in cleartext (mempool), so any
  secret placed in it would be exposed and replayable. A signature reveals nothing and is bound
  to one specific `userOpHash`. Nothing secret ever goes on-chain, in any version.

---

## AccountFactory (V3) — counterfactual deployment

CREATE2 factory: the account address is readable via `getAddress` **before the account exists**,
and the real deployment rides in the first UserOp's `initCode`. Idempotent (a retried first op
returns the existing account instead of reverting). This closed
[limitations.md](./limitations.md) 🟢 b and removed V2's `/deploy` endpoint + deployer key.
Details: [v3-passkeys-factory.md](./v3-passkeys-factory.md).

---

## Counter (demo witness contract)

No ERC-4337 role: a **target** proving a UserOp can call another contract. `increment()` adds 1;
the `msg.sender` the Counter sees is the **account's address**, not the user's EOA — the concrete
demonstration of account abstraction.

---

## Paymaster

Sponsors the gas. **Not an EOA**: it holds an accounting deposit on the EntryPoint, which the
EntryPoint draws from to reimburse the bundler.

| Function | Role |
|---|---|
| `validatePaymasterUserOp` | Checks the caller, returns `("", 0)` → accepts everything |
| `postOp` | No-op (never called — context is empty) |
| `deposit` / `withdrawTo` / `getDeposit` | Fund / withdraw / read the EntryPoint deposit |

⚠️ **Unconditional sponsoring is insecure in production** (anyone can drain the deposit) —
deliberate here. A real version would filter (whitelist, sponsor signature, quota, ERC-20 payment
in `postOp`). In V3 it also sponsors the deploying first UserOp (~1.5M extra gas) with no special
case — the deposit just needs to cover that larger ceiling.

---

## Interfaces

- **`IAccount`**: `validateUserOp(...)` + the `PackedUserOperation` struct (the "packed" fields:
  `accountGasLimits`, `gasFees` — bit-packed to save calldata).
- **`IPaymaster`**: `validatePaymasterUserOp`, `postOp`, `PostOpMode` enum.
- **`IEntryPoint`**: minimal subset of the real EntryPoint — only what we call.

---

## Tests

- `SmartAccount.t.sol` (V1) & `SecretQuestionAccount.t.sol` (V2) — validation, access control,
  execute, batch, prefund, deposit; V2 cross-checks the V2 frontend's KDF vector against the
  contract (the V2 frontend and its KDF live at tag
  [`v2.0.0`](https://github.com/TheBossMickael/erc4337/blob/v2.0.0/docs/v2-auth-by-knowledge.md)).
- `PasskeyAccount.t.sol` (V3) — WebAuthn validation against the locked vector: challenge binding,
  wrong key, malformed signature (returns `1`, never reverts), access control.
- `AccountFactory.t.sol` (V3) — CREATE2 determinism (`getAddress` == deployed address),
  idempotence, distinct keys → distinct addresses.
- `Paymaster.t.sol` — accept, access control, deposit/withdraw.
- `Integration.fork.t.sol` & `Passkey.fork.t.sol` — end-to-end against the **real** EntryPoint
  (and V3's real P-256 precompile) on a Sepolia fork. Skipped without `--fork-url`.
- `fixtures/WebAuthnVector.sol` — the locked WebAuthn assertion (`make vector`), mirrored in the
  frontend's `webauthn.test.ts` (see [v3-passkeys-factory.md](./v3-passkeys-factory.md)).

Commands: `forge build`, `forge test -vvv` (see README.md).

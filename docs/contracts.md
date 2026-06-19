# Contracts — SmartAccount & Paymaster

> Technical detail of the project's Solidity contracts. For the overall flow, see
> [architecture.md](./architecture.md). For the V1 simplifications, see
> [limitations-v1.md](./limitations-v1.md).

## File overview

```
contracts/src/
├── interfaces/
│   ├── IAccount.sol      ← PackedUserOperation struct + IAccount interface
│   ├── IPaymaster.sol    ← IPaymaster interface + PostOpMode enum
│   └── IEntryPoint.sol   ← MINIMAL EntryPoint interface (what we call)
├── SmartAccount.sol      ← the user's account (validate + execute)
├── Paymaster.sol         ← the gas sponsor
└── Counter.sol           ← demo witness contract (UserOps target: increment())
```

---

## SmartAccount

The SmartAccount replaces the user's EOA. It has two responsibilities, called separately by
the EntryPoint:

1. **`validateUserOp`** — "is this UserOp authorized?"
2. **`execute` / `executeBatch`** — "perform the requested action"

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
recovered == owner ?  → 0 (success)  else → 1 (failure)
```

**Absolute invariant**: the client must sign **exactly this prefixed hash**. On the
bundler/client side, this is done by viem's `signMessage({ message: { raw: userOpHash } })`,
which applies the same EIP-191 prefix. If the two sides disagree, `ecrecover` returns a wrong
address → `validateUserOp` always returns `1`. **This is the #1 source of bugs.**

Why `ECDSA.tryRecover` (OpenZeppelin) rather than raw `ecrecover`:
- **Anti-malleability**: `ecrecover` accepts two valid `s` values for the same signature (the
  high "s" and the low "s"). OZ rejects the high "s" → no double signature.
- **No revert**: `tryRecover` returns a `RecoverError` instead of reverting on a malformed
  signature. Essential to honor the "never revert on a bad signature" rule (otherwise the
  bundler's simulation breaks).

> **Convention vs the reference.** We apply the EIP-191 `personal_sign` prefix (the v0.6/v0.7
> `SimpleAccount` style). The v0.8 reference `SimpleAccount` verifies the raw EIP-712 `userOpHash`
> directly instead. Both are valid — the only hard requirement is that the client and the contract
> agree on the scheme. We keep `personal_sign` here for its simplicity.

### The `validationData` return (ERC-4337 packing)

`validateUserOp` returns a packed `uint256`, not a boolean:

```
bits   0-159 : aggregator  (0 = OK, 1 = SIG_VALIDATION_FAILED)
bits 160-207 : validUntil   (expiry timestamp, 0 = never)
bits 208-255 : validAfter   (start-of-validity timestamp)
```

In V1 we only use `0` or `1`. Handling time windows (validUntil / validAfter) is a future
evolution (useful for session keys).

### The prefund (`_payPrefund`)

If no Paymaster sponsors, the account must advance the max gas cost to the EntryPoint:
`missingAccountFunds = maxCost − the account's current deposit`. With a Paymaster,
`missingAccountFunds == 0` and the function does nothing. We deliberately ignore the `call`'s
success: the EntryPoint verifies reception itself and reverts otherwise.

### Execution (`execute` / `executeBatch`)

This is step 2. The UserOp's `callData` encodes a call to `execute(dest, value, func)`. Access
control via `requireFromEntryPointOrOwner`: the EntryPoint (ERC-4337 flow) **or** the owner
(direct EOA control, handy for admin). On a sub-call failure, the revert reason is bubbled up
via the custom error `SmartAccount__ExecuteFailed`.

### Security — key points

- `msg.sender == i_entryPoint` checked in `validateUserOp` (modifier). Without it, anyone
  could trigger validations.
- `s_owner` has **no** setter in V1 → effectively immutable owner (no takeover risk). Adding an
  owner change = an attack surface to secure.
- **Why not a plaintext "secret question"?** The `signature` field is free `bytes`, so one
  COULD put a question's answer in it. But a UserOp travels in cleartext through the mempool:
  the secret would be exposed and reusable for **any** action. A cryptographic signature, on
  the other hand, does not reveal the secret AND is bound to the specific `userOpHash`
  (non-replayable). This is why V2 will use another **signature** (P-256/WebAuthn) or a **ZKP**,
  not a plaintext secret.

---

## Counter (demo witness contract)

`Counter` has no ERC-4337 role: it is just a **target** to prove that a UserOp can **call a
function on another contract** (not only transfer ETH). `increment()` adds 1 to a counter and
emits an event; `count()` reads the value.

Teaching point: during the demo, the `msg.sender` seen by the Counter is the **SmartAccount's
address** (it is the account that acts via `execute`), not the user's EOA. This is the concrete
demonstration of account abstraction.

---

## Paymaster

Sponsors the gas. **It is not an EOA**: it holds an accounting deposit on the EntryPoint (via
`depositTo`), from which the EntryPoint draws to reimburse the bundler.

| Function | V1 role |
|---|---|
| `validatePaymasterUserOp` | Checks the caller, returns `("", 0)` → accepts everything |
| `postOp` | No-op (never called because the context is empty) |
| `deposit` | Funds the Paymaster's deposit on the EntryPoint |
| `withdrawTo` | Withdraws from the deposit (owner only) |
| `getDeposit` | Reads the deposit |

- `context = ""` → the EntryPoint **does not call** `postOp` (nothing to reconcile).
- `validationData = 0` → sponsoring accepted, with no time window.
- The deposit is a finite "gas tank": each sponsored UserOp drains it (the EntryPoint debits it
  to reimburse the bundler). Refill it by calling `deposit()` again; read the balance via
  `getDeposit()`. See [deployment.md](./deployment.md#topping-up-the-paymaster).
- ⚠️ **Unconditional sponsoring = insecure in production** (anyone can drain the deposit). This
  is deliberate and pedagogical. A real version would filter (whitelist, off-chain sponsor
  signature, quota, ERC-20 payment in `postOp`).

---

## Interfaces

- **`IAccount`**: `validateUserOp(...)`. Also defines the `PackedUserOperation` struct (the
  "packed" fields: `accountGasLimits`, `gasFees`).
- **`IPaymaster`**: `validatePaymasterUserOp`, `postOp`, `PostOpMode` enum (`opSucceeded` /
  `opReverted`).
- **`IEntryPoint`**: a minimal subset of the real EntryPoint — `depositTo`, `balanceOf`,
  `withdrawTo`, `getNonce`, `getUserOpHash`, `handleOps`. We only declare what we call.

---

## Tests

- `test/SmartAccount.t.sol` — unit tests (valid/invalid/malformed signature, access control,
  execute, batch, prefund, deposit).
- `test/Paymaster.t.sol` — unit tests (accept, access control, deposit/withdraw).
- `test/mocks/MockEntryPoint.sol` — fake EntryPoint (deposit accounting).
- `test/Integration.fork.t.sol` — **end-to-end against the REAL EntryPoint** via a Sepolia fork
  (real handleOps). Automatically skipped when run without `--fork-url`.

Commands: see [deployment.md](./deployment.md).

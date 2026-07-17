# V3 — Passkeys (WebAuthn / P-256) + counterfactual factory

V3 keeps the exact same architecture as V1/V2 and changes two things:

1. **A third auth scheme** — `PasskeyAccount`, validated by a **WebAuthn passkey** (P-256 /
   secp256r1): Face ID / Touch ID / Windows Hello / a security key. The private key lives in the
   device's authenticator and **never leaves it**.
2. **Counterfactual deployment** — an `AccountFactory` (CREATE2) deploys the account **lazily**,
   inside its first UserOp via `initCode`, instead of a separate deploy step. This closes
   [limitations.md](limitations.md) 🟢 b and removes V2's `/deploy` endpoint + server deployer key.

Both were built together. The proof that the V2 `BaseAccount` refactor holds: a brand-new scheme
touches only **two hooks** (`_validateSignature`, `_authorizedAdmin`).

```
BaseAccount (abstract)     validateUserOp / execute / prefund / deposit  +  _validateSignature (hook)
 ├─ SmartAccount (V1)       secp256k1  · auth by POSSESSION  (you hold a key)
 ├─ SecretQuestionAccount   secp256k1  · auth by KNOWLEDGE   (you know the answers)
 └─ PasskeyAccount (V3)     secp256r1  · auth by DEVICE       (your authenticator signs)
```

## 1. PasskeyAccount — WebAuthn verification on-chain

Source: [contracts/src/PasskeyAccount.sol](../contracts/src/PasskeyAccount.sol). The account
stores only the P-256 **public key** `(x, y)`; validation delegates the hard part to
OpenZeppelin's audited `WebAuthn` + `P256` libraries:

```solidity
(bool ok, WebAuthn.WebAuthnAuth calldata auth) = WebAuthn.tryDecodeAuth(userOp.signature);
if (!ok) return SIG_VALIDATION_FAILED;                        // never reverts on bad input
return WebAuthn.verify(bytes.concat(userOpHash), auth, i_pubKeyX, i_pubKeyY)
    ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
```

Key facts:

- **WebAuthn doesn't sign `userOpHash` directly.** The authenticator signs its own envelope
  (authenticator data + client data), with `userOpHash` embedded inside as the **challenge**.
  `WebAuthn.verify` checks the whole envelope — the challenge match is what binds the signature
  to this specific UserOp.
- **P-256 verification** uses the EIP-7951 precompile at `0x100` when present (live on Sepolia,
  exercised in [Passkey.fork.t.sol](../contracts/test/Passkey.fork.t.sol)) and OZ's pure-Solidity
  fallback otherwise — so local unit tests need no special setup. The library also rejects
  malleable (high-s) signatures; the frontend normalizes before sending.
- **`_authorizedAdmin() = address(0)`**: a P-256 key has no EVM address, so direct
  (non-EntryPoint) `execute()` is disabled by design — every action flows through a validated
  UserOp.

### The signature encoding trap

`userOp.signature` is the ABI-encoding of the 6 `WebAuthnAuth` fields as a **top-level tuple** —
**not** `abi.encode(struct)`, which prepends a `0x20` offset word that breaks OZ's decoder
(`validateUserOp` then always returns `1`). Solidity
([WebAuthnVector.sol](../contracts/test/fixtures/WebAuthnVector.sol)) and the frontend
([webauthn.ts](../frontend/src/lib/webauthn.ts)) both produce the naked tuple; a regression test
asserts the encoded blob starts with `r`, not `0x20`.

## 2. AccountFactory — counterfactual deployment

Source: [contracts/src/AccountFactory.sol](../contracts/src/AccountFactory.sol).

```solidity
function createAccount(bytes32 x, bytes32 y, uint256 salt) external returns (PasskeyAccount) {
    address predicted = getAddress(x, y, salt);
    if (predicted.code.length > 0) return PasskeyAccount(payable(predicted)); // IDEMPOTENT
    return new PasskeyAccount{salt: bytes32(salt)}(entryPoint, x, y);
}
```

- **Counterfactual**: the address is deterministic (CREATE2), so the frontend reads it via
  `getAddress` (an `eth_call`) **before the account exists** and uses it as the UserOp `sender`.
  The EntryPoint runs the `initCode` (= factory ‖ `createAccount` calldata) on the first op,
  right before `validateUserOp`.
- **Idempotent**: a retried/duplicate first op returns the existing account instead of reverting
  on the CREATE2 collision.
- **Deliberately simple**: no proxy (direct deployment — simpler, more deploy gas), no
  `msg.sender` check (public factory, like eth-infinitism's `SimpleAccountFactory`).

The Paymaster sponsors the deploying first op like any other — no special funding step.

## 3. The counterfactual flow (frontend)

[passkeyFlow.ts](../frontend/src/lib/passkeyFlow.ts) drives one gasless increment:

```
[register passkey if none]  →  (x, y)
  → sender = factory.getAddress(x, y, 0)            (read-only — account may not exist yet)
  → build UserOp (initCode only if sender has no code)
  → userOpHash = EntryPoint.getUserOpHash(op)
  → signature = passkey assertion over userOpHash   (biometric prompt)
  → bundler → handleOps   (deploys the account AND runs increment, on first use)
```

- **Single fused button** ([App.tsx](../frontend/src/App.tsx)): the first click registers the
  passkey then signs (two prompts); later clicks just sign (one prompt).
- **The `initCode` decision is on-chain-driven**: included whenever the sender has no code — so
  the flow self-heals if a previous first op failed.
- **Gas**: the deploying first op costs ~1.5M extra gas (the account bytecode inlines the P-256
  code); its `verificationGasLimit` is bumped and the Paymaster deposit must cover that ceiling.
  The bundler's dry-run catches any under-sizing before sending.

[webauthn.ts](../frontend/src/lib/webauthn.ts) does the browser-side plumbing — extract `(x, y)`
from the new credential, re-encode the authenticator's signature as low-s `(r, s)`, build the
naked-tuple `userOp.signature` — each step locked by the test vector below.

## Testing & the locked vector

Foundry has **no P-256 signing cheatcode**, so a deterministic WebAuthn assertion is generated
once (`make vector`) and locked in **two places that must agree**:
[WebAuthnVector.sol](../contracts/test/fixtures/WebAuthnVector.sol) (Solidity) and
[webauthn.test.ts](../frontend/src/lib/webauthn.test.ts) (TS). Any format change breaks both.

- **Local unit tests** — validation, challenge binding, wrong key, malformed signature, factory
  idempotence/determinism (via the OZ Solidity fallback — no precompile needed).
- **Fork test** — the real `0x100` precompile validates the same vector on Sepolia.
- **Full end-to-end** (fresh passkey + `initCode` + `handleOps`) is exercised in the browser
  against the deployed HTTPS URL — Foundry can't produce a fresh P-256 signature.

## Browser support & accepted limitation

WebAuthn requires HTTPS. Every major desktop browser works; **on iPhone/iPad only Safari works**
— the app detects a missing authenticator and shows a hint.

Which passkey/account belongs to a visitor is tracked in `localStorage` only (no backend store):
a passkey is bound to its device/browser, and clearing storage or switching devices means a new
counterfactual account. See [limitations.md](limitations.md) 🟠 h.

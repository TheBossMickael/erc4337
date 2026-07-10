# V3 — Passkeys (WebAuthn / P-256) + counterfactual factory

V3 keeps the exact same architecture as V1/V2 and changes two things:

1. **A third auth scheme** — `PasskeyAccount`, validated by a **WebAuthn passkey** (P-256 / secp256r1):
   Face ID / Touch ID / Windows Hello / a security key. The private key is generated and held by the
   device's authenticator and **never leaves it**.
2. **Counterfactual deployment** — an `AccountFactory` (CREATE2) deploys the account **lazily**, inside
   its first UserOp via `initCode`, instead of a separate deploy step. This closes
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

Source: [contracts/src/PasskeyAccount.sol](../contracts/src/PasskeyAccount.sol).

The account stores only the P-256 **public key** `(x, y)` (as immutables). Validation delegates the
hard part to OpenZeppelin's audited libraries:

```solidity
(bool ok, WebAuthn.WebAuthnAuth calldata auth) = WebAuthn.tryDecodeAuth(userOp.signature);
if (!ok) return SIG_VALIDATION_FAILED;                        // never reverts on bad input
return WebAuthn.verify(bytes.concat(userOpHash), auth, i_pubKeyX, i_pubKeyY)
    ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
```

### Why this isn't a plain signature check

WebAuthn does **not** sign `userOpHash` directly. The authenticator signs:

```
message = sha256( authenticatorData || sha256(clientDataJSON) )
```

and our `userOpHash` appears — base64url-encoded — as the `challenge` field **inside**
`clientDataJSON`:

```json
{"type":"webauthn.get","challenge":"<base64url(userOpHash)>","origin":"…","crossOrigin":false}
```

`WebAuthn.verify` does all of it: checks `type == "webauthn.get"`, re-encodes our `userOpHash` to
base64url and matches it against the `challenge` substring (this is what **binds the signature to
this specific UserOp**), checks the User-Present / User-Verified flag bits, reconstructs `message`,
and finally verifies the P-256 signature.

### P-256 verification: precompile + fallback

`P256.verify` (called inside `WebAuthn.verify`) uses the **EIP-7951 precompile at `0x100`** when it
is present, and falls back to a **pure-Solidity implementation** otherwise:

- **On Sepolia** (post-Fusaka) the precompile is live (~6900 gas) — verified on a fork in
  [contracts/test/Passkey.fork.t.sol](../contracts/test/Passkey.fork.t.sol).
- **On a local EVM without the precompile**, the Solidity fallback runs, so the unit tests are green
  without any special setup. No external verifier (e.g. Daimo's) is needed — OZ bundles the fallback.

Signature **malleability** is handled inside the library: it rejects `s > N/2`, so the client must
send the **low-s** form (the browser/authenticator may return high-s — we normalize off-chain).

### `_authorizedAdmin() = address(0)`

A P-256 public key has **no corresponding EVM address**, so no key could sign an Ethereum
transaction to drive the account directly. Direct (non-EntryPoint) `execute()` is therefore disabled
by design: every action flows through a validated UserOp.

### The signature encoding trap

`userOp.signature` is the ABI-encoding of the 6 `WebAuthnAuth` fields **as a top-level tuple**:

```
(bytes32 r, bytes32 s, uint256 challengeIndex, uint256 typeIndex, bytes authenticatorData, string clientDataJSON)
```

⚠️ It must **not** be `abi.encode(struct)`: OZ's `WebAuthn.tryDecodeAuth` reads the fields straight
from the calldata start (`input.offset`), whereas `abi.encode(struct)` of a dynamic struct prepends
a `0x20` offset word that shifts everything by 32 bytes and makes the decode fail (return `1`). The
Solidity side ([WebAuthnVector.signature()](../contracts/test/fixtures/WebAuthnVector.sol)) and the
frontend ([encodeWebAuthnSignature](../frontend/src/lib/webauthn.ts), 6 params — not a `tuple`) both
produce the naked tuple. A regression test asserts the encoded blob starts with `r`, not `0x20`.

## 2. AccountFactory — counterfactual deployment

Source: [contracts/src/AccountFactory.sol](../contracts/src/AccountFactory.sol).

```solidity
function createAccount(bytes32 x, bytes32 y, uint256 salt) external returns (PasskeyAccount) {
    address predicted = getAddress(x, y, salt);
    if (predicted.code.length > 0) return PasskeyAccount(payable(predicted)); // IDEMPOTENT
    return new PasskeyAccount{salt: bytes32(salt)}(entryPoint, x, y);
}
function getAddress(bytes32 x, bytes32 y, uint256 salt) public view returns (address) {
    bytes memory initCode = abi.encodePacked(type(PasskeyAccount).creationCode, abi.encode(entryPoint, x, y));
    return Create2.computeAddress(bytes32(salt), keccak256(initCode));
}
```

- **Counterfactual**: the address is a deterministic function of `(factory, salt, PasskeyAccount
  bytecode + (entryPoint, x, y))`. The frontend reads it via `getAddress` (an `eth_call` — the
  account need not exist), so there is **no off-chain CREATE2 duplication** to drift.
- **Idempotent**: the canonical EntryPoint calls `createAccount` on the first UserOp (via its
  internal `SenderCreator`) when `sender` has no code; a duplicate/retried call must not revert on
  the CREATE2 collision, so we return the existing account.
- **No proxy**: the account contract is deployed directly (simpler; more deploy gas). **No
  `msg.sender` check**: a public factory, like eth-infinitism's `SimpleAccountFactory`.

The Paymaster already sponsors unconditionally, without presupposing the sender has code, so it pays
the very first (deploying) UserOp exactly like any other — no chicken-and-egg funding problem.

## 3. The counterfactual flow (frontend)

[passkeyFlow.ts](../frontend/src/lib/passkeyFlow.ts) drives one gasless increment:

```
[register passkey if none]  ->  x, y
  -> sender = factory.getAddress(x, y, 0)          (counterfactual address, read-only)
  -> isDeployed(sender)?                            (getBytecode)
  -> build UserOp (initCode = factory ‖ createAccount(x,y,0)  if NOT deployed, else "0x")
  -> userOpHash = EntryPoint.getUserOpHash(op)
  -> signature = passkey.get({ challenge: userOpHash })   (WebAuthn assertion, encoded)
  -> bundler  ->  handleOps  (deploys the account AND runs increment, on first use)
```

- **Single fused button** ([App.tsx](../frontend/src/App.tsx)): no more USE/SETUP screens. On first
  use it registers the passkey (biometric prompt #1) then signs (prompt #2) in the **same click**;
  later uses only sign (one prompt).
- **`initCode` decision is on-chain-driven**: we include it whenever `getBytecode(sender)` is empty,
  so it self-heals even if a previous first-op failed (the account still has no code, so we retry the
  deploy).
- **Gas**: the first op's `verificationGasLimit` is bumped (the account is ~7 KB of inlined
  P256/WebAuthn bytecode, ~1.5M gas to deploy). The bundler's `eth_call` dry-run catches any
  under-sizing before sending. The Paymaster deposit must cover the larger first-op ceiling — fund it
  generously (see `PAYMASTER_DEPOSIT` in `contracts/.env.example`).

### Off-chain WebAuthn parsing

[webauthn.ts](../frontend/src/lib/webauthn.ts), all cross-checked against the locked vector in
[webauthn.test.ts](../frontend/src/lib/webauthn.test.ts):

- **`extractXY`** — the public key from `credential.response.getPublicKey()` (SPKI DER) is the
  trailing 65 bytes `0x04 ‖ x ‖ y`; we take the last 64.
- **`parseDerSignature`** — the assertion signature is DER-encoded ECDSA; we parse it with
  `@noble/curves` and **normalize to low-s** (`s ≤ N/2`), else ~half of signatures are rejected.
- **`webauthnIndices`** — the byte offsets of `"challenge":"` and `"type":"` that OZ's verifier reads.
- **`encodeWebAuthnSignature`** — the naked-tuple encoding described above.

### Browser support (iOS caveat)

WebAuthn needs a **secure context** (HTTPS) — hence testing against the deployed Render URL. On
**iOS, Apple restricts passkey access to Safari**: third-party browsers (Chrome, Firefox, Edge — all
WebKit-wrapped) return a `NotAllowedError` ("permission denied") from
`navigator.credentials.create/get`. This is a platform restriction, not a bug in this code (desktop
Chrome works fine). The frontend does a best-effort
`PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()` check on load and shows a "use
Safari" hint when no authenticator is available, plus a clearer error message if a ceremony fails.

## Testing & the locked vector

Foundry has **no P-256 signing cheatcode**, so a deterministic WebAuthn assertion is generated once
by [frontend/scripts/gen-webauthn-vector.mjs](../frontend/scripts/gen-webauthn-vector.mjs)
(`make vector`) and locked in **two** places that must agree:
[WebAuthnVector.sol](../contracts/test/fixtures/WebAuthnVector.sol) (Solidity) and the `VECTOR` in
[webauthn.test.ts](../frontend/src/lib/webauthn.test.ts) (TS). Any change to the format/derivation
breaks both — exactly like V2's demo-vector cross-check.

- **Local unit tests** ([PasskeyAccount.t.sol](../contracts/test/PasskeyAccount.t.sol),
  [AccountFactory.t.sol](../contracts/test/AccountFactory.t.sol)) — validation, challenge binding,
  wrong key, malformed sig, factory idempotence/determinism; via the OZ Solidity fallback.
- **Fork test** ([Passkey.fork.t.sol](../contracts/test/Passkey.fork.t.sol)) — the **real** `0x100`
  precompile validates the vector on Sepolia.
- **Full end-to-end** (`handleOps` + `initCode` + a *real* passkey) is exercised in the browser
  against the deployed HTTPS URL — Foundry can't produce a fresh P-256 signature for the dynamic
  `userOpHash`.

## Limitation accepted: one browser = one account

Which passkey/account belongs to a visitor is tracked purely in `localStorage` — no backend store
(Render's free plan has an ephemeral filesystem; cross-device sync is out of scope). A passkey is
bound to its device/browser, and there is no shared "public answers" demo account like V2 — every
visitor registers a real passkey. See [limitations.md](limitations.md) 🟠 h.

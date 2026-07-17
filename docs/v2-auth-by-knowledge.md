# V2 — Authentication by knowledge (secret questions)

V2 replaces V1's *auth by possession* (you hold a fixed private key) with **auth by knowledge**:
you prove you know some answers. The curve does not change (still ECDSA secp256k1) — the **auth
model** does.

## The derivation chain

```
answers ──normalize──▶ KDF(salt || answers) ──▶ private key ──▶ address (s_signerAddress)
```

1. The user types the answers in the **browser**.
2. `derivePrivateKey(answers) = keccak256(salt || normalized answers)` — see
   [`frontend/src/lib/derive.ts`](../frontend/src/lib/derive.ts). Normalization = `trim` +
   `lowercase` so trivial formatting differences don't change the key.
3. `privateKeyToAccount(privateKey)` gives the signer; only its **address** is stored on-chain.

The account contract ([`SecretQuestionAccount.sol`](../contracts/src/SecretQuestionAccount.sol))
stores **only** `s_signerAddress` — never the answers, never the key. Validation:

```solidity
recover(toEthSignedMessageHash(userOpHash), signature) == s_signerAddress
```

Answering correctly ⇒ deriving the right key ⇒ producing a signature that recovers to the stored
address. **Correctness is proven by the signature, never compared in clear text.**

## Two invariants (the pitfalls)

1. **EIP-191 hash convention (inherited from V1).** The browser signs with
   `signMessage({ message: { raw: userOpHash } })` (adds the `\x19Ethereum Signed Message:` prefix);
   the contract applies `MessageHashUtils.toEthSignedMessageHash`. Both sides must apply the *same*
   prefix, or `validateUserOp` returns `1` and `handleOps` reverts with `AA24 signature error`.
2. **Deterministic KDF encoding.** The pre-image (`salt || normalized answers`) must be stable —
   same answers ⇒ same key on every machine, forever. Changing the salt, separator, or
   normalization would orphan every existing account. This invariant is **locked by a cross-check**:
   the frontend-derived demo key/address are asserted both in a Vitest test and in the Solidity test
   [`test_demoVector_crossChecksFrontendDerivation`](../contracts/test/SecretQuestionAccount.t.sol).
   The contract itself never recomputes the KDF (it only stores the address), so there is no
   on-chain encoding to match — the cross-check is what keeps the two worlds in sync.

## The two screens

- **USE** (default) — the questions are shown; the user types the answers → the browser derives the
  key, builds a UserOp (`callData = execute(counter, 0, increment())`), signs the `userOpHash`, and
  POSTs it to the bundler. Result: a gasless `Counter.increment()`. On the shared **demo** account
  the public answers (`rex` / `paris` / `inception`) are shown in a banner — insecure on purpose.
- **SETUP** — the user picks *their own* answers → the browser derives only the **address** (the key
  never leaves the page) → `POST /deploy` asks the backend to deploy a fresh `SecretQuestionAccount`
  for that address. The deployer key is **server-side** (deployer ≠ signer). The new account is kept
  in memory + `localStorage` and USE switches to it immediately — no `.env` edit, no restart.

## Who signs, who pays

The user signs a **UserOperation** (an off-chain object), *not* an Ethereum transaction. The
**bundler** wraps it in a single `handleOps` transaction that it signs and pays for; the
**Paymaster**'s deposit reimburses the bundler. So a single on-chain transaction (the bundler's
`handleOps`) contains the `increment()` as an **internal call** — there is no separate "increment
transaction". The user installs no wallet, holds no seed phrase, and pays no gas.

The bundler **simulates** `handleOps` via `eth_call` before sending the real transaction. A wrong
answer ⇒ wrong key ⇒ `validateUserOp` returns `1` ⇒ the simulation reverts (`AA24`) ⇒ the bundler
rejects the op **without sending a transaction** (no gas, no drain). See
[`bundler/src/handler.ts`](../bundler/src/handler.ts).

## Security model

**Brain wallet: the answers ARE the private key.** Public/weak answers ⇒ anyone who guesses them can
drain the account. This demo publishes its answers on purpose (reproducibility) and is
**intentionally insecure**. Hardening (not implemented here, documented honestly):

- **secret, high-entropy answers** per user (never published);
- a **slow KDF** (scrypt / Argon2) instead of `keccak256`, to resist offline brute force;
- a per-user **salt**.

SETUP already supports secret answers (each user chooses their own). The demo simply freezes a known
set. Assuming and explaining the insecurity is a stronger signal than pretending it is safe.

## Hosting

No longer hosted live — [erc4337.onrender.com](https://erc4337.onrender.com) now serves **V3**
(same Render service, reused rather than duplicated). Config: [render.yaml](../render.yaml).

## What did NOT change from V1

The **bundler** and **Paymaster** logic are unchanged (V2 only adds the `/deploy` endpoint, the
`eth_call` simulation, and static file serving). The shared limitations still apply — no account
factory (`initCode`), no ERC-7562 mempool rules, no gas estimation: see
[limitations.md](limitations.md).

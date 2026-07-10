# ERC-4337 Architecture — The full path of a transaction

> Goal: describe **exactly** the journey of a user action, from the client to on-chain
> execution, and clarify **who pays the gas and with which ETH** at each step.

---

## 0. Recap — the path of a classic Ethereum transaction (EOA)

To understand what ERC-4337 changes, you first need the "normal" path of a transaction sent
from an EOA (the case of a MetaMask-style wallet).

```
┌──────────┐   signs with its    ┌──────────────┐   includes the tx ┌─────────┐
│   EOA    │   private key       │  P2P network │   in a block      │ Miner/  │
│  (user)  │ ──── secp256k1 ───▶ │  (mempool)   │ ────────────────▶ │ Valid.  │
└──────────┘                     └──────────────┘                   └─────────┘
     │                                                                    │
     │  the tx already contains: from, to, value, data, gas, nonce, sig   │
     └──────────── the sender pays the gas IN ETH, themselves ───────────┘
```

Characteristics of this model:

1. **The EOA *is* the account.** The address is derived from the public key. No code behind
   it, just a key pair.
2. **A single possible authorization authority**: the secp256k1 signature. Ethereum, at the
   consensus level, can only verify that.
3. **The sender pays their gas, in ETH, from their own balance.** No ETH = no action possible.
4. **`from` = the one who signs = the one who pays.** These three roles are fused and
   inseparable in a classic tx.

It is this rigid fusion that ERC-4337 decouples.

---

## 1. The core idea: decouple 3 roles that used to be fused

In an EOA tx, a single entity does everything. ERC-4337 separates three questions:

| Question | Classic EOA | ERC-4337 |
|---|---|---|
| **Who decides if the action is authorized?** | The protocol (secp256k1 check) | The **account** (custom Solidity code) |
| **Who sends the tx to the network?** | The sending EOA | The **Bundler** (a third-party EOA) |
| **Who pays the gas in native ETH?** | The sender | The sender **OR a Paymaster** |

Important point: ERC-4337 **does not bypass** Ethereum's cryptography. At the lowest level, a
*real* secp256k1-signed transaction is always sent to the network — that of the **Bundler**.
What gets moved is the decision "is this action authorized?": it shifts from the protocol to a
**smart contract**, which can then accept other schemes (P-256 passkey, multisig, session
keys…).

---

## 2. The full path of a UserOperation (ERC-4337)

```
   OFF-CHAIN                                      ON-CHAIN (Sepolia)
 ───────────────────────────────          ──────────────────────────────────────

 ┌─────────────┐
 │    User     │  1. creates a UserOperation (intent)
 │  (client)   │  2. SIGNS it (secp256k1 key — see note *)
 └──────┬──────┘
        │ 3. eth_sendUserOperation (HTTP JSON-RPC)
        ▼
 ┌─────────────┐
 │   BUNDLER   │  4. basic validation of the UserOp
 │  (Node.js,  │  5. builds ONE real Ethereum tx:
 │   an EOA)   │     handleOps([userOp], beneficiary)
 └──────┬──────┘  6. signs it with ITS OWN key + pays the network gas IN ETH
        │
        │ 7. tx sent to the network ─────────────────┐
        │                                            ▼
        │                                   ┌───────────────────┐
        │                                   │    ENTRYPOINT     │  (deployed by the EF,
        │                                   │   (singleton)     │   not by us)
        │                                   └─────────┬─────────┘
        │                                             │
        │             ╔═══════ VERIFICATION LOOP ═════╪═══════════════════╗
        │             ║                               ▼                   ║
        │             ║   8a. validateUserOp() ──▶ ┌──────────────┐       ║
        │             ║       (signature check)    │   ACCOUNT *  │       ║
        │             ║                            └──────────────┘       ║
        │             ║   8b. validatePaymasterUserOp() ──▶ ┌──────────┐  ║
        │             ║       (does the paymaster accept?)  │ PAYMASTER│  ║
        │             ║                                     └──────────┘  ║
        │             ║   8c. checks the deposits cover the max cost      ║
        │             ╚═══════════════════════════════════════════════════╝
        │                                             │
        │             ╔═══════ EXECUTION LOOP ════════╪═══════════════════╗
        │             ║                               ▼                   ║
        │             ║   9a. runs the callData ───▶ ┌──────────────┐     ║
        │             ║       (the real action)      │  ACCOUNT *   │     ║
        │             ║                              │  .execute()  │     ║
        │             ║                              └──────────────┘     ║
        │             ║   9b. postOp() ──▶ ┌──────────┐ (reconcile cost)  ║
        │             ║                    │ PAYMASTER│                   ║
        │             ║                    └──────────┘                   ║
        │             ║   9c. refunds the surplus, pays the BENEFICIARY   ║
        │             ║       (= the bundler, in ETH) ◀───────────────────╫───┐
        │             ╚═══════════════════════════════════════════════════╝   │
        └─────────────────── the bundler recovers its advanced ETH ───────────┘
```

> \* **"ACCOUNT"** is generic here: `SmartAccount` in V1 (owner holds the key directly) or
> `SecretQuestionAccount` in V2 (key derived client-side from secret answers). Both extend the
> same abstract `BaseAccount`, which implements this exact flow — only the signature *check*
> differs (`_validateSignature`). Details: [contracts.md](./contracts.md).

### Two key points of the flow

1. **The account is passive.** It sends nothing on its own: the **Bundler** sends the
   `handleOps()` transaction to the EntryPoint. The account only *responds* when the
   EntryPoint calls it.

2. **The EntryPoint calls the account TWICE, separately**:
   - first `validateUserOp()` ("is this signature valid?");
   - then, in a second phase, the execution of the `callData` (a call to `execute()`).

   Between the two, the EntryPoint also validates the Paymaster and checks the funds. Hence
   the **two loops**: validate everything first, execute everything next.

---

## 3. Why two separate loops? (verification then execution)

It is an **economic protection for the bundler**.

The bundler spends its own ETH to send `handleOps()`. It needs the guarantee of being
reimbursed. If the EntryPoint validated-then-executed each UserOp one by one, a late UserOp in
the bundle could invalidate the state and cause the reimbursement of the earlier ones to fail
— the bundler would have paid for nothing.

By **validating everything first** (and checking the deposits cover the max cost of the
*whole* bundle), the EntryPoint guarantees the bundle is profitable *before* spending the
expensive execution gas.

---

## 4. Who pays the gas, and with which ETH?

This is the most common source of confusion. There are **two distinct "gas" levels**.

### Level 1 — The network gas of the real transaction

`handleOps()` is a real Ethereum transaction. Like any tx, **someone must sign it with an EOA
and advance the ETH to the network**: this is the **Bundler**.

→ The bundler must hold native ETH. It pays the "network" gas at the moment the tx is sent.

### Level 2 — The bundler's reimbursement

At the end of `handleOps()`, the EntryPoint **reimburses** the bundler (the `beneficiary`).
With whose ETH? Two cases:

#### Case A — Without a Paymaster: the account pays

The account must have an **ETH deposit on the EntryPoint** (or send it via the
*prefund*). This is the role of `_payPrefund()` in `BaseAccount.sol` (shared by both
`SmartAccount` and `SecretQuestionAccount`):

```solidity
function _payPrefund(uint256 missingAccountFunds) internal {
    if (missingAccountFunds != 0) {
        (bool success,) = payable(i_entryPoint).call{value: missingAccountFunds}("");
        (success);
    }
}
```

`missingAccountFunds` = (estimated max cost) − (deposit already present on the EntryPoint). The
account "tops up the difference" by sending ETH to the EntryPoint.

→ In this case, the account must hold ETH. The ETH was just moved from the "account" to
the "deposit on the EntryPoint". The need for ETH has not disappeared — only the "sign"
(owner/signer) and "send" (bundler) roles have been decoupled.

#### Case B — With a Paymaster: a third party pays for the user

If the UserOp contains a non-empty `paymasterAndData`:

- `missingAccountFunds` is **0** → the account sends nothing.
- The **Paymaster's deposit on the EntryPoint** covers the cost.
- The EntryPoint calls `validatePaymasterUserOp()` to ask the Paymaster whether it agrees to
  pay. The Paymaster can accept unconditionally (V1 & V2 — unchanged) or based on rules
  (whitelist, ERC-20 payment, quota…).

→ The Paymaster holds the ETH (deposited on the EntryPoint). **The user needs NO ETH.** This is
"gasless": the user signs, a third party pays.

### Summary table "who needs ETH?"

| Actor | Needs native ETH? | Why |
|---|---|---|
| **User (owner/signer)** | ❌ with Paymaster / ✅ without | Without a Paymaster, their account funds the prefund |
| **Account** | ✅ without Paymaster / ❌ with | Source of the reimbursement when there is no sponsor |
| **Bundler** | ✅ **always** | Signs and advances the gas of the real `handleOps()` tx |
| **Paymaster** | ✅ if used | Reimburses the bundler instead of the user |
| **EntryPoint** | ❌ | It only keeps the deposit accounting |

In practice, on a testnet (free ETH via a faucet), you must fund at least the **Bundler**
(mandatory) and, depending on the mode, either the **account** or the **Paymaster**.

---

## 5. Components recap

| Component | Nature | Built in this project? | Role in one sentence |
|---|---|---|---|
| `PackedUserOperation` | struct | ✅ (interface) | The user's signed intent — what these docs informally call "the UserOp"; "packed" refers to a few fields (`accountGasLimits`, `gasFees`) being bit-packed to save calldata, detailed in [contracts.md](./contracts.md#interfaces) |
| `BaseAccount` | abstract Solidity contract | ✅ | Shared validate/execute/prefund logic; `_validateSignature` is the hook |
| `SmartAccount` (V1) | Solidity contract | ✅ | `BaseAccount` + ECDSA against a fixed `s_owner` |
| `SecretQuestionAccount` (V2) | Solidity contract | ✅ | `BaseAccount` + ECDSA against a KDF-derived `s_signerAddress` |
| `Paymaster` | Solidity contract | ✅ | Sponsors the gas for the user |
| `Counter` | Solidity contract | ✅ | Demo witness contract (UserOps target) |
| `Bundler` | Node.js server | ✅ | Collects UserOps, simulates, sends `handleOps` |
| `EntryPoint` | Singleton contract | ❌ (deployed by the EF) | Orchestrates validation + execution |

---

## 6. Going further

- Contract details (validation, signature, packing): [contracts.md](./contracts.md)
- Bundler details (JSON-RPC, hash computation, serialization): [bundler.md](./bundler.md)
- V2 auth-by-knowledge specifics: [v2-auth-by-knowledge.md](./v2-auth-by-knowledge.md)
- Deliberate simplifications (V1 & V2): [limitations.md](./limitations.md)

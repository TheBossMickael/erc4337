# Bundler — architecture and operation

> The bundler is a Node.js/TypeScript server that receives UserOperations over JSON-RPC and
> submits them to the real EntryPoint via a `handleOps` transaction. Overall flow:
> [architecture.md](./architecture.md).

## Positioning — a MINIMAL bundler (pedagogical)

This bundler is **deliberately minimal**, built for learning: 1 UserOp per bundle, no mempool,
no gas estimation, no ERC-7562 validation, synchronous submission. **It is NOT a production
bundler** — the goal was to understand the mechanics end-to-end, not to compete with existing
stacks.

Full / reference implementations:
- eth-infinitism reference bundler: https://github.com/eth-infinitism/bundler
- Reference contracts (EntryPoint, SimpleAccount…): https://github.com/eth-infinitism/account-abstraction
- Production bundlers / infra: [Pimlico](https://pimlico.io), [Alchemy Account Kit](https://www.alchemy.com/account-kit), [Stackup](https://www.stackup.sh)
- ERC-4337 spec: https://eips.ethereum.org/EIPS/eip-4337

On the library side, the bundler uses **[viem](https://viem.sh)** (a TypeScript-first
alternative to ethers.js) for all Ethereum interaction.

## File breakdown (`bundler/src/`)

| File | Responsibility |
|---|---|
| `loadEnv.ts` | Loads `bundler/.env` (absolute path, imported first everywhere) |
| `config.ts` | Creates `publicClient` (read) + `walletClient` (bundler account), exposes the addresses |
| `entryPoint.ts` | Partial EntryPoint ABI (`getUserOpHash`, `handleOps`, `balanceOf`, `getNonce`) |
| `userOp.ts` | `PackedUserOperation` type, field packing, hex ↔ bigint serialization |
| `handler.ts` | `eth_sendUserOperation` logic (validate → submit → wait for receipt) |
| `server.ts` | Express JSON-RPC 2.0 server (method dispatch) |
| `index.ts` | Server startup |
| `client/sendUserOp.ts` | Test client: builds + signs + sends a UserOp that calls `Counter.increment()` |

## Flow of an `eth_sendUserOperation` request

```
client/sendUserOp.ts                  bundler (server → handler)         EntryPoint (Sepolia)
────────────────────                  ──────────────────────────         ───────────────────
 1. getNonce() ───────────────────────────────────────────────────────▶ read
 2. build callData = execute(counter, 0, increment())  ← 2 levels of calldata
 3. getUserOpHash(userOp) ─────────────────────────────────────────────▶ read (canonical hash)
 4. signMessage({ raw: hash })  (personal_sign)
 5. POST eth_sendUserOperation ──────▶ assertValidUserOpHex
                                       toPacked()
                                       getUserOpHash() (re-check) ──────▶ read
                                       handleOps([op], bundler) ────────▶ TX (verif + exec)
                                       waitForTransactionReceipt ───────▶
 6. ◀──────────── { result: userOpHash }
 7. count() (before/after) to prove the effect ────────────────────────▶ read
```

## Important technical points

### 1. The `userOpHash` (consistency with the signature)
We do NOT recompute the hash by hand off-chain. We call `entryPoint.getUserOpHash(userOp)` (a
view) which returns the **canonical** hash as the EntryPoint sees it. In v0.8 this hash embeds
an EIP-712 domain (EntryPoint + chainId): recomputing it manually would be fragile. The client
signs this hash with `personal_sign`; the contract applies the same EIP-191 prefix.

### 2. hex ↔ bigint serialization
JSON does not know `bigint`. On the wire, **all** fields are hex strings
(`UserOperationHex`). Internally we handle `nonce` and `preVerificationGas` as `bigint`
(`PackedUserOperation`). `toPacked()` / `toHexOp()` do the conversion.

### 3. Packing of the packed fields
- `accountGasLimits = packUint128Pair(verificationGasLimit, callGasLimit)`
- `gasFees = packUint128Pair(maxPriorityFeePerGas, maxFeePerGas)`
- `paymasterAndData = paymaster(20) | verifGas(16) | postOpGas(16) | data`

A packing mistake does not crash — it silently produces an invalid UserOp. The `userOp.ts`
helpers encapsulate these bit shifts and validate the bounds.

### 4. Who signs what
- **The owner** signs the **UserOp** (proof of authorization) → `OWNER_PRIVATE_KEY`.
- **The bundler** signs the **`handleOps` transaction** (and pays the network gas) →
  `BUNDLER_PRIVATE_KEY`. The bundler is the `beneficiary`: it receives the reimbursement.

## Exposed JSON-RPC methods

| Method | Behavior |
|---|---|
| `eth_sendUserOperation` | The core of the bundler. Params `[userOp, entryPoint]`, returns `userOpHash` |
| `eth_supportedEntryPoints` | Returns `[configured entryPoint]` |
| `eth_chainId` | Returns `0xaa36a7` (Sepolia) |

## Testing without spending sETH
Run a forked node: `anvil --fork-url $SEPOLIA_RPC_URL`, then point the bundler's
`SEPOLIA_RPC_URL` to `http://localhost:8545`. Transactions run against a local copy of Sepolia
(real EntryPoint included) without touching the real network.

## V1 limitations
No gas estimation (`eth_estimateUserOperationGas`), no ERC-7562 validation, a single UserOp per
bundle, synchronous submission. Details: [limitations-v1.md](./limitations-v1.md).

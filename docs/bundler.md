# Bundler — architecture and operation

> Node.js/TypeScript server that receives UserOperations over JSON-RPC and submits them to the
> real EntryPoint via a `handleOps` transaction — one at a time. Also serves the built frontend
> as static files (single-service hosting). Overall flow: [architecture.md](./architecture.md).

## Positioning — a MINIMAL bundler (pedagogical)

Deliberately minimal, built for learning: 1 UserOp per bundle, no mempool, no gas estimation, no
[ERC-7562](https://eips.ethereum.org/EIPS/eip-7562) validation, synchronous and serialized
submission. **Not a production bundler** (reference:
[eth-infinitism/bundler](https://github.com/eth-infinitism/bundler)). Uses
**[viem](https://viem.sh)** for all Ethereum interaction.

Since V3 the bundler is a **pure relay**: the only key it holds is its own EOA's. V2's
`POST /deploy` and its `DEPLOYER_PRIVATE_KEY` are gone — accounts deploy themselves via the
factory's `initCode` (see [v3-passkeys-factory.md](./v3-passkeys-factory.md)).

## File breakdown (`bundler/src/`)

| File | Responsibility |
|---|---|
| `loadEnv.ts` / `config.ts` | Load `bundler/.env`; create `publicClient` (read) + `walletClient` (bundler account) |
| `entryPoint.ts` | Partial EntryPoint ABI (`getUserOpHash`, `handleOps`, `balanceOf`, `getNonce`) |
| `userOp.ts` | `PackedUserOperation` type, field packing, hex ↔ bigint serialization |
| `handler.ts` | `eth_sendUserOperation`: validate → dry-run → submit → wait, serialized (one in-flight tx) |
| `server.ts` | Express: `POST /rpc`, CORS, `GET /*` static frontend when `frontend/dist` exists |
| `index.ts` | Server startup |
| `client/sendUserOp.ts` | V1-era CLI client (`make client`) — builds, signs and sends one demo UserOp |

## Flow of an `eth_sendUserOperation` request (V3 passkey flow)

```
browser                                 bundler (server → handler)         Sepolia
────────                                ──────────────────────────         ───────
 1. sender = factory.getAddress(x,y,0) ────────────────────────────────▶ read (account may not exist)
 2. isDeployed(sender)? + getNonce(sender) ────────────────────────────▶ read
 3. build callData = execute(counter, 0, increment())
    + initCode = factory ‖ createAccount(x,y,0)   (only if NOT deployed)
 4. getUserOpHash(userOp) ─────────────────────────────────────────────▶ read (canonical hash)
 5. WebAuthn assertion over userOpHash (biometric prompt) → encode signature
 6. POST eth_sendUserOperation ──────▶ validate shape + recompute hash ─▶ read
                                       [queue: wait for any in-flight op]
                                       simulateContract(handleOps) ─────▶ eth_call DRY-RUN (no gas, no tx)
                                       handleOps([op], bundler) ────────▶ TX — only if dry-run passed
 7. ◀──────────── { result: { userOpHash, txHash } }
```

Steps 1–5 are client-side ([passkeyFlow.ts](../frontend/src/lib/passkeyFlow.ts)); the bundler
only sees step 6 and doesn't know (or care) that a passkey signed the op.

## Key technical points

- **`userOpHash`**: never recomputed by hand — `entryPoint.getUserOpHash(userOp)` returns the
  canonical hash. In V3 it is the WebAuthn **challenge** the passkey signs over; in V1/V2 it was
  signed directly with `personal_sign`.
- **Serialization**: JSON has no `bigint`, so wire fields are hex strings; `toPacked()`/`toHexOp()`
  convert. Packed fields are bit-shifted by hand in `userOp.ts` — a mistake there is silent (it
  produces an invalid UserOp, not a crash).
- **The `eth_call` dry-run**: before the real tx, the bundler simulates `handleOps` — free, no
  state change. An op that would revert (`AA24` bad signature, `AA31` underfunded paymaster…) is
  rejected with **no transaction sent**, so invalid ops can never drain the bundler's or the
  Paymaster's funds. Covers the expensive deploying first op too. Not a substitute for ERC-7562
  mempool validation.
- **Serialized submission** (V3): the bundler EOA's tx nonce is only read at send time, so two
  concurrent requests would grab the **same** nonce and one tx would fail. The handler chains
  every simulate+send+wait through an in-process promise queue (`enqueueSend`): one in-flight
  `handleOps` at a time, each op simulated against the state left by the previous one (a
  double-submitted op fails the dry-run instead of reverting on-chain). Trade-offs:
  [limitations.md](./limitations.md) 🟡 i.
- **Who signs what**: the user's authenticator signs the **UserOp** (no private key ever reaches
  the bundler, in any version); the bundler signs the `handleOps` **transaction**
  (`BUNDLER_PRIVATE_KEY`) and is the `beneficiary` reimbursed by the Paymaster.

## Exposed endpoints

| Method / route | Behavior |
|---|---|
| `POST /rpc` — `eth_sendUserOperation` | Params `[userOp, entryPoint]`, returns `{ userOpHash, txHash }` |
| `POST /rpc` — `eth_supportedEntryPoints` / `eth_chainId` | Returns `[configured entryPoint]` / `0xaa36a7` |
| `GET /*` | Serves the built frontend (`frontend/dist`) when present, SPA fallback to `index.html` |

## Limitations

No gas estimation, no ERC-7562 validation, one UserOp per bundle, synchronous + serialized
submission. Details: [limitations.md](./limitations.md).

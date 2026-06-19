# Deployment & end-to-end test

> Full procedure: from local setup to the real test on Sepolia. We follow the order
> **tests first, deployment last**.

## 0. Setup — installing dependencies

Prerequisites: [Foundry](https://book.getfoundry.sh/), Node.js ≥ 18.

```bash
# Contracts: forge-std + OpenZeppelin live in contracts/lib as git submodules.
git clone --recursive <repo-url>
# (if already cloned without --recursive: git submodule update --init --recursive)

# Bundler dependencies (viem, dotenv, express — all declared in package.json)
cd bundler && npm install
```

The OpenZeppelin remapping is already provided in `contracts/remappings.txt`
(`@openzeppelin/=lib/openzeppelin-contracts/`). From the repo root, `make install` does both
steps (submodules + bundler deps) in one go.

## 1. Who needs ETH (Sepolia sETH)?

| Actor | Needs sETH? | Why |
|---|---|---|
| **Deployer** (`PRIVATE_KEY`) | ✅ | Deployment gas + Paymaster deposit |
| **Bundler** (`BUNDLER_PRIVATE_KEY`) | ✅ | Gas of each `handleOps` |
| **Owner** (`OWNER_*`) | ❌ (with Paymaster) | Only signs, does not pay |
| **Paymaster** (contract) | ⛔ not directly | Funded by the script via `depositTo` |

Sepolia faucets: Google Cloud Web3 faucet, Alchemy faucet, or the pk910 PoW faucet.
In V1, the 3 keys **can be identical** for simplicity.

## 2. `.env` files (one per service)

Two separate `.env` files, each in its own package — `contracts/` and `bundler/` are different
services, each reads its own `.env` natively :

```bash
cp contracts/.env.example contracts/.env
cp bundler/.env.example  bundler/.env
```

- **Foundry**: run from `contracts/`, `forge` reads `contracts/.env` automatically (it is the
  directory of `foundry.toml`).
- **Bundler**: `bundler/src/loadEnv.ts` loads `bundler/.env` (`../.env`), regardless of the
  launch directory.

`contracts/.env` must be filled BEFORE deployment. In `bundler/.env`, the keys
`SMART_ACCOUNT_ADDRESS` / `PAYMASTER_ADDRESS` / `COUNTER_ADDRESS` are filled AFTER, with the
addresses output by the script. `SEPOLIA_RPC_URL` and `ENTRYPOINT_ADDRESS` are duplicated in
both (shared values).

## 3. Local tests (to do BEFORE any deployment)

```bash
cd contracts
forge build                 # compile (checks the OZ remappings)
forge test -vvv             # unit tests (local EVM, instant)
```

Integration test against the **real EntryPoint** via a fork (without deploying, without sETH):

```bash
forge test --match-path test/Integration.fork.t.sol --fork-url $SEPOLIA_RPC_URL -vvv
```

> On PowerShell, `$SEPOLIA_RPC_URL` is not set by the `.env`. Pass the URL directly:
> `--fork-url "https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY"`.

## 4. Deployment simulation (no tx sent)

```bash
cd contracts
forge script script/Deploy.s.sol --rpc-url sepolia
```

Checks the script does not revert (reads the `.env`, builds the txs).

## 5. Real deployment on Sepolia

```bash
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast
```

The script prints the **3 deployed addresses**. Copy them into `bundler/.env`:
`SMART_ACCOUNT_ADDRESS`, `PAYMASTER_ADDRESS` and `COUNTER_ADDRESS`.

Check the Paymaster deposit (must be > 0):

```bash
cast call $ENTRYPOINT_ADDRESS "balanceOf(address)(uint256)" $PAYMASTER_ADDRESS --rpc-url sepolia
```

## 6. Start the bundler

```bash
cd bundler
npm run dev
# → "ERC-4337 bundler started" + printed addresses
```

> If `npm run dev`/`npm run client` produces no output (a nodemon/npm quirk under Git Bash on
> some machines), run directly: `npx ts-node src/index.ts`.

## 7. End-to-end test

In another terminal:

```bash
cd bundler
npm run client          # or: npx ts-node src/client/sendUserOp.ts
```

The client builds a UserOp whose `callData` calls `Counter.increment()`
(`execute(counter, 0, increment())`), signs it with the owner, and sends it to the bundler,
which submits it via `handleOps`. The response contains the `userOpHash`, and the client prints
the counter **before/after** (`0 -> 1`).

> No need to fund the SmartAccount: `increment()` sends no ETH (`value = 0`), and the gas is
> covered by the Paymaster.

Check on **Sepolia Etherscan**: the bundler's transaction, the EntryPoint events
(`UserOperationEvent`), and the effect of the `callData` (the incremented counter, `Incremented`
event).

### Variant without spending sETH
Run `anvil --fork-url $SEPOLIA_RPC_URL`, set `SEPOLIA_RPC_URL=http://localhost:8545` in
`bundler/.env`, and replay step 7 against the local fork.

## Topping up the Paymaster

The Paymaster's deposit on the EntryPoint is its "gas tank": every sponsored UserOp debits it
to reimburse the bundler, so it slowly drains. With the default `PAYMASTER_DEPOSIT` (0.05 sETH)
and ~0.0005 sETH per `increment()` op, that is roughly **~90 sponsored ops** before it runs out.
When empty, `handleOps` reverts with `AA31 paymaster deposit too low`.

Check the remaining deposit:

```bash
cast call $ENTRYPOINT_ADDRESS "balanceOf(address)(uint256)" $PAYMASTER_ADDRESS --rpc-url sepolia
```

Top it up (anyone can — `Paymaster.deposit()` is payable):

```bash
cast send $PAYMASTER_ADDRESS "deposit()" --value 0.05ether --private-key 0x<key> --rpc-url sepolia
```

> Locally on Anvil, restarting the fork and redeploying resets the deposit to its initial value.

## Command recap

> All the raw commands below are also wrapped by the root `Makefile`
> (`make build`, `make test`, `make test-fork`, `make deploy`, `make bundler`, `make client`).

```bash
# Setup
git submodule update --init --recursive   # forge-std + OpenZeppelin
cd bundler && npm install

# Tests
forge build && forge test -vvv
forge test --match-path test/Integration.fork.t.sol --fork-url <RPC> -vvv

# Deployment
forge script script/Deploy.s.sol --rpc-url sepolia              # simulation
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast  # real

# Run
npm run dev      # terminal 1: bundler
npm run client   # terminal 2: send a UserOp
```

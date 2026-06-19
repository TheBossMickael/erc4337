# Contracts — ERC-4337 (Foundry)

The Solidity side of the project: the smart account, the paymaster, a demo target contract,
their interfaces, the tests, and the deployment script.

> Full project overview: [root README](../README.md).
> Detailed contract docs (signature convention, packing, security): [docs/contracts.md](../docs/contracts.md).

## Contents

| Path | Role |
|---|---|
| `src/SmartAccount.sol` | The user's account: `validateUserOp` (ECDSA) + `execute` / `executeBatch` |
| `src/Paymaster.sol` | Gas sponsor (unconditional in V1) |
| `src/Counter.sol` | Demo witness contract — target of the UserOps (`increment()`) |
| `src/interfaces/` | `IAccount`, `IEntryPoint`, `IPaymaster` (minimal interfaces) |
| `script/Deploy.s.sol` | Deploys the 3 contracts + funds the Paymaster on the EntryPoint |
| `test/` | Unit tests + one fork integration test |

## Commands

```bash
forge build                                   # compile
forge test -vvv                               # 19 unit tests (local EVM)
forge test --match-path test/Integration.fork.t.sol --fork-url <RPC> -vvv   # vs real EntryPoint
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast              # deploy
```

Or use the root `Makefile`: `make build`, `make test`, `make test-fork`, `make deploy`.

## Tests

- `SmartAccount.t.sol`, `Paymaster.t.sol` — unit tests against a mocked EntryPoint.
- `Integration.fork.t.sol` — end-to-end against the **real** EntryPoint v0.8 on a Sepolia fork
  (auto-skipped without `--fork-url`).

Full setup + end-to-end guide: [docs/deployment.md](../docs/deployment.md).

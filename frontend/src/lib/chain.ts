import { createPublicClient, http, encodeFunctionData, concat, parseGwei, type Hex } from 'viem';
import { sepolia } from 'viem/chains';
import { config } from '../config';
import { counterAbi, entryPointAbi, executeAbi, factoryAbi } from './abis';
import { buildPaymasterAndData, packUint128Pair, type PackedUserOperation } from './userOp';

/** READ client: nonce, getUserOpHash, Counter.count, factory.getAddress, code checks. */
export const publicClient = createPublicClient({ chain: sepolia, transport: http(config.rpcUrl) });

/** Current Counter value (proof of effect, before/after). */
export async function getCount(): Promise<bigint> {
  return (await publicClient.readContract({
    address: config.counter,
    abi: counterAbi,
    functionName: 'count',
  })) as bigint;
}

/** Current account nonce (nonce-space key = 0). Returns 0 for a not-yet-deployed account. */
export async function getNonce(account: Hex): Promise<bigint> {
  return (await publicClient.readContract({
    address: config.entryPoint,
    abi: entryPointAbi,
    functionName: 'getNonce',
    args: [account, 0n],
  })) as bigint;
}

/** Canonical userOpHash from the REAL EntryPoint — the source of truth for what we sign. */
export async function getUserOpHash(userOp: PackedUserOperation): Promise<Hex> {
  return (await publicClient.readContract({
    address: config.entryPoint,
    abi: entryPointAbi,
    functionName: 'getUserOpHash',
    args: [userOp],
  })) as Hex;
}

/**
 * Reads the COUNTERFACTUAL account address for a passkey directly from the factory (getAddress view).
 * The account need not exist yet — this is pure CREATE2 math on-chain, so there is no off-chain
 * bytecode duplication and the address is guaranteed to match what the factory will deploy.
 */
export async function getAccountAddress(x: Hex, y: Hex, salt: bigint = 0n): Promise<Hex> {
  return (await publicClient.readContract({
    address: config.factory,
    abi: factoryAbi,
    functionName: 'getAddress',
    args: [x, y, salt],
  })) as Hex;
}

/** True once the account has on-chain code (i.e. its first UserOp has deployed it). */
export async function isDeployed(account: Hex): Promise<boolean> {
  const code = await publicClient.getBytecode({ address: account });
  return code !== undefined && code !== '0x';
}

/**
 * Builds the `initCode` that lazily deploys the account inside its first UserOp:
 *   factory(20 bytes) || createAccount(x, y, salt) calldata.
 * The EntryPoint's SenderCreator calls this before validation when `sender` has no code.
 */
export function buildFactoryInitCode(x: Hex, y: Hex, salt: bigint = 0n): Hex {
  const factoryData = encodeFunctionData({
    abi: factoryAbi,
    functionName: 'createAccount',
    args: [x, y, salt],
  });
  return concat([config.factory, factoryData]);
}

// Gas limits are hardcoded generous (no gas estimation — see limitations). The FIRST op also
// deploys the account (~7 KB of P256/WebAuthn bytecode, ~1.5M gas), so it needs a much larger
// verification budget. The bundler's eth_call dry-run catches any under-sizing before sending.
const VERIF_GAS_DEPLOY = 2_000_000n;
const VERIF_GAS_NORMAL = 500_000n;
const CALL_GAS = 300_000n;

/**
 * Builds the UserOp (signature still empty) that makes `account` call Counter.increment() through
 * execute(counter, 0, increment()). Pass `initCode` for the account's first (deploying) op, or '0x'
 * once it is already deployed.
 */
export function buildIncrementUserOp(account: Hex, nonce: bigint, initCode: Hex): PackedUserOperation {
  const innerFunc = encodeFunctionData({ abi: counterAbi, functionName: 'increment' });
  const callData = encodeFunctionData({
    abi: executeAbi,
    functionName: 'execute',
    args: [config.counter, 0n, innerFunc],
  });

  const deploying = initCode !== '0x';
  return {
    sender: account,
    nonce,
    initCode,
    callData,
    accountGasLimits: packUint128Pair(deploying ? VERIF_GAS_DEPLOY : VERIF_GAS_NORMAL, CALL_GAS),
    preVerificationGas: deploying ? 200_000n : 100_000n,
    gasFees: packUint128Pair(parseGwei('2'), parseGwei('30')),
    paymasterAndData: buildPaymasterAndData(config.paymaster, 200_000n, 100_000n),
    signature: '0x',
  };
}

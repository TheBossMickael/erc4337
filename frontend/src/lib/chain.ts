import { createPublicClient, http, encodeFunctionData, parseGwei, type Hex } from 'viem';
import { sepolia } from 'viem/chains';
import { config } from '../config';
import { counterAbi, entryPointAbi, executeAbi } from './abis';
import { buildPaymasterAndData, packUint128Pair, type PackedUserOperation } from './userOp';

/** READ client: nonce, getUserOpHash, Counter.count (no signing, no funds). */
export const publicClient = createPublicClient({ chain: sepolia, transport: http(config.rpcUrl) });

/** Current Counter value (proof of effect, before/after). */
export async function getCount(): Promise<bigint> {
  return (await publicClient.readContract({
    address: config.counter,
    abi: counterAbi,
    functionName: 'count',
  })) as bigint;
}

/** Current account nonce (nonce-space key = 0, like V1). */
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
 * Builds the UserOp (signature still empty) that makes `account` call Counter.increment()
 * through execute(counter, 0, increment()). value = 0 → the account needs no funding.
 * Gas limits are hardcoded generous (see V1 limitations: no gas estimation).
 */
export function buildIncrementUserOp(account: Hex, nonce: bigint): PackedUserOperation {
  const innerFunc = encodeFunctionData({ abi: counterAbi, functionName: 'increment' });
  const callData = encodeFunctionData({
    abi: executeAbi,
    functionName: 'execute',
    args: [config.counter, 0n, innerFunc],
  });

  return {
    sender: account,
    nonce,
    initCode: '0x',
    callData,
    accountGasLimits: packUint128Pair(300_000n, 300_000n),
    preVerificationGas: 100_000n,
    gasFees: packUint128Pair(parseGwei('2'), parseGwei('30')),
    paymasterAndData: buildPaymasterAndData(config.paymaster, 200_000n, 100_000n),
    signature: '0x',
  };
}

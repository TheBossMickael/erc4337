import { getAddress, type Hex } from 'viem';
import { config, publicClient, walletClient, bundlerAccount } from './config';
import { entryPointAbi } from './entryPoint';
import { assertValidUserOpHex, toPacked, type UserOperationHex } from './userOp';

/**
 * Implements the `eth_sendUserOperation` JSON-RPC method.
 *
 * Parameters (ERC-4337 spec): [userOp, entryPointAddress]
 * Returns: the userOpHash.
 *
 * Steps:
 *   1. Validate the shape + the targeted EntryPoint.
 *   2. Recompute the userOpHash via the REAL EntryPoint (consistency with the signature).
 *   3. Submit handleOps([userOp], bundler) — the bundler signs and pays the network gas.
 *   4. Wait for the receipt, return the userOpHash.
 *
 * V1 (deliberate simplifications, see docs/limitations-v1.md):
 *   - a single UserOp per bundle (no aggregation).
 *   - no ERC-7562 validation/simulation (forbidden opcodes) nor gas estimation.
 */
export async function handleSendUserOperation(params: unknown[]): Promise<Hex> {
  if (!Array.isArray(params) || params.length < 2) {
    throw new Error('eth_sendUserOperation: expected params [userOp, entryPoint]');
  }

  const opHex = params[0] as UserOperationHex;
  const entryPointParam = params[1] as Hex;

  // 1. Shape validation + EntryPoint
  assertValidUserOpHex(opHex);
  if (getAddress(entryPointParam) !== config.entryPoint) {
    throw new Error(
      `Unsupported EntryPoint: ${entryPointParam} (expected ${config.entryPoint})`,
    );
  }

  const userOp = toPacked(opHex);

  // 2. Canonical hash (source of truth) — also used as the return value
  const userOpHash = (await publicClient.readContract({
    address: config.entryPoint,
    abi: entryPointAbi,
    functionName: 'getUserOpHash',
    args: [userOp],
  })) as Hex;

  // 3. Submission: the bundler is the beneficiary (it receives the gas reimbursement)
  console.log(`[bundler] handleOps for ${userOp.sender}, userOpHash=${userOpHash}`);
  const txHash = await walletClient.writeContract({
    address: config.entryPoint,
    abi: entryPointAbi,
    functionName: 'handleOps',
    args: [[userOp], bundlerAccount.address],
  });

  // 4. Wait for the receipt (V1: synchronous for simplicity)
  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  console.log(`[bundler] tx ${txHash} -> ${receipt.status} (block ${receipt.blockNumber})`);

  return userOpHash;
}

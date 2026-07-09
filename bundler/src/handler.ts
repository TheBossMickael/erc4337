import { BaseError, ContractFunctionRevertedError, getAddress, type Hex } from 'viem';
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
 *   3. DRY-RUN handleOps via eth_call (simulateContract): no gas, no state change. An invalid
 *      UserOp (bad signature => AA24, paymaster underfunded => AA31, ...) reverts HERE, so we
 *      reject it WITHOUT ever sending a transaction — the bundler never wastes gas on a doomed op
 *      (and can't be gas-drained by spamming wrong answers).
 *   4. Submit the real handleOps tx only if the dry-run passed, then wait for the receipt.
 *
 * This lifts part of the V1 "no simulation" limitation (docs/limitations-v1.md): we still do not
 * enforce ERC-7562 opcode rules, but we no longer blindly submit operations that will revert.
 */
export async function handleSendUserOperation(
  params: unknown[],
): Promise<{ userOpHash: Hex; txHash: Hex }> {
  if (!Array.isArray(params) || params.length < 2) {
    throw new Error('eth_sendUserOperation: expected params [userOp, entryPoint]');
  }

  const opHex = params[0] as UserOperationHex;
  const entryPointParam = params[1] as Hex;

  // 1. Shape validation + EntryPoint
  assertValidUserOpHex(opHex);
  if (getAddress(entryPointParam) !== config.entryPoint) {
    throw new Error(`Unsupported EntryPoint: ${entryPointParam} (expected ${config.entryPoint})`);
  }

  const userOp = toPacked(opHex);

  // 2. Canonical hash (source of truth) — also the return value
  const userOpHash = (await publicClient.readContract({
    address: config.entryPoint,
    abi: entryPointAbi,
    functionName: 'getUserOpHash',
    args: [userOp],
  })) as Hex;

  console.log(`[bundler] -> userOp from ${userOp.sender} | userOpHash=${userOpHash}`);

  try {
    // 3. DRY-RUN: simulate handleOps. Throws (without sending a tx) if the op would revert.
    const { request } = await publicClient.simulateContract({
      account: bundlerAccount,
      address: config.entryPoint,
      abi: entryPointAbi,
      functionName: 'handleOps',
      args: [[userOp], bundlerAccount.address],
    });

    // 4. SEND: simulation passed -> the real tx should succeed. The bundler signs and pays it.
    const txHash = await walletClient.writeContract(request);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

    if (receipt.status !== 'success') {
      console.error(`[bundler] !! tx ${txHash} mined but REVERTED (block ${receipt.blockNumber})`);
      throw new Error(`handleOps reverted on-chain: ${txHash}`);
    }

    console.log(`[bundler] OK ACCEPTED ${userOpHash} | tx ${txHash} | block ${receipt.blockNumber}`);
    return { userOpHash, txHash };
  } catch (err) {
    const reason = extractRevertReason(err);
    if (reason) {
      // Validation/execution revert caught at simulation: NO transaction was sent, NO gas spent.
      console.warn(`[bundler] XX REJECTED ${userOpHash} from ${userOp.sender} | reason: ${reason} (no tx sent)`);
      throw new Error(`UserOperation rejected: ${reason}`);
    }
    // Network/other error (not a contract revert): bubble it up unchanged.
    console.error(`[bundler] !! ERROR for ${userOpHash}:`, err instanceof Error ? err.message : err);
    throw err;
  }
}

/**
 * Pulls the human-readable revert reason (e.g. "AA24 signature error") out of a viem contract
 * error. The EntryPoint reverts with FailedOp(opIndex, reason) — reason is the second arg.
 * Returns undefined for non-contract errors (network, RPC, ...), so the caller can tell them apart.
 */
function extractRevertReason(err: unknown): string | undefined {
  if (!(err instanceof BaseError)) return undefined;
  const revert = err.walk((e) => e instanceof ContractFunctionRevertedError);
  if (revert instanceof ContractFunctionRevertedError) {
    const args = revert.data?.args;
    if (args && typeof args[1] === 'string') return args[1]; // FailedOp.reason
    return revert.reason ?? revert.data?.errorName ?? revert.shortMessage;
  }
  return undefined;
}

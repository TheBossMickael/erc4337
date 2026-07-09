import type { Hex } from 'viem';
import { config } from '../config';
import { deriveAccount } from './derive';
import { buildIncrementUserOp, getCount, getNonce, getUserOpHash } from './chain';
import { toHexOp } from './userOp';
import { sendUserOperation } from './bundler';

export interface IncrementOutcome {
  signer: Hex;
  userOpHash: Hex;
  /** The single on-chain tx (bundler handleOps) that contains the increment as an internal call. */
  txHash: Hex;
  countBefore: bigint;
  countAfter: bigint;
}

/**
 * The full USE flow (frontend counterpart of the V1 test client sendUserOp.ts), but the signing
 * key comes from the ANSWERS, not from a .env private key:
 *
 *   answers -> derived key -> build UserOp -> sign userOpHash -> bundler -> Counter.increment()
 *
 * The signature over the canonical userOpHash IS the proof that the user knows the answers
 * matching the account's stored signer address. Gasless: the Paymaster sponsors, the bundler pays.
 */
export async function runIncrement(account: Hex, answers: string[]): Promise<IncrementOutcome> {
  const signer = deriveAccount(answers, config.salt);

  const countBefore = await getCount();

  const nonce = await getNonce(account);
  const userOp = buildIncrementUserOp(account, nonce);
  const userOpHash = await getUserOpHash(userOp);

  // EIP-191 personal_sign convention — MUST mirror the contract's toEthSignedMessageHash.
  // This is the #1 invariant inherited from V1: same prefix on both sides.
  userOp.signature = await signer.signMessage({ message: { raw: userOpHash } });

  const { txHash } = await sendUserOperation(toHexOp(userOp), config.entryPoint);

  const countAfter = await getCount();
  return { signer: signer.address, userOpHash, txHash, countBefore, countAfter };
}

import type { Hex } from 'viem';
import { config } from '../config';
import {
  buildFactoryInitCode,
  buildIncrementUserOp,
  getAccountAddress,
  getCount,
  getNonce,
  getUserOpHash,
  isDeployed,
} from './chain';
import { toHexOp } from './userOp';
import { sendUserOperation } from './bundler';
import { createPasskey, signAssertion, type Passkey } from './webauthn';

export interface IncrementOutcome {
  /** The passkey used (freshly registered on first use, otherwise the known one). */
  passkey: Passkey;
  account: Hex;
  /** True if THIS op deployed the account (counterfactual first use). */
  deployed: boolean;
  userOpHash: Hex;
  /** The single on-chain tx (bundler handleOps) wrapping the increment (+ deploy on first use). */
  txHash: Hex;
  countBefore: bigint;
  countAfter: bigint;
}

/**
 * The full V3 USE flow, driven by a passkey (P-256), gasless:
 *
 *   [register passkey if none] -> counterfactual address -> build UserOp (initCode if not deployed)
 *   -> sign userOpHash with the passkey -> bundler -> Counter.increment()
 *
 * The WebAuthn assertion over the canonical userOpHash IS the proof that the caller holds the
 * device that owns the account. On first use the SAME UserOp also deploys the account via the
 * factory's initCode — no separate deployment step, no server deployer key.
 */
export async function runPasskeyIncrement(existing: Passkey | null): Promise<IncrementOutcome> {
  // 1. First use registers a passkey (biometric prompt #1); later uses reuse the known one.
  const passkey = existing ?? (await createPasskey());

  // 2. Counterfactual address + whether it still needs deploying (drives initCode).
  const account = await getAccountAddress(passkey.x, passkey.y);
  const alreadyDeployed = await isDeployed(account);
  const initCode: Hex = alreadyDeployed ? '0x' : buildFactoryInitCode(passkey.x, passkey.y);

  const countBefore = await getCount();

  // 3. Build the op, fetch the canonical hash, sign it with the passkey (prompt #2, or the only one).
  const nonce = await getNonce(account);
  const userOp = buildIncrementUserOp(account, nonce, initCode);
  const userOpHash = await getUserOpHash(userOp);
  userOp.signature = await signAssertion(userOpHash, passkey.credentialId);

  // 4. Send to the bundler (it simulates, then signs & pays handleOps — deploying the account too
  //    on first use).
  const { txHash } = await sendUserOperation(toHexOp(userOp), config.entryPoint);

  const countAfter = await getCount();
  return {
    passkey,
    account,
    deployed: !alreadyDeployed,
    userOpHash,
    txHash,
    countBefore,
    countAfter,
  };
}

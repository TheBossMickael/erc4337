import type { Hex } from 'viem';
import { config } from '../config';
import type { UserOperationHex } from './userOp';

export interface SendResult {
  userOpHash: Hex;
  /** The single on-chain tx (the bundler's handleOps) that wraps this UserOp. */
  txHash: Hex;
}

/**
 * Sends a UserOperation to the bundler via JSON-RPC (eth_sendUserOperation).
 * The bundler simulates, then signs/pays the handleOps tx and returns both the userOpHash and the
 * resulting txHash. The USER signs nothing here except the off-chain userOpHash (with their passkey).
 *
 * In V3 a first-use UserOp also carries `initCode`, so this same call transparently deploys the
 * account (via the factory, inside handleOps) — no separate deploy request, no server deployer key.
 */
export async function sendUserOperation(op: UserOperationHex, entryPoint: Hex): Promise<SendResult> {
  const res = await fetch(`${config.bundlerUrl}/rpc`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'eth_sendUserOperation',
      params: [op, entryPoint],
    }),
  });
  const json = (await res.json()) as { result?: SendResult; error?: { message: string } };
  if (json.error) throw new Error(json.error.message);
  if (!json.result?.txHash) throw new Error('Bundler returned no result');
  return json.result;
}

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
 * The bundler simulates, then signs/pays the handleOps tx and (V2) returns both the userOpHash and
 * the resulting txHash. The USER signs nothing here except the off-chain userOpHash.
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

/**
 * Asks the backend to deploy a SecretQuestionAccount for the given derived signer address
 * (SETUP flow). The deployer key lives SERVER-SIDE — never in the browser. Returns the address of
 * the freshly deployed account.
 */
export async function deployAccount(signerAddress: Hex): Promise<Hex> {
  const res = await fetch(`${config.bundlerUrl}/deploy`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ signerAddress }),
  });
  const json = (await res.json()) as { account?: Hex; error?: string };
  if (json.error) throw new Error(json.error);
  if (!json.account) throw new Error('Deploy returned no account address');
  return json.account;
}

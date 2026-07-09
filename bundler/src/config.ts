import './loadEnv';
import { createPublicClient, createWalletClient, http, getAddress, type Hex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

/**
 * Reads a REQUIRED environment variable and fails loudly if it is missing.
 * Avoids cryptic errors further down (e.g. "undefined" passed to viem).
 */
function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing environment variable: ${name} (see bundler/.env.example)`);
  }
  return value;
}

/**
 * Centralized bundler configuration, loaded from bundler/.env.
 * - Addresses are normalized (checksum) via getAddress.
 * - OWNER_PRIVATE_KEY is only useful for the test client (signing UserOps),
 *   so it is optional on the server side.
 */
export const config = {
  rpcUrl: required('SEPOLIA_RPC_URL'),
  entryPoint: getAddress(required('ENTRYPOINT_ADDRESS')),
  // Informational only: the bundler relays whatever `sender` the UserOp carries (handler.ts
  // checks only the EntryPoint). Optional in V2 — a freshly SETUP-deployed account needs no restart.
  smartAccount: process.env.SMART_ACCOUNT_ADDRESS
    ? getAddress(process.env.SMART_ACCOUNT_ADDRESS)
    : undefined,
  paymaster: getAddress(required('PAYMASTER_ADDRESS')),
  bundlerKey: required('BUNDLER_PRIVATE_KEY') as Hex,
  // Deployer key for the SETUP flow (POST /deploy). Optional: only required if /deploy is used.
  deployerKey: (process.env.DEPLOYER_PRIVATE_KEY ?? '') as Hex,
  ownerKey: (process.env.OWNER_PRIVATE_KEY ?? '') as Hex,
  port: Number(process.env.PORT ?? 3000),
} as const;

/** READ client (views, nonce, getUserOpHash, waiting for receipt). */
export const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(config.rpcUrl),
});

/** Bundler's EOA — signs and pays the handleOps transaction. */
export const bundlerAccount = privateKeyToAccount(config.bundlerKey);

/** WRITE client (sends the handleOps tx to the network). */
export const walletClient = createWalletClient({
  account: bundlerAccount,
  chain: sepolia,
  transport: http(config.rpcUrl),
});

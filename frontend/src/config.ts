import type { Hex } from 'viem';
import { DEFAULT_SALT } from './lib/derive';

/**
 * Frontend configuration, read from the VITE_* environment variables (frontend/.env).
 *
 * IMPORTANT: every VITE_* var is shipped to the BROWSER. There is intentionally NO private key
 * here — the signing key is DERIVED in the browser from the user's answers. The only secrets that
 * stay server-side (bundler key, deployer key) live in bundler/.env, never here.
 */
const REQUIRED_ENV = [
  'VITE_RPC_URL',
  'VITE_ENTRYPOINT_ADDRESS',
  'VITE_DEMO_ACCOUNT_ADDRESS',
  'VITE_PAYMASTER_ADDRESS',
  'VITE_COUNTER_ADDRESS',
] as const;

/** Names of the required vars that are missing — App shows a friendly setup panel if non-empty. */
export const missingEnv: string[] = REQUIRED_ENV.filter((key) => !import.meta.env[key]);

export const config = {
  rpcUrl: import.meta.env.VITE_RPC_URL ?? '',
  bundlerUrl: import.meta.env.VITE_BUNDLER_URL ?? 'http://localhost:3000',
  entryPoint: (import.meta.env.VITE_ENTRYPOINT_ADDRESS ?? '0x') as Hex,
  demoAccount: (import.meta.env.VITE_DEMO_ACCOUNT_ADDRESS ?? '0x') as Hex,
  paymaster: (import.meta.env.VITE_PAYMASTER_ADDRESS ?? '0x') as Hex,
  counter: (import.meta.env.VITE_COUNTER_ADDRESS ?? '0x') as Hex,
  salt: (import.meta.env.VITE_SALT ?? DEFAULT_SALT) as Hex,
  explorerUrl: import.meta.env.VITE_EXPLORER_URL ?? 'https://sepolia.etherscan.io',
} as const;

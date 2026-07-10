import type { Hex } from 'viem';

/**
 * Frontend configuration, read from the VITE_* environment variables (frontend/.env).
 *
 * IMPORTANT: every VITE_* var is shipped to the BROWSER. There is intentionally NO private key here.
 * In V3 the signing key is a P-256 passkey held by the device's authenticator — it never touches JS.
 * The only secret that stays server-side (the bundler key) lives in bundler/.env, never here.
 */
const REQUIRED_ENV = [
  'VITE_RPC_URL',
  'VITE_ENTRYPOINT_ADDRESS',
  'VITE_FACTORY_ADDRESS',
  'VITE_PAYMASTER_ADDRESS',
  'VITE_COUNTER_ADDRESS',
] as const;

/** Names of the required vars that are missing — App shows a friendly setup panel if non-empty. */
export const missingEnv: string[] = REQUIRED_ENV.filter((key) => !import.meta.env[key]);

export const config = {
  rpcUrl: import.meta.env.VITE_RPC_URL ?? '',
  // Default is RELATIVE (same origin) — correct for the hosted single-service (Render). Local dev
  // sets VITE_BUNDLER_URL=http://localhost:3000 in frontend/.env to reach the bundler on :3000.
  bundlerUrl: import.meta.env.VITE_BUNDLER_URL ?? '',
  entryPoint: (import.meta.env.VITE_ENTRYPOINT_ADDRESS ?? '0x') as Hex,
  // CREATE2 factory: accounts are deployed lazily, inside each passkey's first UserOp (initCode).
  factory: (import.meta.env.VITE_FACTORY_ADDRESS ?? '0x') as Hex,
  paymaster: (import.meta.env.VITE_PAYMASTER_ADDRESS ?? '0x') as Hex,
  counter: (import.meta.env.VITE_COUNTER_ADDRESS ?? '0x') as Hex,
  explorerUrl: import.meta.env.VITE_EXPLORER_URL ?? 'https://sepolia.etherscan.io',
} as const;

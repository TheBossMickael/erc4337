/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_RPC_URL?: string;
  readonly VITE_BUNDLER_URL?: string;
  readonly VITE_ENTRYPOINT_ADDRESS?: string;
  readonly VITE_DEMO_ACCOUNT_ADDRESS?: string;
  readonly VITE_PAYMASTER_ADDRESS?: string;
  readonly VITE_COUNTER_ADDRESS?: string;
  readonly VITE_SALT?: string;
  readonly VITE_EXPLORER_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

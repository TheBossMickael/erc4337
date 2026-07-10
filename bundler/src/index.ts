import { createServer } from './server';
import { config, bundlerAccount } from './config';

/**
 * Bundler entry point: starts the JSON-RPC server.
 * Run with `npm run dev` (auto-reload) or `npm run build && npm start`.
 */
const app = createServer();

app.listen(config.port, () => {
  console.log('─────────────────────────────────────────────');
  console.log(' ERC-4337 bundler started');
  console.log(`  URL        : http://localhost:${config.port}`);
  console.log(`  Bundler EOA: ${bundlerAccount.address}`);
  console.log(`  EntryPoint : ${config.entryPoint}`);
  console.log(`  Account    : ${config.smartAccount ?? '(relays any sender)'}`);
  console.log(`  Paymaster  : ${config.paymaster}`);
  console.log('─────────────────────────────────────────────');
});

import express, { type Request, type Response } from 'express';
import { config } from './config';
import { handleSendUserOperation } from './handler';

/** Sepolia chain id: 11155111 = 0xaa36a7. */
const SEPOLIA_CHAIN_ID = '0xaa36a7';

/**
 * Creates the bundler's JSON-RPC 2.0 server.
 * A single POST / route that dispatches on the `method` field:
 *   - eth_sendUserOperation    (the core of the bundler)
 *   - eth_supportedEntryPoints (stub: returns our EntryPoint)
 *   - eth_chainId              (stub: Sepolia)
 */
export function createServer() {
  const app = express();
  app.use(express.json());

  app.post('/', async (req: Request, res: Response) => {
    const { id, method, params } = req.body ?? {};

    try {
      let result: unknown;
      switch (method) {
        case 'eth_sendUserOperation':
          result = await handleSendUserOperation(params);
          break;
        case 'eth_supportedEntryPoints':
          result = [config.entryPoint];
          break;
        case 'eth_chainId':
          result = SEPOLIA_CHAIN_ID;
          break;
        default:
          throw new Error(`Unsupported method: ${method}`);
      }
      res.json({ jsonrpc: '2.0', id: id ?? null, result });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error('[bundler] error:', message);
      res.json({ jsonrpc: '2.0', id: id ?? null, error: { code: -32000, message } });
    }
  });

  return app;
}

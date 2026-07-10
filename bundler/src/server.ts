import express, { type Request, type Response, type NextFunction } from 'express';
import { existsSync } from 'fs';
import { resolve } from 'path';
import { config } from './config';
import { handleSendUserOperation } from './handler';

/** Sepolia chain id: 11155111 = 0xaa36a7. */
const SEPOLIA_CHAIN_ID = '0xaa36a7';

/** Built frontend, one level up from bundler/src (dev) or bundler/dist (compiled). */
const FRONTEND_DIST = resolve(__dirname, '../../frontend/dist');

/**
 * Permissive CORS. Needed when the frontend is served from a DIFFERENT origin (local dev: Vite on
 * :5173 vs bundler on :3000). When the bundler also serves the frontend (Render, single origin),
 * it is simply a no-op. In V1 the client was Node (no CORS needed).
 */
function cors(req: Request, res: Response, next: NextFunction): void {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.sendStatus(204);
    return;
  }
  next();
}

/**
 * Creates the bundler server.
 *   - POST /rpc     JSON-RPC 2.0, dispatched on `method`:
 *                     eth_sendUserOperation / eth_supportedEntryPoints / eth_chainId
 *   - GET  /*       the built frontend (only if frontend/dist exists — Render "option C"; in local
 *                   dev the frontend runs on the Vite dev server, so this is skipped).
 *
 * V3 note: there is NO deploy endpoint. Accounts deploy themselves lazily via the factory's
 * `initCode` inside the first UserOp (handled transparently in eth_sendUserOperation).
 */
export function createServer() {
  const app = express();
  app.use(cors);
  app.use(express.json());

  // JSON-RPC moved from '/' to '/rpc' so '/' can serve the frontend page.
  app.post('/rpc', async (req: Request, res: Response) => {
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

  // Serve the built frontend (single-service "option C"). Skipped in local dev (no dist).
  if (existsSync(FRONTEND_DIST)) {
    app.use(express.static(FRONTEND_DIST));
    // SPA fallback: any unmatched GET returns index.html (React handles routing). Express 5 wildcard
    // routes are finicky, so we use a trailing middleware instead of app.get('*').
    app.use((req: Request, res: Response, next: NextFunction) => {
      if (req.method === 'GET') {
        res.sendFile(resolve(FRONTEND_DIST, 'index.html'));
      } else {
        next();
      }
    });
    console.log(`[server] serving frontend from ${FRONTEND_DIST}`);
  } else {
    console.log('[server] frontend/dist not found — API only (frontend served separately in dev)');
  }

  return app;
}

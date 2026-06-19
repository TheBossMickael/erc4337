import { config as loadDotenv } from 'dotenv';
import path from 'path';

/**
 * Loads the bundler's .env (bundler/.env), regardless of the directory the server
 * or the client is launched from.
 *
 * __dirname always points to .../bundler/src (ts-node) or .../bundler/dist (build);
 * in both cases, ../.env resolves to bundler/.env.
 *
 * Import this FIRST in any entry point that reads process.env.
 */
loadDotenv({ path: path.resolve(__dirname, '../.env') });

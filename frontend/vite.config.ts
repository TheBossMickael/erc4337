/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Vite + React, with Vitest configured for the (pure, Node-side) derivation library.
export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'node',
  },
});

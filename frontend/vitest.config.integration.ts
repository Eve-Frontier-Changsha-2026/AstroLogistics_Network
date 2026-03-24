import { defineConfig } from 'vitest/config';
import { config } from 'dotenv';
import path from 'node:path';

// Load .env.test.local into process.env BEFORE vitest starts
// (vitest only loads VITE_-prefixed vars by default, TEST_SECRET_KEY needs explicit dotenv)
config({ path: path.resolve(__dirname, '.env.test.local') });

export default defineConfig({
  test: {
    globals: true,
    include: ['src/integration/**/*.integration.test.ts'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
    pool: 'forks',
    poolOptions: {
      forks: { singleFork: true },
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
});

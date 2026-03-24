import { defineConfig } from '@playwright/test';
import { config } from 'dotenv';
import path from 'node:path';

config({ path: path.resolve(__dirname, '.env.test.local') });

export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  retries: 1,
  workers: 1,
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'pnpm dev',
    port: 5173,
    reuseExistingServer: !process.env.CI,
  },
});

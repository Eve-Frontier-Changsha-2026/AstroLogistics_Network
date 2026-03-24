import { test as base, expect } from '@playwright/test';

// Extend Playwright's base test with wallet injection.
// Does NOT navigate — individual tests call page.goto() themselves.
export const test = base.extend<{ walletPage: import('@playwright/test').Page }>({
  walletPage: async ({ page }, use) => {
    const secretKey = process.env.TEST_SECRET_KEY;
    if (!secretKey) throw new Error('TEST_SECRET_KEY not set in .env.test.local');

    // Inject keypair BEFORE any page JS loads via addInitScript
    await page.addInitScript((key) => {
      localStorage.setItem('testKeypair', key);
    }, secretKey);

    // Tests navigate themselves — we only set up the wallet injection
    await use(page);
  },
});

// Re-export expect for convenience
export { expect };

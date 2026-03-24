import { test, expect } from './fixtures/test-wallet.fixture';
import { blockAllGrpc, clearInterceptions } from './helpers/grpc-intercept';

test.describe('ThreatMapPage', () => {
  test('happy: loads threat map data', async ({ walletPage: page }) => {
    await page.goto('/threats');
    await expect(page.getByRole('heading', { name: 'Threat Map' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Decay Lambda:')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByRole('button', { name: 'Query' })).toBeVisible();
  });

  test('error: gRPC failure shows fallback', async ({ page }) => {
    const secretKey = process.env.TEST_SECRET_KEY!;
    await page.addInitScript((key) => localStorage.setItem('testKeypair', key), secretKey);
    await blockAllGrpc(page);
    await page.goto('/threats');
    await expect(page.getByRole('heading', { name: 'Threat Map' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Could not load ThreatMap.')).toBeVisible({ timeout: 10_000 });
    await clearInterceptions(page);
  });

  test('wallet disconnect: shows connect prompt', async ({ page }) => {
    await page.goto('/threats');
    await expect(page.getByText('Connect your wallet to continue.')).toBeVisible({ timeout: 10_000 });
  });
});

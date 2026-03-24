import { test, expect } from './fixtures/test-wallet.fixture';
import { blockAllGrpc, clearInterceptions } from './helpers/grpc-intercept';

test.describe('DashboardPage', () => {
  test('happy: loads and shows FUEL balance + storage count', async ({ walletPage: page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('FUEL Balance')).toBeVisible();
    await expect(page.getByText('My Storages')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Create Storage' })).toBeVisible();
  });

  test('error: gRPC timeout shows fallback values', async ({ page }) => {
    const secretKey = process.env.TEST_SECRET_KEY!;
    await page.addInitScript((key) => localStorage.setItem('testKeypair', key), secretKey);
    await blockAllGrpc(page);
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('FUEL Balance')).toBeVisible();
    await clearInterceptions(page);
  });

  test('wallet disconnect: shows connect prompt', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByText('Connect your wallet to continue.')).toBeVisible({ timeout: 10_000 });
  });
});

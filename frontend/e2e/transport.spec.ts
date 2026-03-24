import { test, expect } from './fixtures/test-wallet.fixture';
import { blockAllGrpc, clearInterceptions } from './helpers/grpc-intercept';

test.describe('TransportPage', () => {
  test('happy: shows order list and create form', async ({ walletPage: page }) => {
    await page.goto('/transport');
    await expect(page.getByRole('heading', { name: 'Transport' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Create Transport Order')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('My Transport Orders')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Create Order' })).toBeVisible();
  });

  test('error: gRPC failure', async ({ page }) => {
    const secretKey = process.env.TEST_SECRET_KEY!;
    await page.addInitScript((key) => localStorage.setItem('testKeypair', key), secretKey);
    await blockAllGrpc(page);
    await page.goto('/transport');
    await expect(page.getByRole('heading', { name: 'Transport' })).toBeVisible({ timeout: 15_000 });
    await clearInterceptions(page);
  });

  test('wallet disconnect: shows connect prompt', async ({ page }) => {
    await page.goto('/transport');
    await expect(page.getByText('Connect your wallet to continue.')).toBeVisible({ timeout: 10_000 });
  });
});

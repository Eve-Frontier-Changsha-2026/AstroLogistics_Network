import { test, expect } from './fixtures/test-wallet.fixture';
import { blockAllGrpc, clearInterceptions } from './helpers/grpc-intercept';

test.describe('BountyBoardPage', () => {
  test('happy: shows contract list and create form', async ({ walletPage: page }) => {
    await page.goto('/bounty');
    await expect(page.getByRole('heading', { name: 'Bounty Board' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('My Contracts')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Create Contract')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Create Contract' })).toBeVisible();
  });

  test('error: gRPC failure shows error state', async ({ page }) => {
    const secretKey = process.env.TEST_SECRET_KEY!;
    await page.addInitScript((key) => localStorage.setItem('testKeypair', key), secretKey);
    await blockAllGrpc(page);
    await page.goto('/bounty');
    await expect(page.getByRole('heading', { name: 'Bounty Board' })).toBeVisible({ timeout: 15_000 });
    await clearInterceptions(page);
  });

  test('wallet disconnect: shows connect prompt', async ({ page }) => {
    await page.goto('/bounty');
    await expect(page.getByText('Connect your wallet to continue.')).toBeVisible({ timeout: 10_000 });
  });
});

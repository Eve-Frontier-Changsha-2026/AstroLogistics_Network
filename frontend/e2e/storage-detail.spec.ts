import { test, expect } from './fixtures/test-wallet.fixture';
import { TESTNET_OBJECTS } from './fixtures/testnet-objects';

test.describe('StorageDetailPage', () => {
  test('happy: shows capacity/fee for existing storage', async ({ walletPage: page }) => {
    await page.goto(`/storage/${TESTNET_OBJECTS.storage1}`);
    await expect(page.getByRole('heading', { name: 'Storage Detail' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Capacity:')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Fee Rate:')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Deposit' })).toBeVisible();
  });

  test('error: object not found shows fallback', async ({ walletPage: page }) => {
    await page.goto('/storage/0x0000000000000000000000000000000000000000000000000000000000000000');
    await expect(page.getByRole('heading', { name: 'Storage Detail' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Storage not found.')).toBeVisible({ timeout: 15_000 });
  });

  test('wallet disconnect: shows connect prompt', async ({ page }) => {
    await page.goto(`/storage/${TESTNET_OBJECTS.storage1}`);
    await expect(page.getByText('Connect your wallet to continue.')).toBeVisible({ timeout: 10_000 });
  });
});

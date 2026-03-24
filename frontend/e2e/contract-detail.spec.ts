import { test, expect } from './fixtures/test-wallet.fixture';

test.describe('ContractDetailPage', () => {
  test('happy: shows contract info or not found for non-existent ID', async ({ walletPage: page }) => {
    await page.goto('/bounty/0x0000000000000000000000000000000000000000000000000000000000000001');
    await expect(page.getByRole('heading', { name: 'Contract Detail' })).toBeVisible({ timeout: 15_000 });
    const notFound = page.getByText('Contract not found or already settled.');
    const contractInfo = page.getByText('Status:');
    await expect(notFound.or(contractInfo)).toBeVisible({ timeout: 15_000 });
  });

  test('error: non-existent contract shows not found', async ({ walletPage: page }) => {
    await page.goto('/bounty/0x0000000000000000000000000000000000000000000000000000000000000001');
    await expect(page.getByRole('heading', { name: 'Contract Detail' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Contract not found or already settled.')).toBeVisible({ timeout: 15_000 });
  });

  test('wallet disconnect: shows connect prompt', async ({ page }) => {
    await page.goto('/bounty/0x0000000000000000000000000000000000000000000000000000000000000001');
    await expect(page.getByText('Connect your wallet to continue.')).toBeVisible({ timeout: 10_000 });
  });
});

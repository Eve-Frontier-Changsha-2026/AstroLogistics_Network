import { test, expect } from './fixtures/test-wallet.fixture';
import { blockTransactionExecution, clearInterceptions } from './helpers/grpc-intercept';

test.describe('FuelStationPage', () => {
  test('happy: shows station stats and buy fuel form', async ({ walletPage: page }) => {
    await page.goto('/fuel');
    await expect(page.getByRole('heading', { name: 'Fuel Station' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Station 1')).toBeVisible();
    await expect(page.getByText('Station 2')).toBeVisible();
    await expect(page.getByText('Fuel Level:')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Base Price:')).toBeVisible();
    await expect(page.getByText('My FUEL Balance')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Buy FUEL' })).toBeVisible();
  });

  test('error: tx failure shows toast error', async ({ walletPage: page }) => {
    await page.goto('/fuel');
    await expect(page.getByText('Fuel Level:')).toBeVisible({ timeout: 15_000 });
    await blockTransactionExecution(page);
    await page.getByRole('button', { name: 'Buy FUEL' }).click();
    await expect(page.getByText('Transaction failed:')).toBeVisible({ timeout: 30_000 });
    await clearInterceptions(page);
  });

  test('wallet disconnect: shows connect prompt', async ({ page }) => {
    await page.goto('/fuel');
    await expect(page.getByText('Connect your wallet to continue.')).toBeVisible({ timeout: 10_000 });
  });
});

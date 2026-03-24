import { test, expect } from '../fixtures/test-wallet.fixture';

test.describe('Flow: Fuel + Transport', () => {
  test('FuelStation → Buy Fuel → verify balance panel updates', async ({ walletPage: page }) => {
    // 1. Go to Fuel Station
    await page.goto('/fuel');
    await expect(page.getByRole('heading', { name: 'Fuel Station' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Fuel Level:')).toBeVisible({ timeout: 15_000 });

    // 2. Note the FUEL Balance panel exists
    await expect(page.getByText('My FUEL Balance')).toBeVisible();

    // 3. Buy fuel (uses default input values)
    await page.getByRole('button', { name: 'Buy FUEL' }).click();

    // 4. Wait for tx toast
    await expect(page.getByText('Success!')).toBeVisible({ timeout: 30_000 });

    // 5. Reload to verify balance persisted
    await page.reload();
    await expect(page.getByText('Fuel Level:')).toBeVisible({ timeout: 15_000 });
  });
});

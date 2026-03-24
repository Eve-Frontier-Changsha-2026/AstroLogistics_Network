import { test, expect } from '../fixtures/test-wallet.fixture';

test.describe('Flow: Storage Deposit', () => {
  test('Dashboard → Create Storage → navigate to detail → verify', async ({ walletPage: page }) => {
    // 1. Start at Dashboard
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible({ timeout: 15_000 });

    // 2. Click "Create Storage"
    await page.getByRole('button', { name: 'Create Storage' }).click();

    // 3. Wait for transaction toast with success
    await expect(page.getByText('Success!')).toBeVisible({ timeout: 30_000 });

    // 4. After tx, new storage should appear in the list
    const storageLinks = page.locator('a[href^="/storage/0x"]');
    await expect(storageLinks.first()).toBeVisible({ timeout: 15_000 });

    // 5. Click first storage link
    await storageLinks.first().click();

    // 6. Verify StorageDetail loaded
    await expect(page.getByRole('heading', { name: 'Storage Detail' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Capacity:')).toBeVisible({ timeout: 15_000 });
  });
});

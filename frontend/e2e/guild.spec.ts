import { test, expect } from './fixtures/test-wallet.fixture';
import { blockTransactionExecution, clearInterceptions } from './helpers/grpc-intercept';

test.describe('GuildPage', () => {
  test('happy: shows guild state (create or detail)', async ({ walletPage: page }) => {
    await page.goto('/guild');
    await expect(page.getByRole('heading', { name: 'Guild' })).toBeVisible({ timeout: 15_000 });
    const createGuild = page.getByText('Create Guild');
    const myGuild = page.getByText('My Guild');
    await expect(createGuild.or(myGuild)).toBeVisible({ timeout: 15_000 });
  });

  test('error: tx failure shows toast error', async ({ walletPage: page }) => {
    await page.goto('/guild');
    await expect(page.getByRole('heading', { name: 'Guild' })).toBeVisible({ timeout: 15_000 });
    const createButton = page.getByRole('button', { name: 'Create Guild' });
    if (await createButton.isVisible({ timeout: 5_000 }).catch(() => false)) {
      await blockTransactionExecution(page);
      const nameInput = page.getByLabel('Guild Name');
      await nameInput.fill('E2E Test Guild');
      await createButton.click();
      await expect(page.getByText('Transaction failed:')).toBeVisible({ timeout: 30_000 });
      await clearInterceptions(page);
    }
  });

  test('wallet disconnect: shows connect prompt', async ({ page }) => {
    await page.goto('/guild');
    await expect(page.getByText('Connect your wallet to continue.')).toBeVisible({ timeout: 10_000 });
  });
});

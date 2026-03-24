import { test, expect } from '../fixtures/test-wallet.fixture';
import { TESTNET_OBJECTS } from '../fixtures/testnet-objects';

test.describe('Flow: Courier Contract', () => {
  test('BountyBoard → Create Contract form is interactable', async ({ walletPage: page }) => {
    // 1. Go to BountyBoard
    await page.goto('/bounty');
    await expect(page.getByRole('heading', { name: 'Bounty Board' })).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Create Contract')).toBeVisible({ timeout: 15_000 });

    // 2. Fill From Storage ID
    const inputs = page.locator('input[type="text"]');
    await inputs.first().fill(TESTNET_OBJECTS.storage1);

    // 3. Verify the form is functional (button visible)
    await expect(page.getByRole('button', { name: 'Create Contract' })).toBeVisible();
  });
});

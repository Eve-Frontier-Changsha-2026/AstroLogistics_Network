import { test, expect } from './fixtures/test-wallet.fixture';

test.describe('Monkey Tests', () => {
  test('paste 10KB string into input fields', async ({ walletPage: page }) => {
    await page.goto('/fuel');
    await expect(page.getByText('Fuel Level:')).toBeVisible({ timeout: 15_000 });
    const longString = 'A'.repeat(10_000);
    const amountInput = page.locator('input[type="number"]').first();
    await amountInput.fill(longString);
    // Page should not crash
    await expect(page.getByRole('heading', { name: 'Fuel Station' })).toBeVisible();
  });

  test('rapid-fire button clicks during transaction pending', async ({ walletPage: page }) => {
    await page.goto('/fuel');
    await expect(page.getByText('Fuel Level:')).toBeVisible({ timeout: 15_000 });
    const buyButton = page.getByRole('button', { name: 'Buy FUEL' });
    // Click rapidly 5 times
    await buyButton.click();
    await buyButton.click({ delay: 50 });
    await buyButton.click({ delay: 50 });
    await buyButton.click({ delay: 50 });
    await buyButton.click({ delay: 50 });
    // Page should not crash — wait for any outcome
    await page.waitForTimeout(5_000);
    await expect(page.getByRole('heading', { name: 'Fuel Station' })).toBeVisible();
  });

  test('navigate away mid-transaction', async ({ walletPage: page }) => {
    await page.goto('/fuel');
    await expect(page.getByText('Fuel Level:')).toBeVisible({ timeout: 15_000 });
    // Start a transaction
    await page.getByRole('button', { name: 'Buy FUEL' }).click();
    // Immediately navigate away
    await page.goto('/guild');
    // New page should load without crash
    await expect(page.getByRole('heading', { name: 'Guild' })).toBeVisible({ timeout: 15_000 });
  });

  test('browser back/forward during form', async ({ walletPage: page }) => {
    await page.goto('/fuel');
    await expect(page.getByRole('heading', { name: 'Fuel Station' })).toBeVisible({ timeout: 15_000 });
    await page.goto('/guild');
    await expect(page.getByRole('heading', { name: 'Guild' })).toBeVisible({ timeout: 15_000 });
    // Go back
    await page.goBack();
    await expect(page.getByRole('heading', { name: 'Fuel Station' })).toBeVisible({ timeout: 15_000 });
    // Go forward
    await page.goForward();
    await expect(page.getByRole('heading', { name: 'Guild' })).toBeVisible({ timeout: 15_000 });
  });

  test('resize to mobile viewport mid-flow', async ({ walletPage: page }) => {
    await page.goto('/fuel');
    await expect(page.getByText('Fuel Level:')).toBeVisible({ timeout: 15_000 });
    // Resize to mobile
    await page.setViewportSize({ width: 375, height: 667 });
    await expect(page.getByRole('heading', { name: 'Fuel Station' })).toBeVisible();
    // Resize back to desktop
    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(page.getByRole('heading', { name: 'Fuel Station' })).toBeVisible();
  });
});

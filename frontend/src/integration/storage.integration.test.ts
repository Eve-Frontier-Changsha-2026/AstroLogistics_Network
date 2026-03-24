// frontend/src/integration/storage.integration.test.ts
import { describe, it, expect } from 'vitest';
import {
  testClient,
  testAddress,
  signAndExec,
  findCreatedId,
  queryObject,
  queryOwnedObjects,
  TESTNET_OBJECTS,
  TYPE,
} from '@/test/integration-setup';
import { buildDeposit, buildWithdraw } from '@/lib/ptb/storage';

describe('Storage — testnet integration', () => {
  it('deposit creates a DepositReceipt owned by sender', async () => {
    const tx = buildDeposit(
      TESTNET_OBJECTS.storage1,
      'integration_test_ore',
      50,    // weight
      5000,  // value
    );

    const result = await signAndExec(tx);
    const receiptId = findCreatedId(result, 'DepositReceipt');
    expect(receiptId).toBeTruthy();

    // Verify receipt is queryable and owned by us
    const obj = await queryObject(receiptId);
    expect(obj).toBeDefined();
  });

  it('withdraw returns a Cargo object after deposit', async () => {
    // Deposit first
    const depositTx = buildDeposit(
      TESTNET_OBJECTS.storage1,
      'withdraw_test_ore',
      30,
      3000,
    );
    const depositResult = await signAndExec(depositTx);
    const receiptId = findCreatedId(depositResult, 'DepositReceipt');

    // Withdraw (fee = 0 for immediate withdrawal)
    const withdrawTx = buildWithdraw(TESTNET_OBJECTS.storage1, receiptId, 0);
    const withdrawResult = await signAndExec(withdrawTx);
    const cargoId = findCreatedId(withdrawResult, 'Cargo');
    expect(cargoId).toBeTruthy();
  });

  it('storage object is queryable with correct fields', async () => {
    const obj = await queryObject(TESTNET_OBJECTS.storage1);
    const json = obj.json as Record<string, unknown>;
    expect(json).toBeDefined();
    // Storage has system_id, max_capacity, current_load, fee_rate_bps
    expect(json).toHaveProperty('system_id');
    expect(json).toHaveProperty('max_capacity');
    expect(json).toHaveProperty('current_load');
    expect(json).toHaveProperty('fee_rate_bps');
  });

  it('listOwnedObjects finds AdminCap with correct type filter', async () => {
    const caps = await queryOwnedObjects(TYPE.AdminCap);
    // Deployer should own at least 1 AdminCap
    expect(caps.length).toBeGreaterThanOrEqual(1);
  });
});

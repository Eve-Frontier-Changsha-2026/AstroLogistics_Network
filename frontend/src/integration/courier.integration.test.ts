// frontend/src/integration/courier.integration.test.ts
import { describe, it, expect } from 'vitest';
import {
  testAddress,
  signAndExec,
  findCreatedId,
  queryObject,
  queryOwnedObjects,
  TESTNET_OBJECTS,
  ADMIN_CAPS,
  TYPE,
} from '@/test/integration-setup';
import { buildDeposit } from '@/lib/ptb/storage';
import {
  buildCreateContract,
  buildAcceptContract,
  buildPickupAndDeliver,
  buildConfirmDelivery,
  buildSettle,
} from '@/lib/ptb/courier';

describe('Courier Market — testnet integration', () => {
  it('createContract creates a CourierContract with Open status', async () => {
    // Deposit to get a receipt
    const depositTx = buildDeposit(
      TESTNET_OBJECTS.storage1,
      'courier_test_cargo',
      40,
      4000,
    );
    const depositResult = await signAndExec(depositTx);
    const receiptId = findCreatedId(depositResult, 'DepositReceipt');

    // Create contract
    const contractTx = buildCreateContract(
      TESTNET_OBJECTS.storage1,
      TESTNET_OBJECTS.storage2,
      receiptId,
      10000,  // rewardAmount
      5000,   // cancelPenaltyAmount
      3000,   // minCourierDeposit
      [1, 2], // route
      600000, // deadlineDuration (10 min)
    );
    const result = await signAndExec(contractTx);
    const contractId = findCreatedId(result, 'CourierContract');
    expect(contractId).toBeTruthy();

    // Query contract
    const obj = await queryObject(contractId);
    const json = obj.json as Record<string, unknown>;
    expect(json).toBeDefined();
    expect(json).toHaveProperty('status');
    // Status 0 = Open
    expect(Number(json.status)).toBe(0);
  });

  it('full courier lifecycle: create → accept → pickup → confirm → settle', async () => {
    // Deposit
    const depositTx = buildDeposit(
      TESTNET_OBJECTS.storage1,
      'lifecycle_cargo',
      25,
      2500,
    );
    const depositResult = await signAndExec(depositTx);
    const receiptId = findCreatedId(depositResult, 'DepositReceipt');

    // Create contract
    const contractTx = buildCreateContract(
      TESTNET_OBJECTS.storage1,
      TESTNET_OBJECTS.storage2,
      receiptId,
      8000,   // reward
      4000,   // penalty
      2000,   // minDeposit
      [1, 2],
      600000, // 10 min deadline
    );
    const contractResult = await signAndExec(contractTx);
    const contractId = findCreatedId(contractResult, 'CourierContract');

    // Accept contract — same keypair acts as client + courier on testnet.
    // If contract adds client != courier check, this test needs a second keypair.
    const acceptTx = buildAcceptContract(contractId, 3000); // deposit > minCourierDeposit
    const acceptResult = await signAndExec(acceptTx);
    // Accept creates a CourierBadge
    const badgeId = findCreatedId(acceptResult, 'CourierBadge');
    expect(badgeId).toBeTruthy();

    // Verify status changed to Accepted (1)
    const afterAccept = await queryObject(contractId);
    const acceptJson = afterAccept.json as Record<string, unknown>;
    expect(Number(acceptJson.status)).toBe(1);

    // Pickup and deliver
    const pickupTx = buildPickupAndDeliver(
      contractId,
      badgeId,
      TESTNET_OBJECTS.storage1,
      TESTNET_OBJECTS.storage2,
    );
    await signAndExec(pickupTx);

    // Verify status changed to PendingConfirm (2)
    const afterPickup = await queryObject(contractId);
    const pickupJson = afterPickup.json as Record<string, unknown>;
    expect(Number(pickupJson.status)).toBe(2);

    // Confirm delivery (client confirms)
    const confirmTx = buildConfirmDelivery(contractId);
    await signAndExec(confirmTx);

    // Verify status changed to Delivered (3)
    const afterConfirm = await queryObject(contractId);
    const confirmJson = afterConfirm.json as Record<string, unknown>;
    expect(Number(confirmJson.status)).toBe(3);

    // Settle (needs OracleCap — deployer is also oracle in testnet)
    const settleTx = buildSettle(contractId, badgeId, ADMIN_CAPS.oracleCap);
    await signAndExec(settleTx);

    // After settle, contract object may be consumed/deleted
    // Just verify the tx succeeded (no throw)
  });

  it('CourierBadge appears in owned objects after accept', async () => {
    const badges = await queryOwnedObjects(TYPE.CourierBadge);
    // After running the lifecycle test, at least 1 badge should exist
    expect(badges.length).toBeGreaterThanOrEqual(1);
  });
});

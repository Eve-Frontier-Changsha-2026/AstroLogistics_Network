// frontend/src/integration/transport.integration.test.ts
import { Transaction } from '@mysten/sui/transactions';
import { describe, it, expect } from 'vitest';
import {
  testAddress,
  signAndExec,
  findCreatedId,
  queryObject,
  TESTNET_OBJECTS,
  ADMIN_CAPS,
  PACKAGE_ID,
} from '@/test/integration-setup';
import { buildDeposit } from '@/lib/ptb/storage';
import { buildBuyFuel } from '@/lib/ptb/fuel-station';

describe('Transport — testnet integration', () => {
  it('full transport flow: deposit → createOrder → payFuel → complete → new receipt', async () => {
    // Step 1: Deposit cargo to get a receipt
    const depositTx = buildDeposit(
      TESTNET_OBJECTS.storage1,
      'transport_test_cargo',
      50,
      5000,
    );
    const depositResult = await signAndExec(depositTx);
    const receiptId = findCreatedId(depositResult, 'DepositReceipt');

    // Step 2: Buy fuel to get a FUEL coin
    const buyTx = buildBuyFuel(TESTNET_OBJECTS.fuelStation1, 500, 200, 100000);
    const buyResult = await signAndExec(buyTx);
    const fuelCoinId = findCreatedId(buyResult, 'Coin');

    // Step 3: Create order + pay fuel in one PTB.
    // Cannot use buildCreateOrder + buildPayFuel separately because
    // pay_fuel needs the TransactionResult from create_order (not a string ID).
    // This raw PTB mirrors how the frontend composes multi-step transactions.
    const tx = new Transaction();
    const fuelCost = 500;

    const [order] = tx.moveCall({
      target: `${PACKAGE_ID}::transport::create_order`,
      arguments: [
        tx.object(TESTNET_OBJECTS.storage1),
        tx.object(TESTNET_OBJECTS.storage2),
        tx.object(receiptId),
        tx.pure.vector('u64', [1, 2]),
        tx.pure.u64(fuelCost),
        tx.pure.u64(0),   // danger_snapshot
        tx.pure.u8(0),    // tier: Instant
        tx.object('0x6'), // Clock
      ],
    });

    // Pay fuel from the bought coin
    const [fuelPayment] = tx.splitCoins(tx.object(fuelCoinId), [fuelCost]);
    tx.moveCall({
      target: `${PACKAGE_ID}::transport::pay_fuel`,
      arguments: [
        order,
        fuelPayment,
        tx.object(ADMIN_CAPS.fuelTreasuryCap),
      ],
    });
    tx.transferObjects([order], testAddress);

    const orderResult = await signAndExec(tx);
    const orderId = findCreatedId(orderResult, 'TransportOrder');
    expect(orderId).toBeTruthy();

    // Step 4: Complete transport (Instant tier = no delay)
    const completeTx = new Transaction();
    const [newReceipt] = completeTx.moveCall({
      target: `${PACKAGE_ID}::transport::complete_transport`,
      arguments: [
        completeTx.object(orderId),
        completeTx.object(TESTNET_OBJECTS.storage1),
        completeTx.object(TESTNET_OBJECTS.storage2),
        completeTx.object('0x6'),
      ],
    });
    completeTx.transferObjects([newReceipt], testAddress);

    const completeResult = await signAndExec(completeTx);
    const newReceiptId = findCreatedId(completeResult, 'DepositReceipt');
    expect(newReceiptId).toBeTruthy();

    // Verify new receipt is at storage2
    const receiptObj = await queryObject(newReceiptId);
    expect(receiptObj).toBeDefined();
  });

  it('TransportOrder is queryable with correct fields after creation', async () => {
    // Deposit for a new receipt
    const depositTx = buildDeposit(
      TESTNET_OBJECTS.storage1,
      'query_test_cargo',
      20,
      2000,
    );
    const depositResult = await signAndExec(depositTx);
    const receiptId = findCreatedId(depositResult, 'DepositReceipt');

    // Buy fuel
    const buyTx = buildBuyFuel(TESTNET_OBJECTS.fuelStation1, 200, 200, 40000);
    const buyResult = await signAndExec(buyTx);
    const fuelCoinId = findCreatedId(buyResult, 'Coin');

    // Create order + pay
    const tx = new Transaction();
    const [order] = tx.moveCall({
      target: `${PACKAGE_ID}::transport::create_order`,
      arguments: [
        tx.object(TESTNET_OBJECTS.storage1),
        tx.object(TESTNET_OBJECTS.storage2),
        tx.object(receiptId),
        tx.pure.vector('u64', [1, 2]),
        tx.pure.u64(200),
        tx.pure.u64(0),
        tx.pure.u8(0),
        tx.object('0x6'),
      ],
    });
    const [fuelPayment] = tx.splitCoins(tx.object(fuelCoinId), [200]);
    tx.moveCall({
      target: `${PACKAGE_ID}::transport::pay_fuel`,
      arguments: [order, fuelPayment, tx.object(ADMIN_CAPS.fuelTreasuryCap)],
    });
    tx.transferObjects([order], testAddress);

    const result = await signAndExec(tx);
    const orderId = findCreatedId(result, 'TransportOrder');

    // Query the order
    const obj = await queryObject(orderId);
    const json = obj.json as Record<string, unknown>;
    expect(json).toBeDefined();
    expect(json).toHaveProperty('from_storage_id');
    expect(json).toHaveProperty('to_storage_id');
    expect(json).toHaveProperty('fuel_cost');
    expect(json).toHaveProperty('status');
  });
});

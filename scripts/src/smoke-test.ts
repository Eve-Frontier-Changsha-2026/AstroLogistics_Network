/**
 * AstroLogistics Network — Testnet Smoke Test
 *
 * Tests core flows:
 *   1. Deposit cargo into storage1
 *   2. Supply FUEL to fuel station
 *   3. Buy FUEL from fuel station (SUI → FUEL)
 *   4. Create transport order (storage1 → storage2) + pay fuel (Instant tier, 0 delay)
 *   5. Complete transport (cargo appears in storage2)
 *   6. Withdraw cargo from storage2
 *
 * Prereq: Run init-testnet.ts first → testnet-objects.json
 */
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Transaction } from '@mysten/sui/transactions';
import { readFileSync } from 'fs';
import {
  GRPC_URL,
  NETWORK,
  PACKAGE_ID,
  FUEL_TREASURY_CAP,
  loadKeypair,
} from './config.js';

const CLOCK = '0x6';

const client = new SuiGrpcClient({ baseUrl: GRPC_URL, network: NETWORK });
const keypair = loadKeypair();
const sender = keypair.toSuiAddress();

// Load objects from init
const objects = JSON.parse(
  readFileSync(new URL('./testnet-objects.json', import.meta.url), 'utf-8'),
);

const {
  storage1, storage2, fuelStation1,
  threatMap, oracleCap, fuelCoin,
} = objects;

console.log('AstroLogistics Network — Smoke Test');
console.log(`Sender: ${sender}`);
console.log(`Network: ${NETWORK}`);
console.log(`Objects:`, JSON.stringify(objects, null, 2), '\n');

// ─── Helpers ────────────────────────────────────────────────────────

async function execTx(label: string, tx: Transaction) {
  console.log(`\n>>> ${label}...`);
  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
    include: { objectTypes: true },
  });

  if (result.$kind === 'FailedTransaction') {
    console.error(`FAILED:`, JSON.stringify(result.FailedTransaction.status, null, 2));
    throw new Error(`${label} failed`);
  }

  const txData = result.Transaction!;
  console.log(`  digest: ${txData.digest}`);
  await client.waitForTransaction({ digest: txData.digest });

  return { digest: txData.digest, objectTypes: txData.objectTypes ?? {} };
}

function findCreatedId(result: { objectTypes: Record<string, string> }, typeSubstr: string): string {
  for (const [id, type] of Object.entries(result.objectTypes)) {
    if (type.includes(typeSubstr)) return id;
  }
  throw new Error(`Object type containing "${typeSubstr}" not found in tx output`);
}

// ─── Test 1: Deposit cargo into storage1 ────────────────────────────

async function test1_deposit(): Promise<string> {
  const tx = new Transaction();

  const [receipt] = tx.moveCall({
    target: `${PACKAGE_ID}::storage::deposit`,
    arguments: [
      tx.object(storage1),                    // &mut Storage
      tx.pure.vector('u8', Array.from(Buffer.from('rare_ore'))), // item_type
      tx.pure.u64(100),                       // weight
      tx.pure.u64(10_000),                    // value
      tx.object.clock(),                      // &Clock
    ],
  });
  tx.transferObjects([receipt], sender);

  const result = await execTx('Test 1: Deposit cargo', tx);
  const receiptId = findCreatedId(result, 'DepositReceipt');
  console.log(`  DepositReceipt: ${receiptId}`);
  return receiptId;
}

// ─── Test 2: Supply FUEL to fuel station ────────────────────────────

async function test2_supplyFuel(): Promise<string> {
  const tx = new Transaction();

  // Split FUEL from our minted coin
  const [fuelPortion] = tx.splitCoins(tx.object(fuelCoin), [100_000_000]); // 0.1 FUEL

  const [supplierReceipt] = tx.moveCall({
    target: `${PACKAGE_ID}::fuel_station::supply_fuel`,
    arguments: [
      tx.object(fuelStation1),
      fuelPortion,
    ],
  });
  tx.transferObjects([supplierReceipt], sender);

  const result = await execTx('Test 2: Supply FUEL to station', tx);
  const receiptId = findCreatedId(result, 'SupplierReceipt');
  console.log(`  SupplierReceipt: ${receiptId}`);
  return receiptId;
}

// ─── Test 3: Buy FUEL from station (SUI → FUEL) ────────────────────

async function test3_buyFuel(): Promise<string> {
  const tx = new Transaction();

  // Pay SUI from gas coin
  const amount = 1000; // buy 1000 FUEL units
  const maxPrice = 200; // max price per unit

  const [suiPayment] = tx.splitCoins(tx.gas, [amount * maxPrice]); // worst case

  const [boughtFuel] = tx.moveCall({
    target: `${PACKAGE_ID}::fuel_station::buy_fuel`,
    arguments: [
      tx.object(fuelStation1),
      suiPayment,
      tx.pure.u64(amount),
      tx.pure.u64(maxPrice),
    ],
  });
  tx.transferObjects([boughtFuel], sender);

  const result = await execTx('Test 3: Buy FUEL from station', tx);
  const coinId = findCreatedId(result, 'Coin');
  console.log(`  Bought FUEL Coin: ${coinId}`);
  return coinId;
}

// ─── Test 4: Create transport order + pay fuel ──────────────────────

async function test4_createAndPayOrder(receiptId: string): Promise<string> {
  const tx = new Transaction();

  // weight=100, min_fuel_cost_per_weight=10 → min fuel_cost = 1000
  const fuelCost = 1000;

  // Create order: Instant tier (0), route [1,2], danger_snapshot 0
  const [order] = tx.moveCall({
    target: `${PACKAGE_ID}::transport::create_order`,
    arguments: [
      tx.object(storage1),                          // from_storage
      tx.object(storage2),                          // to_storage
      tx.object(receiptId),                         // receipt (owned)
      tx.pure.vector('u64', [1n, 2n]),              // route
      tx.pure.u64(fuelCost),                        // fuel_cost
      tx.pure.u64(0),                               // danger_snapshot
      tx.pure.u8(0),                                // tier: Instant
      tx.object.clock(),                            // &Clock
    ],
  });

  // Pay fuel — split from our minted FUEL coin
  const [fuelPayment] = tx.splitCoins(tx.object(fuelCoin), [fuelCost]);

  tx.moveCall({
    target: `${PACKAGE_ID}::transport::pay_fuel`,
    arguments: [
      order,                  // &mut TransportOrder
      fuelPayment,            // Coin<FUEL>
      tx.object(FUEL_TREASURY_CAP), // &mut FuelTreasuryCap
    ],
  });

  tx.transferObjects([order], sender);

  const result = await execTx('Test 4: Create order + pay fuel', tx);
  const orderId = findCreatedId(result, 'TransportOrder');
  console.log(`  TransportOrder: ${orderId}`);
  return orderId;
}

// ─── Test 5: Complete transport ─────────────────────────────────────

async function test5_completeTransport(orderId: string): Promise<string> {
  const tx = new Transaction();

  const [newReceipt] = tx.moveCall({
    target: `${PACKAGE_ID}::transport::complete_transport`,
    arguments: [
      tx.object(orderId),   // TransportOrder (consumed)
      tx.object(storage1),  // &mut from_storage
      tx.object(storage2),  // &mut to_storage
      tx.object.clock(),    // &Clock
    ],
  });
  tx.transferObjects([newReceipt], sender);

  const result = await execTx('Test 5: Complete transport', tx);
  const receiptId = findCreatedId(result, 'DepositReceipt');
  console.log(`  New DepositReceipt at storage2: ${receiptId}`);
  return receiptId;
}

// ─── Test 6: Withdraw cargo from storage2 ───────────────────────────

async function test6_withdraw(receiptId: string) {
  const tx = new Transaction();

  // Fee should be 0 (same-day withdraw, 0 days stored)
  // Still need to provide a SUI coin — even if fee=0
  const [zeroPayment] = tx.splitCoins(tx.gas, [0]);

  const [cargo] = tx.moveCall({
    target: `${PACKAGE_ID}::storage::withdraw`,
    arguments: [
      tx.object(storage2),
      tx.object(receiptId),
      zeroPayment,
      tx.object.clock(),
    ],
  });
  tx.transferObjects([cargo], sender);

  const result = await execTx('Test 6: Withdraw cargo from storage2', tx);
  const cargoId = findCreatedId(result, 'Cargo');
  console.log(`  Withdrawn Cargo: ${cargoId}`);
  return cargoId;
}

// ─── Main ───────────────────────────────────────────────────────────

async function main() {
  console.log('Starting smoke tests...\n');

  // Test 1: Deposit
  const receiptId = await test1_deposit();

  // Test 2: Supply FUEL
  await test2_supplyFuel();

  // Test 3: Buy FUEL
  await test3_buyFuel();

  // Test 4: Create transport + pay fuel (Instant tier = 0 delay)
  const orderId = await test4_createAndPayOrder(receiptId);

  // Test 5: Complete transport (Instant tier = no delay)
  const newReceiptId = await test5_completeTransport(orderId);

  // Test 6: Withdraw from storage2
  await test6_withdraw(newReceiptId);

  console.log('\n=== ALL SMOKE TESTS PASSED ===');
}

main().catch((err) => {
  console.error('\nSMOKE TEST FAILED:', err);
  process.exit(1);
});

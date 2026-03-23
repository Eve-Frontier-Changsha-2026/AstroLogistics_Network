/**
 * AstroLogistics Network — Testnet Initialization
 *
 * TX1: create_threat_map + create_storage x2 + mint FUEL (independent)
 * TX2: create_station x2 (needs Storage shared objects from TX1)
 *
 * Outputs all created object IDs for config.
 */
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Transaction } from '@mysten/sui/transactions';
import { writeFileSync } from 'fs';
import {
  GRPC_URL,
  NETWORK,
  PACKAGE_ID,
  FUEL_TREASURY_CAP,
  INIT_PARAMS,
  loadKeypair,
} from './config.js';

const client = new SuiGrpcClient({ baseUrl: GRPC_URL, network: NETWORK });
const keypair = loadKeypair();
const sender = keypair.toSuiAddress();

console.log(`Sender: ${sender}`);
console.log(`Package: ${PACKAGE_ID}`);
console.log(`Network: ${NETWORK}\n`);

// ─── Helper: execute + parse object types ───────────────────────────

async function execAndParse(label: string, tx: Transaction): Promise<Record<string, string>> {
  console.log(`=== ${label} ===`);

  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
    include: { objectTypes: true },
  });

  if (result.$kind === 'FailedTransaction') {
    throw new Error(`${label} failed: ${JSON.stringify(result.FailedTransaction.status)}`);
  }

  const txData = result.Transaction!;
  console.log(`  digest: ${txData.digest}`);
  await client.waitForTransaction({ digest: txData.digest });

  return txData.objectTypes ?? {};
}

// ─── TX1: Create shared objects + mint FUEL ─────────────────────────

async function tx1_createSharedObjects() {
  const tx = new Transaction();

  // 1. create_threat_map → OracleCap
  const [oracleCap] = tx.moveCall({
    target: `${PACKAGE_ID}::threat_oracle::create_threat_map`,
    arguments: [tx.pure.u64(INIT_PARAMS.decayLambda)],
  });

  // 2. create_storage #1 (Station Alpha, system_id=1)
  const s1 = INIT_PARAMS.storage1;
  const [adminCap1] = tx.moveCall({
    target: `${PACKAGE_ID}::storage::create_storage`,
    arguments: [
      tx.pure.u64(s1.systemId),
      tx.pure.u64(s1.maxCapacity),
      tx.pure.u64(s1.feeRateBps),
      tx.object.clock(),
    ],
  });

  // 3. create_storage #2 (Station Beta, system_id=2)
  const s2 = INIT_PARAMS.storage2;
  const [adminCap2] = tx.moveCall({
    target: `${PACKAGE_ID}::storage::create_storage`,
    arguments: [
      tx.pure.u64(s2.systemId),
      tx.pure.u64(s2.maxCapacity),
      tx.pure.u64(s2.feeRateBps),
      tx.object.clock(),
    ],
  });

  // 4. mint initial FUEL supply
  const [fuelCoin] = tx.moveCall({
    target: `${PACKAGE_ID}::fuel::mint`,
    arguments: [
      tx.object(FUEL_TREASURY_CAP),
      tx.pure.u64(INIT_PARAMS.mintAmount),
    ],
  });

  // Transfer all caps + minted FUEL to sender
  tx.transferObjects([oracleCap, adminCap1, adminCap2, fuelCoin], sender);

  const created = await execAndParse('TX1: Creating shared objects + minting FUEL', tx);
  const objectIds: Record<string, string> = {};

  for (const [objectId, type] of Object.entries(created)) {
    if (type.includes('ThreatMap')) objectIds.threatMap = objectId;
    else if (type.includes('OracleCap')) objectIds.oracleCap = objectId;
    else if (type.includes('Storage')) {
      if (!objectIds.storage1) objectIds.storage1 = objectId;
      else objectIds.storage2 = objectId;
    }
    else if (type.includes('AdminCap')) {
      if (!objectIds.adminCap1) objectIds.adminCap1 = objectId;
      else objectIds.adminCap2 = objectId;
    }
    else if (type.includes('Coin')) objectIds.fuelCoin = objectId;
  }

  console.log('  Created:', JSON.stringify(objectIds, null, 2));
  return objectIds;
}

// ─── TX2: Create fuel stations (need Storage refs) ──────────────────

async function tx2_createFuelStations(storageIds: { storage1: string; storage2: string }) {
  const tx = new Transaction();
  const fp = INIT_PARAMS.fuelStation;

  const [stationCap1] = tx.moveCall({
    target: `${PACKAGE_ID}::fuel_station::create_station`,
    arguments: [
      tx.object(storageIds.storage1),
      tx.pure.u64(fp.basePrice),
      tx.pure.u64(fp.alpha),
      tx.pure.u64(fp.ownerFeeBps),
    ],
  });

  const [stationCap2] = tx.moveCall({
    target: `${PACKAGE_ID}::fuel_station::create_station`,
    arguments: [
      tx.object(storageIds.storage2),
      tx.pure.u64(fp.basePrice),
      tx.pure.u64(fp.alpha),
      tx.pure.u64(fp.ownerFeeBps),
    ],
  });

  tx.transferObjects([stationCap1, stationCap2], sender);

  const created = await execAndParse('TX2: Creating fuel stations', tx);
  const objectIds: Record<string, string> = {};

  for (const [objectId, type] of Object.entries(created)) {
    if (type.includes('FuelStation')) {
      if (!objectIds.fuelStation1) objectIds.fuelStation1 = objectId;
      else objectIds.fuelStation2 = objectId;
    }
    else if (type.includes('StationCap')) {
      if (!objectIds.stationCap1) objectIds.stationCap1 = objectId;
      else objectIds.stationCap2 = objectId;
    }
  }

  console.log('  Created:', JSON.stringify(objectIds, null, 2));
  return objectIds;
}

// ─── Main ───────────────────────────────────────────────────────────

async function main() {
  console.log('AstroLogistics Network — Testnet Initialization\n');

  const tx1Objects = await tx1_createSharedObjects();

  if (!tx1Objects.storage1 || !tx1Objects.storage2) {
    throw new Error('Storage IDs not found in TX1 output');
  }

  const tx2Objects = await tx2_createFuelStations({
    storage1: tx1Objects.storage1,
    storage2: tx1Objects.storage2,
  });

  const allObjects = { ...tx1Objects, ...tx2Objects };
  console.log('\n=== INITIALIZATION COMPLETE ===');
  console.log(JSON.stringify(allObjects, null, 2));

  writeFileSync(
    new URL('./testnet-objects.json', import.meta.url),
    JSON.stringify(allObjects, null, 2),
  );
  console.log('\nSaved to scripts/src/testnet-objects.json');
}

main().catch((err) => {
  console.error('INIT FAILED:', err);
  process.exit(1);
});

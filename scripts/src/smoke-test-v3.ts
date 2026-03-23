/**
 * AstroLogistics Network — v3 Smoke Test
 *
 * Tests v3-specific features:
 *   7. Create guild
 *   8. Set storage guild + encrypted coords
 *   9. Create guild bonus contract → deposit cargo, then create_contract_with_guild_bonus
 *   10. Seal approve guild member (access control only — Seal SDK TODO)
 *
 * Prereq: Run smoke-test.ts first (core flows), testnet-objects.json exists.
 */
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Transaction } from '@mysten/sui/transactions';
import { readFileSync, writeFileSync } from 'fs';
import {
  GRPC_URL,
  NETWORK,
  PACKAGE_ID,
  ORIGINAL_PACKAGE_ID,
  loadKeypair,
} from './config.js';

const CLOCK = '0x6';

const client = new SuiGrpcClient({ baseUrl: GRPC_URL, network: NETWORK });
const keypair = loadKeypair();
const sender = keypair.toSuiAddress();

// Load existing objects
const objects = JSON.parse(
  readFileSync(new URL('./testnet-objects.json', import.meta.url), 'utf-8'),
);

const { storage1, storage2, adminCap2: adminCapForStorage1 } = objects;

console.log('AstroLogistics Network — v3 Smoke Test');
console.log(`Sender: ${sender}`);
console.log(`Network: ${NETWORK}`);
console.log(`Package (v3): ${PACKAGE_ID}\n`);

// ─── Helpers ────────────────────────────────────────────────────────

async function execTx(label: string, tx: Transaction) {
  console.log(`\n>>> ${label}...`);
  tx.setGasBudget(50_000_000); // skip simulation by setting explicit gas budget
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

// ─── Test 7: Create guild ──────────────────────────────────────────

async function test7_createGuild(): Promise<{ guildId: string; leaderCapId: string }> {
  const tx = new Transaction();

  tx.moveCall({
    target: `${PACKAGE_ID}::guild::create_guild`,
    arguments: [
      tx.pure.string('AstroLogistics Pioneers'),
      tx.object.clock(),
    ],
  });

  const result = await execTx('Test 7: Create guild', tx);
  const guildId = findCreatedId(result, 'Guild');
  const leaderCapId = findCreatedId(result, 'GuildMemberCap');
  console.log(`  Guild: ${guildId}`);
  console.log(`  LeaderCap: ${leaderCapId}`);
  return { guildId, leaderCapId };
}

// ─── Test 8: Set storage guild + encrypted coords ──────────────────

async function test8_setStorageGuild(guildId: string) {
  const tx = new Transaction();

  // Set guild_id on storage1
  tx.moveCall({
    target: `${PACKAGE_ID}::storage::set_storage_guild`,
    arguments: [
      tx.object(storage1),
      tx.object(adminCapForStorage1),
      tx.pure.id(guildId),
    ],
  });

  // Set encrypted coords (fake encrypted data for smoke test)
  const fakeEncryptedCoords = Array.from(Buffer.from('encrypted:x=100,y=200,z=50'));
  tx.moveCall({
    target: `${PACKAGE_ID}::storage::set_encrypted_coords`,
    arguments: [
      tx.object(storage1),
      tx.object(adminCapForStorage1),
      tx.pure.vector('u8', fakeEncryptedCoords),
    ],
  });

  await execTx('Test 8: Set storage guild + encrypted coords', tx);
  console.log(`  Storage1 guild set to: ${guildId}`);
  console.log(`  Encrypted coords set (${fakeEncryptedCoords.length} bytes)`);
}

// ─── Test 9: Create guild bonus contract ───────────────────────────

async function test9_createGuildBonusContract(guildId: string): Promise<string> {
  const tx = new Transaction();

  // First deposit cargo into storage1
  const [receipt] = tx.moveCall({
    target: `${PACKAGE_ID}::storage::deposit`,
    arguments: [
      tx.object(storage1),
      tx.pure.vector('u8', Array.from(Buffer.from('guild_cargo'))),
      tx.pure.u64(50),     // weight
      tx.pure.u64(5000),   // value
      tx.object.clock(),
    ],
  });

  // Create contract with guild bonus
  const reward = 2000;
  const cancelPenalty = 1000;
  const guildBonus = 500;
  const minCourierDeposit = 5000;
  const deadlineDuration = 3600_000; // 1 hour

  const [rewardCoin] = tx.splitCoins(tx.gas, [reward]);
  const [penaltyCoin] = tx.splitCoins(tx.gas, [cancelPenalty]);
  const [bonusCoin] = tx.splitCoins(tx.gas, [guildBonus]);

  tx.moveCall({
    target: `${PACKAGE_ID}::courier_market::create_contract_with_guild_bonus`,
    arguments: [
      tx.object(storage1),     // from_storage
      tx.object(storage2),     // to_storage
      receipt,                 // DepositReceipt
      rewardCoin,              // reward
      penaltyCoin,             // cancel_penalty
      bonusCoin,               // guild_bonus
      tx.pure.u64(minCourierDeposit),
      tx.pure.vector('u64', [1n, 2n]),  // route
      tx.pure.u64(deadlineDuration),
      tx.pure.id(guildId),    // required_guild_id
      tx.object.clock(),
    ],
  });

  const result = await execTx('Test 9: Create guild bonus contract', tx);
  const contractId = findCreatedId(result, 'CourierContract');
  console.log(`  CourierContract (guild bonus): ${contractId}`);
  console.log(`  Reward: ${reward}, Penalty: ${cancelPenalty}, Guild Bonus: ${guildBonus}`);
  return contractId;
}

// ─── Test 10: Seal approve guild member (access control) ───────────

async function test10_sealApproveGuildMember(guildId: string, leaderCapId: string) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${PACKAGE_ID}::seal_policy::seal_approve_guild_member`,
    arguments: [
      tx.object(guildId),      // &Guild
      tx.object(leaderCapId),  // &GuildMemberCap
      tx.object(storage1),     // &Storage (with guild_id set)
    ],
  });

  await execTx('Test 10: Seal approve guild member', tx);
  console.log(`  Seal access control PASS (guild member approved for storage1 coords)`);
}

// ─── Main ───────────────────────────────────────────────────────────

async function main() {
  console.log('Starting v3 smoke tests...\n');

  // Test 7: Create guild
  const { guildId, leaderCapId } = await test7_createGuild();

  // Test 8: Set storage guild + encrypted coords
  await test8_setStorageGuild(guildId);

  // Test 9: Create guild bonus contract
  const contractId = await test9_createGuildBonusContract(guildId);

  // Test 10: Seal approve guild member
  await test10_sealApproveGuildMember(guildId, leaderCapId);

  // Save v3 objects
  const v3Objects = {
    guildId,
    leaderCapId,
    guildBonusContractId: contractId,
  };
  const v3Path = new URL('./testnet-objects-v3.json', import.meta.url);
  writeFileSync(v3Path, JSON.stringify(v3Objects, null, 2) + '\n');
  console.log(`\nv3 objects saved to testnet-objects-v3.json`);

  console.log('\n=== ALL V3 SMOKE TESTS PASSED ===');
}

main().catch((err) => {
  console.error('\nV3 SMOKE TEST FAILED:', err);
  process.exit(1);
});

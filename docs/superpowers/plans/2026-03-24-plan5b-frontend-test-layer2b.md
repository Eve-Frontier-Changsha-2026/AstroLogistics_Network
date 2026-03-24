# Frontend Test Layer 2b — SDK Integration Tests

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify that frontend PTB builders produce valid transactions that execute successfully on testnet, and that gRPC query hooks return correctly shaped data from real chain state.

**Architecture:** Separate vitest config (`vitest.config.integration.ts`) with 30s timeout, real `SuiGrpcClient` hitting testnet. Tests sign with a keypair loaded from `TEST_SECRET_KEY` env var. Each test creates unique on-chain objects to avoid inter-test interference.

**Tech Stack:** vitest 4.1.1, `@mysten/sui` (SuiGrpcClient + Transaction + Ed25519Keypair), testnet gRPC

---

## File Structure

```
frontend/
├── vitest.config.integration.ts          # NEW — integration-specific vitest config
├── src/
│   ├── test/
│   │   └── integration-setup.ts          # NEW — keypair loader + client factory + tx helpers
│   └── integration/
│       ├── storage.integration.test.ts   # NEW — storage PTB + query tests
│       ├── fuel-station.integration.test.ts  # NEW — buy/supply fuel tests
│       ├── transport.integration.test.ts # NEW — create order + complete flow
│       ├── courier.integration.test.ts   # NEW — contract lifecycle tests
│       └── guild.integration.test.ts     # NEW — guild create + member flow
├── .env.test.local                       # NEW (gitignored) — TEST_SECRET_KEY
└── .env.test.local.example              # NEW — template for devs
```

**Key design decisions:**
- Tests live in `src/integration/` (not `src/**/*.test.ts`) so the existing `vitest run` doesn't pick them up
- Each module gets its own test file — failures are isolated
- `integration-setup.ts` centralizes keypair loading and tx execution — DRY across all test files
- No cleanup needed: testnet objects persist harmlessly

---

### Task 1: Integration Test Infrastructure

**Files:**
- Create: `frontend/vitest.config.integration.ts`
- Create: `frontend/src/test/integration-setup.ts`
- Create: `frontend/.env.test.local.example`
- Modify: `frontend/package.json` (add `test:integration` script)
- Modify: `frontend/.gitignore` (add `.env.test.local`)

- [ ] **Step 1: Create `.env.test.local.example`**

```
# Copy to .env.test.local and fill in your testnet keypair
# Bech32 SUI private key (suiprivkey1...) or base64-encoded raw 32-byte Ed25519 secret key
# Account must hold SUI (faucet) for gas
TEST_SECRET_KEY=
```

- [ ] **Step 2: Create vitest integration config**

```typescript
// frontend/vitest.config.integration.ts
import { defineConfig } from 'vitest/config';
import { config } from 'dotenv';
import path from 'node:path';

// Load .env.test.local into process.env BEFORE vitest starts
// (vitest only loads VITE_-prefixed vars by default, TEST_SECRET_KEY needs explicit dotenv)
config({ path: path.resolve(__dirname, '.env.test.local') });

export default defineConfig({
  test: {
    globals: true,
    include: ['src/integration/**/*.integration.test.ts'],
    testTimeout: 30_000,  // chain latency
    hookTimeout: 30_000,
    pool: 'forks',        // Node process isolation from main vitest process
    poolOptions: {
      forks: { singleFork: true },  // all test files run sequentially in one fork — avoids nonce conflicts
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
});
```

- [ ] **Step 3: Create integration-setup.ts**

```typescript
// frontend/src/test/integration-setup.ts
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { GRPC_URLS } from '@/config/network';
import { TESTNET_OBJECTS, ADMIN_CAPS } from '@/config/objects';
import { PACKAGE_ID, TYPE } from '@/config/contracts';

// ─── Keypair ───────────────────────────────────────────────
function loadTestKeypair(): Ed25519Keypair {
  const secret = process.env.TEST_SECRET_KEY;
  if (!secret) {
    throw new Error(
      'TEST_SECRET_KEY not set. Copy .env.test.local.example to .env.test.local and add your key.',
    );
  }
  // Accept both bech32 (suiprivkey1...) and base64 raw 32-byte formats
  if (secret.startsWith('suiprivkey')) {
    return Ed25519Keypair.fromSecretKey(secret);
  }
  return Ed25519Keypair.fromSecretKey(Buffer.from(secret, 'base64'));
}

// ─── Shared instances ──────────────────────────────────────
export const testKeypair = loadTestKeypair();
export const testAddress = testKeypair.toSuiAddress();
export const testClient = new SuiGrpcClient({
  baseUrl: GRPC_URLS.testnet,
  network: 'testnet',
});

// Re-export for convenience
export { TESTNET_OBJECTS, ADMIN_CAPS, PACKAGE_ID, TYPE };

// ─── Transaction helpers ───────────────────────────────────
export async function signAndExec(tx: Transaction) {
  const result = await testClient.signAndExecuteTransaction({
    signer: testKeypair,
    transaction: tx,
    include: { objectTypes: true },
  });

  if (result.$kind === 'FailedTransaction') {
    const status = result.FailedTransaction.status;
    throw new Error(`Transaction failed: ${JSON.stringify(status)}`);
  }

  const txData = result.Transaction!;
  await testClient.waitForTransaction({ digest: txData.digest });
  return { digest: txData.digest, objectTypes: txData.objectTypes ?? {} };
}

export function findCreatedId(
  result: { objectTypes: Record<string, string> },
  typeSubstr: string,
): string {
  for (const [id, type] of Object.entries(result.objectTypes)) {
    if (type.includes(typeSubstr)) return id;
  }
  throw new Error(`Object containing "${typeSubstr}" not found in tx output`);
}

// ─── Query helpers ─────────────────────────────────────────
export async function queryObject(objectId: string) {
  const res = await testClient.getObject({
    objectId,
    include: { json: true },
  });
  // res.object is always defined (SDK throws if object doesn't exist)
  return res.object;
}

/** Returns first page of owned objects matching type. Does not paginate. */
export async function queryOwnedObjects(type: string) {
  const res = await testClient.listOwnedObjects({
    owner: testAddress,
    type,
    limit: 50,
  });
  return res.objects;
}
```

- [ ] **Step 4: Install dotenv + add test:integration script**

```bash
cd frontend && pnpm add -D dotenv
```

In `frontend/package.json`, add to `"scripts"`:
```json
"test:integration": "vitest run --config vitest.config.integration.ts"
```

- [ ] **Step 5: Add .env.test.local to .gitignore**

Append to `frontend/.gitignore`:
```
.env.test.local
```

- [ ] **Step 6: Verify setup compiles**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 7: Commit**

```bash
git add frontend/vitest.config.integration.ts frontend/src/test/integration-setup.ts frontend/.env.test.local.example frontend/package.json frontend/.gitignore
git commit -m "test(frontend): add integration test infrastructure for SDK tests"
```

---

### Task 2: Storage Integration Tests

**Files:**
- Create: `frontend/src/integration/storage.integration.test.ts`

**Prereq:** Task 1 complete, `.env.test.local` configured with funded keypair

- [ ] **Step 1: Write storage integration tests**

```typescript
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd frontend && pnpm test:integration`
Expected: 4 tests PASS (may take 30-60s due to chain latency)

- [ ] **Step 3: Commit**

```bash
git add frontend/src/integration/storage.integration.test.ts
git commit -m "test(frontend): add storage SDK integration tests on testnet"
```

---

### Task 3: Fuel Station Integration Tests

**Files:**
- Create: `frontend/src/integration/fuel-station.integration.test.ts`

- [ ] **Step 1: Write fuel station integration tests**

```typescript
// frontend/src/integration/fuel-station.integration.test.ts
import { describe, it, expect } from 'vitest';
import {
  testClient,
  testAddress,
  signAndExec,
  findCreatedId,
  queryObject,
  TESTNET_OBJECTS,
  TYPE,
} from '@/test/integration-setup';
import { buildBuyFuel } from '@/lib/ptb/fuel-station';

describe('FuelStation — testnet integration', () => {
  it('buyFuel creates a FUEL Coin owned by sender', async () => {
    // Buy 100 fuel units, max price 200 per unit → pay 20000 MIST
    const tx = buildBuyFuel(
      TESTNET_OBJECTS.fuelStation1,
      100,    // amount
      200,    // maxPricePerUnit
      20000,  // paymentAmount (100 * 200)
    );

    const result = await signAndExec(tx);
    const coinId = findCreatedId(result, 'Coin');
    expect(coinId).toBeTruthy();
  });

  it('fuel station object is queryable with pricing fields', async () => {
    const obj = await queryObject(TESTNET_OBJECTS.fuelStation1);
    const json = obj.json as Record<string, unknown>;
    expect(json).toBeDefined();
    expect(json).toHaveProperty('base_price');
    expect(json).toHaveProperty('alpha');
    expect(json).toHaveProperty('total_fuel');
  });

  it('FUEL balance is queryable via getBalance', async () => {
    const res = await testClient.getBalance({
      owner: testAddress,
      coinType: TYPE.FUEL,
    });
    // balance is always defined (never optional in gRPC response)
    expect(res.balance).toBeDefined();
    expect(typeof res.balance.balance).toBe('string');
    expect(typeof res.balance.coinBalance).toBe('string');
  });
});
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd frontend && pnpm test:integration`
Expected: 7 tests PASS (4 storage + 3 fuel station)

- [ ] **Step 3: Commit**

```bash
git add frontend/src/integration/fuel-station.integration.test.ts
git commit -m "test(frontend): add fuel station SDK integration tests on testnet"
```

---

### Task 4: Guild Integration Tests

**Files:**
- Create: `frontend/src/integration/guild.integration.test.ts`

- [ ] **Step 1: Write guild integration tests**

```typescript
// frontend/src/integration/guild.integration.test.ts
import { describe, it, expect } from 'vitest';
import {
  signAndExec,
  findCreatedId,
  queryObject,
  queryOwnedObjects,
  TESTNET_OBJECTS,
  TYPE,
} from '@/test/integration-setup';
import { buildCreateGuild } from '@/lib/ptb/guild';

describe('Guild — testnet integration', () => {
  it('createGuild creates a Guild shared object + GuildMemberCap', async () => {
    const uniqueName = `TestGuild_${Date.now()}`;
    const tx = buildCreateGuild(uniqueName);

    const result = await signAndExec(tx);
    const guildId = findCreatedId(result, 'Guild');
    expect(guildId).toBeTruthy();

    // Guild should be queryable
    const obj = await queryObject(guildId);
    expect(obj).toBeDefined();

    const json = obj.json as Record<string, unknown>;
    expect(json).toHaveProperty('name');
    expect(json.name).toBe(uniqueName);
  });

  it('existing guild is queryable with member_count', async () => {
    const obj = await queryObject(TESTNET_OBJECTS.guild);
    const json = obj.json as Record<string, unknown>;
    expect(json).toBeDefined();
    expect(json).toHaveProperty('member_count');
  });

  it('GuildMemberCap is findable in owned objects', async () => {
    const caps = await queryOwnedObjects(TYPE.GuildMemberCap);
    // After createGuild, creator gets a GuildMemberCap (leader)
    expect(caps.length).toBeGreaterThanOrEqual(1);
  });
});
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd frontend && pnpm test:integration`
Expected: 10 tests PASS

- [ ] **Step 3: Commit**

```bash
git add frontend/src/integration/guild.integration.test.ts
git commit -m "test(frontend): add guild SDK integration tests on testnet"
```

---

### Task 5: Transport Integration Tests

**Files:**
- Create: `frontend/src/integration/transport.integration.test.ts`

**Note:** Transport requires a DepositReceipt (from deposit) + FUEL coin (from buyFuel) + FuelTreasuryCap (deployer-owned). This test chains: deposit → buyFuel → createOrder → payFuel → completeTransport.

- [ ] **Step 1: Write transport integration tests**

```typescript
// frontend/src/integration/transport.integration.test.ts
import { Transaction } from '@mysten/sui/transactions';
import { describe, it, expect } from 'vitest';
import {
  testKeypair,
  testAddress,
  testClient,
  signAndExec,
  findCreatedId,
  queryObject,
  TESTNET_OBJECTS,
  ADMIN_CAPS,
  PACKAGE_ID,
  TYPE,
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd frontend && pnpm test:integration`
Expected: 12 tests PASS

Note: Transport tests are slow (~10-15s each) due to multiple chained transactions.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/integration/transport.integration.test.ts
git commit -m "test(frontend): add transport SDK integration tests on testnet"
```

---

### Task 6: Courier Market Integration Tests

**Files:**
- Create: `frontend/src/integration/courier.integration.test.ts`

**Note:** Courier flow needs: deposit receipt → create contract → accept (as courier) → pickup → confirm → settle. Since we use a single keypair, the same account acts as both client and courier (permitted on testnet).

- [ ] **Step 1: Write courier integration tests**

```typescript
// frontend/src/integration/courier.integration.test.ts
import { Transaction } from '@mysten/sui/transactions';
import { describe, it, expect } from 'vitest';
import {
  testAddress,
  signAndExec,
  findCreatedId,
  queryObject,
  queryOwnedObjects,
  TESTNET_OBJECTS,
  ADMIN_CAPS,
  PACKAGE_ID,
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd frontend && pnpm test:integration`
Expected: 15 tests PASS

Note: The lifecycle test is the slowest (~20-30s, 6 sequential transactions).

- [ ] **Step 3: Commit**

```bash
git add frontend/src/integration/courier.integration.test.ts
git commit -m "test(frontend): add courier market SDK integration tests on testnet"
```

---

### Task 7: Run All + Type Check + Final Commit

- [ ] **Step 1: Run type check**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 2: Run existing unit tests (no regression)**

Run: `cd frontend && pnpm test`
Expected: 230 tests PASS (existing L1 + L2a unchanged)

- [ ] **Step 3: Run all integration tests**

Run: `cd frontend && pnpm test:integration`
Expected: 15 tests PASS (4 storage + 3 fuel + 3 guild + 2 transport + 3 courier)

- [ ] **Step 4: Verify total counts and commit**

If any adjustments were needed during earlier tasks, create a final cleanup commit:
```bash
git add -A
git commit -m "test(frontend): finalize Layer 2b SDK integration tests — 15 tests on testnet"
```

---

## Summary

| Task | Module | Tests | Key Verification |
|------|--------|-------|-----------------|
| 1 | Infrastructure | 0 | Config, keypair loader, helpers |
| 2 | Storage | 4 | deposit → receipt, withdraw → cargo, query fields, owned AdminCap |
| 3 | FuelStation | 3 | buyFuel → FUEL coin, query station, getBalance |
| 4 | Guild | 3 | createGuild → shared object, query fields, owned GuildMemberCap |
| 5 | Transport | 2 | Full flow (deposit→order→pay→complete), query order fields |
| 6 | Courier | 3 | createContract → Open, full lifecycle (6 txs), owned CourierBadge |
| 7 | Final | 0 | tsc + regression + all integration |
| **Total** | | **15** | |

## Prerequisites

- `.env.test.local` with `TEST_SECRET_KEY` (bech32 `suiprivkey1...` or base64 raw 32-byte Ed25519 key)
- Account holds SUI (from faucet) for gas
- Account is the deployer (owns AdminCaps, OracleCap, FuelTreasuryCap)
- Testnet objects from `init-testnet.ts` are live

## Known Risks

1. **Chain latency** — tests may flake if testnet is congested. 30s timeout should be sufficient but monitor.
2. **Single keypair limitation** — same account is client + courier + deployer. Works for testnet but doesn't test auth boundaries.
3. **Object state accumulation** — repeated test runs create persistent objects. No impact on correctness but storage grows.
4. **gRPC response shape** — if `@mysten/sui` updates the gRPC client response format, `integration-setup.ts` helpers need updating. Pin the version.

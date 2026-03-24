# Frontend Test Layer 2c — Playwright Browser E2E Design

**Date**: 2026-03-24
**Status**: Approved
**Scope**: Full browser E2E — 8 pages × (happy + error + wallet) + cross-page flows + monkey tests
**Prerequisite**: L2b SDK integration tests (completed), `.env.test.local` with funded keypair

## Overview

Playwright-based browser E2E tests running against testnet via `vite dev`. Full coverage of all 8 pages with happy path, error state (via `page.route()` interception), and wallet disconnect scenarios. Write tests create their own chain objects; read tests share existing testnet objects.

## Architecture

```
Playwright (Chromium)
  → vite dev (webServer)
    → dapp-kit (walletInitializers: TestWallet)
      → SuiGrpcClient (GrpcWebFetchTransport / HTTP fetch) → testnet
```

## Wallet Strategy — `walletInitializers` with Custom TestWallet

### Why not `useTestAccount` hook

`useCurrentAccount()` reads from dapp-kit-core's internal `$connection` nanostore. A custom hook **cannot** override this context. Components like `WalletGuard` would still see `null`. Similarly, `signAndExecuteTransaction` flows through `$connection` — a standalone hook cannot provide signing capabilities.

### Correct approach: `walletInitializers`

`createDAppKit` supports `walletInitializers` — a list of wallet initializers that register wallet-standard wallets via `getWallets().register()`. This flows through the real `$connection` store, making `useCurrentAccount()`, `useDAppKit().signAndExecuteTransaction()`, and all downstream hooks work natively.

### Design

Modify `dapp-kit.ts` to conditionally add a test wallet initializer in DEV mode:

```typescript
// dapp-kit.ts
import { createDAppKit } from '@mysten/dapp-kit-react';
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { NETWORKS, DEFAULT_NETWORK, GRPC_URLS, type Network } from './config/network';

// DEV-only: test wallet initializer
const testWalletInitializers = import.meta.env.DEV && localStorage.getItem('testKeypair')
  ? [{
      id: 'Test Wallet',
      initialize() {
        // Implementation: create a wallet-standard wallet from Ed25519Keypair
        // using the keypair stored in localStorage.testKeypair
        // See e2e/fixtures/test-wallet.ts for the TestWallet class
        const wallets = [new TestWallet(localStorage.getItem('testKeypair')!)];
        const walletsApi = getWallets();
        return { unregister: walletsApi.register(...wallets) };
      },
    }]
  : [];

export const dAppKit = createDAppKit({
  networks: [...NETWORKS],
  defaultNetwork: DEFAULT_NETWORK,
  createClient: (network) =>
    new SuiGrpcClient({
      network: network as Network,
      baseUrl: GRPC_URLS[network as Network],
    }),
  walletInitializers: testWalletInitializers,
  autoConnect: true, // auto-connect to test wallet when present
});
```

### TestWallet class

A minimal wallet-standard compliant wallet that wraps `Ed25519Keypair`:

```typescript
// src/test/TestWallet.ts (dev-only, tree-shaken in production)
// Implements: Wallet standard interface with:
// - name: 'Test Wallet'
// - accounts: [{ address, publicKey, chains: ['sui:testnet'] }]
// - features: { 'standard:connect', 'sui:signTransaction', 'sui:signAndExecuteTransaction' }
```

### Playwright Injection

```typescript
// In beforeEach or test fixture:
await page.addInitScript((key) => {
  localStorage.setItem('testKeypair', key);
}, process.env.TEST_SECRET_KEY);
await page.goto('/');
// dapp-kit auto-connects to TestWallet → useCurrentAccount() returns test address
```

### Guards

- `import.meta.env.DEV` check → dead-code eliminated in `vite build`
- Only activates when `localStorage.testKeypair` is set
- `dapp-kit.ts` change is ~10 lines, all behind DEV guard

### Keypair format

`TEST_SECRET_KEY` in `.env.test.local` uses **bech32** format (`suiprivkey1...`) — same format as L2b integration tests. The `TestWallet` class decodes it via `decodeSuiPrivateKey()` → `Ed25519Keypair.fromSecretKey()`.

## State Isolation Strategy

### Read-only tests (shared objects)

Tests that only query chain state reuse existing testnet objects from L2b:

| Object | Source |
|--------|--------|
| Storage × 2 | `TESTNET_OBJECTS.storage1`, `storage2` |
| FuelStation × 2 | `TESTNET_OBJECTS.fuelStation1`, `fuelStation2` |
| ThreatMap | `TESTNET_OBJECTS.threatMap` |
| Guild | Created during L2b guild tests (or globalSetup) |

These IDs are stored in a shared config (e.g., `e2e/fixtures/testnet-objects.ts`).

### Write tests (self-contained)

Each write test creates its own objects and does not depend on other tests:
- Create Storage → uses new object
- Buy Fuel → uses existing FuelStation, creates FUEL balance change
- Create Contract → creates new CourierContract
- Accept & Complete → creates contract then runs full lifecycle
- Create Guild → creates new Guild

### No teardown needed

Testnet objects persist but don't interfere (unique per test run).

### Execution strategy

- Tests run **sequentially** (single worker) to avoid gas contention on the shared keypair
- `globalSetup` performs a pre-flight gas balance check — aborts early if balance < 1 SUI

## Error Simulation — `page.route()` Interception

### Transport details

`SuiGrpcClient` uses `GrpcWebFetchTransport` from `@protobuf-ts/grpcweb-transport` — this is **grpc-web over HTTP/1.1 fetch**, fully interceptable by Playwright's `page.route()`.

### URL pattern

gRPC-web requests are POST to paths like:
```
https://fullnode.testnet.sui.io:443/sui.rpc.v2.StateService/GetObject
https://fullnode.testnet.sui.io:443/sui.rpc.v2.TransactionExecutionService/ExecuteTransaction
```

Route pattern: `**fullnode.testnet.sui.io:443/sui.rpc.v2.**`

### Error simulation approaches

```typescript
// 1. Network-level abort (for timeout/disconnect errors)
await page.route('**fullnode.testnet.sui.io:443/sui.rpc.v2.**', (route) =>
  route.abort('timedout')
);

// 2. HTTP error (gRPC-web maps HTTP errors to gRPC status)
await page.route('**fullnode.testnet.sui.io:443/sui.rpc.v2.**', (route) =>
  route.fulfill({ status: 503, body: '' })
);

// 3. Selective interception (only intercept specific service methods)
await page.route('**/sui.rpc.v2.StateService/GetObject', (route) =>
  route.abort('failed')
);
// Let other calls through
```

**Note**: For application-level errors (object not found, tx failure), `route.abort()` and HTTP error codes are sufficient to trigger the frontend's error handling UI. We do NOT need to craft valid protobuf grpc-web frames — the `GrpcWebFetchTransport` will throw a `RpcError` on any non-200 response or network failure, which our hooks catch and surface as error states.

### Error scenarios per page

| Error Type | Simulation | Expected UI |
|-----------|-----------|-------------|
| Network timeout | `route.abort('timedout')` | Error banner / retry button |
| Service unavailable | `route.fulfill({ status: 503 })` | Error banner |
| Object not found | Abort `GetObject` route | 404 or "not found" UI |
| Transaction failure | Abort `ExecuteTransaction` route | Toast with error message |

## Test Matrix

### Per-page tests

| Page | Happy Path | Error State | Wallet Disconnect |
|------|-----------|-------------|-------------------|
| DashboardPage | Loads, shows FUEL balance, storage list | gRPC timeout → error UI | Shows connect prompt |
| StorageDetailPage | Navigate → capacity/load/fee displayed | Object not found → 404 UI | Shows connect prompt |
| BountyBoardPage | Contract list renders, filter works | gRPC error → error UI | Shows connect prompt |
| ContractDetailPage | Contract state + action buttons | Tx failure → toast error | Action buttons disabled |
| FuelStationPage | Buy fuel → balance changes in UI | Insufficient gas → error | Shows connect prompt |
| TransportPage | Order list + status badges | gRPC error → error UI | Shows connect prompt |
| GuildPage | Create guild → appears in UI | Tx failure → toast error | Shows connect prompt |
| ThreatMapPage | Threat data renders | gRPC error → fallback UI | Read-only, no wallet gate |

### Cross-page E2E flows

1. **Storage deposit flow**: Dashboard → Create Storage → StorageDetail → Deposit cargo → Verify load change
2. **Courier contract flow**: BountyBoard → Create Contract → ContractDetail → Accept → Complete → Verify settled
3. **Fuel + Transport flow**: FuelStation → Buy Fuel → Transport → Create Order → Verify order

### Monkey tests (via UI)

- Paste 10KB string into input fields
- Rapid-fire button clicks during transaction pending
- Navigate away mid-transaction
- Browser back/forward during form submission
- Resize to mobile viewport mid-flow

## Infrastructure

### Dependencies

```json
{
  "devDependencies": {
    "@playwright/test": "^1.52.0"
  }
}
```

### Config — `playwright.config.ts`

```typescript
import { defineConfig } from '@playwright/test';
import { config } from 'dotenv';
import path from 'node:path';

config({ path: path.resolve(__dirname, '.env.test.local') });

export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,          // 60s per test (chain latency)
  retries: 1,               // Retry once for flaky chain responses
  workers: 1,               // Sequential — shared keypair, avoid gas contention
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'pnpm dev',
    port: 5173,
    reuseExistingServer: !process.env.CI,
  },
});
```

### Directory structure

```
frontend/
├── e2e/
│   ├── fixtures/
│   │   ├── testnet-objects.ts    # Shared object IDs
│   │   └── test-wallet.ts       # Keypair injection + auto-connect fixture
│   ├── dashboard.spec.ts
│   ├── storage-detail.spec.ts
│   ├── bounty-board.spec.ts
│   ├── contract-detail.spec.ts
│   ├── fuel-station.spec.ts
│   ├── transport.spec.ts
│   ├── guild.spec.ts
│   ├── threat-map.spec.ts
│   ├── flows/
│   │   ├── storage-deposit.spec.ts
│   │   ├── courier-contract.spec.ts
│   │   └── fuel-transport.spec.ts
│   └── monkey.spec.ts
├── playwright.config.ts
└── src/
    └── test/
        └── TestWallet.ts         # Wallet-standard compliant test wallet (DEV-only)
```

### Scripts

```json
{
  "test:e2e": "playwright test",
  "test:e2e:headed": "playwright test --headed",
  "test:e2e:ui": "playwright test --ui"
}
```

### Keypair management

Same `.env.test.local` as L2b:
```
TEST_SECRET_KEY=suiprivkey1...  (bech32 encoded)
```

Loaded via `dotenv` in `playwright.config.ts`. Injected into browser via `page.addInitScript()`.

## Test Count Estimate

| Category | Count |
|----------|-------|
| Per-page happy path | 8 |
| Per-page error state | 8 |
| Per-page wallet disconnect | 8 |
| Cross-page E2E flows | 3 |
| Monkey tests | 5 |
| **Total** | **~32** |

## Out of Scope

- Visual regression / screenshot comparison
- Performance / load testing
- Mainnet testing
- Mobile device emulation (beyond resize monkey test)
- CI pipeline integration (future task)

## Dependencies on Frontend Changes

1. `dapp-kit.ts` — add conditional `walletInitializers` (~10 lines, DEV-guarded)
2. `src/test/TestWallet.ts` — new wallet-standard compliant test wallet class (DEV-only)
3. No changes to existing components, hooks, pages, or PTB builders

# Frontend Test Layer 2 — Design Spec

**Date**: 2026-03-24
**Status**: Draft
**Scope**: Component/Hook tests, SDK integration tests, Playwright E2E tests

## Overview

Three-phase testing strategy that progressively increases fidelity: mocked unit tests → real testnet SDK calls → full browser E2E with wallet injection.

## Architecture

```
Layer 2a (vitest + jsdom)     → Hook logic, UI rendering, Page states
Layer 2b (vitest + testnet)   → PTB → chain state verification
Layer 2c (Playwright + testnet) → Browser smoke test with real wallet
```

Each layer is an independent PR with its own test config and scripts.

---

## Layer 2a — Component & Hook Tests

### Environment

- **Runner**: vitest 4.1.1 (existing)
- **DOM**: jsdom (new dependency)
- **Rendering**: `@testing-library/react` + `@testing-library/user-event`
- **Config**: extend existing `vitest.config.ts` to include `*.test.tsx`, add `environment: 'jsdom'`

### Mocking Strategy

**`vi.mock('@mysten/dapp-kit-react')`** at module level, mocking each hook individually:

```typescript
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => ({
    listOwnedObjects: vi.fn(),
    getObject: vi.fn(),
    getBalance: vi.fn(),
    getDynamicField: vi.fn(),
    waitForTransaction: vi.fn(),
  })),
  useCurrentAccount: vi.fn(() => ({ address: '0xTEST' })),
  // useDAppKit returns a dAppKit instance shape (created by createDAppKit)
  // signAndExecuteTransaction is a method on the instance, not a standalone fn
  useDAppKit: vi.fn(() => ({
    signAndExecuteTransaction: vi.fn(),
  })),
}));
```

Each test can override return values via `vi.mocked(useCurrentAccount).mockReturnValue(null)` etc.

**Real `QueryClientProvider`** — `@tanstack/react-query` runs its real lifecycle so we test loading → success/error state transitions.

**`TestProvider` wrapper**:
```tsx
function TestProvider({ children, initialEntries = ['/'] }) {
  return (
    <QueryClientProvider client={new QueryClient({
      defaultOptions: { queries: { retry: false } },
    })}>
      <MemoryRouter initialEntries={initialEntries}>
        {children}
      </MemoryRouter>
    </QueryClientProvider>
  );
}

// For pages with route params:
// <TestProvider initialEntries={['/storage/0x123']}>
//   <Routes><Route path="/storage/:storageId" element={<StorageDetailPage />} /></Routes>
// </TestProvider>
```

### Test Targets

#### Hooks (12 files, 15 exports)

| File | Exports | Key assertions |
|------|---------|---------------|
| `useFuelBalance.ts` | `useFuelBalance` | returns balance from gRPC response; disabled when no account |
| `useStorageList.ts` | `useOwnedAdminCaps`, `useStorageObject`, `parseStorageFields` | `useOwnedAdminCaps`: parses `listOwnedObjects`; `useStorageObject`: disabled when no storageId; `parseStorageFields`: pure fn — field mapping, defaults for missing keys |
| `useStorageDetail.ts` | `useStorageDetail`, `useMyReceipts` | combines storage object + dynamic fields; receipts query |
| `useCourierBadge.ts` | `useCourierBadges` | finds badge in owned objects; returns empty when disconnected |
| `useCourierContracts.ts` | `useMyContracts` | filters contracts by courier address |
| `useTransportOrders.ts` | `useMyTransportOrders` | parses transport order list |
| `useOwnedObjects.ts` | `useOwnedObjects` | generic owned object query with struct type filter |
| `useGuild.ts` | `useGuildDetail` | parses guild shared object; disabled when no guildId |
| `useGuildMemberCap.ts` | `useGuildMemberCap` | finds GuildMemberCap in owned objects |
| `useFuelStation.ts` | `useFuelStationDetail` | parses fuel station object |
| `useContractDetail.ts` | `useContractDetail` | parses single contract object; disabled when no contractId |
| `useTransactionExecutor.ts` | `useTransactionExecutor` | **state machine**: idle → loading → success (digest) / error; `FailedTransaction` branch; `waitForTransaction` + `invalidateQueries` called; rejected promise + network timeout monkey tests |

#### UI Components (8) + Layout (2)

| Component | Key assertions |
|-----------|---------------|
| `WalletGuard` | renders children when connected; shows connect prompt when disconnected |
| `TransactionToast` | shows digest link on success; shows error message on failure; dismiss callback |
| `StatusBadge` | correct variant styling for each status |
| `Button` | loading spinner state; disabled when loading; onClick fires |
| `AddressDisplay` | truncation logic; copy-to-clipboard if applicable |
| `LoadingSpinner` | renders without error |
| `Panel` | renders title + children |
| `Input` | value/onChange binding |
| `Navbar` | nav links render; active link styling; ConnectButton integration (uses dapp-kit hooks) |
| `Layout` | renders Navbar + children outlet |

#### Pages (8)

| Page | Key assertions |
|------|---------------|
| `DashboardPage` | loading state → data state; empty state (no storages); create storage button triggers tx |
| `StorageDetailPage` | loading → detail render; deposit/withdraw interactions |
| `GuildPage` | create guild; member list; join flow |
| `BountyBoardPage` | contract list; filter/sort; create contract |
| `ContractDetailPage` | contract state display; accept/complete actions |
| `TransportPage` | transport order list; status transitions |
| `FuelStationPage` | buy fuel interaction; balance display |
| `ThreatMapPage` | threat data render |

#### Monkey Tests

- All components with `null`, `undefined`, empty string, `Number.MAX_SAFE_INTEGER` props
- Pages with empty/malformed hook responses
- UI components with extremely long strings (10KB)
- `useTransactionExecutor` with rejected promises, network timeouts, and malformed `FailedTransaction` responses

### Scripts

```json
{
  "test": "vitest run",
  "test:watch": "vitest"
}
```

(Same as existing — just expand `include` glob to `['src/**/*.test.{ts,tsx}']`)

---

## Layer 2b — SDK Integration Tests

### Environment

- **Runner**: vitest with separate config `vitest.config.integration.ts`
- **Network**: testnet (real gRPC calls)
- **Timeout**: 30s per test (chain latency)

### Keypair Management

- **Local**: `.env.test.local` (gitignored) containing:
  ```
  TEST_SECRET_KEY=<base64 ed25519 secret key>
  ```
- **CI**: GitHub Secrets → environment variable injection
- Account must hold SUI (faucet) + FUEL (pre-minted) for full test coverage

### Test Targets

Each PTB builder gets at least one happy-path integration test:

| Module | Tests |
|--------|-------|
| Storage | `createStorage` → query exists; `depositCargo` → currentLoad increased |
| Fuel Station | `buyFuel` → FUEL balance increased |
| Transport | `createTransportOrder` → order queryable |
| Courier | `createContract` → contract exists; `acceptContract` → status change |
| Guild | `createGuild` → guild queryable; `joinGuild` → member cap received |

### Cleanup Strategy

- Tests create unique objects (no shared state between tests)
- No teardown needed — testnet objects persist but don't interfere

### Scripts

```json
{
  "test:integration": "vitest run --config vitest.config.integration.ts"
}
```

---

## Layer 2c — Playwright Browser E2E

### Environment

- **Runner**: Playwright (Chromium)
- **Network**: testnet
- **Dev server**: `vite dev` (started by Playwright `webServer` config)

### Wallet Strategy — Programmatic Keypair Bypass

Frontend adds a dev-only code path that reads from `localStorage`:

```typescript
// In dapp-kit.ts or App.tsx
if (import.meta.env.DEV && localStorage.getItem('testKeypair')) {
  // Bypass wallet extension, use Ed25519Keypair directly
  // Auto-connect with the keypair from localStorage
}
```

**Guards**:
- `import.meta.env.DEV` — tree-shaken in production build
- Only activates when `localStorage.testKeypair` is set

Playwright injects the keypair before navigation:
```typescript
await page.evaluate((key) => localStorage.setItem('testKeypair', key), secretKey);
await page.goto('/');
```

**Why localStorage over URL params**: URL params leak into browser history, Vite dev server logs, and Playwright trace artifacts/screenshots.

### Test Scenarios (Smoke Test)

1. **Dashboard** — page loads, shows FUEL balance, storage count
2. **Create Storage** — click button → tx toast appears with digest
3. **Storage Detail** — navigate → shows capacity/load/fee
4. **Buy Fuel** — fuel station → buy → balance changes
5. **Create Contract** — bounty board → create → appears in list
6. **Accept & Complete** — courier flow end-to-end

### Keypair Management

Same `.env.test.local` as Layer 2b.

### Scripts

```json
{
  "test:e2e": "playwright test",
  "test:e2e:headed": "playwright test --headed"
}
```

---

## Out of Scope

- Visual regression testing (CSS/Tailwind)
- react-router routing config tests
- Full gRPC protocol mocking
- Mainnet testing
- Performance/load testing

## Dependencies (new packages)

| Layer | Package | Purpose |
|-------|---------|---------|
| 2a | `@testing-library/react` | Component rendering |
| 2a | `@testing-library/user-event` | User interaction simulation |
| 2a | `@testing-library/jest-dom` | DOM matchers |
| 2a | `jsdom` | DOM environment for vitest |
| 2c | `@playwright/test` | Browser E2E |

## Execution Order

1. **Plan 5a** — Layer 2a (component/hook tests) — independent, no testnet dependency
2. **Plan 5b** — Layer 2b (SDK integration) — needs `.env.test.local` + funded account
3. **Plan 5c** — Layer 2c (Playwright E2E) — needs 2b keypair setup + frontend test bypass code

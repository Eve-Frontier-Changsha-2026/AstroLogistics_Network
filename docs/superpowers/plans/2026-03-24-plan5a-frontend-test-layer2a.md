# Plan 5a — Frontend Component & Hook Tests

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add vitest + jsdom component/hook/page tests with monkey tests, reaching full coverage of all 12 hook files (15 exports), 10 UI/layout components, and 8 pages.

**Architecture:** `vi.mock('@mysten/dapp-kit-react')` at module level to mock SUI hooks. Real `QueryClientProvider` + `MemoryRouter` in a shared `TestProvider` wrapper. `@testing-library/react` for rendering and assertions. Each test file co-locates with its source file.

**Tech Stack:** vitest 4.1.1, jsdom, @testing-library/react, @testing-library/user-event, @testing-library/jest-dom

**Spec:** `docs/superpowers/specs/2026-03-24-frontend-test-layer2-design.md` (Layer 2a section)

---

## File Structure

### New files to create:

| File | Responsibility |
|------|---------------|
| `src/test/setup.ts` | Global test setup: jsdom matchers, cleanup |
| `src/test/TestProvider.tsx` | Shared wrapper: QueryClientProvider + MemoryRouter |
| `src/test/mocks.ts` | Reusable mock factories for dapp-kit hooks and gRPC responses |
| `src/hooks/useStorageList.test.tsx` | Tests for useOwnedAdminCaps, useStorageObject, parseStorageFields |
| `src/hooks/useStorageDetail.test.tsx` | Tests for useStorageDetail, useMyReceipts |
| `src/hooks/useFuelBalance.test.tsx` | Tests for useFuelBalance |
| `src/hooks/useOwnedObjects.test.tsx` | Tests for useOwnedObjects |
| `src/hooks/useCourierBadge.test.tsx` | Tests for useCourierBadges |
| `src/hooks/useCourierContracts.test.tsx` | Tests for useMyContracts |
| `src/hooks/useTransportOrders.test.tsx` | Tests for useMyTransportOrders |
| `src/hooks/useGuild.test.tsx` | Tests for useGuildDetail |
| `src/hooks/useGuildMemberCap.test.tsx` | Tests for useGuildMemberCap |
| `src/hooks/useFuelStation.test.tsx` | Tests for useFuelStationDetail |
| `src/hooks/useContractDetail.test.tsx` | Tests for useContractDetail |
| `src/hooks/useTransactionExecutor.test.tsx` | Tests for useTransactionExecutor state machine |
| `src/components/ui/WalletGuard.test.tsx` | Tests for WalletGuard |
| `src/components/ui/TransactionToast.test.tsx` | Tests for TransactionToast |
| `src/components/ui/StatusBadge.test.tsx` | Tests for StatusBadge |
| `src/components/ui/Button.test.tsx` | Tests for Button |
| `src/components/ui/AddressDisplay.test.tsx` | Tests for AddressDisplay |
| `src/components/ui/LoadingSpinner.test.tsx` | Tests for LoadingSpinner |
| `src/components/ui/Panel.test.tsx` | Tests for Panel |
| `src/components/ui/Input.test.tsx` | Tests for Input |
| `src/components/layout/Navbar.test.tsx` | Tests for Navbar |
| `src/components/layout/Layout.test.tsx` | Tests for Layout |
| `src/pages/DashboardPage.test.tsx` | Tests for DashboardPage |
| `src/pages/StorageDetailPage.test.tsx` | Tests for StorageDetailPage |
| `src/pages/GuildPage.test.tsx` | Tests for GuildPage |
| `src/pages/BountyBoardPage.test.tsx` | Tests for BountyBoardPage |
| `src/pages/ContractDetailPage.test.tsx` | Tests for ContractDetailPage |
| `src/pages/TransportPage.test.tsx` | Tests for TransportPage |
| `src/pages/FuelStationPage.test.tsx` | Tests for FuelStationPage |
| `src/pages/ThreatMapPage.test.tsx` | Tests for ThreatMapPage |
| `src/pages/monkey-pages.test.tsx` | Monkey tests for all pages with extreme inputs |

### Files to modify:

| File | Change |
|------|--------|
| `vitest.config.ts` | Add jsdom environment, include `*.test.tsx`, setupFiles |
| `package.json` | Add test deps to devDependencies |

---

## Task 1: Setup test infrastructure

**Files:**
- Modify: `frontend/package.json`
- Modify: `frontend/vitest.config.ts`
- Create: `frontend/src/test/setup.ts`
- Create: `frontend/src/test/TestProvider.tsx`
- Create: `frontend/src/test/mocks.ts`

- [ ] **Step 1: Install test dependencies**

```bash
cd frontend && pnpm add -D @testing-library/react @testing-library/user-event @testing-library/jest-dom jsdom
```

- [ ] **Step 2: Update vitest.config.ts**

```typescript
import { defineConfig } from 'vitest/config';
import path from 'node:path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['src/test/setup.ts'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
});
```

- [ ] **Step 3: Create test setup file**

```typescript
// src/test/setup.ts
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});
```

- [ ] **Step 4: Create TestProvider wrapper**

```tsx
// src/test/TestProvider.tsx
import type { ReactNode } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';

interface TestProviderProps {
  children: ReactNode;
  initialEntries?: string[];
}

export function TestProvider({ children, initialEntries = ['/'] }: TestProviderProps) {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
    },
  });
  return (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={initialEntries}>
        {children}
      </MemoryRouter>
    </QueryClientProvider>
  );
}
```

- [ ] **Step 5: Create mock factories**

```typescript
// src/test/mocks.ts
import { vi } from 'vitest';

// --- Mock gRPC client ---
export function createMockClient(overrides: Record<string, unknown> = {}) {
  return {
    listOwnedObjects: vi.fn().mockResolvedValue({ objects: [] }),
    getObject: vi.fn().mockResolvedValue({ object: null }),
    getBalance: vi.fn().mockResolvedValue({ balance: { balance: '0' } }),
    getDynamicField: vi.fn().mockResolvedValue({ dynamicField: null }),
    waitForTransaction: vi.fn().mockResolvedValue({}),
    ...overrides,
  };
}

// --- Mock account ---
export const MOCK_ADDRESS = '0x' + 'a'.repeat(64);
export const MOCK_ACCOUNT = { address: MOCK_ADDRESS };

// --- Mock dAppKit instance ---
export function createMockDAppKit(overrides: Record<string, unknown> = {}) {
  return {
    signAndExecuteTransaction: vi.fn().mockResolvedValue({
      Transaction: { digest: 'mock-digest-abc123' },
    }),
    ...overrides,
  };
}

// --- Mock gRPC response shapes ---
export function mockListOwnedObjectsResponse(objects: Array<{ objectId: string; json: Record<string, unknown> }>) {
  return { objects };
}

export function mockGetObjectResponse(id: string, json: Record<string, unknown>, isShared = true) {
  return {
    object: {
      objectId: id,
      json,
      owner: isShared ? { $kind: 'Shared' as const } : { $kind: 'AddressOwner' as const, AddressOwner: MOCK_ADDRESS },
    },
  };
}
```

- [ ] **Step 6: Verify existing tests still pass**

Run: `cd frontend && pnpm test`
Expected: 107 tests PASS (all existing Layer 1 tests)

- [ ] **Step 7: Commit**

```bash
git add frontend/package.json frontend/pnpm-lock.yaml frontend/vitest.config.ts frontend/src/test/
git commit -m "test(frontend): add jsdom + testing-library infrastructure for component tests"
```

---

## Task 2: Hook tests — core hooks

**Files:**
- Create: `frontend/src/hooks/useOwnedObjects.test.tsx`
- Create: `frontend/src/hooks/useFuelBalance.test.tsx`
- Create: `frontend/src/hooks/useStorageList.test.tsx`

- [ ] **Step 1: Write useOwnedObjects tests**

```tsx
// src/hooks/useOwnedObjects.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useOwnedObjects } from './useOwnedObjects';
import { useCurrentAccount } from '@mysten/dapp-kit-react';

describe('useOwnedObjects', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries owned objects with struct type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(
      mockListOwnedObjectsResponse([{ objectId: '0x1', json: { foo: 'bar' } }])
    );
    const { result } = renderHook(() => useOwnedObjects('0xpkg::mod::Type'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: '0xpkg::mod::Type',
      include: { json: true },
    });
    expect(result.current.data?.objects).toHaveLength(1);
  });

  it('is disabled when account is null', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useOwnedObjects('0xpkg::mod::Type'), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});
```

- [ ] **Step 2: Write useFuelBalance tests**

```tsx
// src/hooks/useFuelBalance.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useFuelBalance } from './useFuelBalance';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

describe('useFuelBalance', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns balance from gRPC response', async () => {
    mockClient.getBalance.mockResolvedValueOnce({ balance: { balance: '5000000000000' } });
    const { result } = renderHook(() => useFuelBalance(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getBalance).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      coinType: TYPE.FUEL,
    });
    expect(result.current.data?.balance.balance).toBe('5000000000000');
  });

  it('is disabled when account is null', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useFuelBalance(), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});
```

- [ ] **Step 3: Write useStorageList tests (3 exports)**

```tsx
// src/hooks/useStorageList.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockGetObjectResponse, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useOwnedAdminCaps, useStorageObject, parseStorageFields } from './useStorageList';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

describe('useOwnedAdminCaps', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries AdminCap type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(mockListOwnedObjectsResponse([]));
    const { result } = renderHook(() => useOwnedAdminCaps(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: TYPE.AdminCap,
      include: { json: true },
    });
  });

  it('is disabled when no account', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useOwnedAdminCaps(), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

describe('useStorageObject', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries object by id', async () => {
    mockClient.getObject.mockResolvedValueOnce(mockGetObjectResponse('0xSTORAGE', { owner: '0xABC' }));
    const { result } = renderHook(() => useStorageObject('0xSTORAGE'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getObject).toHaveBeenCalledWith({ objectId: '0xSTORAGE', include: { json: true } });
  });

  it('is disabled when storageId is undefined', () => {
    const { result } = renderHook(() => useStorageObject(undefined), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

describe('parseStorageFields', () => {
  it('maps all fields correctly', () => {
    const json = { owner: '0xABC', system_id: 42, max_capacity: 1000, current_load: 500, fee_rate_bps: 200 };
    const result = parseStorageFields(json, '0xID', true);
    expect(result).toEqual({
      id: '0xID', owner: '0xABC', systemId: 42, maxCapacity: 1000,
      currentLoad: 500, feeRateBps: 200, guildId: null, isShared: true,
    });
  });

  it('defaults missing fields to 0 or empty', () => {
    const result = parseStorageFields({}, '0xID', false);
    expect(result).toEqual({
      id: '0xID', owner: '', systemId: 0, maxCapacity: 0,
      currentLoad: 0, feeRateBps: 0, guildId: null, isShared: false,
    });
  });
});
```

- [ ] **Step 4: Run tests**

Run: `cd frontend && pnpm test`
Expected: All new hook tests PASS + 107 existing tests PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/src/hooks/useOwnedObjects.test.tsx frontend/src/hooks/useFuelBalance.test.tsx frontend/src/hooks/useStorageList.test.tsx
git commit -m "test(frontend): add hook tests for useOwnedObjects, useFuelBalance, useStorageList"
```

---

## Task 3: Hook tests — remaining data hooks

**Files:**
- Create: `frontend/src/hooks/useStorageDetail.test.tsx`
- Create: `frontend/src/hooks/useCourierBadge.test.tsx`
- Create: `frontend/src/hooks/useCourierContracts.test.tsx`
- Create: `frontend/src/hooks/useTransportOrders.test.tsx`
- Create: `frontend/src/hooks/useGuild.test.tsx`
- Create: `frontend/src/hooks/useGuildMemberCap.test.tsx`
- Create: `frontend/src/hooks/useFuelStation.test.tsx`
- Create: `frontend/src/hooks/useContractDetail.test.tsx`

All these hooks follow two patterns:

**Pattern A (getObject hooks)**: `useStorageDetail`, `useGuildDetail`, `useFuelStationDetail`, `useContractDetail`
- Call `client.getObject({ objectId, include: { json: true } })`
- Disabled when objectId is falsy

**Pattern B (wrapper hooks)**: `useCourierBadges`, `useMyTransportOrders`, `useGuildMemberCap`
- Just call `useOwnedObjects(TYPE.X)` — verify correct TYPE passed

**Pattern C (listOwnedObjects hooks)**: `useMyContracts`, `useMyReceipts`
- Call `client.listOwnedObjects` with account + type
- Disabled when no account

- [ ] **Step 1: Write Pattern A tests (getObject hooks)**

```tsx
// src/hooks/useStorageDetail.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockGetObjectResponse, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useStorageDetail, useMyReceipts } from './useStorageDetail';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

describe('useStorageDetail', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches storage object by id', async () => {
    mockClient.getObject.mockResolvedValueOnce(mockGetObjectResponse('0xS1', { owner: '0xA' }));
    const { result } = renderHook(() => useStorageDetail('0xS1'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getObject).toHaveBeenCalledWith({ objectId: '0xS1', include: { json: true } });
  });

  it('is disabled when storageId is empty string', () => {
    const { result } = renderHook(() => useStorageDetail(''), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

describe('useMyReceipts', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries DepositReceipt type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(mockListOwnedObjectsResponse([]));
    const { result } = renderHook(() => useMyReceipts(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: TYPE.DepositReceipt,
      include: { json: true },
    });
  });

  it('is disabled when no account', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useMyReceipts(), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});
```

Each remaining getObject hook test follows the same pattern. Create one test file per hook with:
1. "fetches by id" — mock getObject, verify called with correct objectId
2. "is disabled when id is falsy" — verify fetchStatus is 'idle'

For Pattern B wrappers (`useCourierBadges`, `useMyTransportOrders`, `useGuildMemberCap`):
- Verify `listOwnedObjects` is called with the correct `TYPE.*` string
- Each needs its own `vi.mock` block

```tsx
// src/hooks/useCourierBadge.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useCourierBadges } from './useCourierBadge';
import { TYPE } from '../config/contracts';

describe('useCourierBadges', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries CourierBadge type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(mockListOwnedObjectsResponse([]));
    const { result } = renderHook(() => useCourierBadges(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: TYPE.CourierBadge,
      include: { json: true },
    });
  });
});
```

Follow the same pattern for `useTransportOrders.test.tsx` (TYPE.TransportOrder), `useGuildMemberCap.test.tsx` (TYPE.GuildMemberCap), `useGuild.test.tsx` (getObject), `useFuelStation.test.tsx` (getObject), `useContractDetail.test.tsx` (getObject), `useCourierContracts.test.tsx` (listOwnedObjects with TYPE.CourierContract).

- [ ] **Step 2: Run tests**

Run: `cd frontend && pnpm test`
Expected: All hook tests PASS

- [ ] **Step 3: Commit**

```bash
git add frontend/src/hooks/*.test.tsx
git commit -m "test(frontend): add hook tests for remaining data hooks (8 files)"
```

---

## Task 4: Hook test — useTransactionExecutor state machine

**Files:**
- Create: `frontend/src/hooks/useTransactionExecutor.test.tsx`

This is the most complex hook — it has a state machine with multiple branches.

- [ ] **Step 1: Write useTransactionExecutor tests**

```tsx
// src/hooks/useTransactionExecutor.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, createMockDAppKit } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();
const mockInvalidateQueries = vi.fn().mockResolvedValue(undefined);

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@tanstack/react-query', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@tanstack/react-query')>();
  return {
    ...actual,
    useQueryClient: vi.fn(() => ({ invalidateQueries: mockInvalidateQueries })),
  };
});

import { useTransactionExecutor } from './useTransactionExecutor';
import { Transaction } from '@mysten/sui/transactions';

describe('useTransactionExecutor', () => {
  beforeEach(() => vi.clearAllMocks());

  it('starts in idle state', () => {
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });
    expect(result.current.digest).toBeNull();
    expect(result.current.error).toBeNull();
    expect(result.current.loading).toBe(false);
  });

  it('transitions to loading → success on successful tx', async () => {
    mockDAppKit.signAndExecuteTransaction.mockResolvedValueOnce({
      Transaction: { digest: 'tx-digest-123' },
    });
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    let executePromise: Promise<string | null>;
    act(() => {
      executePromise = result.current.execute(new Transaction());
    });

    // During execution, loading should be true
    expect(result.current.loading).toBe(true);

    const digest = await executePromise!;
    expect(digest).toBe('tx-digest-123');
    expect(result.current.digest).toBe('tx-digest-123');
    expect(result.current.error).toBeNull();
    expect(result.current.loading).toBe(false);
    expect(mockClient.waitForTransaction).toHaveBeenCalledWith({ digest: 'tx-digest-123' });
    expect(mockInvalidateQueries).toHaveBeenCalled();
  });

  it('handles FailedTransaction response', async () => {
    mockDAppKit.signAndExecuteTransaction.mockResolvedValueOnce({
      FailedTransaction: { status: { error: { message: 'Abort: 42' } } },
    });
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    let digest: string | null;
    await act(async () => {
      digest = await result.current.execute(new Transaction());
    });

    expect(digest!).toBeNull();
    expect(result.current.error).toBe('Abort: 42');
    expect(result.current.loading).toBe(false);
  });

  it('handles FailedTransaction with missing error message', async () => {
    mockDAppKit.signAndExecuteTransaction.mockResolvedValueOnce({
      FailedTransaction: {},
    });
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    await act(async () => {
      await result.current.execute(new Transaction());
    });

    expect(result.current.error).toBe('Transaction failed');
  });

  it('handles thrown error', async () => {
    mockDAppKit.signAndExecuteTransaction.mockRejectedValueOnce(new Error('Network timeout'));
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    await act(async () => {
      await result.current.execute(new Transaction());
    });

    expect(result.current.error).toBe('Network timeout');
    expect(result.current.digest).toBeNull();
    expect(result.current.loading).toBe(false);
  });

  it('handles non-Error thrown value', async () => {
    mockDAppKit.signAndExecuteTransaction.mockRejectedValueOnce('string-error');
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    await act(async () => {
      await result.current.execute(new Transaction());
    });

    expect(result.current.error).toBe('Unknown error');
  });

  it('handles concurrent executions — last one wins', async () => {
    let resolve1: (v: unknown) => void;
    let resolve2: (v: unknown) => void;
    mockDAppKit.signAndExecuteTransaction
      .mockImplementationOnce(() => new Promise(r => { resolve1 = r; }))
      .mockImplementationOnce(() => new Promise(r => { resolve2 = r; }));
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    // Fire two executions concurrently
    let p1: Promise<string | null>, p2: Promise<string | null>;
    act(() => {
      p1 = result.current.execute(new Transaction());
      p2 = result.current.execute(new Transaction());
    });

    // Resolve second first, then first
    await act(async () => {
      resolve2!({ Transaction: { digest: 'tx-2' } });
      await p2!;
    });
    await act(async () => {
      resolve1!({ Transaction: { digest: 'tx-1' } });
      await p1!;
    });

    // Final state reflects the last resolved
    expect(result.current.loading).toBe(false);
  });

  it('reset clears digest and error', async () => {
    mockDAppKit.signAndExecuteTransaction.mockResolvedValueOnce({
      Transaction: { digest: 'tx-123' },
    });
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    await act(async () => {
      await result.current.execute(new Transaction());
    });
    expect(result.current.digest).toBe('tx-123');

    act(() => result.current.reset());
    expect(result.current.digest).toBeNull();
    expect(result.current.error).toBeNull();
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd frontend && pnpm test`
Expected: 7 new tests PASS

- [ ] **Step 3: Commit**

```bash
git add frontend/src/hooks/useTransactionExecutor.test.tsx
git commit -m "test(frontend): add useTransactionExecutor state machine tests (7 cases)"
```

---

## Task 5: UI component tests

**Files:**
- Create: `frontend/src/components/ui/Button.test.tsx`
- Create: `frontend/src/components/ui/Panel.test.tsx`
- Create: `frontend/src/components/ui/Input.test.tsx`
- Create: `frontend/src/components/ui/LoadingSpinner.test.tsx`
- Create: `frontend/src/components/ui/StatusBadge.test.tsx`
- Create: `frontend/src/components/ui/AddressDisplay.test.tsx`
- Create: `frontend/src/components/ui/WalletGuard.test.tsx`
- Create: `frontend/src/components/ui/TransactionToast.test.tsx`

- [ ] **Step 1: Write simple UI component tests**

```tsx
// src/components/ui/Button.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Button } from './Button';

describe('Button', () => {
  it('renders children text', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByRole('button', { name: 'Click me' })).toBeInTheDocument();
  });

  it('shows "Processing..." when loading', () => {
    render(<Button loading>Click me</Button>);
    expect(screen.getByRole('button')).toHaveTextContent('Processing...');
  });

  it('is disabled when loading', () => {
    render(<Button loading>Click me</Button>);
    expect(screen.getByRole('button')).toBeDisabled();
  });

  it('is disabled when disabled prop is true', () => {
    render(<Button disabled>Click me</Button>);
    expect(screen.getByRole('button')).toBeDisabled();
  });

  it('calls onClick handler', async () => {
    const handler = vi.fn();
    render(<Button onClick={handler}>Click</Button>);
    await userEvent.click(screen.getByRole('button'));
    expect(handler).toHaveBeenCalledOnce();
  });

  it('does not fire onClick when loading', async () => {
    const handler = vi.fn();
    render(<Button loading onClick={handler}>Click</Button>);
    await userEvent.click(screen.getByRole('button'));
    expect(handler).not.toHaveBeenCalled();
  });

  it('applies variant classes', () => {
    const { rerender } = render(<Button variant="danger">Del</Button>);
    expect(screen.getByRole('button')).toHaveClass('bg-red-600');
    rerender(<Button variant="secondary">Sec</Button>);
    expect(screen.getByRole('button')).toHaveClass('bg-gray-700');
  });
});
```

```tsx
// src/components/ui/Panel.test.tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { Panel } from './Panel';

describe('Panel', () => {
  it('renders children', () => {
    render(<Panel>Content here</Panel>);
    expect(screen.getByText('Content here')).toBeInTheDocument();
  });

  it('renders title when provided', () => {
    render(<Panel title="My Title">Content</Panel>);
    expect(screen.getByText('My Title')).toBeInTheDocument();
  });

  it('does not render title element when not provided', () => {
    const { container } = render(<Panel>Content</Panel>);
    expect(container.querySelector('h3')).toBeNull();
  });
});
```

```tsx
// src/components/ui/Input.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Input } from './Input';

describe('Input', () => {
  it('renders label', () => {
    render(<Input label="Amount" />);
    expect(screen.getByLabelText('Amount')).toBeInTheDocument();
  });

  it('generates id from label', () => {
    render(<Input label="Fuel Cost" />);
    expect(screen.getByLabelText('Fuel Cost')).toHaveAttribute('id', 'fuel-cost');
  });

  it('uses provided id over generated', () => {
    render(<Input label="Amount" id="custom-id" />);
    expect(screen.getByLabelText('Amount')).toHaveAttribute('id', 'custom-id');
  });

  it('handles value change', async () => {
    const onChange = vi.fn();
    render(<Input label="Val" value="" onChange={onChange} />);
    await userEvent.type(screen.getByLabelText('Val'), '42');
    expect(onChange).toHaveBeenCalled();
  });
});
```

```tsx
// src/components/ui/LoadingSpinner.test.tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { LoadingSpinner } from './LoadingSpinner';

describe('LoadingSpinner', () => {
  it('renders the spinner element', () => {
    const { container } = render(<LoadingSpinner />);
    expect(container.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('applies custom className', () => {
    const { container } = render(<LoadingSpinner className="mt-4" />);
    expect(container.firstChild).toHaveClass('mt-4');
  });
});
```

```tsx
// src/components/ui/StatusBadge.test.tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StatusBadge } from './StatusBadge';

describe('StatusBadge', () => {
  it.each([
    ['Open', 'bg-blue-900/60'],
    ['Accepted', 'bg-yellow-900/60'],
    ['Delivered', 'bg-green-900/60'],
    ['Disputed', 'bg-red-900/60'],
  ])('renders %s with correct color', (status, expectedClass) => {
    render(<StatusBadge status={status} />);
    const badge = screen.getByText(status);
    expect(badge).toBeInTheDocument();
    expect(badge.className).toContain(expectedClass);
  });

  it('uses fallback colors for unknown status', () => {
    render(<StatusBadge status="Unknown" />);
    expect(screen.getByText('Unknown').className).toContain('bg-gray-800');
  });
});
```

```tsx
// src/components/ui/AddressDisplay.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AddressDisplay } from './AddressDisplay';

describe('AddressDisplay', () => {
  const address = '0x' + 'a'.repeat(64);

  beforeEach(() => {
    Object.assign(navigator, { clipboard: { writeText: vi.fn().mockResolvedValue(undefined) } });
  });

  it('displays truncated address', () => {
    render(<AddressDisplay address={address} />);
    expect(screen.getByText('0xaaaa...aaaa')).toBeInTheDocument();
  });

  it('copies full address on click', async () => {
    render(<AddressDisplay address={address} />);
    await userEvent.click(screen.getByRole('button'));
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(address);
  });

  it('shows "Copied!" after click', async () => {
    render(<AddressDisplay address={address} />);
    await userEvent.click(screen.getByRole('button'));
    expect(screen.getByText('Copied!')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Write WalletGuard and TransactionToast tests**

```tsx
// src/components/ui/WalletGuard.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { WalletGuard } from './WalletGuard';
import { MOCK_ACCOUNT } from '../../test/mocks';

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useCurrentAccount } from '@mysten/dapp-kit-react';

describe('WalletGuard', () => {
  it('renders children when wallet is connected', () => {
    render(<WalletGuard><p>Protected content</p></WalletGuard>);
    expect(screen.getByText('Protected content')).toBeInTheDocument();
  });

  it('shows connect prompt when wallet is disconnected', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    render(<WalletGuard><p>Protected content</p></WalletGuard>);
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument();
    expect(screen.getByText('Connect your wallet to continue.')).toBeInTheDocument();
  });
});
```

```tsx
// src/components/ui/TransactionToast.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { TransactionToast } from './TransactionToast';

describe('TransactionToast', () => {
  const onClose = vi.fn();
  beforeEach(() => vi.clearAllMocks());

  it('is hidden when digest and error are null', () => {
    const { container } = render(<TransactionToast digest={null} error={null} onClose={onClose} />);
    expect(container.firstChild).toBeNull();
  });

  it('shows success message with explorer link when digest is set', () => {
    render(<TransactionToast digest="tx-abc123" error={null} onClose={onClose} />);
    expect(screen.getByText('Success!')).toBeInTheDocument();
    const link = screen.getByRole('link', { name: 'View on explorer' });
    expect(link).toHaveAttribute('href', 'https://suiscan.xyz/testnet/tx/tx-abc123');
  });

  it('shows error message when error is set', () => {
    render(<TransactionToast digest={null} error="Abort: 42" onClose={onClose} />);
    expect(screen.getByText(/Transaction failed: Abort: 42/)).toBeInTheDocument();
  });

  it('auto-closes after 5 seconds', () => {
    vi.useFakeTimers();
    render(<TransactionToast digest="tx-123" error={null} onClose={onClose} />);
    expect(screen.getByText('Success!')).toBeInTheDocument();
    vi.advanceTimersByTime(5000);
    expect(onClose).toHaveBeenCalledOnce();
    vi.useRealTimers();
  });
});
```

- [ ] **Step 3: Run tests**

Run: `cd frontend && pnpm test`
Expected: All UI component tests PASS

- [ ] **Step 4: Commit**

```bash
git add frontend/src/components/ui/*.test.tsx
git commit -m "test(frontend): add UI component tests (Button, Panel, Input, StatusBadge, AddressDisplay, WalletGuard, TransactionToast, LoadingSpinner)"
```

---

## Task 6: Layout component tests

**Files:**
- Create: `frontend/src/components/layout/Navbar.test.tsx`
- Create: `frontend/src/components/layout/Layout.test.tsx`

- [ ] **Step 1: Write Navbar tests**

```tsx
// src/components/layout/Navbar.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { Navbar } from './Navbar';

vi.mock('@mysten/dapp-kit-react', () => ({
  useDAppKit: vi.fn(() => ({})),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: ({ instance: _instance }: { instance: unknown }) => <button>Connect Wallet</button>,
}));

describe('Navbar', () => {
  const renderNavbar = () => render(
    <MemoryRouter><Navbar /></MemoryRouter>
  );

  it('renders brand name', () => {
    renderNavbar();
    expect(screen.getByText('AstroLogistics')).toBeInTheDocument();
  });

  it('renders all nav links', () => {
    renderNavbar();
    expect(screen.getByText('Dashboard')).toBeInTheDocument();
    expect(screen.getByText('Bounty Board')).toBeInTheDocument();
    expect(screen.getByText('Fuel Station')).toBeInTheDocument();
    expect(screen.getByText('Transport')).toBeInTheDocument();
    expect(screen.getByText('Guild')).toBeInTheDocument();
    expect(screen.getByText('Threats')).toBeInTheDocument();
  });

  it('renders ConnectButton', () => {
    renderNavbar();
    expect(screen.getByText('Connect Wallet')).toBeInTheDocument();
  });
});
```

```tsx
// src/components/layout/Layout.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { Layout } from './Layout';

vi.mock('@mysten/dapp-kit-react', () => ({
  useDAppKit: vi.fn(() => ({})),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

describe('Layout', () => {
  it('renders Navbar and Outlet content', () => {
    render(
      <MemoryRouter initialEntries={['/']}>
        <Routes>
          <Route element={<Layout />}>
            <Route index element={<p>Home Page</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    );
    expect(screen.getByText('AstroLogistics')).toBeInTheDocument();
    expect(screen.getByText('Home Page')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests**

Run: `cd frontend && pnpm test`
Expected: Layout tests PASS

- [ ] **Step 3: Commit**

```bash
git add frontend/src/components/layout/*.test.tsx
git commit -m "test(frontend): add Navbar and Layout component tests"
```

---

## Task 7: Page tests — DashboardPage, GuildPage, ThreatMapPage

**Files:**
- Create: `frontend/src/pages/DashboardPage.test.tsx`
- Create: `frontend/src/pages/GuildPage.test.tsx`
- Create: `frontend/src/pages/ThreatMapPage.test.tsx`

Pages need: `vi.mock` for dapp-kit + mock for `@mysten/dapp-kit-react/ui` (ConnectButton) + mock PTB builders to avoid loading Transaction class.

- [ ] **Step 1: Write DashboardPage tests**

```tsx
// src/pages/DashboardPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, createMockDAppKit, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import DashboardPage from './DashboardPage';

describe('DashboardPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
    mockClient.getBalance.mockResolvedValue({ balance: { balance: '50000000000' } });
  });

  it('shows loading state then data', async () => {
    render(<TestProvider><DashboardPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Dashboard')).toBeInTheDocument();
    });
  });

  it('shows FUEL balance', async () => {
    // 50000000000 / 1e9 = 50.00
    render(<TestProvider><DashboardPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('50.00')).toBeInTheDocument();
    });
  });

  it('shows empty state when no storages', async () => {
    render(<TestProvider><DashboardPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('No storages yet.')).toBeInTheDocument();
    });
  });

  it('shows storage links when caps exist', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([
        { objectId: '0xCAP1', json: { storage_id: '0xSTORE1' } },
      ])
    );
    render(<TestProvider><DashboardPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText(/0xSTORE1/)).toBeInTheDocument();
    });
  });

  it('Create Storage button triggers tx', async () => {
    render(<TestProvider><DashboardPage /></TestProvider>);
    await waitFor(() => expect(screen.getByText('Create Storage')).toBeInTheDocument());
    await userEvent.click(screen.getByText('Create Storage'));
    expect(mockDAppKit.signAndExecuteTransaction).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Write GuildPage tests**

```tsx
// src/pages/GuildPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, createMockDAppKit, mockListOwnedObjectsResponse, mockGetObjectResponse } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import GuildPage from './GuildPage';

describe('GuildPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows "Create Guild" form when user has no guild', async () => {
    render(<TestProvider><GuildPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText(/Create Guild/)).toBeInTheDocument();
      expect(screen.getByText(/You are not in a guild/)).toBeInTheDocument();
    });
  });

  it('shows guild detail when user has GuildMemberCap', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([{ objectId: '0xCAP1', json: { guild_id: '0xGUILD1' } }])
    );
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xGUILD1', { name: 'Test Guild', leader: MOCK_ACCOUNT.address, member_count: 3 })
    );
    render(<TestProvider><GuildPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Test Guild')).toBeInTheDocument();
    });
  });

  it('shows leader actions when user is leader', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([{ objectId: '0xCAP1', json: { guild_id: '0xGUILD1' } }])
    );
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xGUILD1', { name: 'My Guild', leader: MOCK_ACCOUNT.address, member_count: 1 })
    );
    render(<TestProvider><GuildPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Add Member')).toBeInTheDocument();
    });
  });

  it('shows "Leave Guild" when user is not leader', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([{ objectId: '0xCAP1', json: { guild_id: '0xGUILD1' } }])
    );
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xGUILD1', { name: 'Other Guild', leader: '0xOTHER', member_count: 5 })
    );
    render(<TestProvider><GuildPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Leave Guild')).toBeInTheDocument();
    });
  });
});
```

- [ ] **Step 3: Write ThreatMapPage tests**

```tsx
// src/pages/ThreatMapPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockGetObjectResponse } from '../test/mocks';

const mockClient = createMockClient();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import ThreatMapPage from './ThreatMapPage';

describe('ThreatMapPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xTM', { decay_lambda: '100' })
    );
  });

  it('shows threat map overview', async () => {
    render(<TestProvider><ThreatMapPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Threat Map')).toBeInTheDocument();
      expect(screen.getByText(/100/)).toBeInTheDocument();
    });
  });

  it('shows "Could not load" when data is null', async () => {
    mockClient.getObject.mockResolvedValueOnce({ object: null });
    render(<TestProvider><ThreatMapPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Could not load ThreatMap.')).toBeInTheDocument();
    });
  });
});
```

- [ ] **Step 4: Run tests**

Run: `cd frontend && pnpm test`
Expected: All page tests PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/src/pages/DashboardPage.test.tsx frontend/src/pages/GuildPage.test.tsx frontend/src/pages/ThreatMapPage.test.tsx
git commit -m "test(frontend): add page tests for Dashboard, Guild, ThreatMap"
```

---

## Task 8: Page tests — StorageDetailPage, BountyBoardPage, ContractDetailPage

**Files:**
- Create: `frontend/src/pages/StorageDetailPage.test.tsx`
- Create: `frontend/src/pages/BountyBoardPage.test.tsx`
- Create: `frontend/src/pages/ContractDetailPage.test.tsx`

These pages use `useParams` and need `initialEntries` with route params.

- [ ] **Step 1: Write StorageDetailPage tests**

```tsx
// src/pages/StorageDetailPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { Routes, Route, MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createMockClient, MOCK_ACCOUNT, createMockDAppKit, mockGetObjectResponse, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import StorageDetailPage from './StorageDetailPage';

function renderWithRoute(storageId: string) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })}>
      <MemoryRouter initialEntries={[`/storage/${storageId}`]}>
        <Routes>
          <Route path="/storage/:storageId" element={<StorageDetailPage />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  );
}

describe('StorageDetailPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows storage info when loaded', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xS1', { owner: '0xABC', system_id: 1, max_capacity: 1000, current_load: 500, fee_rate_bps: 200 })
    );
    renderWithRoute('0xS1');
    await waitFor(() => {
      expect(screen.getByText('Storage Detail')).toBeInTheDocument();
      expect(screen.getByText(/500 \/ 1000/)).toBeInTheDocument();
    });
  });

  it('shows "Storage not found" when object is null', async () => {
    mockClient.getObject.mockResolvedValue({ object: null });
    renderWithRoute('0xS1');
    await waitFor(() => {
      expect(screen.getByText('Storage not found.')).toBeInTheDocument();
    });
  });

  it('shows admin actions when user has AdminCap for this storage', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xS1', { owner: MOCK_ACCOUNT.address, system_id: 1, max_capacity: 1000, current_load: 0, fee_rate_bps: 100 }, false)
    );
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([{ objectId: '0xCAP1', json: { storage_id: '0xS1' } }])
    );
    renderWithRoute('0xS1');
    await waitFor(() => {
      expect(screen.getByText('Admin Actions')).toBeInTheDocument();
      expect(screen.getByText('Claim Fees')).toBeInTheDocument();
    });
  });
});
```

- [ ] **Step 2: Write BountyBoardPage tests**

```tsx
// src/pages/BountyBoardPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, createMockDAppKit, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import BountyBoardPage from './BountyBoardPage';

describe('BountyBoardPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows empty contracts message', async () => {
    render(<TestProvider><BountyBoardPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('No contracts found.')).toBeInTheDocument();
    });
  });

  it('shows contracts with status badges', async () => {
    mockClient.listOwnedObjects
      .mockResolvedValueOnce(mockListOwnedObjectsResponse([
        { objectId: '0xC1', json: { status: 0, reward: 1000000000 } },
      ]))
      .mockResolvedValueOnce(mockListOwnedObjectsResponse([])); // receipts
    render(<TestProvider><BountyBoardPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Open')).toBeInTheDocument();
    });
  });
});
```

- [ ] **Step 3: Write ContractDetailPage tests**

```tsx
// src/pages/ContractDetailPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { Routes, Route, MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createMockClient, MOCK_ACCOUNT, MOCK_ADDRESS, createMockDAppKit, mockGetObjectResponse, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import ContractDetailPage from './ContractDetailPage';

function renderWithRoute(contractId: string) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })}>
      <MemoryRouter initialEntries={[`/bounty/${contractId}`]}>
        <Routes>
          <Route path="/bounty/:contractId" element={<ContractDetailPage />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  );
}

describe('ContractDetailPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows contract info', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xCON1', {
        status: 0, reward: 1000000000, client: MOCK_ADDRESS, courier: '',
        cargo_value: 500000000, min_courier_deposit: 1000000000, deadline: 0,
        from_storage: '0xS1', to_storage: '0xS2',
      })
    );
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText('Open')).toBeInTheDocument();
      expect(screen.getByText(/1\.00 SUI/)).toBeInTheDocument();
    });
  });

  it('shows Cancel button when client views Open contract', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xCON1', {
        status: 0, reward: 1000000000, client: MOCK_ADDRESS, courier: '',
        cargo_value: 0, min_courier_deposit: 0, deadline: 0,
      })
    );
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText('Cancel Contract')).toBeInTheDocument();
    });
  });

  it('shows Accept button when non-client views Open contract', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xCON1', {
        status: 0, reward: 1000000000, client: '0xOTHER', courier: '',
        cargo_value: 0, min_courier_deposit: 0, deadline: 0,
      })
    );
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText('Accept Contract')).toBeInTheDocument();
    });
  });

  it('shows "Contract not found" for null object', async () => {
    mockClient.getObject.mockResolvedValue({ object: null });
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText(/Contract not found/)).toBeInTheDocument();
    });
  });
});
```

- [ ] **Step 4: Run tests**

Run: `cd frontend && pnpm test`
Expected: All page tests PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/src/pages/StorageDetailPage.test.tsx frontend/src/pages/BountyBoardPage.test.tsx frontend/src/pages/ContractDetailPage.test.tsx
git commit -m "test(frontend): add page tests for StorageDetail, BountyBoard, ContractDetail"
```

---

## Task 9: Page tests — TransportPage, FuelStationPage

**Files:**
- Create: `frontend/src/pages/TransportPage.test.tsx`
- Create: `frontend/src/pages/FuelStationPage.test.tsx`

- [ ] **Step 1: Write TransportPage tests**

```tsx
// src/pages/TransportPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, createMockDAppKit, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import TransportPage from './TransportPage';

describe('TransportPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows empty orders message', async () => {
    render(<TestProvider><TransportPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('No transport orders.')).toBeInTheDocument();
    });
  });

  it('shows orders with status badges', async () => {
    mockClient.listOwnedObjects
      .mockResolvedValueOnce(mockListOwnedObjectsResponse([
        { objectId: '0xO1', json: { status: 1, from_storage: '0xS1', to_storage: '0xS2', tier: 0 } },
      ]))
      .mockResolvedValueOnce(mockListOwnedObjectsResponse([])); // receipts
    render(<TestProvider><TransportPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Paid')).toBeInTheDocument();
    });
  });

  it('shows Complete button for Paid orders', async () => {
    mockClient.listOwnedObjects
      .mockResolvedValueOnce(mockListOwnedObjectsResponse([
        { objectId: '0xO1', json: { status: 1, from_storage: '0xS1', to_storage: '0xS2', tier: 0 } },
      ]))
      .mockResolvedValueOnce(mockListOwnedObjectsResponse([]));
    render(<TestProvider><TransportPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Complete')).toBeInTheDocument();
    });
  });
});
```

- [ ] **Step 2: Write FuelStationPage tests**

```tsx
// src/pages/FuelStationPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, createMockDAppKit, mockGetObjectResponse, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import FuelStationPage from './FuelStationPage';

describe('FuelStationPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xFS1', {
        current_fuel: 1000000000000, max_fuel: 5000000000000,
        base_price: 100, owner_fee_bps: 500, total_supplied: 2000000000000,
      })
    );
    mockClient.getBalance.mockResolvedValue({ balance: { balance: '5000000000' } });
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows station stats', async () => {
    render(<TestProvider><FuelStationPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Station Stats')).toBeInTheDocument();
    });
  });

  it('shows FUEL balance', async () => {
    // 5000000000 / 1e9 = 5.00
    render(<TestProvider><FuelStationPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('5.00')).toBeInTheDocument();
    });
  });

  it('shows station selector buttons', () => {
    render(<TestProvider><FuelStationPage /></TestProvider>);
    expect(screen.getByText('Station 1')).toBeInTheDocument();
    expect(screen.getByText('Station 2')).toBeInTheDocument();
  });

  it('shows empty supplier receipts', async () => {
    render(<TestProvider><FuelStationPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('No supplier receipts.')).toBeInTheDocument();
    });
  });
});
```

- [ ] **Step 3: Run tests**

Run: `cd frontend && pnpm test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add frontend/src/pages/TransportPage.test.tsx frontend/src/pages/FuelStationPage.test.tsx
git commit -m "test(frontend): add page tests for Transport, FuelStation"
```

---

## Task 10: Monkey tests

**Files:**
- Create: `frontend/src/pages/monkey-pages.test.tsx`

- [ ] **Step 1: Write monkey tests**

```tsx
// src/pages/monkey-pages.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { Routes, Route, MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createMockClient, MOCK_ACCOUNT, createMockDAppKit } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

import { useCurrentAccount } from '@mysten/dapp-kit-react';
import DashboardPage from './DashboardPage';
import GuildPage from './GuildPage';
import BountyBoardPage from './BountyBoardPage';
import TransportPage from './TransportPage';
import FuelStationPage from './FuelStationPage';
import ThreatMapPage from './ThreatMapPage';
import StorageDetailPage from './StorageDetailPage';
import ContractDetailPage from './ContractDetailPage';
import { Button } from '../components/ui/Button';
import { StatusBadge } from '../components/ui/StatusBadge';
import { AddressDisplay } from '../components/ui/AddressDisplay';
import { TransactionToast } from '../components/ui/TransactionToast';
import { Panel } from '../components/ui/Panel';
import { Input } from '../components/ui/Input';

function qc() {
  return new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } });
}

describe('Monkey Tests — Pages render without crash', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // All hooks return empty/null to simulate "no data" state
    mockClient.listOwnedObjects.mockResolvedValue({ objects: [] });
    mockClient.getObject.mockResolvedValue({ object: null });
    mockClient.getBalance.mockResolvedValue({ balance: { balance: '0' } });
    mockClient.getDynamicField.mockResolvedValue({ dynamicField: null });
  });

  it.each([
    ['DashboardPage', <DashboardPage />],
    ['GuildPage', <GuildPage />],
    ['BountyBoardPage', <BountyBoardPage />],
    ['TransportPage', <TransportPage />],
    ['FuelStationPage', <FuelStationPage />],
    ['ThreatMapPage', <ThreatMapPage />],
  ])('%s renders with null/empty data without crash', (_name, element) => {
    expect(() =>
      render(<TestProvider>{element}</TestProvider>)
    ).not.toThrow();
  });

  it('StorageDetailPage with missing storage', () => {
    expect(() =>
      render(
        <QueryClientProvider client={qc()}>
          <MemoryRouter initialEntries={['/storage/0xBAD']}>
            <Routes><Route path="/storage/:storageId" element={<StorageDetailPage />} /></Routes>
          </MemoryRouter>
        </QueryClientProvider>
      )
    ).not.toThrow();
  });

  it('ContractDetailPage with missing contract', () => {
    expect(() =>
      render(
        <QueryClientProvider client={qc()}>
          <MemoryRouter initialEntries={['/bounty/0xBAD']}>
            <Routes><Route path="/bounty/:contractId" element={<ContractDetailPage />} /></Routes>
          </MemoryRouter>
        </QueryClientProvider>
      )
    ).not.toThrow();
  });
});

describe('Monkey Tests — UI components with extreme inputs', () => {
  const LONG_STRING = 'x'.repeat(10_000);
  const noop = vi.fn();

  beforeEach(() => {
    Object.assign(navigator, { clipboard: { writeText: vi.fn().mockResolvedValue(undefined) } });
  });

  it('Button with extremely long text', () => {
    expect(() => render(<Button>{LONG_STRING}</Button>)).not.toThrow();
  });

  it('StatusBadge with empty string', () => {
    expect(() => render(<StatusBadge status="" />)).not.toThrow();
  });

  it('StatusBadge with 10KB string', () => {
    expect(() => render(<StatusBadge status={LONG_STRING} />)).not.toThrow();
  });

  it('AddressDisplay with short address (less than 10 chars)', () => {
    expect(() => render(<AddressDisplay address="0x1" />)).not.toThrow();
  });

  it('AddressDisplay with empty address', () => {
    expect(() => render(<AddressDisplay address="" />)).not.toThrow();
  });

  it('TransactionToast with 10KB error message', () => {
    expect(() => render(<TransactionToast digest={null} error={LONG_STRING} onClose={noop} />)).not.toThrow();
  });

  it('Panel with no title and empty children', () => {
    expect(() => render(<Panel>{''}</Panel>)).not.toThrow();
  });

  it('Input with MAX_SAFE_INTEGER as value', () => {
    expect(() => render(<Input label="test" value={String(Number.MAX_SAFE_INTEGER)} onChange={noop} />)).not.toThrow();
  });
});

describe('Monkey Tests — useTransactionExecutor edge cases', () => {
  it('pages survive when signAndExecuteTransaction throws sync error', () => {
    mockDAppKit.signAndExecuteTransaction.mockImplementation(() => { throw new Error('Sync kaboom'); });
    expect(() =>
      render(<TestProvider><DashboardPage /></TestProvider>)
    ).not.toThrow();
  });

  it('pages survive with disconnected wallet', () => {
    vi.mocked(useCurrentAccount).mockReturnValue(null);
    // WalletGuard should show connect prompt, no crash
    expect(() =>
      render(<TestProvider><DashboardPage /></TestProvider>)
    ).not.toThrow();
  });
});
```

Note: the last "disconnected wallet" test may need adjustment — `useCurrentAccount` returning null should trigger `WalletGuard` which shows the connect prompt. The point is to verify no crash.

- [ ] **Step 2: Run tests**

Run: `cd frontend && pnpm test`
Expected: All monkey tests PASS

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/monkey-pages.test.tsx
git commit -m "test(frontend): add monkey tests for all pages and UI components with extreme inputs"
```

---

## Task 11: Final verification and count

- [ ] **Step 1: Run all tests**

Run: `cd frontend && pnpm test`
Expected: 107 (Layer 1) + new Layer 2a tests all PASS

- [ ] **Step 2: Run type check**

Run: `cd frontend && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Update progress.md**

Update `tasks/progress.md`:
- Mark `前端 tests Layer 2` checkbox with sub-item for Layer 2a
- Add completed history entry with test count

- [ ] **Step 4: Commit progress update**

```bash
git add tasks/progress.md
git commit -m "docs: update progress with Layer 2a test results"
```

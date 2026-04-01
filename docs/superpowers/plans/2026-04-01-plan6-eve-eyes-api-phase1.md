# EVE Eyes API Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace raw system_id numbers with human-readable star system names from the EVE Eyes World API, and add route distance preview to the Transport page.

**Architecture:** New `lib/eve-eyes/` module (types → client → hooks) consumed by 4 pages. All API calls are best-effort with silent degradation — pages display raw numbers when the API is unavailable. React Query with `staleTime: Infinity` for caching.

**Tech Stack:** TypeScript, React Query (`@tanstack/react-query`), Vitest, `fetch` API

**Spec:** `docs/superpowers/specs/2026-04-01-eve-eyes-api-phase1-design.md`

---

### Task 1: Types + Client

**Files:**
- Create: `frontend/src/lib/eve-eyes/types.ts`
- Create: `frontend/src/lib/eve-eyes/client.ts`
- Create: `frontend/src/lib/eve-eyes/client.test.ts`

- [ ] **Step 1: Create types.ts**

```typescript
// frontend/src/lib/eve-eyes/types.ts

export interface EveSystem {
  id: number;
  name: string;
  constellationId: number;
  regionId: number;
  location: { x: number; y: number; z: number };
  gateLinks: number[];
}

export interface EveSystemSummary {
  id: number;
  name: string;
  constellationId: number;
  regionId: number;
  location: { x: number; y: number; z: number };
}

export interface EveRoute {
  origin: EveSystem;
  destination: EveSystem;
  jumps: number;
  systems: EveSystem[];
}
```

- [ ] **Step 2: Create client.ts**

```typescript
// frontend/src/lib/eve-eyes/client.ts

import type { EveSystem, EveRoute, EveSystemSummary } from './types';

const BASE_URL = import.meta.env.VITE_EVE_EYES_URL ?? 'https://eve-eyes.d0v.xyz';
const TIMEOUT_MS = 5000;

async function fetchJson<T>(path: string): Promise<T | null> {
  try {
    const res = await fetch(`${BASE_URL}${path}`, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export async function getSystem(systemId: number): Promise<EveSystem | null> {
  return fetchJson<EveSystem>(`/api/world/systems/${systemId}`);
}

export async function getRoute(originId: number, destinationId: number): Promise<EveRoute | null> {
  return fetchJson<EveRoute>(`/api/world/route?originId=${originId}&destinationId=${destinationId}`);
}

export async function searchSystems(query: string): Promise<EveSystemSummary[]> {
  const result = await fetchJson<{ data: EveSystemSummary[] }>(`/api/world/systems/search?q=${encodeURIComponent(query)}`);
  return result?.data ?? [];
}

/** Euclidean distance in light-years. EVE coords are in meters. */
export function calculateDistanceLY(a: { x: number; y: number; z: number }, b: { x: number; y: number; z: number }): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  const meters = Math.sqrt(dx * dx + dy * dy + dz * dz);
  return meters / 9.461e18; // meters → light-years
}
```

- [ ] **Step 3: Write client tests**

```typescript
// frontend/src/lib/eve-eyes/client.test.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { getSystem, getRoute, searchSystems, calculateDistanceLY } from './client';

const MOCK_SYSTEM = {
  id: 30000142,
  name: 'EHK-KH7',
  constellationId: 20000011,
  regionId: 10000005,
  location: { x: -4552684025457672000, y: -1259408930879045600, z: 715413939445301200 },
  gateLinks: [],
};

describe('getSystem', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns system on 200', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(MOCK_SYSTEM),
    });
    const result = await getSystem(30000142);
    expect(result).toEqual(MOCK_SYSTEM);
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/world/systems/30000142'),
      expect.objectContaining({ signal: expect.any(AbortSignal) }),
    );
  });

  it('returns null on 404', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({ ok: false, status: 404 });
    expect(await getSystem(99999)).toBeNull();
  });

  it('returns null on network error', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockRejectedValue(new TypeError('Failed to fetch'));
    expect(await getSystem(1)).toBeNull();
  });
});

describe('getRoute', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns null on 404 (no gate links)', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({ ok: false, status: 404 });
    expect(await getRoute(30000142, 30000143)).toBeNull();
  });

  it('returns route data on 200', async () => {
    const mockRoute = { origin: MOCK_SYSTEM, destination: MOCK_SYSTEM, jumps: 5, systems: [] };
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockRoute),
    });
    const result = await getRoute(1, 2);
    expect(result).toEqual(mockRoute);
  });
});

describe('searchSystems', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns array from data field', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: [{ id: 1, name: 'Test' }] }),
    });
    const result = await searchSystems('test');
    expect(result).toEqual([{ id: 1, name: 'Test' }]);
  });

  it('returns empty array on error', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockRejectedValue(new Error('fail'));
    expect(await searchSystems('test')).toEqual([]);
  });

  it('encodes query parameter', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: [] }),
    });
    await searchSystems('hello world');
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('q=hello%20world'),
      expect.any(Object),
    );
  });
});

describe('calculateDistanceLY', () => {
  it('returns 0 for same coordinates', () => {
    const p = { x: 100, y: 200, z: 300 };
    expect(calculateDistanceLY(p, p)).toBe(0);
  });

  it('calculates distance for known coordinates', () => {
    const a = { x: 0, y: 0, z: 0 };
    const b = { x: 9.461e18, y: 0, z: 0 }; // exactly 1 LY apart on x-axis
    expect(calculateDistanceLY(a, b)).toBeCloseTo(1.0, 5);
  });

  it('calculates 3D distance', () => {
    const a = { x: 0, y: 0, z: 0 };
    // sqrt(1^2 + 1^2 + 1^2) = sqrt(3) ≈ 1.732 LY
    const unit = 9.461e18;
    const b = { x: unit, y: unit, z: unit };
    expect(calculateDistanceLY(a, b)).toBeCloseTo(Math.sqrt(3), 3);
  });
});
```

- [ ] **Step 4: Run tests**

Run: `cd frontend && pnpm vitest run src/lib/eve-eyes/client.test.ts`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/src/lib/eve-eyes/types.ts frontend/src/lib/eve-eyes/client.ts frontend/src/lib/eve-eyes/client.test.ts
git commit -m "feat(eve-eyes): add types, client, and distance calculation"
```

---

### Task 2: React Query Hooks

**Files:**
- Create: `frontend/src/lib/eve-eyes/hooks.ts`
- Create: `frontend/src/lib/eve-eyes/hooks.test.ts`

**Reference:** Existing hook pattern in `frontend/src/hooks/useStorageDetail.ts` — uses `useCurrentClient()` + `useQuery()` from `@tanstack/react-query`. Our hooks don't need SUI client; they use our own `getSystem`/`getRoute` from `client.ts`.

- [ ] **Step 1: Create hooks.ts**

```typescript
// frontend/src/lib/eve-eyes/hooks.ts

import { useQuery } from '@tanstack/react-query';
import { getSystem, getRoute, calculateDistanceLY } from './client';
import type { EveSystem } from './types';

const QUERY_OPTIONS = {
  staleTime: Infinity,
  gcTime: Infinity,
  retry: 1,
  refetchOnWindowFocus: false,
} as const;

export function useSystemName(systemId: number | null | undefined) {
  const query = useQuery({
    queryKey: ['eve-eyes', 'system', systemId],
    queryFn: () => getSystem(systemId!),
    enabled: systemId != null && systemId > 0,
    ...QUERY_OPTIONS,
  });

  return {
    name: query.data?.name ?? null,
    system: query.data ?? null,
    isLoading: query.isLoading,
  };
}

export function useRoute(
  originSystemId: number | null | undefined,
  destinationSystemId: number | null | undefined,
) {
  const origin = useSystemName(originSystemId);
  const destination = useSystemName(destinationSystemId);

  const routeQuery = useQuery({
    queryKey: ['eve-eyes', 'route', originSystemId, destinationSystemId],
    queryFn: () => getRoute(originSystemId!, destinationSystemId!),
    enabled: originSystemId != null && originSystemId > 0 && destinationSystemId != null && destinationSystemId > 0,
    ...QUERY_OPTIONS,
  });

  const distance = origin.system?.location && destination.system?.location
    ? calculateDistanceLY(origin.system.location, destination.system.location)
    : null;

  return {
    originName: origin.name,
    destinationName: destination.name,
    jumps: routeQuery.data?.jumps ?? null,
    distance,
    isLoading: origin.isLoading || destination.isLoading || routeQuery.isLoading,
  };
}
```

- [ ] **Step 2: Write hook tests**

The hooks use React Query, so we need `QueryClientProvider` in tests. Follow existing pattern from `frontend/src/test/setup.ts`.

```typescript
// frontend/src/lib/eve-eyes/hooks.test.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createElement, type ReactNode } from 'react';
import { useSystemName, useRoute } from './hooks';
import * as client from './client';

vi.mock('./client', () => ({
  getSystem: vi.fn(),
  getRoute: vi.fn(),
  calculateDistanceLY: vi.fn(),
}));

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(QueryClientProvider, { client: queryClient }, children);
  };
}

describe('useSystemName', () => {
  beforeEach(() => {
    vi.mocked(client.getSystem).mockReset();
  });

  it('returns name when API succeeds', async () => {
    vi.mocked(client.getSystem).mockResolvedValue({
      id: 30000142,
      name: 'EHK-KH7',
      constellationId: 20000011,
      regionId: 10000005,
      location: { x: 0, y: 0, z: 0 },
      gateLinks: [],
    });

    const { result } = renderHook(() => useSystemName(30000142), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.name).toBe('EHK-KH7');
    expect(result.current.system?.id).toBe(30000142);
  });

  it('returns null when API fails', async () => {
    vi.mocked(client.getSystem).mockResolvedValue(null);

    const { result } = renderHook(() => useSystemName(30000142), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.name).toBeNull();
    expect(result.current.system).toBeNull();
  });

  it('does not fetch when systemId is null', () => {
    renderHook(() => useSystemName(null), { wrapper: createWrapper() });
    expect(client.getSystem).not.toHaveBeenCalled();
  });

  it('does not fetch when systemId is 0', () => {
    renderHook(() => useSystemName(0), { wrapper: createWrapper() });
    expect(client.getSystem).not.toHaveBeenCalled();
  });

  it('does not fetch when systemId is negative', () => {
    renderHook(() => useSystemName(-1), { wrapper: createWrapper() });
    expect(client.getSystem).not.toHaveBeenCalled();
  });
});

describe('useRoute', () => {
  beforeEach(() => {
    vi.mocked(client.getSystem).mockReset();
    vi.mocked(client.getRoute).mockReset();
    vi.mocked(client.calculateDistanceLY).mockReset();
  });

  it('returns distance and names when both systems resolve', async () => {
    const sysA = { id: 1, name: 'Alpha', constellationId: 1, regionId: 1, location: { x: 0, y: 0, z: 0 }, gateLinks: [] };
    const sysB = { id: 2, name: 'Beta', constellationId: 2, regionId: 2, location: { x: 100, y: 0, z: 0 }, gateLinks: [] };

    vi.mocked(client.getSystem).mockImplementation(async (id) => id === 1 ? sysA : sysB);
    vi.mocked(client.getRoute).mockResolvedValue(null);
    vi.mocked(client.calculateDistanceLY).mockReturnValue(5.5);

    const { result } = renderHook(() => useRoute(1, 2), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.originName).toBe('Alpha');
    expect(result.current.destinationName).toBe('Beta');
    expect(result.current.distance).toBe(5.5);
    expect(result.current.jumps).toBeNull();
  });

  it('returns jumps when route API succeeds', async () => {
    const sys = { id: 1, name: 'X', constellationId: 1, regionId: 1, location: { x: 0, y: 0, z: 0 }, gateLinks: [] };
    vi.mocked(client.getSystem).mockResolvedValue(sys);
    vi.mocked(client.getRoute).mockResolvedValue({ origin: sys, destination: sys, jumps: 7, systems: [] });
    vi.mocked(client.calculateDistanceLY).mockReturnValue(0);

    const { result } = renderHook(() => useRoute(1, 2), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.jumps).toBe(7);
  });

  it('does not fetch when origin is null', () => {
    renderHook(() => useRoute(null, 2), { wrapper: createWrapper() });
    expect(client.getRoute).not.toHaveBeenCalled();
  });

  it('does not fetch when destination is null', () => {
    renderHook(() => useRoute(1, null), { wrapper: createWrapper() });
    expect(client.getRoute).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 3: Run tests**

Run: `cd frontend && pnpm vitest run src/lib/eve-eyes/hooks.test.ts`
Expected: all tests PASS

- [ ] **Step 4: Run all tests to confirm no regressions**

Run: `cd frontend && pnpm vitest run`
Expected: all 230+ existing tests PASS plus new tests

- [ ] **Step 5: Commit**

```bash
git add frontend/src/lib/eve-eyes/hooks.ts frontend/src/lib/eve-eyes/hooks.test.ts
git commit -m "feat(eve-eyes): add useSystemName and useRoute hooks"
```

---

### Task 3: formatDistance helper + env var

**Files:**
- Modify: `frontend/src/lib/format.ts`
- Modify: `frontend/src/lib/format.test.ts`
- Modify: `frontend/.env.test.local.example` (or create `frontend/.env` if not exists)

- [ ] **Step 1: Write failing test for formatDistance**

Add to `frontend/src/lib/format.test.ts`:

```typescript
describe('formatDistance', () => {
  it('formats light-years with 2 decimals', () => {
    expect(formatDistance(1.2345)).toBe('1.23 LY');
  });

  it('formats zero', () => {
    expect(formatDistance(0)).toBe('0.00 LY');
  });

  it('formats large values', () => {
    expect(formatDistance(1234.567)).toBe('1,234.57 LY');
  });

  it('formats small values', () => {
    expect(formatDistance(0.001)).toBe('0.00 LY');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && pnpm vitest run src/lib/format.test.ts`
Expected: FAIL — `formatDistance` is not exported

- [ ] **Step 3: Implement formatDistance**

Add to `frontend/src/lib/format.ts`:

```typescript
export function formatDistance(ly: number): string {
  return `${ly.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} LY`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && pnpm vitest run src/lib/format.test.ts`
Expected: PASS

- [ ] **Step 5: Add env var**

Create `frontend/.env` (if not exists, otherwise append):

```
VITE_EVE_EYES_URL=https://eve-eyes.d0v.xyz
```

- [ ] **Step 6: Commit**

```bash
git add frontend/src/lib/format.ts frontend/src/lib/format.test.ts frontend/.env
git commit -m "feat: add formatDistance helper and EVE Eyes env var"
```

---

### Task 4: StorageDetailPage — system name display

**Files:**
- Modify: `frontend/src/pages/StorageDetailPage.tsx:97`

- [ ] **Step 1: Add import**

At the top of `StorageDetailPage.tsx`, add:

```typescript
import { useSystemName } from '../lib/eve-eyes/hooks';
```

- [ ] **Step 2: Add hook call**

After `const isShared = obj?.owner.$kind === 'Shared';` (line 33), add:

```typescript
  const systemIdNum = Number(fields?.['system_id'] ?? 0);
  const systemInfo = useSystemName(fields ? systemIdNum : null);
```

- [ ] **Step 3: Update display**

Replace line 97:
```tsx
<div><span className="text-gray-400">System ID: </span>{String(fields['system_id'] ?? '')}</div>
```

With:
```tsx
<div><span className="text-gray-400">System ID: </span>{String(fields['system_id'] ?? '')}{systemInfo.name && <span className="text-cyan-400"> ({systemInfo.name})</span>}</div>
```

- [ ] **Step 4: Type-check**

Run: `cd frontend && npx tsc --noEmit`
Expected: clean

- [ ] **Step 5: Commit**

```bash
git add frontend/src/pages/StorageDetailPage.tsx
git commit -m "feat(storage-detail): display system name from EVE Eyes API"
```

---

### Task 5: ThreatMapPage — system name display

**Files:**
- Modify: `frontend/src/pages/ThreatMapPage.tsx`

- [ ] **Step 1: Add import**

At the top of `ThreatMapPage.tsx`, add:

```typescript
import { useSystemName } from '../lib/eve-eyes/hooks';
```

- [ ] **Step 2: Add hook call**

Inside the component, after the `dangerEntry` query (after line 36), add:

```typescript
  const systemInfo = useSystemName(queryId ? Number(queryId) : null);
```

- [ ] **Step 3: Update display in result panel**

Replace line 70:
```tsx
<div><span className="text-gray-400">System ID: </span>{systemId}</div>
```

With:
```tsx
<div><span className="text-gray-400">System ID: </span>{systemId}{systemInfo.name && <span className="text-cyan-400"> ({systemInfo.name})</span>}</div>
```

- [ ] **Step 4: Also update "no entry" message**

Replace line 80:
```tsx
<p className="text-gray-500 text-sm">No entry for system {systemId}.</p>
```

With:
```tsx
<p className="text-gray-500 text-sm">No entry for system {systemId}{systemInfo.name ? ` (${systemInfo.name})` : ''}.</p>
```

- [ ] **Step 5: Type-check**

Run: `cd frontend && npx tsc --noEmit`
Expected: clean

- [ ] **Step 6: Commit**

```bash
git add frontend/src/pages/ThreatMapPage.tsx
git commit -m "feat(threat-map): display system name from EVE Eyes API"
```

---

### Task 6: DashboardPage — system name in storage list

**Files:**
- Modify: `frontend/src/pages/DashboardPage.tsx`

The DashboardPage lists AdminCaps which only have `storage_id` (object ID), not `system_id`. To display system names, we need to fetch each Storage object to get its `system_id`, then resolve the name. We'll create an inline component to avoid prop drilling.

- [ ] **Step 1: Add imports**

At the top of `DashboardPage.tsx`, add:

```typescript
import { useStorageObject } from '../hooks/useStorageList';
import { useSystemName } from '../lib/eve-eyes/hooks';
```

- [ ] **Step 2: Create SystemLabel component inside the file**

Add before the `DashboardPage` export:

```typescript
function SystemLabel({ storageId }: { storageId: string }) {
  const storage = useStorageObject(storageId);
  const json = storage.data?.object?.json as Record<string, unknown> | null;
  const systemId = Number(json?.['system_id'] ?? 0);
  const systemInfo = useSystemName(systemId > 0 ? systemId : null);

  if (systemInfo.name) {
    return <span className="text-gray-300 text-xs ml-2">— {systemInfo.name}</span>;
  }
  if (systemId > 0) {
    return <span className="text-gray-500 text-xs ml-2">— #{systemId}</span>;
  }
  return null;
}
```

- [ ] **Step 3: Use SystemLabel in storage list**

In the storage list `map` callback (around line 57), replace:

```tsx
<span className="text-cyan-400 font-mono text-sm">{storageId.slice(0, 10)}...</span>
```

With:

```tsx
<span className="text-cyan-400 font-mono text-sm">{storageId.slice(0, 10)}...</span>
<SystemLabel storageId={storageId} />
```

- [ ] **Step 4: Type-check**

Run: `cd frontend && npx tsc --noEmit`
Expected: clean

- [ ] **Step 5: Commit**

```bash
git add frontend/src/pages/DashboardPage.tsx
git commit -m "feat(dashboard): display system name next to storage entries"
```

---

### Task 7: TransportPage — route preview panel

**Files:**
- Modify: `frontend/src/pages/TransportPage.tsx`

- [ ] **Step 1: Add imports**

At the top of `TransportPage.tsx`, add:

```typescript
import { useStorageObject } from '../hooks/useStorageList';
import { useRoute } from '../lib/eve-eyes/hooks';
import { formatDistance } from '../lib/format';
```

- [ ] **Step 2: Add storage + route hooks**

Inside the component, after the state declarations (after line 24), add:

```typescript
  const fromStorageObj = useStorageObject(fromStorage || undefined);
  const toStorageObj = useStorageObject(toStorage || undefined);

  const fromJson = fromStorageObj.data?.object?.json as Record<string, unknown> | null;
  const toJson = toStorageObj.data?.object?.json as Record<string, unknown> | null;
  const fromSystemId = Number(fromJson?.['system_id'] ?? 0) || null;
  const toSystemId = Number(toJson?.['system_id'] ?? 0) || null;

  const route = useRoute(fromSystemId, toSystemId);
```

- [ ] **Step 3: Add route preview panel**

After the closing `</Panel>` of "Create Transport Order" (after line 88), add:

```tsx
        {(route.originName || route.distance != null) && (
          <div className="px-4 py-3 bg-gray-800/30 rounded-lg border border-gray-700/50 text-sm text-gray-300 flex items-center gap-2">
            {route.isLoading ? (
              <LoadingSpinner />
            ) : (
              <>
                <span className="text-cyan-400">{route.originName ?? `#${fromSystemId}`}</span>
                <span className="text-gray-500">→</span>
                <span className="text-cyan-400">{route.destinationName ?? `#${toSystemId}`}</span>
                {route.distance != null && (
                  <>
                    <span className="text-gray-600 mx-1">|</span>
                    <span>{formatDistance(route.distance)}</span>
                  </>
                )}
                {route.jumps != null && (
                  <>
                    <span className="text-gray-600 mx-1">|</span>
                    <span>{route.jumps} jumps</span>
                  </>
                )}
              </>
            )}
          </div>
        )}
```

- [ ] **Step 4: Type-check**

Run: `cd frontend && npx tsc --noEmit`
Expected: clean

- [ ] **Step 5: Vite build check**

Run: `cd frontend && pnpm build`
Expected: build successful

- [ ] **Step 6: Commit**

```bash
git add frontend/src/pages/TransportPage.tsx
git commit -m "feat(transport): add route preview with distance and system names"
```

---

### Task 8: Final verification

**Files:** None (verification only)

- [ ] **Step 1: Run all unit tests**

Run: `cd frontend && pnpm vitest run`
Expected: all tests PASS (230+ existing + ~20 new)

- [ ] **Step 2: Type-check**

Run: `cd frontend && npx tsc --noEmit`
Expected: clean

- [ ] **Step 3: Production build**

Run: `cd frontend && pnpm build`
Expected: clean build

- [ ] **Step 4: Verify test count**

Check that new tests from Task 1-3 are included in the run output. Expected new test files:
- `src/lib/eve-eyes/client.test.ts` (~11 tests)
- `src/lib/eve-eyes/hooks.test.ts` (~9 tests)
- `src/lib/format.test.ts` (4 new tests added to existing file)

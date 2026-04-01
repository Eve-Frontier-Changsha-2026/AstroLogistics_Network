# EVE Eyes API Phase 1 — World API Integration Design

## Goal

Replace raw `system_id` numbers across the frontend with human-readable star system names from the EVE Eyes World API. Add route preview (distance + optional jump count) to the Transport page.

## Scope

- **In scope**: system name resolution, Euclidean distance calculation, route API (best-effort), 4 page modifications
- **Out of scope**: star system search/autocomplete, API key management, Phase 2 endpoints (killmails, leaderboard, module summary), local fallback map

## API Endpoints

All endpoints are public (no auth required).

Base URL: `https://eve-eyes.d0v.xyz` (configurable via `VITE_EVE_EYES_URL`)

### GET /api/world/systems/search?q={name}

Search solar systems by name (partial match).

Response:
```json
{
  "data": [
    {
      "id": 30007477,
      "name": "EHK-1D2",
      "constellationId": 20000465,
      "regionId": 10000062,
      "location": { "x": -5863298037475967000, "y": -365024013447069700, "z": -5683501498055524000 }
    }
  ]
}
```

Phase 1 usage: not consumed directly (no search UI). Reserved for Phase 2.

### GET /api/world/systems/{id}

Solar system detail by numeric ID.

Response:
```json
{
  "id": 30000142,
  "name": "EHK-KH7",
  "constellationId": 20000011,
  "regionId": 10000005,
  "location": { "x": -4552684025457672000, "y": -1259408930879045600, "z": 715413939445301200 },
  "gateLinks": []
}
```

Note: `gateLinks` is currently empty for all systems in EVE Frontier. This is expected — the game world may not have gate connections established yet.

### GET /api/world/route?originId={X}&destinationId={Y}

Compute route between two solar systems.

Currently returns 404 for all system pairs (no gate connections). Client must handle gracefully.

## Architecture

### New Files

```
frontend/src/lib/eve-eyes/
├── client.ts    — fetch wrapper (3 functions)
├── types.ts     — response type definitions
└── hooks.ts     — React Query hooks (2 hooks)
```

### client.ts

```typescript
const BASE_URL = import.meta.env.VITE_EVE_EYES_URL ?? 'https://eve-eyes.d0v.xyz';

async function getSystem(systemId: number): Promise<EveSystem | null>
async function getRoute(originId: number, destinationId: number): Promise<EveRoute | null>
async function searchSystems(query: string): Promise<EveSystemSummary[]>  // reserved for Phase 2
```

- All functions return `null` on any error (network, 404, timeout)
- No API key header (all endpoints public)
- `fetch` with 5s timeout via `AbortSignal.timeout(5000)`

### types.ts

```typescript
interface EveSystem {
  id: number;
  name: string;
  constellationId: number;
  regionId: number;
  location: { x: number; y: number; z: number };
  gateLinks: number[];
}

interface EveSystemSummary {
  id: number;
  name: string;
  constellationId: number;
  regionId: number;
  location: { x: number; y: number; z: number };
}

interface EveRoute {
  origin: EveSystem;
  destination: EveSystem;
  jumps: number;
  systems: EveSystem[];
}
```

Note: `EveRoute` shape is speculative since the API currently returns 404. Will be validated when gate data becomes available.

### hooks.ts

```typescript
function useSystemName(systemId: number | null | undefined): {
  name: string | null;
  system: EveSystem | null;
  isLoading: boolean;
}

function useRoute(originSystemId: number | null | undefined, destinationSystemId: number | null | undefined): {
  jumps: number | null;
  distance: number | null;  // Euclidean distance from location coords
  originName: string | null;
  destinationName: string | null;
  isLoading: boolean;
}
```

**`useSystemName`**:
- Calls `getSystem(systemId)` via `useQuery`
- `staleTime: Infinity` — system names never change
- `retry: 1` — one retry then give up
- `enabled: systemId != null && systemId > 0`

**`useRoute`**:
- Fetches both systems via `useSystemName` for name + location data
- Attempts `getRoute()` in parallel (best-effort, likely 404)
- Calculates Euclidean distance from `location.x/y/z`: `Math.sqrt(dx² + dy² + dz²)`
- Distance displayed as raw large number with `formatDistance()` helper (divide by `9.461e+18` for light-years, label "LY"). EVE uses meters internally.
- Returns jumps from route API if available, otherwise `null`
- Distance is always available if both systems resolve

## Page Modifications

### StorageDetailPage

- Import `useSystemName`
- Read `systemId` from parsed Storage fields
- Display: `System ID: 30000142 (EHK-KH7)` — parenthesized name appended when available
- Fallback: just `System ID: 30000142` if API fails

### ThreatMapPage

- Import `useSystemName`
- After query result loads, resolve system name for the queried `systemId`
- Display name next to danger level result
- Input field stays as manual number input (no change to interaction)

### DashboardPage

- Each Storage card in the list calls `useSystemName(storage.systemId)`
- Display: `System: EHK-KH7 (30000142)` — name first, ID in parens
- Fallback: `System: #30000142`

### TransportPage

- After user fills `fromStorage` and `toStorage`, both `useStorageDetail` hooks fire
- Extract `systemId` from each storage's fields
- Pass both to `useRoute(fromSystemId, toSystemId)`
- Display route preview panel below form:
  - `EHK-KH7 → A 2560 | Distance: 1.23 LY` (Euclidean, coords in meters / 9.461e18)
  - If route API returns data: `| 12 jumps` appended
  - Loading state: subtle spinner, no skeleton
  - Error/unavailable: panel hidden entirely
- Route preview is pure display — does not affect `buildCreateOrder` PTB

## Error Handling & Caching

| Scenario | Behavior |
|----------|----------|
| API timeout (>5s) | Return `null`, show raw system_id |
| API 404 | Return `null`, show raw system_id |
| Network error | Return `null`, show raw system_id |
| Invalid system_id (0, negative) | Hook disabled, no request |
| Route 404 (no gates) | Distance still shown from coords, jumps hidden |

React Query config per hook:
- `staleTime: Infinity`
- `gcTime: Infinity` (keep in cache forever during session)
- `retry: 1`
- `refetchOnWindowFocus: false`

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `VITE_EVE_EYES_URL` | No | `https://eve-eyes.d0v.xyz` | World API base URL |

Add to `.env`:
```
VITE_EVE_EYES_URL=https://eve-eyes.d0v.xyz
```

## File Impact Summary

| File | Action | Change |
|------|--------|--------|
| `src/lib/eve-eyes/client.ts` | New | Fetch wrapper (3 functions) |
| `src/lib/eve-eyes/types.ts` | New | Response type defs |
| `src/lib/eve-eyes/hooks.ts` | New | 2 React Query hooks |
| `src/pages/StorageDetailPage.tsx` | Modify | Add system name display |
| `src/pages/ThreatMapPage.tsx` | Modify | Add system name display |
| `src/pages/DashboardPage.tsx` | Modify | Add system name column |
| `src/pages/TransportPage.tsx` | Modify | Add route preview panel |
| `.env` | Modify | Add VITE_EVE_EYES_URL |

Total: 3 new + 4 modified + 1 env = 8 files

## Testing Strategy

- Unit tests for `client.ts` — mock fetch, test null returns on error/timeout
- Unit tests for distance calculation (Euclidean math)
- Hook tests with mocked client — verify staleTime, enabled conditions, fallback behavior
- No E2E test changes needed (existing tests use mocked routes, system names are additive display)

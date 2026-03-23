# AstroLogistics Network — Frontend dApp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a React SPA that lets players manage Storage, trade FUEL, create/accept courier bounties, manage guilds, and self-transport cargo across star systems — all connected to the AstroLogistics Move contracts on SUI testnet.

**Architecture:** Vite + React 19 + TypeScript SPA following the established EVE Frontier scaffold pattern (Bounty_Escrow_Protocol reference). Data layer reads on-chain state via `@mysten/dapp-kit-react` hooks (`useSuiClientQuery`) and writes via PTB (Programmable Transaction Block) builders. 7 route-based pages behind a shared Layout with Navbar. Tailwind CSS for styling with EVE Frontier space theme (Orbitron + Exo 2 fonts).

**Tech Stack:**
- React 19 + Vite 8 + TypeScript 5.9
- `@mysten/dapp-kit-react` ^2.0.1 + `@mysten/sui` ^2.9.1
- `@tanstack/react-query` ^5.91.3
- `react-router-dom` ^7.13.1
- Tailwind CSS 4.2
- pnpm

**Reference scaffold:** `../../Bounty_Escrow_Protocol/frontend/` (exact dependency versions, config patterns, provider stack)

**Contract IDs (testnet v3):**
- ORIGINAL_PACKAGE_ID: `0x564d32c9ce29b9f75c1821311aded4b84ee6d912c39e434309b9803e19f5f25c` (type references)
- PACKAGE_ID: `0x3407e5c8c245040bb2325dc1f5160188ec5ce811378107f1d2e6e82466bf706a` (function calls)
- FUEL_TYPE: `${ORIGINAL_PACKAGE_ID}::fuel::FUEL`
- CLOCK: `0x6`

---

## File Structure

```
frontend/
├── index.html
├── package.json
├── pnpm-lock.yaml
├── vite.config.ts
├── tsconfig.json
├── tsconfig.app.json
├── tsconfig.node.json
├── eslint.config.js
├── public/
│   └── favicon.svg
└── src/
    ├── main.tsx                          # ReactDOM + providers
    ├── App.tsx                           # Router + lazy pages
    ├── dapp-kit.ts                       # createDAppKit + module augmentation
    ├── index.css                         # Tailwind + EVE theme vars
    ├── config/
    │   ├── network.ts                    # NETWORKS, GRPC_URLS
    │   ├── contracts.ts                  # PACKAGE_ID, MODULE map, CLOCK
    │   └── objects.ts                    # Testnet shared object IDs
    ├── lib/
    │   ├── types.ts                      # On-chain data types (parsed)
    │   ├── format.ts                     # Address, MIST, timestamp formatters
    │   ├── constants.ts                  # UI constants (status labels, tier names)
    │   └── ptb/
    │       ├── storage.ts               # createStorage, deposit, withdraw, share, setGuild, setEncryptedCoords
    │       ├── guild.ts                 # createGuild, addMember, removeMember, leaveGuild
    │       ├── courier.ts               # createContract, acceptContract, pickupAndDeliver, confirmDelivery, settle, raiseDispute, cancelByClient, claimTimeout
    │       ├── fuel-station.ts          # buyFuel, supplyFuel, claimRevenue, withdrawSupplier
    │       └── transport.ts             # createOrder, payFuel, completeTransport, cancelOrder
    ├── hooks/
    │   ├── useTransactionExecutor.ts     # Sign + execute + toast
    │   ├── useOwnedObjects.ts           # Generic owned-object query (AdminCap, GuildMemberCap, etc.)
    │   ├── useStorageList.ts            # Query all Storage objects (owned + shared)
    │   ├── useStorageDetail.ts          # Single Storage + cargo list
    │   ├── useFuelStation.ts            # FuelStation state + price
    │   ├── useGuild.ts                  # Guild detail + member list
    │   ├── useGuildMemberCap.ts         # User's GuildMemberCap
    │   ├── useCourierContracts.ts       # Contract list (all/by user)
    │   ├── useContractDetail.ts         # Single CourierContract
    │   ├── useCourierBadge.ts           # User's CourierBadge for a contract
    │   ├── useTransportOrders.ts        # User's TransportOrder objects
    │   └── useFuelBalance.ts            # User's FUEL coin balance
    ├── components/
    │   ├── layout/
    │   │   ├── Layout.tsx               # Outlet + Navbar + footer
    │   │   └── Navbar.tsx               # Logo + nav links + wallet connect
    │   └── ui/
    │       ├── Button.tsx               # Styled button (variant: primary/secondary/danger)
    │       ├── Panel.tsx                # Card container with glassmorphism
    │       ├── Input.tsx                # Labeled text input
    │       ├── LoadingSpinner.tsx        # Spinner + skeleton
    │       ├── WalletGuard.tsx          # Require wallet connection
    │       ├── TransactionToast.tsx      # Success/error toast with tx link
    │       ├── StatusBadge.tsx           # Colored status pill
    │       └── AddressDisplay.tsx        # Truncated address with copy
    └── pages/
        ├── DashboardPage.tsx            # My storages + cargo overview + quick actions
        ├── StorageDetailPage.tsx         # Single storage: cargo list, deposit, withdraw, guild settings
        ├── BountyBoardPage.tsx           # Courier contract list + create contract form
        ├── ContractDetailPage.tsx        # Contract lifecycle actions
        ├── FuelStationPage.tsx           # Buy/sell FUEL + station stats
        ├── TransportPage.tsx             # Self-transport: create order, pay, complete
        ├── GuildPage.tsx                 # Guild management (create, members, link storage)
        └── ThreatMapPage.tsx            # Threat oracle data (table view)
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `frontend/package.json`
- Create: `frontend/vite.config.ts`
- Create: `frontend/tsconfig.json`
- Create: `frontend/tsconfig.app.json`
- Create: `frontend/tsconfig.node.json`
- Create: `frontend/index.html`
- Create: `frontend/eslint.config.js`
- Create: `frontend/public/favicon.svg`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "astrologistics-frontend",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "lint": "eslint .",
    "preview": "vite preview"
  },
  "dependencies": {
    "@mysten/dapp-kit-react": "^2.0.1",
    "@mysten/sui": "^2.9.1",
    "@tanstack/react-query": "^5.91.3",
    "react": "^19.2.4",
    "react-dom": "^19.2.4",
    "react-router-dom": "^7.13.1"
  },
  "devDependencies": {
    "@eslint/js": "^9.39.4",
    "@tailwindcss/vite": "^4.2.2",
    "@types/node": "^24.12.0",
    "@types/react": "^19.2.14",
    "@types/react-dom": "^19.2.3",
    "@vitejs/plugin-react": "^6.0.1",
    "eslint": "^9.39.4",
    "eslint-plugin-react-hooks": "^7.0.1",
    "eslint-plugin-react-refresh": "^0.5.2",
    "globals": "^17.4.0",
    "tailwindcss": "^4.2.2",
    "typescript": "~5.9.3",
    "typescript-eslint": "^8.57.0",
    "vite": "^8.0.1"
  }
}
```

- [ ] **Step 2: Create vite.config.ts**

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    rolldownOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules/react-dom') || id.includes('node_modules/react/') || id.includes('node_modules/react-router')) {
            return 'vendor-react';
          }
          if (id.includes('node_modules/@mysten/')) {
            return 'vendor-sui';
          }
        },
      },
    },
  },
});
```

- [ ] **Step 3: Create tsconfig files**

`tsconfig.json`:
```json
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ]
}
```

`tsconfig.app.json`:
```json
{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
    "target": "ES2023",
    "useDefineForClassFields": true,
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "types": ["vite/client"],
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "verbatimModuleSyntax": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "erasableSyntaxOnly": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedSideEffectImports": true
  },
  "include": ["src"]
}
```

`tsconfig.node.json`:
```json
{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.node.tsbuildinfo",
    "target": "ES2023",
    "lib": ["ES2023"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "verbatimModuleSyntax": true,
    "moduleDetection": "force",
    "noEmit": true,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "erasableSyntaxOnly": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedSideEffectImports": true
  },
  "include": ["vite.config.ts"]
}
```

- [ ] **Step 4: Create index.html**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <link rel="stylesheet" href="https://artifacts.evefrontier.com/fonts/fonts.css" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@500;700;900&family=Exo+2:wght@300;400;600;700&display=swap" rel="stylesheet" />
    <title>AstroLogistics — EVE Frontier</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 5: Create eslint.config.js (copy from scaffold)**

- [ ] **Step 6: Create favicon.svg (simple rocket icon)**

- [ ] **Step 7: Install dependencies**

Run: `cd frontend && pnpm install`
Expected: All dependencies installed, lock file generated.

- [ ] **Step 8: Verify build setup**

Run: `cd frontend && pnpm build`
Expected: Build fails (no src/main.tsx yet) — confirms toolchain works.

- [ ] **Step 9: Commit**

```bash
git add frontend/package.json frontend/vite.config.ts frontend/tsconfig*.json frontend/index.html frontend/eslint.config.js frontend/public/
git commit -m "feat(frontend): scaffold — vite + react + tailwind + dapp-kit"
```

---

## Task 2: Config Layer

**Files:**
- Create: `frontend/src/config/network.ts`
- Create: `frontend/src/config/contracts.ts`
- Create: `frontend/src/config/objects.ts`

- [ ] **Step 1: Create network.ts**

```ts
export const NETWORKS = ['testnet'] as const;
export type Network = (typeof NETWORKS)[number];

export const DEFAULT_NETWORK: Network = 'testnet';

export const GRPC_URLS: Record<Network, string> = {
  testnet: 'https://fullnode.testnet.sui.io:443',
};
```

- [ ] **Step 2: Create contracts.ts**

```ts
// Original (v1) — struct types are defined here
export const ORIGINAL_PACKAGE_ID =
  '0x564d32c9ce29b9f75c1821311aded4b84ee6d912c39e434309b9803e19f5f25c';

// Latest (v3) — function calls target this
export const PACKAGE_ID =
  '0x3407e5c8c245040bb2325dc1f5160188ec5ce811378107f1d2e6e82466bf706a';

export const MODULE = {
  storage: `${PACKAGE_ID}::storage`,
  courier_market: `${PACKAGE_ID}::courier_market`,
  guild: `${PACKAGE_ID}::guild`,
  fuel_station: `${PACKAGE_ID}::fuel_station`,
  transport: `${PACKAGE_ID}::transport`,
  fuel: `${PACKAGE_ID}::fuel`,
  threat_oracle: `${PACKAGE_ID}::threat_oracle`,
  seal_policy: `${PACKAGE_ID}::seal_policy`,
} as const;

// Struct types use ORIGINAL_PACKAGE_ID (where they were first defined)
export const TYPE = {
  Storage: `${ORIGINAL_PACKAGE_ID}::storage::Storage`,
  AdminCap: `${ORIGINAL_PACKAGE_ID}::storage::AdminCap`,
  Cargo: `${ORIGINAL_PACKAGE_ID}::storage::Cargo`,
  DepositReceipt: `${ORIGINAL_PACKAGE_ID}::storage::DepositReceipt`,
  CourierContract: `${ORIGINAL_PACKAGE_ID}::courier_market::CourierContract`,
  CourierBadge: `${ORIGINAL_PACKAGE_ID}::courier_market::CourierBadge`,
  Guild: `${ORIGINAL_PACKAGE_ID}::guild::Guild`,
  GuildMemberCap: `${ORIGINAL_PACKAGE_ID}::guild::GuildMemberCap`,
  FuelStation: `${ORIGINAL_PACKAGE_ID}::fuel_station::FuelStation`,
  StationCap: `${ORIGINAL_PACKAGE_ID}::fuel_station::StationCap`,
  SupplierReceipt: `${ORIGINAL_PACKAGE_ID}::fuel_station::SupplierReceipt`,
  TransportOrder: `${ORIGINAL_PACKAGE_ID}::transport::TransportOrder`,
  ThreatMap: `${ORIGINAL_PACKAGE_ID}::threat_oracle::ThreatMap`,
  OracleCap: `${ORIGINAL_PACKAGE_ID}::threat_oracle::OracleCap`,
  ReporterCap: `${ORIGINAL_PACKAGE_ID}::threat_oracle::ReporterCap`,
  FuelTreasuryCap: `${ORIGINAL_PACKAGE_ID}::fuel::FuelTreasuryCap`,
  FUEL: `${ORIGINAL_PACKAGE_ID}::fuel::FUEL`,
} as const;

export const CLOCK = '0x6';
```

- [ ] **Step 3: Create objects.ts**

```ts
// Shared objects deployed on testnet (from init-testnet.ts)
export const TESTNET_OBJECTS = {
  storage1: '0x1fcf2620712dad4745c8c2e4be10e5e3ffc6688b8a6c5dd8f5581d6223e7614c',
  storage2: '0x2a97c1b681a0420e8023e18b24230e23fb18cbfbc1962f06ab9edc24f59d7bcb',
  threatMap: '0xed6223a66967c994c781139af5bfe779a75309bbe6aea365ea00f58d68504f71',
  fuelStation1: '0x6d9f65c5a91e9d3f5b3f44d1bb0d6cff9fa9d96233973691e0f7f98479652238',
  fuelStation2: '0xecacfc19504df97bbbe164e499902d4fd7e015332fe54bc02aa0974c0f7eb3d6',
  // v3 objects
  guild: '0x6b1dafcaf0b2fce591440a0e43f3dd0a4b7d06ae6ceea4138c00154f742e75c4',
} as const;

// Admin caps (deployer-owned, not used in regular UI)
export const ADMIN_CAPS = {
  adminCap1: '0x60b9678a56c9cfa20e249434f958fbee8a9a1307acf8bca01ea51654ad63c1c3',
  adminCap2: '0x910553b99d112e29e2d73f4c0337d1a4085afc4997570a68b78d28189edcce13',
  oracleCap: '0xf3fd216ef4a86d818ba2aec607735f1ee079ffe40810d1f4c8de874b85cccd35',
  fuelTreasuryCap: '0x077592721b6425e85c5c2cfbb8bef7a479719e07b83878a30aa6c07c1428bfbc',
} as const;
```

- [ ] **Step 4: Commit**

```bash
git add frontend/src/config/
git commit -m "feat(frontend): config layer — network, contracts, testnet objects"
```

---

## Task 3: DAppKit + Providers + Layout Shell

**Files:**
- Create: `frontend/src/dapp-kit.ts`
- Create: `frontend/src/main.tsx`
- Create: `frontend/src/App.tsx`
- Create: `frontend/src/index.css`
- Create: `frontend/src/components/layout/Layout.tsx`
- Create: `frontend/src/components/layout/Navbar.tsx`

- [ ] **Step 1: Create dapp-kit.ts**

```ts
import { createDAppKit } from '@mysten/dapp-kit-react';
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { NETWORKS, DEFAULT_NETWORK, GRPC_URLS, type Network } from './config/network';

export const dAppKit = createDAppKit({
  networks: [...NETWORKS],
  defaultNetwork: DEFAULT_NETWORK,
  createClient: (network) =>
    new SuiGrpcClient({
      network: network as Network,
      baseUrl: GRPC_URLS[network as Network],
    }),
});

declare module '@mysten/dapp-kit-react' {
  interface Register {
    dAppKit: typeof dAppKit;
  }
}
```

- [ ] **Step 2: Create index.css with Tailwind + EVE theme**

```css
@import 'tailwindcss';

:root {
  --color-bg-primary: #0a0e17;
  --color-bg-secondary: #111827;
  --color-bg-panel: rgba(17, 24, 39, 0.8);
  --color-border: rgba(75, 85, 99, 0.4);
  --color-accent: #06b6d4;
  --color-accent-bright: #22d3ee;
  --color-success: #10b981;
  --color-warning: #f59e0b;
  --color-danger: #ef4444;
  --color-text-primary: #f3f4f6;
  --color-text-secondary: #9ca3af;
  --font-display: 'Orbitron', sans-serif;
  --font-body: 'Exo 2', sans-serif;
}

body {
  margin: 0;
  background: var(--color-bg-primary);
  color: var(--color-text-primary);
  font-family: var(--font-body);
  min-height: 100vh;
}

h1, h2, h3, h4 {
  font-family: var(--font-display);
}
```

- [ ] **Step 3: Create Navbar.tsx**

```tsx
import { ConnectButton } from '@mysten/dapp-kit-react';
import { NavLink } from 'react-router-dom';

const NAV_ITEMS = [
  { to: '/', label: 'Dashboard' },
  { to: '/bounty', label: 'Bounty Board' },
  { to: '/fuel', label: 'Fuel Station' },
  { to: '/transport', label: 'Transport' },
  { to: '/guild', label: 'Guild' },
  { to: '/threats', label: 'Threats' },
] as const;

export function Navbar() {
  return (
    <nav className="flex items-center justify-between px-6 py-3 border-b"
         style={{ borderColor: 'var(--color-border)', background: 'var(--color-bg-secondary)' }}>
      <div className="flex items-center gap-6">
        <span className="text-lg font-bold" style={{ fontFamily: 'var(--font-display)', color: 'var(--color-accent)' }}>
          AstroLogistics
        </span>
        <div className="flex gap-4">
          {NAV_ITEMS.map(({ to, label }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `text-sm transition-colors ${isActive ? 'text-cyan-400' : 'text-gray-400 hover:text-gray-200'}`
              }
            >
              {label}
            </NavLink>
          ))}
        </div>
      </div>
      <ConnectButton />
    </nav>
  );
}
```

- [ ] **Step 4: Create Layout.tsx**

```tsx
import { Outlet } from 'react-router-dom';
import { Navbar } from './Navbar';

export function Layout() {
  return (
    <div className="min-h-screen flex flex-col">
      <Navbar />
      <main className="flex-1 p-6 max-w-7xl mx-auto w-full">
        <Outlet />
      </main>
    </div>
  );
}
```

- [ ] **Step 5: Create App.tsx with lazy-loaded page stubs**

```tsx
import { lazy, Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import { Layout } from './components/layout/Layout';

const DashboardPage = lazy(() => import('./pages/DashboardPage'));
const BountyBoardPage = lazy(() => import('./pages/BountyBoardPage'));
const ContractDetailPage = lazy(() => import('./pages/ContractDetailPage'));
const FuelStationPage = lazy(() => import('./pages/FuelStationPage'));
const TransportPage = lazy(() => import('./pages/TransportPage'));
const GuildPage = lazy(() => import('./pages/GuildPage'));
const ThreatMapPage = lazy(() => import('./pages/ThreatMapPage'));
const StorageDetailPage = lazy(() => import('./pages/StorageDetailPage'));

function Fallback() {
  return <div className="text-gray-400 py-12 text-center">Loading…</div>;
}

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Suspense fallback={<Fallback />}><DashboardPage /></Suspense>} />
        <Route path="storage/:storageId" element={<Suspense fallback={<Fallback />}><StorageDetailPage /></Suspense>} />
        <Route path="bounty" element={<Suspense fallback={<Fallback />}><BountyBoardPage /></Suspense>} />
        <Route path="bounty/:contractId" element={<Suspense fallback={<Fallback />}><ContractDetailPage /></Suspense>} />
        <Route path="fuel" element={<Suspense fallback={<Fallback />}><FuelStationPage /></Suspense>} />
        <Route path="transport" element={<Suspense fallback={<Fallback />}><TransportPage /></Suspense>} />
        <Route path="guild" element={<Suspense fallback={<Fallback />}><GuildPage /></Suspense>} />
        <Route path="threats" element={<Suspense fallback={<Fallback />}><ThreatMapPage /></Suspense>} />
      </Route>
    </Routes>
  );
}
```

- [ ] **Step 6: Create main.tsx**

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DAppKitProvider } from '@mysten/dapp-kit-react';
import { BrowserRouter } from 'react-router-dom';
import { dAppKit } from './dapp-kit';
import App from './App';
import './index.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
      retry: 1,
      staleTime: 10_000,
    },
  },
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <DAppKitProvider dAppKit={dAppKit}>
        <BrowserRouter>
          <App />
        </BrowserRouter>
      </DAppKitProvider>
    </QueryClientProvider>
  </StrictMode>,
);
```

- [ ] **Step 7: Create page stubs (all 8 pages)**

Each page file exports a default component returning a placeholder:

```tsx
// Example: src/pages/DashboardPage.tsx
export default function DashboardPage() {
  return <h1 className="text-2xl">Dashboard</h1>;
}
```

Create all 8: `DashboardPage`, `StorageDetailPage`, `BountyBoardPage`, `ContractDetailPage`, `FuelStationPage`, `TransportPage`, `GuildPage`, `ThreatMapPage`.

- [ ] **Step 8: Verify dev server starts**

Run: `cd frontend && pnpm dev`
Expected: Vite dev server starts, browser shows "Dashboard" heading with navbar.

- [ ] **Step 9: Verify `tsc --noEmit` passes**

Run: `cd frontend && npx tsc --noEmit`
Expected: No errors.

- [ ] **Step 10: Commit**

```bash
git add frontend/src/
git commit -m "feat(frontend): dapp-kit setup + layout + page stubs — dev server working"
```

---

## Task 4: Shared UI Components

**Files:**
- Create: `frontend/src/components/ui/Button.tsx`
- Create: `frontend/src/components/ui/Panel.tsx`
- Create: `frontend/src/components/ui/Input.tsx`
- Create: `frontend/src/components/ui/LoadingSpinner.tsx`
- Create: `frontend/src/components/ui/WalletGuard.tsx`
- Create: `frontend/src/components/ui/TransactionToast.tsx`
- Create: `frontend/src/components/ui/StatusBadge.tsx`
- Create: `frontend/src/components/ui/AddressDisplay.tsx`

- [ ] **Step 1: Create Button.tsx**

```tsx
import type { ButtonHTMLAttributes } from 'react';

type Variant = 'primary' | 'secondary' | 'danger';

const VARIANT_CLASSES: Record<Variant, string> = {
  primary: 'bg-cyan-600 hover:bg-cyan-500 text-white',
  secondary: 'bg-gray-700 hover:bg-gray-600 text-gray-200 border border-gray-600',
  danger: 'bg-red-600 hover:bg-red-500 text-white',
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  loading?: boolean;
}

export function Button({ variant = 'primary', loading, disabled, children, className = '', ...props }: ButtonProps) {
  return (
    <button
      disabled={disabled || loading}
      className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${VARIANT_CLASSES[variant]} ${className}`}
      {...props}
    >
      {loading ? 'Processing…' : children}
    </button>
  );
}
```

- [ ] **Step 2: Create Panel.tsx**

```tsx
import type { ReactNode } from 'react';

interface PanelProps {
  title?: string;
  children: ReactNode;
  className?: string;
}

export function Panel({ title, children, className = '' }: PanelProps) {
  return (
    <div
      className={`rounded-xl border p-5 backdrop-blur-sm ${className}`}
      style={{ background: 'var(--color-bg-panel)', borderColor: 'var(--color-border)' }}
    >
      {title && (
        <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-400 mb-3"
            style={{ fontFamily: 'var(--font-display)' }}>
          {title}
        </h3>
      )}
      {children}
    </div>
  );
}
```

- [ ] **Step 3: Create Input.tsx**

```tsx
import type { InputHTMLAttributes } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
}

export function Input({ label, id, className = '', ...props }: InputProps) {
  const inputId = id ?? label.toLowerCase().replace(/\s+/g, '-');
  return (
    <div className={className}>
      <label htmlFor={inputId} className="block text-xs text-gray-400 mb-1">{label}</label>
      <input
        id={inputId}
        className="w-full px-3 py-2 rounded-lg bg-gray-800 border border-gray-600 text-gray-100 text-sm focus:outline-none focus:border-cyan-500"
        {...props}
      />
    </div>
  );
}
```

- [ ] **Step 4: Create LoadingSpinner.tsx**

```tsx
export function LoadingSpinner({ className = '' }: { className?: string }) {
  return (
    <div className={`flex items-center justify-center py-8 ${className}`}>
      <div className="w-6 h-6 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin" />
    </div>
  );
}
```

- [ ] **Step 5: Create WalletGuard.tsx**

```tsx
import type { ReactNode } from 'react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { Panel } from './Panel';

export function WalletGuard({ children }: { children: ReactNode }) {
  const account = useCurrentAccount();
  if (!account) {
    return (
      <Panel className="text-center py-12">
        <p className="text-gray-400">Connect your wallet to continue.</p>
      </Panel>
    );
  }
  return <>{children}</>;
}
```

- [ ] **Step 6: Create TransactionToast.tsx**

```tsx
import { useEffect, useState } from 'react';

interface ToastProps {
  digest: string | null;
  error: string | null;
  onClose: () => void;
}

export function TransactionToast({ digest, error, onClose }: ToastProps) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (digest || error) {
      setVisible(true);
      const timer = setTimeout(() => { setVisible(false); onClose(); }, 5000);
      return () => clearTimeout(timer);
    }
  }, [digest, error, onClose]);

  if (!visible) return null;

  return (
    <div className={`fixed bottom-4 right-4 z-50 px-4 py-3 rounded-lg border text-sm max-w-sm ${
      error ? 'bg-red-900/80 border-red-700 text-red-200' : 'bg-green-900/80 border-green-700 text-green-200'
    }`}>
      {error ? (
        <p>Transaction failed: {error}</p>
      ) : (
        <p>
          Success!{' '}
          <a
            href={`https://suiscan.xyz/testnet/tx/${digest}`}
            target="_blank"
            rel="noopener noreferrer"
            className="underline"
          >
            View on explorer
          </a>
        </p>
      )}
    </div>
  );
}
```

- [ ] **Step 7: Create StatusBadge.tsx**

```tsx
const BADGE_COLORS: Record<string, string> = {
  Open: 'bg-blue-900/60 text-blue-300 border-blue-700',
  Accepted: 'bg-yellow-900/60 text-yellow-300 border-yellow-700',
  PendingConfirm: 'bg-purple-900/60 text-purple-300 border-purple-700',
  Delivered: 'bg-green-900/60 text-green-300 border-green-700',
  Disputed: 'bg-red-900/60 text-red-300 border-red-700',
  Created: 'bg-blue-900/60 text-blue-300 border-blue-700',       // transport
  Paid: 'bg-yellow-900/60 text-yellow-300 border-yellow-700',    // transport
  Completed: 'bg-green-900/60 text-green-300 border-green-700',  // transport
  Cancelled: 'bg-gray-800 text-gray-400 border-gray-600',        // transport
};

export function StatusBadge({ status }: { status: string }) {
  const colors = BADGE_COLORS[status] ?? 'bg-gray-800 text-gray-400 border-gray-600';
  return (
    <span className={`inline-block px-2 py-0.5 text-xs rounded-full border ${colors}`}>
      {status}
    </span>
  );
}
```

- [ ] **Step 8: Create AddressDisplay.tsx**

```tsx
import { useState } from 'react';

export function AddressDisplay({ address }: { address: string }) {
  const [copied, setCopied] = useState(false);
  const short = `${address.slice(0, 6)}…${address.slice(-4)}`;

  const copy = () => {
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <button onClick={copy} className="text-cyan-400 hover:text-cyan-300 text-sm font-mono" title={address}>
      {copied ? 'Copied!' : short}
    </button>
  );
}
```

- [ ] **Step 9: Verify tsc --noEmit**

Run: `cd frontend && npx tsc --noEmit`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add frontend/src/components/
git commit -m "feat(frontend): shared UI components — Button, Panel, Input, WalletGuard, Toast, StatusBadge, AddressDisplay"
```

---

## Task 5: Lib Layer — Types, Format, Constants

**Files:**
- Create: `frontend/src/lib/types.ts`
- Create: `frontend/src/lib/format.ts`
- Create: `frontend/src/lib/constants.ts`

- [ ] **Step 1: Create types.ts**

```ts
// Parsed on-chain data types (from useSuiClientQuery results)

export interface StorageData {
  id: string;
  owner: string;
  systemId: number;
  maxCapacity: number;
  currentLoad: number;
  feeRateBps: number;
  guildId: string | null;        // dynamic_field, may not exist
  isShared: boolean;             // inferred from object owner type
}

export interface CargoData {
  id: string;
  owner: string;
  itemType: string;
  weight: number;
  value: number;
  depositedAt: number;
}

export interface DepositReceiptData {
  id: string;
  storageId: string;
  cargoId: string;
  depositor: string;
}

export interface CourierContractData {
  id: string;
  client: string;
  fromStorage: string;
  toStorage: string;
  reward: number;              // MIST
  clientDeposit: number;       // combined reward + cancel_penalty balance
  minCourierDeposit: number;
  deadline: number;
  status: number;
  courier: string | null;
  cargoValue: number;
  hasGuildBonus: boolean;      // check via getDynamicFieldObject(GuildBonusKey)
}

export interface GuildData {
  id: string;
  leader: string;
  name: string;
  memberCount: number;
  memberTableId: string;       // Table<address, bool> — enumerate via getDynamicFields
  createdAt: number;
}

export interface FuelStationData {
  id: string;
  owner: string;
  storageId: string;
  basePrice: number;
  alpha: number;
  ownerFeeBps: number;
  currentFuel: number;
  maxFuel: number;
  totalSupplied: number;
}

export interface TransportOrderData {
  id: string;
  sender: string;
  fromStorage: string;
  toStorage: string;
  tier: number;
  fuelCost: number;
  status: number;
  earliestCompleteAt: number;
}
```

- [ ] **Step 2: Create format.ts**

```ts
export function formatAddress(addr: string, chars = 6): string {
  if (addr.length <= chars * 2 + 1) return addr;
  return `${addr.slice(0, chars)}…${addr.slice(-4)}`;
}

export function formatMist(mist: number | bigint): string {
  const sui = Number(mist) / 1_000_000_000;
  return sui.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 });
}

export function formatFuel(raw: number | bigint): string {
  const fuel = Number(raw) / 1_000_000_000; // 9 decimals
  return fuel.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 });
}

export function formatTimestamp(ms: number): string {
  return new Date(ms).toLocaleString();
}

export function formatBps(bps: number): string {
  return `${(bps / 100).toFixed(1)}%`;
}

export function timeRemaining(deadlineMs: number): string {
  const diff = deadlineMs - Date.now();
  if (diff <= 0) return 'Expired';
  const hours = Math.floor(diff / 3_600_000);
  const mins = Math.floor((diff % 3_600_000) / 60_000);
  if (hours > 24) return `${Math.floor(hours / 24)}d ${hours % 24}h`;
  return `${hours}h ${mins}m`;
}
```

- [ ] **Step 3: Create constants.ts**

```ts
// On-chain statuses — contracts are destroyed on settle/cancel/timeout
export const CONTRACT_STATUS: Record<number, string> = {
  0: 'Open',
  1: 'Accepted',
  2: 'PendingConfirm',
  3: 'Delivered',
  4: 'Disputed',
};

export const TRANSPORT_STATUS: Record<number, string> = {
  0: 'Created',
  1: 'Paid',
  2: 'Completed',
  3: 'Cancelled',
};

export const TRANSPORT_TIER: Record<number, string> = {
  0: 'Instant',
  1: 'Express',
  2: 'Standard',
};
```

- [ ] **Step 4: Verify tsc**

Run: `cd frontend && npx tsc --noEmit`

- [ ] **Step 5: Commit**

```bash
git add frontend/src/lib/
git commit -m "feat(frontend): lib layer — types, format utils, UI constants"
```

---

## Task 6: Transaction Executor Hook

**Files:**
- Create: `frontend/src/hooks/useTransactionExecutor.ts`

- [ ] **Step 1: Create useTransactionExecutor.ts**

```ts
import { useCallback, useState } from 'react';
import { useSignAndExecuteTransaction } from '@mysten/dapp-kit-react';
import type { Transaction } from '@mysten/sui/transactions';

interface TxResult {
  digest: string | null;
  error: string | null;
  loading: boolean;
  execute: (tx: Transaction) => Promise<string | null>;
  reset: () => void;
}

export function useTransactionExecutor(): TxResult {
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction();
  const [digest, setDigest] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const execute = useCallback(async (tx: Transaction): Promise<string | null> => {
    setLoading(true);
    setDigest(null);
    setError(null);
    try {
      const result = await signAndExecute({ transaction: tx });
      setDigest(result.digest);
      return result.digest;
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Unknown error';
      setError(msg);
      return null;
    } finally {
      setLoading(false);
    }
  }, [signAndExecute]);

  const reset = useCallback(() => {
    setDigest(null);
    setError(null);
  }, []);

  return { digest, error, loading, execute, reset };
}
```

- [ ] **Step 2: Verify tsc**

Run: `cd frontend && npx tsc --noEmit`

- [ ] **Step 3: Commit**

```bash
git add frontend/src/hooks/useTransactionExecutor.ts
git commit -m "feat(frontend): useTransactionExecutor hook — sign + execute + error state"
```

---

## Task 7: PTB Builders — Storage + Guild

**Files:**
- Create: `frontend/src/lib/ptb/storage.ts`
- Create: `frontend/src/lib/ptb/guild.ts`

- [ ] **Step 1: Create storage.ts PTB builders**

```ts
import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK } from '../../config/contracts';

export function buildCreateStorage(
  systemId: number,
  maxCapacity: number,
  feeRateBps: number,
): Transaction {
  const tx = new Transaction();
  // Returns AdminCap (key+store) — auto-transferred to sender by SUI runtime
  // Storage itself is shared via transfer::share_object inside the Move function
  tx.moveCall({
    target: `${MODULE.storage}::create_storage`,
    arguments: [
      tx.pure.u64(systemId),
      tx.pure.u64(maxCapacity),
      tx.pure.u64(feeRateBps),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildDeposit(
  storageId: string,
  itemType: string,
  weight: number,
  value: number,
): Transaction {
  const tx = new Transaction();
  // Returns DepositReceipt (key+store) — auto-transferred to sender
  // item_type is vector<u8> on-chain; tx.pure.string() encodes as BCS vector<u8> (same wire format)
  tx.moveCall({
    target: `${MODULE.storage}::deposit`,
    arguments: [
      tx.object(storageId),
      tx.pure.string(itemType),
      tx.pure.u64(weight),
      tx.pure.u64(value),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildWithdraw(
  storageId: string,
  receiptId: string,
  paymentAmount: number,
): Transaction {
  const tx = new Transaction();
  const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(paymentAmount)]);
  tx.moveCall({
    target: `${MODULE.storage}::withdraw`,
    arguments: [
      tx.object(storageId),
      tx.object(receiptId),
      payment,
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildShareStorage(storageId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::share_storage`,
    arguments: [tx.object(storageId)],
  });
  return tx;
}

export function buildSetStorageGuild(
  storageId: string,
  adminCapId: string,
  guildId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::set_storage_guild`,
    arguments: [
      tx.object(storageId),
      tx.object(adminCapId),
      tx.pure.id(guildId),
    ],
  });
  return tx;
}

export function buildClaimFees(
  storageId: string,
  adminCapId: string,
): Transaction {
  const tx = new Transaction();
  // Returns Coin<SUI> — auto-transferred to sender by SUI runtime (key+store)
  tx.moveCall({
    target: `${MODULE.storage}::claim_fees`,
    arguments: [
      tx.object(storageId),
      tx.object(adminCapId),
    ],
  });
  return tx;
}

export function buildUpdateFeeRate(
  storageId: string,
  adminCapId: string,
  newRate: number,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::update_fee_rate`,
    arguments: [
      tx.object(storageId),
      tx.object(adminCapId),
      tx.pure.u64(newRate),
    ],
  });
  return tx;
}

export function buildSetEncryptedCoords(
  storageId: string,
  adminCapId: string,
  encryptedData: Uint8Array,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::set_encrypted_coords`,
    arguments: [
      tx.object(storageId),
      tx.object(adminCapId),
      tx.pure('vector<u8>', Array.from(encryptedData)),
    ],
  });
  return tx;
}
```

- [ ] **Step 2: Create guild.ts PTB builders**

```ts
import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK } from '../../config/contracts';

export function buildCreateGuild(name: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.guild}::create_guild`,
    arguments: [
      tx.pure.string(name),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildAddMember(
  guildId: string,
  leaderCapId: string,
  memberAddress: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.guild}::add_member`,
    arguments: [
      tx.object(guildId),
      tx.object(leaderCapId),
      tx.pure.address(memberAddress),
    ],
  });
  return tx;
}

export function buildRemoveMember(
  guildId: string,
  leaderCapId: string,
  memberAddress: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.guild}::remove_member`,
    arguments: [
      tx.object(guildId),
      tx.object(leaderCapId),
      tx.pure.address(memberAddress),
    ],
  });
  return tx;
}

export function buildLeaveGuild(
  guildId: string,
  memberCapId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.guild}::leave_guild`,
    arguments: [
      tx.object(guildId),
      tx.object(memberCapId),
    ],
  });
  return tx;
}
```

- [ ] **Step 3: Verify tsc**

Run: `cd frontend && npx tsc --noEmit`

- [ ] **Step 4: Commit**

```bash
git add frontend/src/lib/ptb/
git commit -m "feat(frontend): PTB builders — storage + guild transactions"
```

---

## Task 8: PTB Builders — Courier + Fuel Station + Transport

**Files:**
- Create: `frontend/src/lib/ptb/courier.ts`
- Create: `frontend/src/lib/ptb/fuel-station.ts`
- Create: `frontend/src/lib/ptb/transport.ts`

- [ ] **Step 1: Create courier.ts PTB builders**

```ts
import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK } from '../../config/contracts';

export function buildCreateContract(
  fromStorageId: string,
  toStorageId: string,
  receiptId: string,
  rewardAmount: number,
  cancelPenaltyAmount: number,
  minCourierDeposit: number,
  route: number[],
  deadlineDuration: number,
): Transaction {
  const tx = new Transaction();
  const [reward] = tx.splitCoins(tx.gas, [tx.pure.u64(rewardAmount)]);
  const [penalty] = tx.splitCoins(tx.gas, [tx.pure.u64(cancelPenaltyAmount)]);
  tx.moveCall({
    target: `${MODULE.courier_market}::create_contract`,
    arguments: [
      tx.object(fromStorageId),
      tx.object(toStorageId),
      tx.object(receiptId),
      reward,
      penalty,
      tx.pure.u64(minCourierDeposit),
      tx.pure.vector('u64', route),
      tx.pure.u64(deadlineDuration),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildAcceptContract(
  contractId: string,
  depositAmount: number,
): Transaction {
  const tx = new Transaction();
  const [deposit] = tx.splitCoins(tx.gas, [tx.pure.u64(depositAmount)]);
  tx.moveCall({
    target: `${MODULE.courier_market}::accept_contract`,
    arguments: [
      tx.object(contractId),
      deposit,
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildPickupAndDeliver(
  contractId: string,
  badgeId: string,
  fromStorageId: string,
  toStorageId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::pickup_and_deliver`,
    arguments: [
      tx.object(contractId),
      tx.object(badgeId),
      tx.object(fromStorageId),
      tx.object(toStorageId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildConfirmDelivery(contractId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::confirm_delivery`,
    arguments: [tx.object(contractId)],
  });
  return tx;
}

export function buildSettle(
  contractId: string,
  badgeId: string,
  oracleCapId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::settle`,
    arguments: [
      tx.object(contractId),
      tx.object(badgeId),
      tx.object(oracleCapId),
    ],
  });
  return tx;
}

export function buildRaiseDispute(contractId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::raise_dispute`,
    arguments: [
      tx.object(contractId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildCancelByClient(contractId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::cancel_by_client`,
    arguments: [tx.object(contractId)],
  });
  return tx;
}

export function buildClaimTimeout(contractId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::claim_timeout`,
    arguments: [
      tx.object(contractId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}
```

- [ ] **Step 2: Create fuel-station.ts PTB builders**

```ts
import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK, TYPE } from '../../config/contracts';

export function buildBuyFuel(
  stationId: string,
  amount: number,
  maxPricePerUnit: number,
  paymentAmount: number,
): Transaction {
  const tx = new Transaction();
  const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(paymentAmount)]);
  tx.moveCall({
    target: `${MODULE.fuel_station}::buy_fuel`,
    arguments: [
      tx.object(stationId),
      payment,
      tx.pure.u64(amount),
      tx.pure.u64(maxPricePerUnit),
    ],
  });
  return tx;
}

export function buildSupplyFuel(
  stationId: string,
  fuelCoinId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.fuel_station}::supply_fuel`,
    arguments: [
      tx.object(stationId),
      tx.object(fuelCoinId),
    ],
  });
  return tx;
}

export function buildClaimRevenue(
  stationId: string,
  receiptId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.fuel_station}::claim_revenue`,
    arguments: [
      tx.object(stationId),
      tx.object(receiptId),
    ],
  });
  return tx;
}

export function buildWithdrawSupplier(
  stationId: string,
  receiptId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.fuel_station}::withdraw_supplier`,
    arguments: [
      tx.object(stationId),
      tx.object(receiptId),
    ],
  });
  return tx;
}
```

- [ ] **Step 3: Create transport.ts PTB builders**

```ts
import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK } from '../../config/contracts';
import { ADMIN_CAPS } from '../../config/objects';

export function buildCreateOrder(
  fromStorageId: string,
  toStorageId: string,
  receiptId: string,
  route: number[],
  fuelCost: number,
  dangerSnapshot: number,
  tier: number,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.transport}::create_order`,
    arguments: [
      tx.object(fromStorageId),
      tx.object(toStorageId),
      tx.object(receiptId),
      tx.pure.vector('u64', route),
      tx.pure.u64(fuelCost),
      tx.pure.u64(dangerSnapshot),
      tx.pure.u8(tier),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildPayFuel(
  orderId: string,
  fuelCoinId: string,
  treasuryCapId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.transport}::pay_fuel`,
    arguments: [
      tx.object(orderId),
      tx.object(fuelCoinId),
      tx.object(treasuryCapId),
    ],
  });
  return tx;
}

export function buildCompleteTransport(
  orderId: string,
  fromStorageId: string,
  toStorageId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.transport}::complete_transport`,
    arguments: [
      tx.object(orderId),
      tx.object(fromStorageId),
      tx.object(toStorageId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildCancelOrder(orderId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.transport}::cancel_order`,
    arguments: [tx.object(orderId)],
  });
  return tx;
}
```

- [ ] **Step 4: Verify tsc**

Run: `cd frontend && npx tsc --noEmit`

- [ ] **Step 5: Commit**

```bash
git add frontend/src/lib/ptb/
git commit -m "feat(frontend): PTB builders — courier, fuel-station, transport"
```

---

## Task 9: Data Hooks — Storage + Guild + FUEL Balance

**Files:**
- Create: `frontend/src/hooks/useOwnedObjects.ts`
- Create: `frontend/src/hooks/useStorageList.ts`
- Create: `frontend/src/hooks/useStorageDetail.ts`
- Create: `frontend/src/hooks/useGuild.ts`
- Create: `frontend/src/hooks/useGuildMemberCap.ts`
- Create: `frontend/src/hooks/useFuelBalance.ts`

- [ ] **Step 1: Create useOwnedObjects.ts**

Generic hook to query owned objects by type. Uses `useSuiClientQuery('getOwnedObjects', ...)`.

```ts
import { useSuiClientQuery } from '@mysten/dapp-kit-react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';

export function useOwnedObjects(structType: string) {
  const account = useCurrentAccount();
  return useSuiClientQuery(
    'getOwnedObjects',
    {
      owner: account?.address ?? '',
      filter: { StructType: structType },
      options: { showContent: true, showType: true },
    },
    { enabled: !!account },
  );
}
```

- [ ] **Step 2: Create useStorageList.ts**

Query user's AdminCaps to find their storages, then fetch each Storage object.

```ts
import { useSuiClientQuery } from '@mysten/dapp-kit-react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';
import type { StorageData } from '../lib/types';

export function useOwnedAdminCaps() {
  const account = useCurrentAccount();
  return useSuiClientQuery(
    'getOwnedObjects',
    {
      owner: account?.address ?? '',
      filter: { StructType: TYPE.AdminCap },
      options: { showContent: true },
    },
    { enabled: !!account },
  );
}

export function useStorageObject(storageId: string | undefined) {
  return useSuiClientQuery(
    'getObject',
    {
      id: storageId ?? '',
      options: { showContent: true, showOwner: true },
    },
    { enabled: !!storageId },
  );
}

export function parseStorageFields(data: Record<string, unknown>, id: string, ownerType: string): StorageData {
  const fields = (data as { fields: Record<string, unknown> }).fields;
  return {
    id,
    owner: String(fields['owner'] ?? ''),
    systemId: Number(fields['system_id'] ?? 0),
    maxCapacity: Number(fields['max_capacity'] ?? 0),
    currentLoad: Number(fields['current_load'] ?? 0),
    feeRateBps: Number(fields['fee_rate_bps'] ?? 0),
    guildId: null, // read from dynamic_field separately
    isShared: ownerType === 'Shared',
  };
}
```

- [ ] **Step 3: Create useStorageDetail.ts**

Single storage + its deposit receipts.

```ts
import { useSuiClientQuery } from '@mysten/dapp-kit-react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

export function useStorageDetail(storageId: string) {
  return useSuiClientQuery(
    'getObject',
    {
      id: storageId,
      options: { showContent: true, showOwner: true },
    },
    { enabled: !!storageId },
  );
}

export function useMyReceipts() {
  const account = useCurrentAccount();
  return useSuiClientQuery(
    'getOwnedObjects',
    {
      owner: account?.address ?? '',
      filter: { StructType: TYPE.DepositReceipt },
      options: { showContent: true },
    },
    { enabled: !!account },
  );
}
```

- [ ] **Step 4: Create useGuild.ts**

```ts
import { useSuiClientQuery } from '@mysten/dapp-kit-react';

export function useGuildDetail(guildId: string | undefined) {
  return useSuiClientQuery(
    'getObject',
    {
      id: guildId ?? '',
      options: { showContent: true },
    },
    { enabled: !!guildId },
  );
}
```

- [ ] **Step 5: Create useGuildMemberCap.ts**

```ts
import { useOwnedObjects } from './useOwnedObjects';
import { TYPE } from '../config/contracts';

export function useGuildMemberCap() {
  return useOwnedObjects(TYPE.GuildMemberCap);
}
```

- [ ] **Step 6: Create useFuelBalance.ts**

```ts
import { useSuiClientQuery } from '@mysten/dapp-kit-react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

export function useFuelBalance() {
  const account = useCurrentAccount();
  return useSuiClientQuery(
    'getBalance',
    {
      owner: account?.address ?? '',
      coinType: TYPE.FUEL,
    },
    { enabled: !!account },
  );
}
```

- [ ] **Step 7: Verify tsc**

Run: `cd frontend && npx tsc --noEmit`

- [ ] **Step 8: Commit**

```bash
git add frontend/src/hooks/
git commit -m "feat(frontend): data hooks — storage, guild, fuel balance queries"
```

---

## Task 10: Data Hooks — Courier + Fuel Station + Transport

**Files:**
- Create: `frontend/src/hooks/useCourierContracts.ts`
- Create: `frontend/src/hooks/useContractDetail.ts`
- Create: `frontend/src/hooks/useCourierBadge.ts`
- Create: `frontend/src/hooks/useFuelStation.ts`
- Create: `frontend/src/hooks/useTransportOrders.ts`

- [ ] **Step 1: Create useCourierContracts.ts**

CourierContract is a **shared object** (`transfer::share_object`), NOT owned. Cannot use `getOwnedObjects`. Use event-based discovery via `suix_queryEvents` filtering on `ContractCreated` events.

```ts
import { useSuiClientQuery } from '@mysten/dapp-kit-react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';

// CourierContract is shared — discover via ContractCreated events by sender
export function useMyContracts() {
  const account = useCurrentAccount();
  return useSuiClientQuery(
    'queryEvents',
    {
      query: {
        MoveEventType: `${ORIGINAL_PACKAGE_ID}::courier_market::ContractCreated`,
      },
      order: 'descending',
      limit: 50,
    },
    { enabled: !!account },
  );
}

// Parse ContractCreated event to extract contract_id + client address
export function parseContractCreatedEvent(event: { parsedJson: Record<string, unknown> }) {
  const json = event.parsedJson;
  return {
    contractId: String(json['contract_id'] ?? ''),
    client: String(json['client'] ?? ''),
    fromStorage: String(json['from_storage'] ?? ''),
    toStorage: String(json['to_storage'] ?? ''),
    reward: Number(json['reward'] ?? 0),
    deadline: Number(json['deadline'] ?? 0),
  };
}
```

- [ ] **Step 2: Create useContractDetail.ts**

```ts
import { useSuiClientQuery } from '@mysten/dapp-kit-react';

export function useContractDetail(contractId: string | undefined) {
  return useSuiClientQuery(
    'getObject',
    {
      id: contractId ?? '',
      options: { showContent: true, showOwner: true },
    },
    { enabled: !!contractId },
  );
}
```

- [ ] **Step 3: Create useCourierBadge.ts**

```ts
import { useOwnedObjects } from './useOwnedObjects';
import { TYPE } from '../config/contracts';

export function useCourierBadges() {
  return useOwnedObjects(TYPE.CourierBadge);
}
```

- [ ] **Step 4: Create useFuelStation.ts**

```ts
import { useSuiClientQuery } from '@mysten/dapp-kit-react';

export function useFuelStationDetail(stationId: string) {
  return useSuiClientQuery(
    'getObject',
    {
      id: stationId,
      options: { showContent: true },
    },
    { enabled: !!stationId },
  );
}
```

- [ ] **Step 5: Create useTransportOrders.ts**

```ts
import { useOwnedObjects } from './useOwnedObjects';
import { TYPE } from '../config/contracts';

export function useMyTransportOrders() {
  return useOwnedObjects(TYPE.TransportOrder);
}
```

- [ ] **Step 6: Verify tsc**

Run: `cd frontend && npx tsc --noEmit`

- [ ] **Step 7: Commit**

```bash
git add frontend/src/hooks/
git commit -m "feat(frontend): data hooks — courier, fuel station, transport queries"
```

---

## Task 11: Dashboard Page

**Files:**
- Modify: `frontend/src/pages/DashboardPage.tsx`

- [ ] **Step 1: Implement DashboardPage**

Shows:
1. Wallet connection status
2. User's Storage list (from AdminCap → Storage object lookup)
3. User's FUEL balance
4. User's active courier contracts count
5. Quick action buttons: Create Storage, Deposit Cargo

Key components:
- `WalletGuard` wraps content
- `Panel` for each section
- `useOwnedAdminCaps` → map each cap to its storage ID → `useStorageObject`
- `useFuelBalance` for FUEL display
- Link to `/storage/:id` for each storage

```tsx
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { useOwnedAdminCaps } from '../hooks/useStorageList';
import { useFuelBalance } from '../hooks/useFuelBalance';
import { useMyContracts } from '../hooks/useCourierContracts';
import { formatMist, formatFuel } from '../lib/format';
import { Link } from 'react-router-dom';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { TransactionToast } from '../components/ui/TransactionToast';
import { buildCreateStorage } from '../lib/ptb/storage';

export default function DashboardPage() {
  const adminCaps = useOwnedAdminCaps();
  const fuelBalance = useFuelBalance();
  const contracts = useMyContracts();
  const tx = useTransactionExecutor();

  const handleCreateStorage = async () => {
    // Default params — user can customize later
    const ptb = buildCreateStorage(1, 100_000, 200);
    await tx.execute(ptb);
    adminCaps.refetch();
  };

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Dashboard</h1>

        {/* Stats row */}
        <div className="grid grid-cols-3 gap-4">
          <Panel title="FUEL Balance">
            <p className="text-2xl font-bold text-cyan-400">
              {fuelBalance.data ? formatFuel(fuelBalance.data.totalBalance) : '—'}
            </p>
          </Panel>
          <Panel title="My Storages">
            <p className="text-2xl font-bold">{adminCaps.data?.data.length ?? 0}</p>
          </Panel>
          <Panel title="My Contracts">
            <p className="text-2xl font-bold">{contracts.data?.data?.length ?? 0}</p>
          </Panel>
        </div>

        {/* Storages list */}
        <Panel title="My Storages">
          {adminCaps.isPending ? <LoadingSpinner /> : (
            <div className="space-y-3">
              {adminCaps.data?.data.map((obj) => {
                const fields = (obj.data?.content as { fields: Record<string, unknown> })?.fields;
                const storageId = String(fields?.['storage_id'] ?? '');
                return (
                  <Link key={obj.data?.objectId} to={`/storage/${storageId}`}
                    className="block p-3 rounded-lg bg-gray-800/50 hover:bg-gray-700/50 transition-colors border border-gray-700">
                    <span className="text-sm text-gray-400">Storage: </span>
                    <span className="text-cyan-400 font-mono text-sm">{storageId.slice(0, 10)}…</span>
                  </Link>
                );
              })}
              {adminCaps.data?.data.length === 0 && (
                <p className="text-gray-500 text-sm">No storages yet.</p>
              )}
            </div>
          )}
          <Button className="mt-4" onClick={handleCreateStorage} loading={tx.loading}>
            Create Storage
          </Button>
        </Panel>

        <TransactionToast digest={tx.digest} error={tx.error} onClose={tx.reset} />
      </div>
    </WalletGuard>
  );
}
```

- [ ] **Step 2: Verify dev server renders Dashboard**

Run: `cd frontend && pnpm dev`
Expected: Dashboard page renders with wallet guard, stats panels, storage list.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/DashboardPage.tsx
git commit -m "feat(frontend): Dashboard page — storage list, fuel balance, create storage"
```

---

## Task 12: Storage Detail Page

**Files:**
- Modify: `frontend/src/pages/StorageDetailPage.tsx`

- [ ] **Step 1: Implement StorageDetailPage**

Shows:
1. Storage stats (system_id, capacity, load, fee rate, guild_id)
2. User's deposit receipts for this storage
3. Actions: Deposit cargo, Withdraw cargo, Share storage, Set guild
4. Admin actions (if user owns AdminCap): Claim fees, Update fee rate

Uses `useParams()` to get storageId, `useStorageDetail` to fetch storage data, `useMyReceipts` to list receipts.

Implement the full page with:
- Storage info panel (formatted stats)
- Deposit form (item_type, weight, value inputs)
- Receipts list with withdraw button per receipt (calls `buildWithdraw`)
- Share button (calls `buildShareStorage`, shows confirmation since it's irreversible)
- Guild settings (if AdminCap owned)

- [ ] **Step 2: Verify in dev server**

Navigate to `/storage/<some-id>` — should show storage details or "not found".

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/StorageDetailPage.tsx
git commit -m "feat(frontend): Storage detail page — deposit, withdraw, share, guild settings"
```

---

## Task 13: Guild Page

**Files:**
- Modify: `frontend/src/pages/GuildPage.tsx`

- [ ] **Step 1: Implement GuildPage**

Sections:
1. **My Guild** — if user has GuildMemberCap, show guild details (name, leader, member count)
2. **Create Guild** — form with name input, calls `buildCreateGuild`
3. **Leader Actions** (if leader) — Add member (address input), Remove member (from list), Link storage
4. **Member Actions** — Leave guild

Uses `useGuildMemberCap` to check membership, `useGuildDetail` for guild data.

- [ ] **Step 2: Verify in dev server**

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/GuildPage.tsx
git commit -m "feat(frontend): Guild page — create, manage members, link storage"
```

---

## Task 14: Bounty Board Page

**Files:**
- Modify: `frontend/src/pages/BountyBoardPage.tsx`

- [ ] **Step 1: Implement BountyBoardPage**

Sections:
1. **Active Contracts** — list user's CourierContract objects with status badges
2. **Create Contract Form** — inputs for from_storage, to_storage, receipt, reward, penalty, deposit, route, deadline
3. Each contract links to `/bounty/:contractId`

Uses `useMyContracts`, `useMyReceipts` (to select receipt for contract creation).

Note: Full contract discovery (not just user-owned) would require event indexing. For hackathon, show only user's own contracts.

- [ ] **Step 2: Verify in dev server**

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/BountyBoardPage.tsx
git commit -m "feat(frontend): Bounty Board page — contract list + create contract form"
```

---

## Task 15: Contract Detail Page

**Files:**
- Modify: `frontend/src/pages/ContractDetailPage.tsx`

- [ ] **Step 1: Implement ContractDetailPage**

Shows contract lifecycle with conditional actions:
- **Created** (client view): Cancel button
- **Created** (courier view): Accept button (deposit input)
- **Accepted** (courier view): Pickup & Deliver button
- **PendingConfirm** (client view): Confirm or Raise Dispute
- **Disputed** (oracle view): Resolve Dispute (ruling select)
- **Any status**: Claim Timeout (if deadline passed)

Uses `useContractDetail`, `useCourierBadges`, `useCurrentAccount` to determine role (client vs courier).

Displays: status, reward, deadline (with countdown), cargo value, from/to storage IDs, courier address.

- [ ] **Step 2: Verify in dev server**

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/ContractDetailPage.tsx
git commit -m "feat(frontend): Contract detail page — full lifecycle actions"
```

---

## Task 16: Fuel Station Page

**Files:**
- Modify: `frontend/src/pages/FuelStationPage.tsx`

- [ ] **Step 1: Implement FuelStationPage**

Sections:
1. **Station selector** — dropdown for station1/station2 (from objects.ts)
2. **Station stats** — fuel level, base price, current price, alpha, owner fee
3. **Buy FUEL** — amount input, max price input, shows estimated cost, buy button
4. **Supply FUEL** — select FUEL coin from wallet, supply button
5. **My Receipts** — list SupplierReceipts with claim revenue / withdraw buttons

Uses `useFuelStationDetail` with selected station ID, `useFuelBalance` for user's FUEL, `useOwnedObjects(TYPE.SupplierReceipt)` for receipts.

- [ ] **Step 2: Verify in dev server**

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/FuelStationPage.tsx
git commit -m "feat(frontend): Fuel Station page — buy/sell FUEL, supply, claim revenue"
```

---

## Task 17: Transport Page

**Files:**
- Modify: `frontend/src/pages/TransportPage.tsx`

- [ ] **Step 1: Implement TransportPage**

Sections:
1. **Create Transport Order** — from_storage, to_storage, receipt, route, fuel_cost, tier selector
2. **My Orders** — list TransportOrder objects with status
3. **Order Actions** — Pay Fuel (for Created), Complete (for Paid), Cancel (for Created)

Uses `useMyTransportOrders`, `useMyReceipts`, `useFuelBalance`.

Note: `pay_fuel` requires FuelTreasuryCap (admin-only) and a FUEL coin. `complete_transport` requires the order to have passed earliest_complete_at. UI should show countdown for Express/Standard tiers.

- [ ] **Step 2: Verify in dev server**

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/TransportPage.tsx
git commit -m "feat(frontend): Transport page — create order, pay fuel, complete"
```

---

## Task 18: Threat Map Page

**Files:**
- Modify: `frontend/src/pages/ThreatMapPage.tsx`

- [ ] **Step 1: Implement ThreatMapPage**

Simple table view of threat data:
- Fetch ThreatMap shared object
- Parse `entries` (Table<u64, DangerEntry>)
- Display system_id, danger_score, last_update, decay status
- Note: Reading Table contents requires `getDynamicFields` + `getDynamicFieldObject` queries

For hackathon MVP, show the ThreatMap metadata and a note about querying individual entries by system_id. Full table enumeration would need a system_id input field.

- [ ] **Step 2: Verify in dev server**

- [ ] **Step 3: Commit**

```bash
git add frontend/src/pages/ThreatMapPage.tsx
git commit -m "feat(frontend): Threat Map page — table view of danger scores"
```

---

## Task 19: Final Polish + Build Verification

**Files:**
- Modify: various

- [ ] **Step 1: Verify full tsc --noEmit passes**

Run: `cd frontend && npx tsc --noEmit`

- [ ] **Step 2: Verify production build succeeds**

Run: `cd frontend && pnpm build`
Expected: Build output in `frontend/dist/`, no errors.

- [ ] **Step 3: Test all pages in dev server**

Manual smoke test:
1. `/` — Dashboard renders, connect wallet works
2. `/storage/:id` — Shows storage or not found
3. `/bounty` — Contract list renders
4. `/fuel` — Station stats render
5. `/transport` — Order list renders
6. `/guild` — Guild form renders
7. `/threats` — Threat table renders

- [ ] **Step 4: Add .gitignore entry for frontend build artifacts**

Verify `frontend/node_modules/` and `frontend/dist/` are gitignored.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat(frontend): final polish — build verified, all pages functional"
```

---

## Implementation Notes

### SUI Upgrade Type References
- **Struct types** (for `getOwnedObjects` filter, `getBalance` coinType) always use `ORIGINAL_PACKAGE_ID` — where the struct was first defined
- **Function calls** (for `moveCall` target) always use latest `PACKAGE_ID`
- This is a SUI upgrade pattern: types live at the original address, code at the latest

### Dynamic Fields
- Guild ID on Storage, GuildBonusInfo on CourierContract, OwnerFees on FuelStation are stored as `dynamic_field`
- Reading them requires `getDynamicFieldObject` with the correct key type/value
- For hackathon MVP, some dynamic field reads may be deferred

### SUI Seal Integration
- Encrypted coords on Storage use SUI Seal for encryption/decryption
- Full Seal SDK integration (encrypt on deposit, decrypt for guild members/couriers) is a stretch goal
- The `seal_policy` module's `seal_approve_guild_member` and `seal_approve_courier` entry functions are ready
- Frontend integration requires `@mysten/seal` SDK (check availability)

### CourierContract Discovery
- Contracts are `key` only objects, transferred to client on creation
- For hackathon, only show user's own contracts (`getOwnedObjects`)
- Full discovery (all open contracts) would need event-based indexing (`suix_queryEvents` with `ContractCreated` filter)

### Transport Limitations
- `pay_fuel` requires `FuelTreasuryCap` — this is an admin-controlled operation
- For hackathon, may need to expose a simplified flow or pre-fund orders
- `complete_transport` has a time delay for Express/Standard tiers (300s / 900s)

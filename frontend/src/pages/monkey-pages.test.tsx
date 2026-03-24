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

vi.mock('@mysten/sui/bcs', () => ({
  bcs: {
    u64: () => ({
      serialize: (_val: unknown) => ({
        toBytes: () => new Uint8Array([0, 0, 0, 0, 0, 0, 0, 1]),
      }),
    }),
  },
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

  const PAGES = [
    { name: 'DashboardPage', Component: DashboardPage },
    { name: 'GuildPage', Component: GuildPage },
    { name: 'BountyBoardPage', Component: BountyBoardPage },
    { name: 'TransportPage', Component: TransportPage },
    { name: 'FuelStationPage', Component: FuelStationPage },
    { name: 'ThreatMapPage', Component: ThreatMapPage },
  ];

  PAGES.forEach(({ name, Component }) => {
    it(`${name} renders with null/empty data without crash`, () => {
      expect(() =>
        render(<TestProvider><Component /></TestProvider>)
      ).not.toThrow();
    });
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
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.listOwnedObjects.mockResolvedValue({ objects: [] });
    mockClient.getObject.mockResolvedValue({ object: null });
    mockClient.getBalance.mockResolvedValue({ balance: { balance: '0' } });
    mockClient.getDynamicField.mockResolvedValue({ dynamicField: null });
  });

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

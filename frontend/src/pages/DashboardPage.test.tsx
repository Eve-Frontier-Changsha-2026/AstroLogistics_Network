import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { TestProvider } from '../test/TestProvider';
import {
  createMockClient,
  MOCK_ACCOUNT,
  createMockDAppKit,
  mockListOwnedObjectsResponse,
} from '../test/mocks';

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

  it('renders Dashboard heading', async () => {
    render(
      <TestProvider>
        <DashboardPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Dashboard')).toBeInTheDocument();
    });
  });

  it('shows FUEL balance formatted to 2 decimal places', async () => {
    // formatFuel(50000000000) = 50000000000 / 1e9 = "50.00"
    render(
      <TestProvider>
        <DashboardPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('50.00')).toBeInTheDocument();
    });
  });

  it('shows empty state when no storages', async () => {
    render(
      <TestProvider>
        <DashboardPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('No storages yet.')).toBeInTheDocument();
    });
  });

  it('shows storage link when admin cap exists', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([
        { objectId: '0xCAP1', json: { storage_id: '0xSTORE1aabbcc' } },
      ])
    );
    render(
      <TestProvider>
        <DashboardPage />
      </TestProvider>
    );
    await waitFor(() => {
      // The page renders storageId.slice(0,10) + "..."
      expect(screen.getByText('0xSTORE1aa...')).toBeInTheDocument();
    });
  });

  it('Create Storage button triggers signAndExecuteTransaction', async () => {
    render(
      <TestProvider>
        <DashboardPage />
      </TestProvider>
    );
    await waitFor(() => expect(screen.getByText('Create Storage')).toBeInTheDocument());
    await userEvent.click(screen.getByText('Create Storage'));
    expect(mockDAppKit.signAndExecuteTransaction).toHaveBeenCalled();
  });
});

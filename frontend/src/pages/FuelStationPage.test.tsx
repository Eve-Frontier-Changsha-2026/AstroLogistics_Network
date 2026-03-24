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
    // formatFuel(5000000000) = 5000000000 / 1e9 = "5.00"
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

  it('shows Fuel Station heading', async () => {
    render(<TestProvider><FuelStationPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Fuel Station')).toBeInTheDocument();
    });
  });
});

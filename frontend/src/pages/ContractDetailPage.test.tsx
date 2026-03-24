import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { Routes, Route, MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import {
  createMockClient,
  MOCK_ACCOUNT,
  MOCK_ADDRESS,
  createMockDAppKit,
  mockGetObjectResponse,
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

import ContractDetailPage from './ContractDetailPage';

function renderWithRoute(contractId: string) {
  return render(
    <QueryClientProvider
      client={new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })}
    >
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
    // Default: no courier badges
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows "Contract Detail" heading', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xCON1', {
        status: 0,
        reward: 1000000000,
        client: MOCK_ADDRESS,
        courier: '',
        cargo_value: 0,
        min_courier_deposit: 0,
        deadline: 0,
      })
    );
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText('Contract Detail')).toBeInTheDocument();
    });
  });

  it('shows status and reward formatted as SUI', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xCON1', {
        status: 0,
        reward: 3000000000, // 3.00 SUI — unique value so getByText won't find duplicates
        client: MOCK_ADDRESS,
        courier: '',
        cargo_value: 500000000,
        min_courier_deposit: 1000000000,
        deadline: 0,
        from_storage: '0xS1',
        to_storage: '0xS2',
      })
    );
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText('Open')).toBeInTheDocument();
      // formatMist(3000000000) = "3.00" — only appears once (reward)
      expect(screen.getByText(/3\.00 SUI/)).toBeInTheDocument();
    });
  });

  it('shows "Cancel Contract" button when client views Open contract', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xCON1', {
        status: 0,
        reward: 1000000000,
        client: MOCK_ADDRESS, // MOCK_ACCOUNT.address matches this
        courier: '',
        cargo_value: 0,
        min_courier_deposit: 0,
        deadline: 0,
      })
    );
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText('Cancel Contract')).toBeInTheDocument();
    });
  });

  it('shows "Accept Contract" button when non-client views Open contract', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xCON1', {
        status: 0,
        reward: 1000000000,
        client: '0x' + 'b'.repeat(64), // different address — not MOCK_ADDRESS
        courier: '',
        cargo_value: 0,
        min_courier_deposit: 0,
        deadline: 0,
      })
    );
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText('Accept Contract')).toBeInTheDocument();
    });
  });

  it('shows "Contract not found or already settled." for null object', async () => {
    mockClient.getObject.mockResolvedValue({ object: null });
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText(/Contract not found or already settled/)).toBeInTheDocument();
    });
  });

  it('does not show Cancel or Accept when status is Accepted (1)', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xCON1', {
        status: 1,
        reward: 1000000000,
        client: MOCK_ADDRESS,
        courier: '0x' + 'c'.repeat(64),
        cargo_value: 0,
        min_courier_deposit: 0,
        deadline: 0,
      })
    );
    renderWithRoute('0xCON1');
    await waitFor(() => {
      expect(screen.getByText('Accepted')).toBeInTheDocument();
    });
    expect(screen.queryByText('Cancel Contract')).not.toBeInTheDocument();
    expect(screen.queryByText('Accept Contract')).not.toBeInTheDocument();
  });
});

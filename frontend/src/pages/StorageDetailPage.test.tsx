import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { Routes, Route, MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import {
  createMockClient,
  MOCK_ACCOUNT,
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

import StorageDetailPage from './StorageDetailPage';

function renderWithRoute(storageId: string) {
  return render(
    <QueryClientProvider
      client={new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })}
    >
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
    // Default: no receipts, no admin caps
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows "Storage Detail" heading', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xS1', {
        owner: '0xABC',
        system_id: 1,
        max_capacity: 1000,
        current_load: 500,
        fee_rate_bps: 200,
      })
    );
    renderWithRoute('0xS1');
    await waitFor(() => {
      expect(screen.getByText('Storage Detail')).toBeInTheDocument();
    });
  });

  it('shows capacity as current_load / max_capacity', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xS1', {
        owner: '0xABC',
        system_id: 1,
        max_capacity: 1000,
        current_load: 500,
        fee_rate_bps: 200,
      })
    );
    renderWithRoute('0xS1');
    await waitFor(() => {
      // Renders as: {current_load} / {max_capacity}
      expect(screen.getByText(/500/)).toBeInTheDocument();
      expect(screen.getByText(/1000/)).toBeInTheDocument();
    });
  });

  it('shows "Storage not found." when object is null', async () => {
    mockClient.getObject.mockResolvedValue({ object: null });
    renderWithRoute('0xS1');
    await waitFor(() => {
      expect(screen.getByText('Storage not found.')).toBeInTheDocument();
    });
  });

  it('shows Admin Actions panel with Claim Fees button when user has AdminCap', async () => {
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse(
        '0xS1',
        {
          owner: MOCK_ACCOUNT.address,
          system_id: 1,
          max_capacity: 1000,
          current_load: 0,
          fee_rate_bps: 100,
        },
        false // not shared — so owned
      )
    );
    // useOwnedAdminCaps and useMyReceipts both call listOwnedObjects.
    // AdminCap has json.storage_id matching the storageId.
    mockClient.listOwnedObjects.mockImplementation(
      ({ type }: { type: string }) => {
        if (type?.includes('AdminCap')) {
          return Promise.resolve(
            mockListOwnedObjectsResponse([
              { objectId: '0xCAP1', json: { storage_id: '0xS1' } },
            ])
          );
        }
        return Promise.resolve(mockListOwnedObjectsResponse([]));
      }
    );
    renderWithRoute('0xS1');
    await waitFor(() => {
      expect(screen.getByText('Admin Actions')).toBeInTheDocument();
      expect(screen.getByText('Claim Fees')).toBeInTheDocument();
    });
  });
});

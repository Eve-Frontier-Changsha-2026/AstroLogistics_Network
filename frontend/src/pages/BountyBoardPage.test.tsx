import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
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

import BountyBoardPage from './BountyBoardPage';

describe('BountyBoardPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Default: no objects for any type
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
  });

  it('shows "Bounty Board" heading', async () => {
    render(
      <TestProvider>
        <BountyBoardPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Bounty Board')).toBeInTheDocument();
    });
  });

  it('shows "No contracts found." when empty', async () => {
    render(
      <TestProvider>
        <BountyBoardPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('No contracts found.')).toBeInTheDocument();
    });
  });

  it('shows contract with Open status badge', async () => {
    // useMyContracts calls listOwnedObjects with type CourierContract
    // useMyReceipts calls listOwnedObjects with type DepositReceipt
    // Use mockImplementation to distinguish by type
    mockClient.listOwnedObjects.mockImplementation(
      ({ type }: { type: string }) => {
        if (type?.includes('CourierContract')) {
          return Promise.resolve(
            mockListOwnedObjectsResponse([
              { objectId: '0xC1aabbccddeeff', json: { status: 0, reward: 1000000000 } },
            ])
          );
        }
        // DepositReceipt and anything else
        return Promise.resolve(mockListOwnedObjectsResponse([]));
      }
    );
    render(
      <TestProvider>
        <BountyBoardPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Open')).toBeInTheDocument();
    });
  });

  it('shows reward formatted as SUI amount', async () => {
    mockClient.listOwnedObjects.mockImplementation(
      ({ type }: { type: string }) => {
        if (type?.includes('CourierContract')) {
          return Promise.resolve(
            mockListOwnedObjectsResponse([
              { objectId: '0xC1aabbccddeeff', json: { status: 0, reward: 2000000000 } },
            ])
          );
        }
        return Promise.resolve(mockListOwnedObjectsResponse([]));
      }
    );
    render(
      <TestProvider>
        <BountyBoardPage />
      </TestProvider>
    );
    await waitFor(() => {
      // formatMist(2000000000) = "2.00" SUI
      expect(screen.getByText(/2\.00 SUI/)).toBeInTheDocument();
    });
  });

  it('shows multiple contracts with different statuses', async () => {
    mockClient.listOwnedObjects.mockImplementation(
      ({ type }: { type: string }) => {
        if (type?.includes('CourierContract')) {
          return Promise.resolve(
            mockListOwnedObjectsResponse([
              { objectId: '0xC1aabbccddeeff11', json: { status: 0, reward: 1000000000 } },
              { objectId: '0xC2aabbccddeeff22', json: { status: 1, reward: 500000000 } },
            ])
          );
        }
        return Promise.resolve(mockListOwnedObjectsResponse([]));
      }
    );
    render(
      <TestProvider>
        <BountyBoardPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Open')).toBeInTheDocument();
      expect(screen.getByText('Accepted')).toBeInTheDocument();
    });
  });
});

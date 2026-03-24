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
    mockClient.listOwnedObjects.mockImplementation(async (args: Record<string, unknown>) => {
      const type = String(args.type ?? '');
      if (type.includes('TransportOrder')) {
        return mockListOwnedObjectsResponse([
          { objectId: '0xO1', json: { status: 1, from_storage: '0xS1', to_storage: '0xS2', tier: 0 } },
        ]);
      }
      return mockListOwnedObjectsResponse([]);
    });
    render(<TestProvider><TransportPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Paid')).toBeInTheDocument();
    });
  });

  it('shows Complete button for Paid orders', async () => {
    mockClient.listOwnedObjects.mockImplementation(async (args: Record<string, unknown>) => {
      const type = String(args.type ?? '');
      if (type.includes('TransportOrder')) {
        return mockListOwnedObjectsResponse([
          { objectId: '0xO1', json: { status: 1, from_storage: '0xS1', to_storage: '0xS2', tier: 0 } },
        ]);
      }
      return mockListOwnedObjectsResponse([]);
    });
    render(<TestProvider><TransportPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Complete')).toBeInTheDocument();
    });
  });

  it('shows Cancel button for Created orders', async () => {
    mockClient.listOwnedObjects.mockImplementation(async (args: Record<string, unknown>) => {
      const type = String(args.type ?? '');
      if (type.includes('TransportOrder')) {
        return mockListOwnedObjectsResponse([
          { objectId: '0xO2', json: { status: 0, from_storage: '0xS1', to_storage: '0xS2', tier: 0 } },
        ]);
      }
      return mockListOwnedObjectsResponse([]);
    });
    render(<TestProvider><TransportPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });
  });

  it('shows Transport heading', async () => {
    render(<TestProvider><TransportPage /></TestProvider>);
    await waitFor(() => {
      expect(screen.getByText('Transport')).toBeInTheDocument();
    });
  });
});

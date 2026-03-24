import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockGetObjectResponse } from '../test/mocks';

const mockClient = createMockClient();

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

vi.mock('@mysten/dapp-kit-react/ui', () => ({
  ConnectButton: () => <button>Connect</button>,
}));

// bcs.u64().serialize() is only called on user interaction (Query button), not on render.
// Mock it defensively to avoid any BCS import issues in test env.
vi.mock('@mysten/sui/bcs', () => ({
  bcs: {
    u64: () => ({
      serialize: (_val: unknown) => ({
        toBytes: () => new Uint8Array([0, 0, 0, 0, 0, 0, 0, 1]),
      }),
    }),
  },
}));

import ThreatMapPage from './ThreatMapPage';

describe('ThreatMapPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xTM', { decay_lambda: '100' })
    );
  });

  it('renders Threat Map heading', async () => {
    render(
      <TestProvider>
        <ThreatMapPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Threat Map')).toBeInTheDocument();
    });
  });

  it('shows Decay Lambda value when data loads', async () => {
    render(
      <TestProvider>
        <ThreatMapPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Decay Lambda:')).toBeInTheDocument();
      expect(screen.getByText('100')).toBeInTheDocument();
    });
  });

  it('shows "Could not load ThreatMap." when object is null', async () => {
    mockClient.getObject.mockResolvedValue({ object: null });
    render(
      <TestProvider>
        <ThreatMapPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Could not load ThreatMap.')).toBeInTheDocument();
    });
  });
});

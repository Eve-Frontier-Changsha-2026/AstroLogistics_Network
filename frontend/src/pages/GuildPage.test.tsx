import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import {
  createMockClient,
  MOCK_ACCOUNT,
  createMockDAppKit,
  mockListOwnedObjectsResponse,
  mockGetObjectResponse,
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

import GuildPage from './GuildPage';

describe('GuildPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Default: no guild member cap
    mockClient.listOwnedObjects.mockResolvedValue(mockListOwnedObjectsResponse([]));
    mockClient.getObject.mockResolvedValue({ object: null });
  });

  it('shows "You are not in a guild" and Create Guild button when no cap', async () => {
    render(
      <TestProvider>
        <GuildPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText(/You are not in a guild/)).toBeInTheDocument();
      // Panel title + button both say "Create Guild" — verify at least the button is present
      const allCreateGuild = screen.getAllByText('Create Guild');
      expect(allCreateGuild.length).toBeGreaterThanOrEqual(1);
    });
  });

  it('shows guild name when user has GuildMemberCap', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([
        { objectId: '0xCAP1', json: { guild_id: '0xGUILD1' } },
      ])
    );
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xGUILD1', {
        name: 'Test Guild',
        leader: MOCK_ACCOUNT.address,
        member_count: 3,
      })
    );
    render(
      <TestProvider>
        <GuildPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Test Guild')).toBeInTheDocument();
    });
  });

  it('shows Add Member button in Leader Actions when user is leader', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([
        { objectId: '0xCAP1', json: { guild_id: '0xGUILD1' } },
      ])
    );
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xGUILD1', {
        name: 'My Guild',
        leader: MOCK_ACCOUNT.address,
        member_count: 1,
      })
    );
    render(
      <TestProvider>
        <GuildPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Add Member')).toBeInTheDocument();
      // Leader Actions panel title
      expect(screen.getByText('Leader Actions')).toBeInTheDocument();
    });
  });

  it('shows Leave Guild button in Member Actions when user is not leader', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([
        { objectId: '0xCAP1', json: { guild_id: '0xGUILD1' } },
      ])
    );
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xGUILD1', {
        name: 'Other Guild',
        leader: '0xOTHER',
        member_count: 5,
      })
    );
    render(
      <TestProvider>
        <GuildPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.getByText('Leave Guild')).toBeInTheDocument();
      expect(screen.getByText('Member Actions')).toBeInTheDocument();
    });
  });

  it('does not show Add Member for non-leader', async () => {
    mockClient.listOwnedObjects.mockResolvedValue(
      mockListOwnedObjectsResponse([
        { objectId: '0xCAP1', json: { guild_id: '0xGUILD1' } },
      ])
    );
    mockClient.getObject.mockResolvedValue(
      mockGetObjectResponse('0xGUILD1', {
        name: 'Other Guild',
        leader: '0xOTHER',
        member_count: 5,
      })
    );
    render(
      <TestProvider>
        <GuildPage />
      </TestProvider>
    );
    await waitFor(() => {
      expect(screen.queryByText('Add Member')).not.toBeInTheDocument();
    });
  });
});

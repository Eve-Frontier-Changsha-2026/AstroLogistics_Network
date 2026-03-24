// src/hooks/useOwnedObjects.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useOwnedObjects } from './useOwnedObjects';
import { useCurrentAccount } from '@mysten/dapp-kit-react';

describe('useOwnedObjects', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries owned objects with struct type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(
      mockListOwnedObjectsResponse([{ objectId: '0x1', json: { foo: 'bar' } }])
    );
    const { result } = renderHook(() => useOwnedObjects('0xpkg::mod::Type'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: '0xpkg::mod::Type',
      include: { json: true },
    });
    expect(result.current.data?.objects).toHaveLength(1);
  });

  it('is disabled when account is null', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useOwnedObjects('0xpkg::mod::Type'), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

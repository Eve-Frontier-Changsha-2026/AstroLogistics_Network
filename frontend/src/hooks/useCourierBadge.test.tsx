import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useCourierBadges } from './useCourierBadge';
import { TYPE } from '../config/contracts';

describe('useCourierBadges', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries CourierBadge type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(mockListOwnedObjectsResponse([]));
    const { result } = renderHook(() => useCourierBadges(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: TYPE.CourierBadge,
      include: { json: true },
    });
  });
});

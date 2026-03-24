import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useMyContracts } from './useCourierContracts';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

describe('useMyContracts', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries CourierContract type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(mockListOwnedObjectsResponse([]));
    const { result } = renderHook(() => useMyContracts(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: TYPE.CourierContract,
      include: { json: true },
    });
  });

  it('is disabled when no account', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useMyContracts(), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

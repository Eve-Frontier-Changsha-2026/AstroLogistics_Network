import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockGetObjectResponse, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useStorageDetail, useMyReceipts } from './useStorageDetail';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

describe('useStorageDetail', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches storage object by id', async () => {
    mockClient.getObject.mockResolvedValueOnce(mockGetObjectResponse('0xS1', { owner: '0xA' }));
    const { result } = renderHook(() => useStorageDetail('0xS1'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getObject).toHaveBeenCalledWith({ objectId: '0xS1', include: { json: true } });
  });

  it('is disabled when storageId is empty string', () => {
    const { result } = renderHook(() => useStorageDetail(''), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

describe('useMyReceipts', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries DepositReceipt type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(mockListOwnedObjectsResponse([]));
    const { result } = renderHook(() => useMyReceipts(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: TYPE.DepositReceipt,
      include: { json: true },
    });
  });

  it('is disabled when no account', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useMyReceipts(), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

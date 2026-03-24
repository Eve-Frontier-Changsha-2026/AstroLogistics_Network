// src/hooks/useStorageList.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT, mockGetObjectResponse, mockListOwnedObjectsResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useOwnedAdminCaps, useStorageObject, parseStorageFields } from './useStorageList';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

describe('useOwnedAdminCaps', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries AdminCap type', async () => {
    mockClient.listOwnedObjects.mockResolvedValueOnce(mockListOwnedObjectsResponse([]));
    const { result } = renderHook(() => useOwnedAdminCaps(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.listOwnedObjects).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      type: TYPE.AdminCap,
      include: { json: true },
    });
  });

  it('is disabled when no account', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useOwnedAdminCaps(), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

describe('useStorageObject', () => {
  beforeEach(() => vi.clearAllMocks());

  it('queries object by id', async () => {
    mockClient.getObject.mockResolvedValueOnce(mockGetObjectResponse('0xSTORAGE', { owner: '0xABC' }));
    const { result } = renderHook(() => useStorageObject('0xSTORAGE'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getObject).toHaveBeenCalledWith({ objectId: '0xSTORAGE', include: { json: true } });
  });

  it('is disabled when storageId is undefined', () => {
    const { result } = renderHook(() => useStorageObject(undefined), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

describe('parseStorageFields', () => {
  it('maps all fields correctly', () => {
    const json = { owner: '0xABC', system_id: 42, max_capacity: 1000, current_load: 500, fee_rate_bps: 200 };
    const result = parseStorageFields(json, '0xID', true);
    expect(result).toEqual({
      id: '0xID', owner: '0xABC', systemId: 42, maxCapacity: 1000,
      currentLoad: 500, feeRateBps: 200, guildId: null, isShared: true,
    });
  });

  it('defaults missing fields to 0 or empty', () => {
    const result = parseStorageFields({}, '0xID', false);
    expect(result).toEqual({
      id: '0xID', owner: '', systemId: 0, maxCapacity: 0,
      currentLoad: 0, feeRateBps: 0, guildId: null, isShared: false,
    });
  });
});

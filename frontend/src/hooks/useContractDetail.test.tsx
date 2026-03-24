import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, mockGetObjectResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
}));

import { useContractDetail } from './useContractDetail';

describe('useContractDetail', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches contract by id', async () => {
    mockClient.getObject.mockResolvedValueOnce(mockGetObjectResponse('0xC1', { status: 0 }));
    const { result } = renderHook(() => useContractDetail('0xC1'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getObject).toHaveBeenCalledWith({ objectId: '0xC1', include: { json: true } });
  });

  it('is disabled when contractId is undefined', () => {
    const { result } = renderHook(() => useContractDetail(undefined), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

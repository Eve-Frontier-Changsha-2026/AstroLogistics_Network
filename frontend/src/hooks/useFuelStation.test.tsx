import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, mockGetObjectResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
}));

import { useFuelStationDetail } from './useFuelStation';

describe('useFuelStationDetail', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches station by id', async () => {
    mockClient.getObject.mockResolvedValueOnce(mockGetObjectResponse('0xFS1', { current_fuel: 1000 }));
    const { result } = renderHook(() => useFuelStationDetail('0xFS1'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getObject).toHaveBeenCalledWith({ objectId: '0xFS1', include: { json: true } });
  });

  it('is disabled when stationId is empty string', () => {
    const { result } = renderHook(() => useFuelStationDetail(''), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

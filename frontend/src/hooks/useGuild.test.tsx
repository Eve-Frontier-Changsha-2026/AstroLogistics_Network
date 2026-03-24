import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, mockGetObjectResponse } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
}));

import { useGuildDetail } from './useGuild';

describe('useGuildDetail', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches guild by id', async () => {
    mockClient.getObject.mockResolvedValueOnce(mockGetObjectResponse('0xG1', { name: 'Test' }));
    const { result } = renderHook(() => useGuildDetail('0xG1'), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getObject).toHaveBeenCalledWith({ objectId: '0xG1', include: { json: true } });
  });

  it('is disabled when guildId is undefined', () => {
    const { result } = renderHook(() => useGuildDetail(undefined), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

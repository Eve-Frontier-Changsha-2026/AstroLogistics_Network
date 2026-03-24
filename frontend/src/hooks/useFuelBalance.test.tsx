// src/hooks/useFuelBalance.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, MOCK_ACCOUNT } from '../test/mocks';

const mockClient = createMockClient();
vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useCurrentAccount: vi.fn(() => MOCK_ACCOUNT),
}));

import { useFuelBalance } from './useFuelBalance';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { TYPE } from '../config/contracts';

describe('useFuelBalance', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns balance from gRPC response', async () => {
    mockClient.getBalance.mockResolvedValueOnce({ balance: { balance: '5000000000000' } });
    const { result } = renderHook(() => useFuelBalance(), { wrapper: TestProvider });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockClient.getBalance).toHaveBeenCalledWith({
      owner: MOCK_ACCOUNT.address,
      coinType: TYPE.FUEL,
    });
    expect(result.current.data?.balance.balance).toBe('5000000000000');
  });

  it('is disabled when account is null', () => {
    vi.mocked(useCurrentAccount).mockReturnValueOnce(null);
    const { result } = renderHook(() => useFuelBalance(), { wrapper: TestProvider });
    expect(result.current.fetchStatus).toBe('idle');
  });
});

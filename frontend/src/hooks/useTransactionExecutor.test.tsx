// src/hooks/useTransactionExecutor.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { TestProvider } from '../test/TestProvider';
import { createMockClient, createMockDAppKit } from '../test/mocks';

const mockClient = createMockClient();
const mockDAppKit = createMockDAppKit();
const mockInvalidateQueries = vi.fn().mockResolvedValue(undefined);

vi.mock('@mysten/dapp-kit-react', () => ({
  useCurrentClient: vi.fn(() => mockClient),
  useDAppKit: vi.fn(() => mockDAppKit),
}));

vi.mock('@tanstack/react-query', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@tanstack/react-query')>();
  return {
    ...actual,
    useQueryClient: vi.fn(() => ({ invalidateQueries: mockInvalidateQueries })),
  };
});

import { useTransactionExecutor } from './useTransactionExecutor';
import { Transaction } from '@mysten/sui/transactions';

describe('useTransactionExecutor', () => {
  beforeEach(() => vi.clearAllMocks());

  it('starts in idle state', () => {
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });
    expect(result.current.digest).toBeNull();
    expect(result.current.error).toBeNull();
    expect(result.current.loading).toBe(false);
  });

  it('transitions to loading → success on successful tx', async () => {
    mockDAppKit.signAndExecuteTransaction.mockResolvedValueOnce({
      Transaction: { digest: 'tx-digest-123' },
    });
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    let executePromise: Promise<string | null>;
    act(() => {
      executePromise = result.current.execute(new Transaction());
    });

    expect(result.current.loading).toBe(true);

    const digest = await act(async () => executePromise!);
    expect(digest).toBe('tx-digest-123');
    expect(result.current.digest).toBe('tx-digest-123');
    expect(result.current.error).toBeNull();
    expect(result.current.loading).toBe(false);
    expect(mockClient.waitForTransaction).toHaveBeenCalledWith({ digest: 'tx-digest-123' });
    expect(mockInvalidateQueries).toHaveBeenCalled();
  });

  it('handles FailedTransaction response', async () => {
    mockDAppKit.signAndExecuteTransaction.mockResolvedValueOnce({
      FailedTransaction: { status: { error: { message: 'Abort: 42' } } },
    });
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    let digest: string | null;
    await act(async () => {
      digest = await result.current.execute(new Transaction());
    });

    expect(digest!).toBeNull();
    expect(result.current.error).toBe('Abort: 42');
    expect(result.current.loading).toBe(false);
  });

  it('handles FailedTransaction with missing error message', async () => {
    mockDAppKit.signAndExecuteTransaction.mockResolvedValueOnce({
      FailedTransaction: {},
    });
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    await act(async () => {
      await result.current.execute(new Transaction());
    });

    expect(result.current.error).toBe('Transaction failed');
  });

  it('handles thrown error', async () => {
    mockDAppKit.signAndExecuteTransaction.mockRejectedValueOnce(new Error('Network timeout'));
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    await act(async () => {
      await result.current.execute(new Transaction());
    });

    expect(result.current.error).toBe('Network timeout');
    expect(result.current.digest).toBeNull();
    expect(result.current.loading).toBe(false);
  });

  it('handles non-Error thrown value', async () => {
    mockDAppKit.signAndExecuteTransaction.mockRejectedValueOnce('string-error');
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    await act(async () => {
      await result.current.execute(new Transaction());
    });

    expect(result.current.error).toBe('Unknown error');
  });

  it('handles concurrent executions — last one wins', async () => {
    let resolve1: (v: unknown) => void;
    let resolve2: (v: unknown) => void;
    mockDAppKit.signAndExecuteTransaction
      .mockImplementationOnce(() => new Promise(r => { resolve1 = r; }))
      .mockImplementationOnce(() => new Promise(r => { resolve2 = r; }));
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    let p1: Promise<string | null>, p2: Promise<string | null>;
    act(() => {
      p1 = result.current.execute(new Transaction());
      p2 = result.current.execute(new Transaction());
    });

    await act(async () => {
      resolve2!({ Transaction: { digest: 'tx-2' } });
      await p2!;
    });
    await act(async () => {
      resolve1!({ Transaction: { digest: 'tx-1' } });
      await p1!;
    });

    expect(result.current.loading).toBe(false);
  });

  it('reset clears digest and error', async () => {
    mockDAppKit.signAndExecuteTransaction.mockResolvedValueOnce({
      Transaction: { digest: 'tx-123' },
    });
    const { result } = renderHook(() => useTransactionExecutor(), { wrapper: TestProvider });

    await act(async () => {
      await result.current.execute(new Transaction());
    });
    expect(result.current.digest).toBe('tx-123');

    act(() => result.current.reset());
    expect(result.current.digest).toBeNull();
    expect(result.current.error).toBeNull();
  });
});

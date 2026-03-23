import { useCallback, useState } from 'react';
import { useDAppKit, useCurrentClient } from '@mysten/dapp-kit-react';
import type { Transaction } from '@mysten/sui/transactions';
import { useQueryClient } from '@tanstack/react-query';

interface TxResult {
  digest: string | null;
  error: string | null;
  loading: boolean;
  execute: (tx: Transaction) => Promise<string | null>;
  reset: () => void;
}

export function useTransactionExecutor(): TxResult {
  const dAppKit = useDAppKit();
  const client = useCurrentClient();
  const queryClient = useQueryClient();
  const [digest, setDigest] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const execute = useCallback(async (tx: Transaction): Promise<string | null> => {
    setLoading(true);
    setDigest(null);
    setError(null);
    try {
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx });
      if ('FailedTransaction' in result) {
        const msg = result.FailedTransaction?.status?.error?.message ?? 'Transaction failed';
        setError(msg);
        return null;
      }
      const txDigest = result.Transaction.digest;
      setDigest(txDigest);
      // Wait for indexing before invalidating queries
      await client.waitForTransaction({ digest: txDigest });
      await queryClient.invalidateQueries();
      return txDigest;
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Unknown error';
      setError(msg);
      return null;
    } finally {
      setLoading(false);
    }
  }, [dAppKit, client, queryClient]);

  const reset = useCallback(() => {
    setDigest(null);
    setError(null);
  }, []);

  return { digest, error, loading, execute, reset };
}

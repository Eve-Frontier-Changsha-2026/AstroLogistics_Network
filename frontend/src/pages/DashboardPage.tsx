import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { useOwnedAdminCaps } from '../hooks/useStorageList';
import { useFuelBalance } from '../hooks/useFuelBalance';
import { useMyContracts } from '../hooks/useCourierContracts';
import { formatFuel } from '../lib/format';
import { Link } from 'react-router-dom';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { TransactionToast } from '../components/ui/TransactionToast';
import { buildCreateStorage } from '../lib/ptb/storage';

export default function DashboardPage() {
  const adminCaps = useOwnedAdminCaps();
  const fuelBalance = useFuelBalance();
  const contracts = useMyContracts();
  const tx = useTransactionExecutor();

  const handleCreateStorage = async () => {
    const ptb = buildCreateStorage(1, 100_000, 200);
    await tx.execute(ptb);
  };

  const caps = adminCaps.data?.objects ?? [];
  const contractCount = contracts.data?.objects?.length ?? 0;

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Dashboard</h1>

        <div className="grid grid-cols-3 gap-4">
          <Panel title="FUEL Balance">
            <p className="text-2xl font-bold text-cyan-400">
              {fuelBalance.data ? formatFuel(Number(fuelBalance.data.balance.balance)) : '—'}
            </p>
          </Panel>
          <Panel title="My Storages">
            <p className="text-2xl font-bold">{caps.length}</p>
          </Panel>
          <Panel title="My Contracts">
            <p className="text-2xl font-bold">{contractCount}</p>
          </Panel>
        </div>

        <Panel title="My Storages">
          {adminCaps.isPending ? <LoadingSpinner /> : (
            <div className="space-y-3">
              {caps.map((obj) => {
                const json = obj.json as Record<string, unknown> | null;
                const storageId = String(json?.['storage_id'] ?? '');
                return (
                  <Link key={obj.objectId} to={`/storage/${storageId}`}
                    className="block p-3 rounded-lg bg-gray-800/50 hover:bg-gray-700/50 transition-colors border border-gray-700">
                    <span className="text-sm text-gray-400">Storage: </span>
                    <span className="text-cyan-400 font-mono text-sm">{storageId.slice(0, 10)}...</span>
                  </Link>
                );
              })}
              {caps.length === 0 && (
                <p className="text-gray-500 text-sm">No storages yet.</p>
              )}
            </div>
          )}
          <Button className="mt-4" onClick={handleCreateStorage} loading={tx.loading}>
            Create Storage
          </Button>
        </Panel>

        <TransactionToast digest={tx.digest} error={tx.error} onClose={tx.reset} />
      </div>
    </WalletGuard>
  );
}

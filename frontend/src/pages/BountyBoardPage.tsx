import { useState } from 'react';
import { Link } from 'react-router-dom';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { TransactionToast } from '../components/ui/TransactionToast';
import { StatusBadge } from '../components/ui/StatusBadge';
import { useMyContracts } from '../hooks/useCourierContracts';
import { useMyReceipts } from '../hooks/useStorageDetail';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildCreateContract } from '../lib/ptb/courier';
import { formatMist } from '../lib/format';
import { CONTRACT_STATUS } from '../lib/constants';

export default function BountyBoardPage() {
  const contracts = useMyContracts();
  const receipts = useMyReceipts();
  const tx = useTransactionExecutor();

  const [fromStorage, setFromStorage] = useState('');
  const [toStorage, setToStorage] = useState('');
  const [receiptId, setReceiptId] = useState('');
  const [reward, setReward] = useState('1000000000');
  const [penalty, setPenalty] = useState('500000000');
  const [minDeposit, setMinDeposit] = useState('1000000000');
  const [deadline, setDeadline] = useState('86400000');

  const handleCreate = async () => {
    if (!fromStorage || !toStorage || !receiptId) return;
    const ptb = buildCreateContract(
      fromStorage, toStorage, receiptId,
      Number(reward), Number(penalty), Number(minDeposit),
      [1, 2], Number(deadline),
    );
    await tx.execute(ptb);
  };

  const contractObjects = contracts.data?.objects ?? [];
  const receiptObjects = receipts.data?.objects ?? [];

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Bounty Board</h1>

        <Panel title="My Contracts">
          {contracts.isPending ? <LoadingSpinner /> : contractObjects.length === 0 ? (
            <p className="text-gray-500 text-sm">No contracts found.</p>
          ) : (
            <div className="space-y-2">
              {contractObjects.map((obj) => {
                const json = obj.json as Record<string, unknown> | null;
                const status = Number(json?.['status'] ?? 0);
                return (
                  <Link key={obj.objectId} to={`/bounty/${obj.objectId}`}
                    className="block p-3 rounded-lg bg-gray-800/50 hover:bg-gray-700/50 transition-colors border border-gray-700">
                    <div className="flex items-center justify-between">
                      <div className="text-sm">
                        <span className="text-gray-400">Contract: </span>
                        <span className="font-mono text-cyan-400">{obj.objectId.slice(0, 10)}...</span>
                      </div>
                      <div className="flex items-center gap-3">
                        <span className="text-sm text-gray-400">{formatMist(Number(json?.['reward'] ?? 0))} SUI</span>
                        <StatusBadge status={CONTRACT_STATUS[status] ?? 'Unknown'} />
                      </div>
                    </div>
                  </Link>
                );
              })}
            </div>
          )}
        </Panel>

        <Panel title="Create Contract">
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <Input label="From Storage ID" value={fromStorage} onChange={(e) => setFromStorage(e.target.value)} />
              <Input label="To Storage ID" value={toStorage} onChange={(e) => setToStorage(e.target.value)} />
            </div>
            <div>
              <label className="block text-xs text-gray-400 mb-1">Receipt</label>
              <select
                value={receiptId}
                onChange={(e) => setReceiptId(e.target.value)}
                className="w-full px-3 py-2 rounded-lg bg-gray-800 border border-gray-600 text-gray-100 text-sm"
              >
                <option value="">Select receipt...</option>
                {receiptObjects.map((obj) => (
                  <option key={obj.objectId} value={obj.objectId}>
                    {obj.objectId.slice(0, 16)}...
                  </option>
                ))}
              </select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <Input label="Reward (MIST)" type="number" value={reward} onChange={(e) => setReward(e.target.value)} />
              <Input label="Cancel Penalty (MIST)" type="number" value={penalty} onChange={(e) => setPenalty(e.target.value)} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <Input label="Min Courier Deposit (MIST)" type="number" value={minDeposit} onChange={(e) => setMinDeposit(e.target.value)} />
              <Input label="Deadline Duration (ms)" type="number" value={deadline} onChange={(e) => setDeadline(e.target.value)} />
            </div>
            <Button onClick={handleCreate} loading={tx.loading}>Create Contract</Button>
          </div>
        </Panel>

        <TransactionToast digest={tx.digest} error={tx.error} onClose={tx.reset} />
      </div>
    </WalletGuard>
  );
}

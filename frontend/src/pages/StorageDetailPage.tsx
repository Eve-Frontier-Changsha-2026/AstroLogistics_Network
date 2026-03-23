import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { TransactionToast } from '../components/ui/TransactionToast';
import { AddressDisplay } from '../components/ui/AddressDisplay';
import { useStorageDetail, useMyReceipts } from '../hooks/useStorageDetail';
import { useOwnedAdminCaps } from '../hooks/useStorageList';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildDeposit, buildWithdraw, buildShareStorage, buildSetStorageGuild, buildClaimFees, buildUpdateFeeRate } from '../lib/ptb/storage';
import { formatBps } from '../lib/format';

export default function StorageDetailPage() {
  const { storageId } = useParams<{ storageId: string }>();
  const storage = useStorageDetail(storageId ?? '');
  const receipts = useMyReceipts();
  const adminCaps = useOwnedAdminCaps();
  const tx = useTransactionExecutor();

  const [itemType, setItemType] = useState('ore');
  const [weight, setWeight] = useState('100');
  const [value, setValue] = useState('1000');
  const [guildId, setGuildId] = useState('');
  const [newFeeRate, setNewFeeRate] = useState('');

  if (!storageId) return <p className="text-gray-400">No storage ID provided.</p>;

  const content = storage.data?.data?.content;
  const fields = content && 'fields' in content ? (content.fields as Record<string, unknown>) : null;
  const ownerData = storage.data?.data?.owner;
  const isShared = typeof ownerData === 'object' && ownerData !== null && 'Shared' in ownerData;

  // Find matching AdminCap for this storage
  const myAdminCap = adminCaps.data?.data.find((obj) => {
    const c = obj.data?.content;
    const f = c && 'fields' in c ? (c.fields as Record<string, unknown>) : null;
    return String(f?.['storage_id'] ?? '') === storageId;
  });
  const adminCapId = myAdminCap?.data?.objectId;

  // Filter receipts for this storage
  const myReceipts = receipts.data?.data.filter((obj) => {
    const c = obj.data?.content;
    const f = c && 'fields' in c ? (c.fields as Record<string, unknown>) : null;
    return String(f?.['storage_id'] ?? '') === storageId;
  }) ?? [];

  const handleDeposit = async () => {
    const ptb = buildDeposit(storageId, itemType, Number(weight), Number(value));
    await tx.execute(ptb);
  };

  const handleWithdraw = async (receiptId: string) => {
    const feeRateBps = Number(fields?.['fee_rate_bps'] ?? 0);
    const fee = Math.ceil(Number(value) * feeRateBps / 10000);
    const ptb = buildWithdraw(storageId, receiptId, fee);
    await tx.execute(ptb);
  };

  const handleShare = async () => {
    if (!confirm('Share storage is IRREVERSIBLE. Continue?')) return;
    const ptb = buildShareStorage(storageId);
    await tx.execute(ptb);
  };

  const handleSetGuild = async () => {
    if (!adminCapId || !guildId) return;
    const ptb = buildSetStorageGuild(storageId, adminCapId, guildId);
    await tx.execute(ptb);
  };

  const handleClaimFees = async () => {
    if (!adminCapId) return;
    const ptb = buildClaimFees(storageId, adminCapId);
    await tx.execute(ptb);
  };

  const handleUpdateFeeRate = async () => {
    if (!adminCapId || !newFeeRate) return;
    const ptb = buildUpdateFeeRate(storageId, adminCapId, Number(newFeeRate));
    await tx.execute(ptb);
  };

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Storage Detail</h1>

        {storage.isPending ? <LoadingSpinner /> : !fields ? (
          <Panel><p className="text-gray-400">Storage not found.</p></Panel>
        ) : (
          <>
            <Panel title="Storage Info">
              <div className="grid grid-cols-2 gap-3 text-sm">
                <div><span className="text-gray-400">ID: </span><AddressDisplay address={storageId} /></div>
                <div><span className="text-gray-400">Owner: </span><AddressDisplay address={String(fields['owner'] ?? '')} /></div>
                <div><span className="text-gray-400">System ID: </span>{String(fields['system_id'] ?? '')}</div>
                <div><span className="text-gray-400">Capacity: </span>{String(fields['current_load'] ?? 0)} / {String(fields['max_capacity'] ?? 0)}</div>
                <div><span className="text-gray-400">Fee Rate: </span>{formatBps(Number(fields['fee_rate_bps'] ?? 0))}</div>
                <div><span className="text-gray-400">Shared: </span>{isShared ? 'Yes' : 'No (Owned)'}</div>
              </div>
            </Panel>

            {/* Deposit */}
            <Panel title="Deposit Cargo">
              <div className="flex gap-3 items-end">
                <Input label="Item Type" value={itemType} onChange={(e) => setItemType(e.target.value)} className="flex-1" />
                <Input label="Weight" type="number" value={weight} onChange={(e) => setWeight(e.target.value)} className="w-28" />
                <Input label="Value (MIST)" type="number" value={value} onChange={(e) => setValue(e.target.value)} className="w-36" />
                <Button onClick={handleDeposit} loading={tx.loading}>Deposit</Button>
              </div>
            </Panel>

            {/* Receipts */}
            <Panel title={`My Receipts (${myReceipts.length})`}>
              {myReceipts.length === 0 ? <p className="text-gray-500 text-sm">No receipts for this storage.</p> : (
                <div className="space-y-2">
                  {myReceipts.map((obj) => {
                    const c = obj.data?.content;
                    const f = c && 'fields' in c ? (c.fields as Record<string, unknown>) : null;
                    const rId = obj.data?.objectId ?? '';
                    return (
                      <div key={rId} className="flex items-center justify-between p-2 bg-gray-800/50 rounded-lg">
                        <div className="text-sm">
                          <span className="text-gray-400">Cargo: </span>
                          <span className="font-mono text-cyan-400">{String(f?.['cargo_id'] ?? '').slice(0, 10)}...</span>
                        </div>
                        <Button variant="secondary" onClick={() => handleWithdraw(rId)} loading={tx.loading}>
                          Withdraw
                        </Button>
                      </div>
                    );
                  })}
                </div>
              )}
            </Panel>

            {/* Admin actions */}
            {adminCapId && (
              <Panel title="Admin Actions">
                <div className="space-y-4">
                  {!isShared && (
                    <Button variant="danger" onClick={handleShare} loading={tx.loading}>
                      Share Storage (Irreversible)
                    </Button>
                  )}
                  <div className="flex gap-3 items-end">
                    <Input label="Guild ID" value={guildId} onChange={(e) => setGuildId(e.target.value)} className="flex-1" />
                    <Button variant="secondary" onClick={handleSetGuild} loading={tx.loading}>Set Guild</Button>
                  </div>
                  <div className="flex gap-3 items-end">
                    <Input label="New Fee Rate (bps)" type="number" value={newFeeRate} onChange={(e) => setNewFeeRate(e.target.value)} className="w-40" />
                    <Button variant="secondary" onClick={handleUpdateFeeRate} loading={tx.loading}>Update Fee</Button>
                  </div>
                  <Button variant="secondary" onClick={handleClaimFees} loading={tx.loading}>Claim Fees</Button>
                </div>
              </Panel>
            )}
          </>
        )}

        <TransactionToast digest={tx.digest} error={tx.error} onClose={tx.reset} />
      </div>
    </WalletGuard>
  );
}

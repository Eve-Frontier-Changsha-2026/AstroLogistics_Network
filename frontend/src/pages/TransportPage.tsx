import { useState } from 'react';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { TransactionToast } from '../components/ui/TransactionToast';
import { StatusBadge } from '../components/ui/StatusBadge';
import { useMyTransportOrders } from '../hooks/useTransportOrders';
import { useMyReceipts } from '../hooks/useStorageDetail';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildCreateOrder, buildCompleteTransport, buildCancelOrder } from '../lib/ptb/transport';
import { TRANSPORT_STATUS, TRANSPORT_TIER } from '../lib/constants';
import { useStorageObject } from '../hooks/useStorageList';
import { useRoute } from '../lib/eve-eyes/hooks';
import { formatDistance } from '../lib/format';
import { parseU64 } from '../lib/parse';

export default function TransportPage() {
  const orders = useMyTransportOrders();
  const receipts = useMyReceipts();
  const tx = useTransactionExecutor();

  const [fromStorage, setFromStorage] = useState('');
  const [toStorage, setToStorage] = useState('');
  const [receiptId, setReceiptId] = useState('');
  const [fuelCost, setFuelCost] = useState('100000000000');
  const [tier, setTier] = useState('0');

  const fromStorageObj = useStorageObject(fromStorage || undefined);
  const toStorageObj = useStorageObject(toStorage || undefined);

  const fromJson = fromStorageObj.data?.object?.json as Record<string, unknown> | null;
  const toJson = toStorageObj.data?.object?.json as Record<string, unknown> | null;
  const fromSystemId = Number(fromJson?.['system_id'] ?? 0) || null;
  const toSystemId = Number(toJson?.['system_id'] ?? 0) || null;

  const route = useRoute(fromSystemId, toSystemId);

  const handleCreate = async () => {
    if (!fromStorage || !toStorage || !receiptId) return;
    // M-2 fix: derive route from storage system_ids
    const route = (fromSystemId && toSystemId) ? [fromSystemId, toSystemId] : [1, 2];
    const ptb = buildCreateOrder(fromStorage, toStorage, receiptId, route, parseU64(fuelCost), 0, Number(tier));
    await tx.execute(ptb);
  };

  const handleComplete = async (orderId: string, from: string, to: string) => {
    const ptb = buildCompleteTransport(orderId, from, to);
    await tx.execute(ptb);
  };

  const handleCancel = async (orderId: string) => {
    const ptb = buildCancelOrder(orderId);
    await tx.execute(ptb);
  };

  const orderObjects = orders.data?.objects ?? [];
  const receiptObjects = receipts.data?.objects ?? [];

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Transport</h1>

        <Panel title="Create Transport Order">
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
              <Input label="Fuel Cost (raw)" type="number" value={fuelCost} onChange={(e) => setFuelCost(e.target.value)} />
              <div>
                <label className="block text-xs text-gray-400 mb-1">Tier</label>
                <select
                  value={tier}
                  onChange={(e) => setTier(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg bg-gray-800 border border-gray-600 text-gray-100 text-sm"
                >
                  {Object.entries(TRANSPORT_TIER).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
              </div>
            </div>
            <Button onClick={handleCreate} loading={tx.loading}>Create Order</Button>
          </div>
        </Panel>

        {(route.originName || route.distance != null) && (
          <div className="px-4 py-3 bg-gray-800/30 rounded-lg border border-gray-700/50 text-sm text-gray-300 flex items-center gap-2">
            {route.isLoading ? (
              <LoadingSpinner />
            ) : (
              <>
                <span className="text-cyan-400">{route.originName ?? `#${fromSystemId}`}</span>
                <span className="text-gray-500">→</span>
                <span className="text-cyan-400">{route.destinationName ?? `#${toSystemId}`}</span>
                {route.distance != null && (
                  <>
                    <span className="text-gray-600 mx-1">|</span>
                    <span>{formatDistance(route.distance)}</span>
                  </>
                )}
                {route.jumps != null && (
                  <>
                    <span className="text-gray-600 mx-1">|</span>
                    <span>{route.jumps} jumps</span>
                  </>
                )}
              </>
            )}
          </div>
        )}

        <Panel title="My Transport Orders">
          {orders.isPending ? <LoadingSpinner /> : (
            <div className="space-y-2">
              {orderObjects.length === 0 ? (
                <p className="text-gray-500 text-sm">No transport orders.</p>
              ) : (
                orderObjects.map((obj) => {
                  const json = obj.json as Record<string, unknown> | null;
                  if (!json) return null;
                  const orderStatus = Number(json['status'] ?? 0);
                  const from = String(json['from_storage'] ?? '');
                  const to = String(json['to_storage'] ?? '');
                  return (
                    <div key={obj.objectId} className="p-3 bg-gray-800/50 rounded-lg border border-gray-700">
                      <div className="flex items-center justify-between mb-2">
                        <span className="font-mono text-sm text-cyan-400">{obj.objectId.slice(0, 16)}...</span>
                        <StatusBadge status={TRANSPORT_STATUS[orderStatus] ?? 'Unknown'} />
                      </div>
                      <div className="text-xs text-gray-400 mb-2">
                        {TRANSPORT_TIER[Number(json['tier'] ?? 0)]} tier
                      </div>
                      <div className="flex gap-2">
                        {orderStatus === 1 && (
                          <Button variant="primary" onClick={() => handleComplete(obj.objectId, from, to)} loading={tx.loading}>Complete</Button>
                        )}
                        {orderStatus === 0 && (
                          <Button variant="danger" onClick={() => handleCancel(obj.objectId)} loading={tx.loading}>Cancel</Button>
                        )}
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          )}
        </Panel>

        <TransactionToast digest={tx.digest} error={tx.error} onClose={tx.reset} />
      </div>
    </WalletGuard>
  );
}

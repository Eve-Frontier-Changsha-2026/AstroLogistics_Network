import { useState } from 'react';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { TransactionToast } from '../components/ui/TransactionToast';
import { useFuelStationDetail } from '../hooks/useFuelStation';
import { useFuelBalance } from '../hooks/useFuelBalance';
import { useOwnedObjects } from '../hooks/useOwnedObjects';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildBuyFuel, buildClaimRevenue, buildWithdrawSupplier } from '../lib/ptb/fuel-station';
import { TESTNET_OBJECTS } from '../config/objects';
import { TYPE } from '../config/contracts';
import { formatFuel, formatBps } from '../lib/format';
import { parseU64 } from '../lib/parse';

const STATIONS = [
  { id: TESTNET_OBJECTS.fuelStation1, label: 'Station 1' },
  { id: TESTNET_OBJECTS.fuelStation2, label: 'Station 2' },
];

export default function FuelStationPage() {
  const [selectedStation, setSelectedStation] = useState(STATIONS[0].id);
  const station = useFuelStationDetail(selectedStation);
  const fuelBalance = useFuelBalance();
  const supplierReceipts = useOwnedObjects(TYPE.SupplierReceipt);
  const tx = useTransactionExecutor();

  const [buyAmount, setBuyAmount] = useState('100000000000');
  const [maxPrice, setMaxPrice] = useState('200');
  const [paymentAmount, setPaymentAmount] = useState('1000000000');

  const fields = station.data?.object?.json as Record<string, unknown> | null;

  const handleBuy = async () => {
    const ptb = buildBuyFuel(selectedStation, parseU64(buyAmount), parseU64(maxPrice), parseU64(paymentAmount));
    await tx.execute(ptb);
  };

  const handleClaimRevenue = async (receiptId: string) => {
    const ptb = buildClaimRevenue(selectedStation, receiptId);
    await tx.execute(ptb);
  };

  const handleWithdraw = async (receiptId: string) => {
    const ptb = buildWithdrawSupplier(selectedStation, receiptId);
    await tx.execute(ptb);
  };

  const receiptObjects = supplierReceipts.data?.objects ?? [];

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Fuel Station</h1>

        <div className="flex gap-2">
          {STATIONS.map((s) => (
            <button
              key={s.id}
              onClick={() => setSelectedStation(s.id)}
              className={`px-4 py-2 rounded-lg text-sm transition-colors ${
                selectedStation === s.id
                  ? 'bg-cyan-600 text-white'
                  : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
              }`}
            >
              {s.label}
            </button>
          ))}
        </div>

        {station.isPending ? <LoadingSpinner /> : fields ? (
          <Panel title="Station Stats">
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div><span className="text-gray-400">Fuel Level: </span>{formatFuel(Number(fields['current_fuel'] ?? 0))} / {formatFuel(Number(fields['max_fuel'] ?? 0))}</div>
              <div><span className="text-gray-400">Base Price: </span>{String(fields['base_price'] ?? 0)} MIST/unit</div>
              <div><span className="text-gray-400">Owner Fee: </span>{formatBps(Number(fields['owner_fee_bps'] ?? 0))}</div>
              <div><span className="text-gray-400">Total Supplied: </span>{formatFuel(Number(fields['total_supplied'] ?? 0))}</div>
            </div>
          </Panel>
        ) : null}

        <Panel title="My FUEL Balance">
          <p className="text-2xl font-bold text-cyan-400">
            {fuelBalance.data ? formatFuel(Number(fuelBalance.data.balance.balance)) : '—'}
          </p>
        </Panel>

        <Panel title="Buy FUEL">
          <div className="space-y-3">
            <div className="grid grid-cols-3 gap-3">
              <Input label="Amount (raw)" type="number" value={buyAmount} onChange={(e) => setBuyAmount(e.target.value)} />
              <Input label="Max Price/Unit" type="number" value={maxPrice} onChange={(e) => setMaxPrice(e.target.value)} />
              <Input label="Payment (MIST)" type="number" value={paymentAmount} onChange={(e) => setPaymentAmount(e.target.value)} />
            </div>
            <Button onClick={handleBuy} loading={tx.loading}>Buy FUEL</Button>
          </div>
        </Panel>

        <Panel title="My Supplier Receipts">
          {supplierReceipts.isPending ? <LoadingSpinner /> : (
            <div className="space-y-2">
              {receiptObjects.length === 0 ? (
                <p className="text-gray-500 text-sm">No supplier receipts.</p>
              ) : (
                receiptObjects.map((obj) => (
                  <div key={obj.objectId} className="flex items-center justify-between p-2 bg-gray-800/50 rounded-lg">
                    <span className="font-mono text-sm text-cyan-400">{obj.objectId.slice(0, 16)}...</span>
                    <div className="flex gap-2">
                      <Button variant="secondary" onClick={() => handleClaimRevenue(obj.objectId)} loading={tx.loading}>Claim</Button>
                      <Button variant="danger" onClick={() => handleWithdraw(obj.objectId)} loading={tx.loading}>Withdraw</Button>
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
        </Panel>

        <TransactionToast digest={tx.digest} error={tx.error} onClose={tx.reset} />
      </div>
    </WalletGuard>
  );
}

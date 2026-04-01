import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { TransactionToast } from '../components/ui/TransactionToast';
import { StatusBadge } from '../components/ui/StatusBadge';
import { AddressDisplay } from '../components/ui/AddressDisplay';
import { useContractDetail } from '../hooks/useContractDetail';
import { useCourierBadges } from '../hooks/useCourierBadge';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildAcceptContract, buildPickupAndDeliver, buildConfirmDelivery, buildRaiseDispute, buildCancelByClient, buildClaimTimeout } from '../lib/ptb/courier';
import { CONTRACT_STATUS } from '../lib/constants';
import { formatMist, timeRemaining } from '../lib/format';
import { parseU64 } from '../lib/parse';

export default function ContractDetailPage() {
  const { contractId } = useParams<{ contractId: string }>();
  const account = useCurrentAccount();
  const contract = useContractDetail(contractId);
  const badges = useCourierBadges();
  const tx = useTransactionExecutor();
  const [depositAmount, setDepositAmount] = useState('1000000000');

  if (!contractId) return <p className="text-gray-400">No contract ID.</p>;

  const fields = contract.data?.object?.json as Record<string, unknown> | null;

  const status = Number(fields?.['status'] ?? 0);
  const statusLabel = CONTRACT_STATUS[status] ?? 'Unknown';
  const clientAddr = String(fields?.['client'] ?? '');
  const courierAddr = String(fields?.['courier'] ?? '');
  const isClient = account?.address === clientAddr;
  const isCourier = account?.address === courierAddr;
  const deadlineMs = Number(fields?.['deadline'] ?? 0);

  // Find badge for this contract
  const myBadge = (badges.data?.objects ?? []).find((obj) => {
    const json = obj.json as Record<string, unknown> | null;
    return String(json?.['contract_id'] ?? '') === contractId;
  });
  const badgeId = myBadge?.objectId;

  const handleAccept = async () => {
    const ptb = buildAcceptContract(contractId, parseU64(depositAmount));
    await tx.execute(ptb);
  };

  const handlePickup = async () => {
    if (!badgeId) return;
    const fromStorage = String(fields?.['from_storage'] ?? '');
    const toStorage = String(fields?.['to_storage'] ?? '');
    const ptb = buildPickupAndDeliver(contractId, badgeId, fromStorage, toStorage);
    await tx.execute(ptb);
  };

  const handleConfirm = async () => {
    const ptb = buildConfirmDelivery(contractId);
    await tx.execute(ptb);
  };

  const handleDispute = async () => {
    const ptb = buildRaiseDispute(contractId);
    await tx.execute(ptb);
  };

  const handleCancel = async () => {
    const ptb = buildCancelByClient(contractId);
    await tx.execute(ptb);
  };

  const handleTimeout = async () => {
    const ptb = buildClaimTimeout(contractId);
    await tx.execute(ptb);
  };

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Contract Detail</h1>

        {contract.isPending ? <LoadingSpinner /> : !fields ? (
          <Panel><p className="text-gray-400">Contract not found or already settled.</p></Panel>
        ) : (
          <>
            <Panel title="Contract Info">
              <div className="grid grid-cols-2 gap-3 text-sm">
                <div><span className="text-gray-400">Status: </span><StatusBadge status={statusLabel} /></div>
                <div><span className="text-gray-400">Reward: </span>{formatMist(Number(fields['reward'] ?? 0))} SUI</div>
                <div><span className="text-gray-400">Client: </span><AddressDisplay address={clientAddr} /></div>
                <div><span className="text-gray-400">Courier: </span>{courierAddr ? <AddressDisplay address={courierAddr} /> : 'None'}</div>
                <div><span className="text-gray-400">Deadline: </span>{timeRemaining(deadlineMs)}</div>
                <div><span className="text-gray-400">Cargo Value: </span>{formatMist(Number(fields['cargo_value'] ?? 0))} SUI</div>
                <div><span className="text-gray-400">Min Deposit: </span>{formatMist(Number(fields['min_courier_deposit'] ?? 0))} SUI</div>
              </div>
            </Panel>

            <Panel title="Actions">
              <div className="space-y-3">
                {status === 0 && isClient && (
                  <Button variant="danger" onClick={handleCancel} loading={tx.loading}>Cancel Contract</Button>
                )}
                {status === 0 && !isClient && (
                  <div className="flex gap-3 items-end">
                    <Input label="Deposit (MIST)" type="number" value={depositAmount} onChange={(e) => setDepositAmount(e.target.value)} className="w-48" />
                    <Button onClick={handleAccept} loading={tx.loading}>Accept Contract</Button>
                  </div>
                )}
                {status === 1 && isCourier && badgeId && (
                  <Button onClick={handlePickup} loading={tx.loading}>Pickup & Deliver</Button>
                )}
                {status === 2 && isClient && (
                  <div className="flex gap-3">
                    <Button onClick={handleConfirm} loading={tx.loading}>Confirm Delivery</Button>
                    <Button variant="danger" onClick={handleDispute} loading={tx.loading}>Raise Dispute</Button>
                  </div>
                )}
                {deadlineMs > 0 && Date.now() > deadlineMs && (
                  <Button variant="secondary" onClick={handleTimeout} loading={tx.loading}>Claim Timeout</Button>
                )}
              </div>
            </Panel>
          </>
        )}

        <TransactionToast digest={tx.digest} error={tx.error} onClose={tx.reset} />
      </div>
    </WalletGuard>
  );
}

import { useState } from 'react';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { TransactionToast } from '../components/ui/TransactionToast';
import { AddressDisplay } from '../components/ui/AddressDisplay';
import { useGuildMemberCap } from '../hooks/useGuildMemberCap';
import { useGuildDetail } from '../hooks/useGuild';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildCreateGuild, buildAddMember, buildRemoveMember, buildLeaveGuild } from '../lib/ptb/guild';
import { useCurrentAccount } from '@mysten/dapp-kit-react';

export default function GuildPage() {
  const account = useCurrentAccount();
  const memberCaps = useGuildMemberCap();
  const tx = useTransactionExecutor();
  const [guildName, setGuildName] = useState('');
  const [memberAddress, setMemberAddress] = useState('');
  const [removeAddress, setRemoveAddress] = useState('');

  // Get first GuildMemberCap
  const firstCap = memberCaps.data?.data[0];
  const capContent = firstCap?.data?.content;
  const capFields = capContent && 'fields' in capContent ? (capContent.fields as Record<string, unknown>) : null;
  const guildId = capFields ? String(capFields['guild_id'] ?? '') : undefined;
  const capId = firstCap?.data?.objectId;

  const guildDetail = useGuildDetail(guildId);
  const guildContent = guildDetail.data?.data?.content;
  const guildFields = guildContent && 'fields' in guildContent ? (guildContent.fields as Record<string, unknown>) : null;
  const isLeader = guildFields ? String(guildFields['leader'] ?? '') === account?.address : false;

  const handleCreateGuild = async () => {
    if (!guildName) return;
    const ptb = buildCreateGuild(guildName);
    await tx.execute(ptb);
    setGuildName('');
  };

  const handleAddMember = async () => {
    if (!guildId || !capId || !memberAddress) return;
    const ptb = buildAddMember(guildId, capId, memberAddress);
    await tx.execute(ptb);
    setMemberAddress('');
  };

  const handleRemoveMember = async () => {
    if (!guildId || !capId || !removeAddress) return;
    const ptb = buildRemoveMember(guildId, capId, removeAddress);
    await tx.execute(ptb);
    setRemoveAddress('');
  };

  const handleLeaveGuild = async () => {
    if (!guildId || !capId) return;
    if (!confirm('Leave guild? Your GuildMemberCap will be destroyed.')) return;
    const ptb = buildLeaveGuild(guildId, capId);
    await tx.execute(ptb);
  };

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Guild</h1>

        {memberCaps.isPending ? <LoadingSpinner /> : guildId ? (
          <>
            <Panel title="My Guild">
              {guildDetail.isPending ? <LoadingSpinner /> : guildFields ? (
                <div className="space-y-2 text-sm">
                  <div><span className="text-gray-400">Name: </span><span className="text-white font-semibold">{String(guildFields['name'] ?? '')}</span></div>
                  <div><span className="text-gray-400">Leader: </span><AddressDisplay address={String(guildFields['leader'] ?? '')} /></div>
                  <div><span className="text-gray-400">Members: </span>{String(guildFields['member_count'] ?? 0)}</div>
                  <div><span className="text-gray-400">Guild ID: </span><AddressDisplay address={guildId} /></div>
                </div>
              ) : <p className="text-gray-400">Guild not found.</p>}
            </Panel>

            {isLeader && (
              <Panel title="Leader Actions">
                <div className="space-y-4">
                  <div className="flex gap-3 items-end">
                    <Input label="Member Address" value={memberAddress} onChange={(e) => setMemberAddress(e.target.value)} className="flex-1" />
                    <Button onClick={handleAddMember} loading={tx.loading}>Add Member</Button>
                  </div>
                  <div className="flex gap-3 items-end">
                    <Input label="Address to Remove" value={removeAddress} onChange={(e) => setRemoveAddress(e.target.value)} className="flex-1" />
                    <Button variant="danger" onClick={handleRemoveMember} loading={tx.loading}>Remove</Button>
                  </div>
                </div>
              </Panel>
            )}

            {!isLeader && (
              <Panel title="Member Actions">
                <Button variant="danger" onClick={handleLeaveGuild} loading={tx.loading}>Leave Guild</Button>
              </Panel>
            )}
          </>
        ) : (
          <Panel title="Create Guild">
            <p className="text-gray-400 text-sm mb-4">You are not in a guild. Create one to get started.</p>
            <div className="flex gap-3 items-end">
              <Input label="Guild Name" value={guildName} onChange={(e) => setGuildName(e.target.value)} className="flex-1" />
              <Button onClick={handleCreateGuild} loading={tx.loading}>Create Guild</Button>
            </div>
          </Panel>
        )}

        <TransactionToast digest={tx.digest} error={tx.error} onClose={tx.reset} />
      </div>
    </WalletGuard>
  );
}

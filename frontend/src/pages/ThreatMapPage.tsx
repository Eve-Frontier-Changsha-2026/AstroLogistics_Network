import { useState } from 'react';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';
import { TESTNET_OBJECTS } from '../config/objects';

export default function ThreatMapPage() {
  const client = useCurrentClient();
  const [systemId, setSystemId] = useState('1');
  const [queryId, setQueryId] = useState<string | null>(null);

  // Fetch ThreatMap metadata
  const threatMap = useQuery({
    queryKey: ['getObject', TESTNET_OBJECTS.threatMap],
    queryFn: () =>
      client.getObject({
        id: TESTNET_OBJECTS.threatMap,
        options: { showContent: true },
      }),
  });

  // Fetch specific danger entry by system_id (dynamic field)
  const dangerEntry = useQuery({
    queryKey: ['getDynamicFieldObject', TESTNET_OBJECTS.threatMap, queryId],
    queryFn: () =>
      client.getDynamicFieldObject({
        parentId: TESTNET_OBJECTS.threatMap,
        name: { type: 'u64', value: queryId! },
      }),
    enabled: !!queryId,
  });

  const tmContent = threatMap.data?.data?.content;
  const tmFields = tmContent && 'fields' in tmContent ? (tmContent.fields as Record<string, unknown>) : null;

  const deContent = dangerEntry.data?.data?.content;
  const deFields = deContent && 'fields' in deContent ? (deContent.fields as Record<string, unknown>) : null;
  const deValue = deFields?.['value'] as Record<string, unknown> | undefined;
  const dangerFields = deValue?.['fields'] as Record<string, unknown> | undefined;

  const handleQuery = () => {
    setQueryId(systemId);
  };

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Threat Map</h1>

        {/* ThreatMap metadata */}
        <Panel title="Threat Map Overview">
          {threatMap.isPending ? <LoadingSpinner /> : tmFields ? (
            <div className="text-sm space-y-1">
              <div><span className="text-gray-400">Decay Lambda: </span>{String(tmFields['decay_lambda'] ?? '')}</div>
              <div><span className="text-gray-400">Map ID: </span><span className="font-mono text-cyan-400">{TESTNET_OBJECTS.threatMap.slice(0, 16)}...</span></div>
            </div>
          ) : <p className="text-gray-400">Could not load ThreatMap.</p>}
        </Panel>

        {/* Query by system ID */}
        <Panel title="Query Danger Score">
          <div className="flex gap-3 items-end mb-4">
            <Input label="System ID" type="number" value={systemId} onChange={(e) => setSystemId(e.target.value)} className="w-32" />
            <Button onClick={handleQuery}>Query</Button>
          </div>

          {dangerEntry.isPending && queryId && <LoadingSpinner />}
          {dangerFields ? (
            <div className="p-3 bg-gray-800/50 rounded-lg text-sm space-y-1">
              <div><span className="text-gray-400">System ID: </span>{systemId}</div>
              <div><span className="text-gray-400">Danger Score: </span>
                <span className="text-red-400 font-bold">{String(dangerFields['danger_score'] ?? 'N/A')}</span>
              </div>
              <div><span className="text-gray-400">Last Update: </span>{String(dangerFields['last_update'] ?? 'N/A')}</div>
              <div><span className="text-gray-400">Reporter Count: </span>{String(dangerFields['reporter_count'] ?? 'N/A')}</div>
            </div>
          ) : queryId && !dangerEntry.isPending ? (
            <p className="text-gray-500 text-sm">No entry for system {systemId}.</p>
          ) : null}
        </Panel>
      </div>
    </WalletGuard>
  );
}

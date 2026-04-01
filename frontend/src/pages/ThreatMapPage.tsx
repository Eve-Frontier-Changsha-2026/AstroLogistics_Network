import { useState } from 'react';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';
import { TESTNET_OBJECTS } from '../config/objects';
import { bcs } from '@mysten/sui/bcs';
import { useSystemName } from '../lib/eve-eyes/hooks';

export default function ThreatMapPage() {
  const client = useCurrentClient();
  const [systemId, setSystemId] = useState('1');
  const [queryId, setQueryId] = useState<string | null>(null);

  const threatMap = useQuery({
    queryKey: ['getObject', TESTNET_OBJECTS.threatMap],
    queryFn: () =>
      client.getObject({
        objectId: TESTNET_OBJECTS.threatMap,
        include: { json: true },
      }),
  });

  // Fetch specific danger entry by system_id (dynamic field)
  // DynamicFieldName requires BCS-encoded name
  const dangerEntry = useQuery({
    queryKey: ['getDynamicField', TESTNET_OBJECTS.threatMap, queryId],
    queryFn: () =>
      client.getDynamicField({
        parentId: TESTNET_OBJECTS.threatMap,
        name: { type: 'u64', bcs: bcs.u64().serialize(BigInt(queryId!)).toBytes() },
      }),
    enabled: !!queryId,
  });

  const systemInfo = useSystemName(queryId ? Number(queryId) : null);

  const tmFields = threatMap.data?.object?.json as Record<string, unknown> | null;
  // getDynamicField returns { dynamicField: { name, valueType, ... } }
  // For hackathon, just show that the query worked
  const dfResult = dangerEntry.data?.dynamicField;

  const handleQuery = () => {
    setQueryId(systemId);
  };

  return (
    <WalletGuard>
      <div className="space-y-6">
        <h1 className="text-2xl" style={{ fontFamily: 'var(--font-display)' }}>Threat Map</h1>

        <Panel title="Threat Map Overview">
          {threatMap.isPending ? <LoadingSpinner /> : tmFields ? (
            <div className="text-sm space-y-1">
              <div><span className="text-gray-400">Decay Lambda: </span>{String(tmFields['decay_lambda'] ?? '')}</div>
              <div><span className="text-gray-400">Map ID: </span><span className="font-mono text-cyan-400">{TESTNET_OBJECTS.threatMap.slice(0, 16)}...</span></div>
            </div>
          ) : <p className="text-gray-400">Could not load ThreatMap.</p>}
        </Panel>

        <Panel title="Query Danger Score">
          <div className="flex gap-3 items-end mb-4">
            <Input label="System ID" type="number" value={systemId} onChange={(e) => setSystemId(e.target.value)} className="w-32" />
            <Button onClick={handleQuery}>Query</Button>
          </div>

          {dangerEntry.isPending && queryId && <LoadingSpinner />}
          {dfResult ? (
            <div className="p-3 bg-gray-800/50 rounded-lg text-sm space-y-1">
              <div><span className="text-gray-400">System ID: </span>{systemId}{systemInfo.name && <span className="text-cyan-400"> ({systemInfo.name})</span>}</div>
              <div><span className="text-gray-400">Value Type: </span>
                <span className="text-cyan-400">{dfResult.valueType}</span>
              </div>
              <div><span className="text-gray-400">Field ID: </span>
                <span className="font-mono text-cyan-400">{dfResult.fieldId.slice(0, 16)}...</span>
              </div>
              <p className="text-gray-500 text-xs mt-2">Full BCS decode requires generated Move struct types.</p>
            </div>
          ) : queryId && !dangerEntry.isPending ? (
            <p className="text-gray-500 text-sm">No entry for system {systemId}{systemInfo.name ? ` (${systemInfo.name})` : ''}.</p>
          ) : null}
        </Panel>
      </div>
    </WalletGuard>
  );
}

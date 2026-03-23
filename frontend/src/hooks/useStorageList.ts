import { useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';
import { TYPE } from '../config/contracts';
import type { StorageData } from '../lib/types';

export function useOwnedAdminCaps() {
  const client = useCurrentClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ['listOwnedObjects', account?.address, 'AdminCap'],
    queryFn: () =>
      client.listOwnedObjects({
        owner: account!.address,
        type: TYPE.AdminCap,
        include: { json: true },
      }),
    enabled: !!account,
  });
}

export function useStorageObject(storageId: string | undefined) {
  const client = useCurrentClient();

  return useQuery({
    queryKey: ['getObject', storageId],
    queryFn: () =>
      client.getObject({
        objectId: storageId!,
        include: { json: true },
      }),
    enabled: !!storageId,
  });
}

export function parseStorageFields(json: Record<string, unknown>, id: string, isShared: boolean): StorageData {
  return {
    id,
    owner: String(json['owner'] ?? ''),
    systemId: Number(json['system_id'] ?? 0),
    maxCapacity: Number(json['max_capacity'] ?? 0),
    currentLoad: Number(json['current_load'] ?? 0),
    feeRateBps: Number(json['fee_rate_bps'] ?? 0),
    guildId: null,
    isShared,
  };
}

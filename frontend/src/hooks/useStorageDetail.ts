import { useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';
import { TYPE } from '../config/contracts';

export function useStorageDetail(storageId: string) {
  const client = useCurrentClient();

  return useQuery({
    queryKey: ['getObject', storageId],
    queryFn: () =>
      client.getObject({
        objectId: storageId,
        include: { json: true },
      }),
    enabled: !!storageId,
  });
}

export function useMyReceipts() {
  const client = useCurrentClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ['listOwnedObjects', account?.address, 'DepositReceipt'],
    queryFn: () =>
      client.listOwnedObjects({
        owner: account!.address,
        type: TYPE.DepositReceipt,
        include: { json: true },
      }),
    enabled: !!account,
  });
}

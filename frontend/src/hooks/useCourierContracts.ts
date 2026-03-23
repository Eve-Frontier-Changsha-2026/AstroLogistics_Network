import { useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';
import { TYPE } from '../config/contracts';

// CourierContract uses key+store, owned by client after creation
// Use listOwnedObjects to find user's contracts
export function useMyContracts() {
  const client = useCurrentClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ['listOwnedObjects', account?.address, 'CourierContract'],
    queryFn: () =>
      client.listOwnedObjects({
        owner: account!.address,
        type: TYPE.CourierContract,
        include: { json: true },
      }),
    enabled: !!account,
  });
}

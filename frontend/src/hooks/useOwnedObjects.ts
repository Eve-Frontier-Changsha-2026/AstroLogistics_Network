import { useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';

export function useOwnedObjects(structType: string) {
  const client = useCurrentClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ['listOwnedObjects', account?.address, structType],
    queryFn: () =>
      client.listOwnedObjects({
        owner: account!.address,
        type: structType,
        include: { json: true },
      }),
    enabled: !!account,
  });
}

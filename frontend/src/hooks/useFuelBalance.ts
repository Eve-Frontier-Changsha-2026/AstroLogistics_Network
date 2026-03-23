import { useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';
import { TYPE } from '../config/contracts';

export function useFuelBalance() {
  const client = useCurrentClient();
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ['getBalance', account?.address, 'FUEL'],
    queryFn: () =>
      client.getBalance({
        owner: account!.address,
        coinType: TYPE.FUEL,
      }),
    enabled: !!account,
  });
}

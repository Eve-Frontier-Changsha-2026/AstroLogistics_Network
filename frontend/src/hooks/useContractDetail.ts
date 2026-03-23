import { useCurrentClient } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';

export function useContractDetail(contractId: string | undefined) {
  const client = useCurrentClient();

  return useQuery({
    queryKey: ['getObject', contractId],
    queryFn: () =>
      client.getObject({
        objectId: contractId!,
        include: { json: true },
      }),
    enabled: !!contractId,
  });
}

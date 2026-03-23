import { useCurrentClient } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';

export function useFuelStationDetail(stationId: string) {
  const client = useCurrentClient();

  return useQuery({
    queryKey: ['getObject', stationId],
    queryFn: () =>
      client.getObject({
        objectId: stationId,
        include: { json: true },
      }),
    enabled: !!stationId,
  });
}

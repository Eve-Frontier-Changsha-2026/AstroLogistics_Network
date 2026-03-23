import { useCurrentClient } from '@mysten/dapp-kit-react';
import { useQuery } from '@tanstack/react-query';

export function useGuildDetail(guildId: string | undefined) {
  const client = useCurrentClient();

  return useQuery({
    queryKey: ['getObject', guildId],
    queryFn: () =>
      client.getObject({
        objectId: guildId!,
        include: { json: true },
      }),
    enabled: !!guildId,
  });
}

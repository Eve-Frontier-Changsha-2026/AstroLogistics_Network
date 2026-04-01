// frontend/src/lib/eve-eyes/hooks.ts

import { useQuery } from '@tanstack/react-query';
import { getSystem, getRoute, calculateDistanceLY } from './client';

const QUERY_OPTIONS = {
  staleTime: Infinity,
  gcTime: Infinity,
  retry: 1,
  refetchOnWindowFocus: false,
} as const;

export function useSystemName(systemId: number | null | undefined) {
  const query = useQuery({
    queryKey: ['eve-eyes', 'system', systemId],
    queryFn: () => getSystem(systemId!),
    enabled: systemId != null && systemId > 0,
    ...QUERY_OPTIONS,
  });

  return {
    name: query.data?.name ?? null,
    system: query.data ?? null,
    isLoading: query.isLoading,
  };
}

export function useRoute(
  originSystemId: number | null | undefined,
  destinationSystemId: number | null | undefined,
) {
  const origin = useSystemName(originSystemId);
  const destination = useSystemName(destinationSystemId);

  const routeQuery = useQuery({
    queryKey: ['eve-eyes', 'route', originSystemId, destinationSystemId],
    queryFn: () => getRoute(originSystemId!, destinationSystemId!),
    enabled: originSystemId != null && originSystemId > 0 && destinationSystemId != null && destinationSystemId > 0,
    ...QUERY_OPTIONS,
  });

  const distance = origin.system?.location && destination.system?.location
    ? calculateDistanceLY(origin.system.location, destination.system.location)
    : null;

  return {
    originName: origin.name,
    destinationName: destination.name,
    jumps: routeQuery.data?.jumps ?? null,
    distance,
    isLoading: origin.isLoading || destination.isLoading || routeQuery.isLoading,
  };
}

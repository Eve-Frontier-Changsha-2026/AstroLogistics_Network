import { useOwnedObjects } from './useOwnedObjects';
import { TYPE } from '../config/contracts';

export function useCourierBadges() {
  return useOwnedObjects(TYPE.CourierBadge);
}

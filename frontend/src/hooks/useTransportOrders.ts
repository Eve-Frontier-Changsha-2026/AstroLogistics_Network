import { useOwnedObjects } from './useOwnedObjects';
import { TYPE } from '../config/contracts';

export function useMyTransportOrders() {
  return useOwnedObjects(TYPE.TransportOrder);
}

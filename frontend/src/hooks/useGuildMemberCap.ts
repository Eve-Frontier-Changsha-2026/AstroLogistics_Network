import { useOwnedObjects } from './useOwnedObjects';
import { TYPE } from '../config/contracts';

export function useGuildMemberCap() {
  return useOwnedObjects(TYPE.GuildMemberCap);
}

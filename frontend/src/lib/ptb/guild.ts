import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK } from '../../config/contracts';

export function buildCreateGuild(name: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.guild}::create_guild`,
    arguments: [
      tx.pure.string(name),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildAddMember(
  guildId: string,
  leaderCapId: string,
  memberAddress: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.guild}::add_member`,
    arguments: [
      tx.object(guildId),
      tx.object(leaderCapId),
      tx.pure.address(memberAddress),
    ],
  });
  return tx;
}

export function buildRemoveMember(
  guildId: string,
  leaderCapId: string,
  memberAddress: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.guild}::remove_member`,
    arguments: [
      tx.object(guildId),
      tx.object(leaderCapId),
      tx.pure.address(memberAddress),
    ],
  });
  return tx;
}

export function buildLeaveGuild(
  guildId: string,
  memberCapId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.guild}::leave_guild`,
    arguments: [
      tx.object(guildId),
      tx.object(memberCapId),
    ],
  });
  return tx;
}

import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK } from '../../config/contracts';

export function buildCreateContract(
  fromStorageId: string,
  toStorageId: string,
  receiptId: string,
  rewardAmount: number,
  cancelPenaltyAmount: number,
  minCourierDeposit: number,
  route: number[],
  deadlineDuration: number,
): Transaction {
  const tx = new Transaction();
  const [reward] = tx.splitCoins(tx.gas, [tx.pure.u64(rewardAmount)]);
  const [penalty] = tx.splitCoins(tx.gas, [tx.pure.u64(cancelPenaltyAmount)]);
  tx.moveCall({
    target: `${MODULE.courier_market}::create_contract`,
    arguments: [
      tx.object(fromStorageId),
      tx.object(toStorageId),
      tx.object(receiptId),
      reward,
      penalty,
      tx.pure.u64(minCourierDeposit),
      tx.pure.vector('u64', route),
      tx.pure.u64(deadlineDuration),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildAcceptContract(
  contractId: string,
  depositAmount: number,
): Transaction {
  const tx = new Transaction();
  const [deposit] = tx.splitCoins(tx.gas, [tx.pure.u64(depositAmount)]);
  tx.moveCall({
    target: `${MODULE.courier_market}::accept_contract`,
    arguments: [
      tx.object(contractId),
      deposit,
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildPickupAndDeliver(
  contractId: string,
  badgeId: string,
  fromStorageId: string,
  toStorageId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::pickup_and_deliver`,
    arguments: [
      tx.object(contractId),
      tx.object(badgeId),
      tx.object(fromStorageId),
      tx.object(toStorageId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildConfirmDelivery(contractId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::confirm_delivery`,
    arguments: [tx.object(contractId)],
  });
  return tx;
}

export function buildSettle(
  contractId: string,
  badgeId: string,
  oracleCapId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::settle`,
    arguments: [
      tx.object(contractId),
      tx.object(badgeId),
      tx.object(oracleCapId),
    ],
  });
  return tx;
}

export function buildRaiseDispute(contractId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::raise_dispute`,
    arguments: [
      tx.object(contractId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildCancelByClient(contractId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::cancel_by_client`,
    arguments: [tx.object(contractId)],
  });
  return tx;
}

export function buildClaimTimeout(contractId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.courier_market}::claim_timeout`,
    arguments: [
      tx.object(contractId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

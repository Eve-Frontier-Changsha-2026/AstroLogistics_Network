import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK } from '../../config/contracts';

export function buildCreateStorage(
  systemId: number,
  maxCapacity: number,
  feeRateBps: number,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::create_storage`,
    arguments: [
      tx.pure.u64(systemId),
      tx.pure.u64(maxCapacity),
      tx.pure.u64(feeRateBps),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildDeposit(
  storageId: string,
  itemType: string,
  weight: number,
  value: number,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::deposit`,
    arguments: [
      tx.object(storageId),
      tx.pure.string(itemType),
      tx.pure.u64(weight),
      tx.pure.u64(value),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildWithdraw(
  storageId: string,
  receiptId: string,
  paymentAmount: number,
): Transaction {
  const tx = new Transaction();
  const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(paymentAmount)]);
  tx.moveCall({
    target: `${MODULE.storage}::withdraw`,
    arguments: [
      tx.object(storageId),
      tx.object(receiptId),
      payment,
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildShareStorage(storageId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::share_storage`,
    arguments: [tx.object(storageId)],
  });
  return tx;
}

export function buildSetStorageGuild(
  storageId: string,
  adminCapId: string,
  guildId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::set_storage_guild`,
    arguments: [
      tx.object(storageId),
      tx.object(adminCapId),
      tx.pure.id(guildId),
    ],
  });
  return tx;
}

export function buildClaimFees(
  storageId: string,
  adminCapId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::claim_fees`,
    arguments: [
      tx.object(storageId),
      tx.object(adminCapId),
    ],
  });
  return tx;
}

export function buildUpdateFeeRate(
  storageId: string,
  adminCapId: string,
  newRate: number,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::update_fee_rate`,
    arguments: [
      tx.object(storageId),
      tx.object(adminCapId),
      tx.pure.u64(newRate),
    ],
  });
  return tx;
}

export function buildSetEncryptedCoords(
  storageId: string,
  adminCapId: string,
  encryptedData: Uint8Array,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.storage}::set_encrypted_coords`,
    arguments: [
      tx.object(storageId),
      tx.object(adminCapId),
      tx.pure('vector<u8>', Array.from(encryptedData)),
    ],
  });
  return tx;
}

import { Transaction } from '@mysten/sui/transactions';
import { MODULE, CLOCK } from '../../config/contracts';

export function buildCreateOrder(
  fromStorageId: string,
  toStorageId: string,
  receiptId: string,
  route: number[],
  fuelCost: number,
  dangerSnapshot: number,
  tier: number,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.transport}::create_order`,
    arguments: [
      tx.object(fromStorageId),
      tx.object(toStorageId),
      tx.object(receiptId),
      tx.pure.vector('u64', route),
      tx.pure.u64(fuelCost),
      tx.pure.u64(dangerSnapshot),
      tx.pure.u8(tier),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildPayFuel(
  orderId: string,
  fuelCoinId: string,
  treasuryCapId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.transport}::pay_fuel`,
    arguments: [
      tx.object(orderId),
      tx.object(fuelCoinId),
      tx.object(treasuryCapId),
    ],
  });
  return tx;
}

export function buildCompleteTransport(
  orderId: string,
  fromStorageId: string,
  toStorageId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.transport}::complete_transport`,
    arguments: [
      tx.object(orderId),
      tx.object(fromStorageId),
      tx.object(toStorageId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

export function buildCancelOrder(orderId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.transport}::cancel_order`,
    arguments: [tx.object(orderId)],
  });
  return tx;
}

import { Transaction } from '@mysten/sui/transactions';
import { MODULE } from '../../config/contracts';

export function buildBuyFuel(
  stationId: string,
  amount: number | bigint,
  maxPricePerUnit: number | bigint,
  paymentAmount: number | bigint,
): Transaction {
  const tx = new Transaction();
  const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(paymentAmount)]);
  tx.moveCall({
    target: `${MODULE.fuel_station}::buy_fuel`,
    arguments: [
      tx.object(stationId),
      payment,
      tx.pure.u64(amount),
      tx.pure.u64(maxPricePerUnit),
    ],
  });
  return tx;
}

export function buildSupplyFuel(
  stationId: string,
  fuelCoinId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.fuel_station}::supply_fuel`,
    arguments: [
      tx.object(stationId),
      tx.object(fuelCoinId),
    ],
  });
  return tx;
}

export function buildClaimRevenue(
  stationId: string,
  receiptId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.fuel_station}::claim_revenue`,
    arguments: [
      tx.object(stationId),
      tx.object(receiptId),
    ],
  });
  return tx;
}

export function buildWithdrawSupplier(
  stationId: string,
  receiptId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${MODULE.fuel_station}::withdraw_supplier`,
    arguments: [
      tx.object(stationId),
      tx.object(receiptId),
    ],
  });
  return tx;
}

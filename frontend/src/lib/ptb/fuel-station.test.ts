import { describe, it, expect, vi, beforeEach } from 'vitest';
import { MODULE } from '../../config/contracts';

const mockMoveCall = vi.fn();
const mockSplitCoins = vi.fn().mockReturnValue(['mockCoin']);
const mockPure = {
  u64: vi.fn((v: number) => `pure:u64:${v}`),
};
const mockObject = vi.fn((id: string) => `obj:${id}`);

vi.mock('@mysten/sui/transactions', () => ({
  Transaction: vi.fn().mockImplementation(function (this: Record<string, unknown>) { return Object.assign(this, {
    moveCall: mockMoveCall,
    splitCoins: mockSplitCoins,
    gas: 'GAS',
    pure: mockPure,
    object: mockObject,
  })}),
}));

import {
  buildBuyFuel,
  buildSupplyFuel,
  buildClaimRevenue,
  buildWithdrawSupplier,
} from './fuel-station';

beforeEach(() => {
  vi.clearAllMocks();
});

describe('buildBuyFuel', () => {
  it('creates TX with correct target and 4 arguments', () => {
    buildBuyFuel('station1', 100, 50, 5000);

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.fuel_station}::buy_fuel`);
    expect(call.arguments).toHaveLength(4);
    expect(mockSplitCoins).toHaveBeenCalledOnce();
  });

  it('splits gas for payment amount', () => {
    buildBuyFuel('s', 10, 5, 999);
    expect(mockSplitCoins).toHaveBeenCalledWith('GAS', ['pure:u64:999']);
  });
});

describe('buildSupplyFuel', () => {
  it('creates TX with correct target and 2 arguments', () => {
    buildSupplyFuel('station1', 'fuelCoin1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.fuel_station}::supply_fuel`);
    expect(call.arguments).toHaveLength(2);
    expect(mockSplitCoins).not.toHaveBeenCalled();
  });
});

describe('buildClaimRevenue', () => {
  it('creates TX with correct target and 2 arguments', () => {
    buildClaimRevenue('station1', 'receipt1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.fuel_station}::claim_revenue`);
    expect(call.arguments).toHaveLength(2);
  });
});

describe('buildWithdrawSupplier', () => {
  it('creates TX with correct target and 2 arguments', () => {
    buildWithdrawSupplier('station1', 'receipt1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.fuel_station}::withdraw_supplier`);
    expect(call.arguments).toHaveLength(2);
  });
});

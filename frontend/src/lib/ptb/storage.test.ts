import { describe, it, expect, vi, beforeEach } from 'vitest';
import { MODULE, CLOCK } from '../../config/contracts';

const mockMoveCall = vi.fn();
const mockSplitCoins = vi.fn().mockReturnValue(['mockCoin']);
const mockPure: Record<string, ReturnType<typeof vi.fn>> = {
  u64: vi.fn((v: number) => `pure:u64:${v}`),
  string: vi.fn((v: string) => `pure:string:${v}`),
  id: vi.fn((v: string) => `pure:id:${v}`),
};
const mockObject = vi.fn((id: string) => `obj:${id}`);

// Also mock tx.pure() direct call for vector<u8>
const mockPureFn = Object.assign(
  vi.fn((_type: string, v: unknown) => `pure:${_type}:${JSON.stringify(v)}`),
  mockPure,
);

vi.mock('@mysten/sui/transactions', () => ({
  Transaction: vi.fn().mockImplementation(function (this: Record<string, unknown>) { return Object.assign(this, {
    moveCall: mockMoveCall,
    splitCoins: mockSplitCoins,
    gas: 'GAS',
    pure: mockPureFn,
    object: mockObject,
  })}),
}));

import {
  buildCreateStorage,
  buildDeposit,
  buildWithdraw,
  buildShareStorage,
  buildSetStorageGuild,
  buildClaimFees,
  buildUpdateFeeRate,
  buildSetEncryptedCoords,
} from './storage';

beforeEach(() => {
  vi.clearAllMocks();
});

describe('buildCreateStorage', () => {
  it('creates TX with correct target and 4 arguments', () => {
    buildCreateStorage(1001, 500, 250);

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.storage}::create_storage`);
    expect(call.arguments).toHaveLength(4);
  });
});

describe('buildDeposit', () => {
  it('creates TX with correct target and 5 arguments', () => {
    buildDeposit('storage1', 'Ore', 100, 5000);

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.storage}::deposit`);
    expect(call.arguments).toHaveLength(5);
  });
});

describe('buildWithdraw', () => {
  it('creates TX with splitCoins for payment and 4 arguments', () => {
    buildWithdraw('storage1', 'receipt1', 1000);

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.storage}::withdraw`);
    expect(call.arguments).toHaveLength(4);
    expect(mockSplitCoins).toHaveBeenCalledOnce();
  });
});

describe('buildShareStorage', () => {
  it('creates TX with correct target and 1 argument', () => {
    buildShareStorage('storage1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.storage}::share_storage`);
    expect(call.arguments).toHaveLength(1);
  });
});

describe('buildSetStorageGuild', () => {
  it('creates TX with correct target and 3 arguments', () => {
    buildSetStorageGuild('storage1', 'adminCap1', 'guild1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.storage}::set_storage_guild`);
    expect(call.arguments).toHaveLength(3);
  });
});

describe('buildClaimFees', () => {
  it('creates TX with correct target and 2 arguments', () => {
    buildClaimFees('storage1', 'adminCap1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.storage}::claim_fees`);
    expect(call.arguments).toHaveLength(2);
  });
});

describe('buildUpdateFeeRate', () => {
  it('creates TX with correct target and 3 arguments', () => {
    buildUpdateFeeRate('storage1', 'adminCap1', 500);

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.storage}::update_fee_rate`);
    expect(call.arguments).toHaveLength(3);
  });
});

describe('buildSetEncryptedCoords', () => {
  it('creates TX with correct target and 3 arguments', () => {
    buildSetEncryptedCoords('storage1', 'adminCap1', new Uint8Array([1, 2, 3]));

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.storage}::set_encrypted_coords`);
    expect(call.arguments).toHaveLength(3);
  });
});

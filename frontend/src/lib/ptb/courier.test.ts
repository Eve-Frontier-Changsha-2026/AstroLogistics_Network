import { describe, it, expect, vi, beforeEach } from 'vitest';
import { MODULE, CLOCK } from '../../config/contracts';

// Capture all moveCall / splitCoins invocations
const mockMoveCall = vi.fn();
const mockSplitCoins = vi.fn().mockReturnValue(['mockCoin']);
const mockPure = {
  u64: vi.fn((v: number) => `pure:u64:${v}`),
  u8: vi.fn((v: number) => `pure:u8:${v}`),
  string: vi.fn((v: string) => `pure:string:${v}`),
  address: vi.fn((v: string) => `pure:address:${v}`),
  id: vi.fn((v: string) => `pure:id:${v}`),
  vector: vi.fn((_t: string, v: number[]) => `pure:vector:${JSON.stringify(v)}`),
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

// Import AFTER mock
import {
  buildCreateContract,
  buildAcceptContract,
  buildPickupAndDeliver,
  buildConfirmDelivery,
  buildSettle,
  buildRaiseDispute,
  buildCancelByClient,
  buildClaimTimeout,
} from './courier';

beforeEach(() => {
  vi.clearAllMocks();
});

describe('buildCreateContract', () => {
  it('creates TX with correct target and 9 arguments', () => {
    const tx = buildCreateContract('from1', 'to1', 'receipt1', 1000, 500, 200, [1, 2, 3], 86400);

    expect(mockMoveCall).toHaveBeenCalledOnce();
    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.courier_market}::create_contract`);
    expect(call.arguments).toHaveLength(9);

    // reward & penalty are splitCoins results
    expect(mockSplitCoins).toHaveBeenCalledTimes(2);
  });

  it('splits gas for reward and penalty', () => {
    buildCreateContract('f', 't', 'r', 5000, 2000, 100, [], 3600);
    expect(mockSplitCoins).toHaveBeenCalledWith('GAS', ['pure:u64:5000']);
    expect(mockSplitCoins).toHaveBeenCalledWith('GAS', ['pure:u64:2000']);
  });

  it('passes CLOCK as last argument', () => {
    buildCreateContract('f', 't', 'r', 1, 1, 1, [], 1);
    const args = mockMoveCall.mock.calls[0][0].arguments;
    expect(args[args.length - 1]).toBe(`obj:${CLOCK}`);
  });
});

describe('buildAcceptContract', () => {
  it('creates TX with correct target and 3 arguments', () => {
    buildAcceptContract('contract1', 1000);

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.courier_market}::accept_contract`);
    expect(call.arguments).toHaveLength(3);
    expect(mockSplitCoins).toHaveBeenCalledOnce();
  });
});

describe('buildPickupAndDeliver', () => {
  it('creates TX with correct target and 5 arguments', () => {
    buildPickupAndDeliver('contract1', 'badge1', 'from1', 'to1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.courier_market}::pickup_and_deliver`);
    expect(call.arguments).toHaveLength(5);
    // No splitCoins for this operation
    expect(mockSplitCoins).not.toHaveBeenCalled();
  });
});

describe('buildConfirmDelivery', () => {
  it('creates TX with correct target and 1 argument', () => {
    buildConfirmDelivery('contract1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.courier_market}::confirm_delivery`);
    expect(call.arguments).toHaveLength(1);
  });
});

describe('buildSettle', () => {
  it('creates TX with correct target and 3 arguments', () => {
    buildSettle('contract1', 'badge1', 'oracle1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.courier_market}::settle`);
    expect(call.arguments).toHaveLength(3);
  });
});

describe('buildRaiseDispute', () => {
  it('creates TX with correct target and 2 arguments (contract + clock)', () => {
    buildRaiseDispute('contract1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.courier_market}::raise_dispute`);
    expect(call.arguments).toHaveLength(2);
  });
});

describe('buildCancelByClient', () => {
  it('creates TX with correct target and 1 argument', () => {
    buildCancelByClient('contract1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.courier_market}::cancel_by_client`);
    expect(call.arguments).toHaveLength(1);
  });
});

describe('buildClaimTimeout', () => {
  it('creates TX with correct target and 2 arguments (contract + clock)', () => {
    buildClaimTimeout('contract1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.courier_market}::claim_timeout`);
    expect(call.arguments).toHaveLength(2);
  });
});

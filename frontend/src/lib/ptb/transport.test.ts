import { describe, it, expect, vi, beforeEach } from 'vitest';
import { MODULE, CLOCK } from '../../config/contracts';

const mockMoveCall = vi.fn();
const mockPure = {
  u64: vi.fn((v: number) => `pure:u64:${v}`),
  u8: vi.fn((v: number) => `pure:u8:${v}`),
  vector: vi.fn((_t: string, v: number[]) => `pure:vector:${JSON.stringify(v)}`),
};
const mockObject = vi.fn((id: string) => `obj:${id}`);

vi.mock('@mysten/sui/transactions', () => ({
  Transaction: vi.fn().mockImplementation(function (this: Record<string, unknown>) { return Object.assign(this, {
    moveCall: mockMoveCall,
    gas: 'GAS',
    pure: mockPure,
    object: mockObject,
  })}),
}));

import {
  buildCreateOrder,
  buildPayFuel,
  buildCompleteTransport,
  buildCancelOrder,
} from './transport';

beforeEach(() => {
  vi.clearAllMocks();
});

describe('buildCreateOrder', () => {
  it('creates TX with correct target and 8 arguments', () => {
    buildCreateOrder('from1', 'to1', 'receipt1', [1, 2], 500, 3, 1);

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.transport}::create_order`);
    expect(call.arguments).toHaveLength(8);
  });

  it('uses u8 for tier', () => {
    buildCreateOrder('f', 't', 'r', [], 0, 0, 2);
    expect(mockPure.u8).toHaveBeenCalledWith(2);
  });

  it('uses vector for route', () => {
    buildCreateOrder('f', 't', 'r', [10, 20, 30], 0, 0, 0);
    expect(mockPure.vector).toHaveBeenCalledWith('u64', [10, 20, 30]);
  });

  it('passes CLOCK as last argument', () => {
    buildCreateOrder('f', 't', 'r', [], 0, 0, 0);
    const args = mockMoveCall.mock.calls[0][0].arguments;
    expect(args[args.length - 1]).toBe(`obj:${CLOCK}`);
  });
});

describe('buildPayFuel', () => {
  it('creates TX with correct target and 3 arguments', () => {
    buildPayFuel('order1', 'fuelCoin1', 'treasury1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.transport}::pay_fuel`);
    expect(call.arguments).toHaveLength(3);
  });
});

describe('buildCompleteTransport', () => {
  it('creates TX with correct target and 4 arguments', () => {
    buildCompleteTransport('order1', 'from1', 'to1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.transport}::complete_transport`);
    expect(call.arguments).toHaveLength(4);
    // Last arg is clock
    expect(call.arguments[3]).toBe(`obj:${CLOCK}`);
  });
});

describe('buildCancelOrder', () => {
  it('creates TX with correct target and 1 argument', () => {
    buildCancelOrder('order1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.transport}::cancel_order`);
    expect(call.arguments).toHaveLength(1);
  });
});

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { MODULE, CLOCK } from '../../config/contracts';

const mockMoveCall = vi.fn();
const mockPure = {
  string: vi.fn((v: string) => `pure:string:${v}`),
  address: vi.fn((v: string) => `pure:address:${v}`),
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
  buildCreateGuild,
  buildAddMember,
  buildRemoveMember,
  buildLeaveGuild,
} from './guild';

beforeEach(() => {
  vi.clearAllMocks();
});

describe('buildCreateGuild', () => {
  it('creates TX with correct target and 2 arguments (name + clock)', () => {
    buildCreateGuild('My Guild');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.guild}::create_guild`);
    expect(call.arguments).toHaveLength(2);
    expect(mockPure.string).toHaveBeenCalledWith('My Guild');
  });

  it('passes CLOCK', () => {
    buildCreateGuild('test');
    const args = mockMoveCall.mock.calls[0][0].arguments;
    expect(args[1]).toBe(`obj:${CLOCK}`);
  });
});

describe('buildAddMember', () => {
  it('creates TX with correct target and 3 arguments', () => {
    buildAddMember('guild1', 'cap1', '0xABC');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.guild}::add_member`);
    expect(call.arguments).toHaveLength(3);
    expect(mockPure.address).toHaveBeenCalledWith('0xABC');
  });
});

describe('buildRemoveMember', () => {
  it('creates TX with correct target and 3 arguments', () => {
    buildRemoveMember('guild1', 'cap1', '0xDEF');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.guild}::remove_member`);
    expect(call.arguments).toHaveLength(3);
  });
});

describe('buildLeaveGuild', () => {
  it('creates TX with correct target and 2 arguments', () => {
    buildLeaveGuild('guild1', 'memberCap1');

    const call = mockMoveCall.mock.calls[0][0];
    expect(call.target).toBe(`${MODULE.guild}::leave_guild`);
    expect(call.arguments).toHaveLength(2);
  });
});

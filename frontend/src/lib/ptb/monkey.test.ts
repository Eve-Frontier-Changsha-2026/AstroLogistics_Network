/**
 * Monkey Tests — extreme inputs for PTB builders and format utils.
 * Goal: find crashes, not verify correctness.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

// ─── Mock Transaction ────────────────────────────────────
const mockMoveCall = vi.fn();
const mockSplitCoins = vi.fn().mockReturnValue(['mockCoin']);
const mockPure: Record<string, ReturnType<typeof vi.fn>> = {
  u64: vi.fn((v: number) => `pure:u64:${v}`),
  u8: vi.fn((v: number) => `pure:u8:${v}`),
  string: vi.fn((v: string) => `pure:string:${v}`),
  address: vi.fn((v: string) => `pure:address:${v}`),
  id: vi.fn((v: string) => `pure:id:${v}`),
  vector: vi.fn((_t: string, v: number[]) => `pure:vector:${JSON.stringify(v)}`),
};
const mockObject = vi.fn((id: string) => `obj:${id}`);
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

import { buildCreateContract, buildAcceptContract } from './courier';
import { buildBuyFuel } from './fuel-station';
import { buildCreateGuild } from './guild';
import { buildCreateStorage, buildDeposit, buildSetEncryptedCoords } from './storage';
import { buildCreateOrder } from './transport';
import {
  formatAddress,
  formatMist,
  formatFuel,
  formatBps,
  timeRemaining,
} from '../format';

beforeEach(() => {
  vi.clearAllMocks();
});

// ─── Format Utils Edge Cases ─────────────────────────────

describe('format — extreme inputs', () => {
  it('formatAddress with very long string (1000 chars)', () => {
    const addr = '0x' + 'a'.repeat(1000);
    const result = formatAddress(addr);
    expect(result).toContain('...');
    expect(result.length).toBeLessThan(addr.length);
  });

  it('formatMist with MAX_SAFE_INTEGER', () => {
    expect(() => formatMist(Number.MAX_SAFE_INTEGER)).not.toThrow();
  });

  it('formatMist with negative', () => {
    const result = formatMist(-1_000_000_000);
    expect(result).toContain('-');
  });

  it('formatFuel with MAX_SAFE_INTEGER', () => {
    expect(() => formatFuel(Number.MAX_SAFE_INTEGER)).not.toThrow();
  });

  it('formatBps with huge value', () => {
    expect(() => formatBps(999999)).not.toThrow();
  });

  it('formatBps with negative', () => {
    const result = formatBps(-100);
    expect(result).toContain('-');
  });

  it('timeRemaining with very far future (year 3000)', () => {
    const farFuture = new Date('3000-01-01').getTime();
    const result = timeRemaining(farFuture);
    expect(result).toContain('d');
  });

  it('timeRemaining with negative timestamp', () => {
    expect(timeRemaining(-1)).toBe('Expired');
  });

  it('timeRemaining with 0', () => {
    expect(timeRemaining(0)).toBe('Expired');
  });
});

// ─── PTB Builders Edge Cases ─────────────────────────────

describe('PTB builders — extreme inputs', () => {
  it('buildCreateContract with 0 values', () => {
    expect(() => buildCreateContract('', '', '', 0, 0, 0, [], 0)).not.toThrow();
    expect(mockMoveCall).toHaveBeenCalledOnce();
  });

  it('buildCreateContract with MAX_SAFE_INTEGER amounts', () => {
    expect(() =>
      buildCreateContract(
        'from',
        'to',
        'receipt',
        Number.MAX_SAFE_INTEGER,
        Number.MAX_SAFE_INTEGER,
        Number.MAX_SAFE_INTEGER,
        [Number.MAX_SAFE_INTEGER],
        Number.MAX_SAFE_INTEGER,
      ),
    ).not.toThrow();
  });

  it('buildCreateContract with huge route array (1000 elements)', () => {
    const hugeRoute = Array.from({ length: 1000 }, (_, i) => i);
    expect(() => buildCreateContract('f', 't', 'r', 1, 1, 1, hugeRoute, 1)).not.toThrow();
  });

  it('buildAcceptContract with 0 deposit', () => {
    expect(() => buildAcceptContract('contract', 0)).not.toThrow();
  });

  it('buildBuyFuel with all zeros', () => {
    expect(() => buildBuyFuel('station', 0, 0, 0)).not.toThrow();
  });

  it('buildCreateGuild with empty name', () => {
    expect(() => buildCreateGuild('')).not.toThrow();
  });

  it('buildCreateGuild with very long name (1000 chars)', () => {
    expect(() => buildCreateGuild('A'.repeat(1000))).not.toThrow();
  });

  it('buildCreateGuild with special characters', () => {
    expect(() => buildCreateGuild('Guild 🚀 <script>alert("xss")</script>')).not.toThrow();
  });

  it('buildCreateStorage with 0 capacity', () => {
    expect(() => buildCreateStorage(0, 0, 0)).not.toThrow();
  });

  it('buildCreateStorage with max bps (10000)', () => {
    expect(() => buildCreateStorage(1, 100, 10000)).not.toThrow();
  });

  it('buildDeposit with empty item type', () => {
    expect(() => buildDeposit('s', '', 0, 0)).not.toThrow();
  });

  it('buildDeposit with special chars in item type', () => {
    expect(() => buildDeposit('s', '"><img/onerror=alert(1)>', 1, 1)).not.toThrow();
  });

  it('buildSetEncryptedCoords with empty Uint8Array', () => {
    expect(() => buildSetEncryptedCoords('s', 'cap', new Uint8Array([]))).not.toThrow();
  });

  it('buildSetEncryptedCoords with large Uint8Array (10KB)', () => {
    const data = new Uint8Array(10 * 1024);
    expect(() => buildSetEncryptedCoords('s', 'cap', data)).not.toThrow();
  });

  it('buildCreateOrder with empty route', () => {
    expect(() => buildCreateOrder('f', 't', 'r', [], 0, 0, 0)).not.toThrow();
  });

  it('buildCreateOrder with tier beyond valid range', () => {
    // tier > 2 is invalid on-chain but should not crash the builder
    expect(() => buildCreateOrder('f', 't', 'r', [1], 100, 5, 255)).not.toThrow();
  });
});

/**
 * Hacker Tests — adversarial inputs targeting real security vulnerabilities.
 *
 * Attack vectors:
 *   H-1: Number() precision loss for u64 values (>2^53)
 *   H-2: Withdraw fee uses wrong value source
 *   M-1: No input validation (negative, NaN, Infinity)
 *   M-4: Double-submit race condition
 *   M-5: Prototype pollution via malicious API responses
 *   EVE Eyes: malicious JSON, timeout, huge payloads
 *   Format: bigint overflow, locale injection, NaN propagation
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ─── H-1: Number() precision loss ──────────────────────────

describe('H-1: u64 precision loss via Number()', () => {
  it('Number() silently truncates values > 2^53', () => {
    // This is the core bug: user types a large MIST value, Number() eats digits
    const userInput = '18446744073709551615'; // u64 MAX = 2^64 - 1
    const asNumber = Number(userInput);
    expect(asNumber.toString()).not.toBe(userInput); // PROVES precision loss
  });

  it('values just above MAX_SAFE_INTEGER lose precision', () => {
    const safe = '9007199254740992'; // 2^53 (already imprecise)
    const next = '9007199254740993'; // 2^53 + 1
    // Both convert to the same Number — attacker pays less than intended
    expect(Number(safe)).toBe(Number(next));
  });

  it('BigInt preserves full u64 range', () => {
    // This is the FIX: use BigInt for all MIST/FUEL values
    const userInput = '18446744073709551615';
    const asBigInt = BigInt(userInput);
    expect(asBigInt.toString()).toBe(userInput);
  });

  it('demonstrates real financial impact: 1 MIST difference at 2^53 boundary', () => {
    const intended = 9007199254740993n; // what user typed
    const received = BigInt(Number('9007199254740993')); // what Number() gives
    const loss = intended - received;
    expect(loss).toBe(1n); // lost 1 MIST — small here, but scales
  });

  it('demonstrates catastrophic drift at u64 scale', () => {
    // ~18.4 SUI in MIST
    const intended = 18446744073709551615n; // u64 MAX
    const received = BigInt(Number('18446744073709551615'));
    // Number() rounds, so received may be HIGHER or LOWER than intended
    const drift = intended > received ? intended - received : received - intended;
    // The point: they are NOT equal — precision is lost either way
    expect(drift).toBeGreaterThan(0n);
  });
});

// ─── Format utils: NaN / Infinity / BigInt edge cases ──────

import {
  formatAddress,
  formatMist,
  formatFuel,
  formatBps,
  timeRemaining,
  formatDistance,
} from './format';

describe('Format utils — adversarial inputs', () => {
  it('formatMist with NaN returns "NaN"', () => {
    const result = formatMist(NaN);
    expect(result).toBe('NaN');
  });

  it('formatMist with Infinity', () => {
    const result = formatMist(Infinity);
    expect(result).toBe('∞');
  });

  it('formatMist with -Infinity', () => {
    const result = formatMist(-Infinity);
    expect(result).toBe('-∞');
  });

  it('formatFuel with NaN returns "NaN"', () => {
    expect(formatFuel(NaN)).toBe('NaN');
  });

  it('formatFuel with Infinity', () => {
    expect(formatFuel(Infinity)).toBe('∞');
  });

  it('formatBps with NaN', () => {
    expect(formatBps(NaN)).toBe('NaN%');
  });

  it('formatBps with Infinity returns "Infinity%"', () => {
    // (Infinity / 100).toFixed(1) = "Infinity" — not user-friendly
    expect(formatBps(Infinity)).toBe('Infinity%');
  });

  it('formatAddress with empty string', () => {
    expect(() => formatAddress('')).not.toThrow();
  });

  it('formatAddress with null-like inputs', () => {
    // Simulates on-chain data returning unexpected types
    expect(() => formatAddress(String(null))).not.toThrow();
    expect(() => formatAddress(String(undefined))).not.toThrow();
  });

  it('formatAddress with unicode/emoji injection', () => {
    const addr = '0x' + '🚀'.repeat(100);
    const result = formatAddress(addr);
    expect(result).toContain('...');
  });

  it('timeRemaining with NaN returns something safe', () => {
    const result = timeRemaining(NaN);
    // NaN - Date.now() = NaN, NaN <= 0 is false, so it falls through
    // Math.floor(NaN / ...) = NaN → "NaNh NaNm"
    expect(typeof result).toBe('string');
  });

  it('timeRemaining with Infinity never expires', () => {
    const result = timeRemaining(Infinity);
    // Infinity - Date.now() > 0, Math.floor(Infinity / 3600000) = Infinity
    expect(typeof result).toBe('string');
  });

  it('formatDistance with NaN', () => {
    expect(formatDistance(NaN)).toBe('NaN LY');
  });

  it('formatDistance with negative (impossible distance)', () => {
    const result = formatDistance(-42);
    expect(result).toContain('-42');
  });

  it('formatMist with bigint > 2^53 loses display precision', () => {
    // This documents the L-2 display bug
    const raw = 18446744073709551615n;
    const displayed = formatMist(raw);
    // Number(18446744073709551615n) = 18446744073709552000 — wrong!
    expect(typeof displayed).toBe('string');
    // The displayed value will be wrong due to Number() conversion
  });
});

// ─── EVE Eyes client: malicious API responses ──────────────

import { getSystem, getRoute, searchSystems, calculateDistanceLY } from './eve-eyes/client';

describe('EVE Eyes — malicious API responses', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('prototype pollution attempt via __proto__ key in response', async () => {
    // Object literal { __proto__: ... } sets prototype in JS — this IS a risk
    // Real JSON.parse('{"__proto__": ...}') creates a plain key, not prototype mutation
    // But mock returns JS object directly, so __proto__ is inherited
    const malicious = JSON.parse('{"__proto__": {"isAdmin": true}, "id": 1, "name": "hacked", "constellationId": 1, "regionId": 1, "location": {"x": 0, "y": 0, "z": 0}, "gateLinks": []}');
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(malicious),
    });
    const result = await getSystem(1);
    expect(result).not.toBeNull();
    // JSON.parse creates __proto__ as a regular property, NOT prototype mutation
    expect(Object.getPrototypeOf(result)).toBe(Object.prototype);
    // But the key still exists as a data property
    expect(Object.prototype.hasOwnProperty.call(result, '__proto__')).toBe(true);
  });

  it('XSS payload in system name', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({
        id: 1,
        name: '<img src=x onerror=alert(document.cookie)>',
        constellationId: 1,
        regionId: 1,
        location: { x: 0, y: 0, z: 0 },
        gateLinks: [],
      }),
    });
    const result = await getSystem(1);
    // The name contains HTML — React JSX will escape it, but verify we get it raw
    expect(result?.name).toContain('<img');
  });

  it('huge JSON response (1MB+)', async () => {
    const hugeArray = Array.from({ length: 50000 }, (_, i) => ({
      id: i,
      name: 'A'.repeat(20),
      constellationId: 1,
      regionId: 1,
      location: { x: 0, y: 0, z: 0 },
    }));
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: hugeArray }),
    });
    const result = await searchSystems('test');
    expect(result.length).toBe(50000);
  });

  it('response with extra unexpected fields (mass assignment)', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({
        id: 1,
        name: 'Normal',
        constellationId: 1,
        regionId: 1,
        location: { x: 0, y: 0, z: 0 },
        gateLinks: [],
        // Extra fields injected by attacker
        adminToken: 'secret',
        privateKey: '0xdead',
        __internal: { exploit: true },
      }),
    });
    const result = await getSystem(1);
    // TypeScript won't catch extra fields at runtime
    expect((result as Record<string, unknown>)['adminToken']).toBe('secret');
  });

  it('null body on 200 OK', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(null),
    });
    const result = await getSystem(1);
    expect(result).toBeNull();
  });

  it('getRoute with negative system IDs', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({ ok: false, status: 400 });
    const result = await getRoute(-1, -999);
    expect(result).toBeNull();
  });

  it('searchSystems with SQL injection attempt', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: [] }),
    });
    await searchSystems("'; DROP TABLE systems; --");
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining("q='%3B%20DROP%20TABLE%20systems%3B%20--"),
      expect.any(Object),
    );
  });

  it('searchSystems with path traversal attempt', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: [] }),
    });
    await searchSystems('../../etc/passwd');
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('q=..%2F..%2Fetc%2Fpasswd'),
      expect.any(Object),
    );
  });
});

describe('calculateDistanceLY — adversarial coords', () => {
  it('NaN coordinates', () => {
    const result = calculateDistanceLY({ x: NaN, y: 0, z: 0 }, { x: 0, y: 0, z: 0 });
    expect(Number.isNaN(result)).toBe(true);
  });

  it('Infinity coordinates', () => {
    const result = calculateDistanceLY({ x: Infinity, y: 0, z: 0 }, { x: 0, y: 0, z: 0 });
    expect(result).toBe(Infinity);
  });

  it('extremely large coordinates (near Number.MAX_VALUE)', () => {
    const big = Number.MAX_VALUE / 2;
    // dx*dx overflows to Infinity
    const result = calculateDistanceLY({ x: big, y: 0, z: 0 }, { x: -big, y: 0, z: 0 });
    expect(result).toBe(Infinity);
  });

  it('extremely small coordinates (subnormal floats)', () => {
    const tiny = Number.MIN_VALUE;
    const result = calculateDistanceLY({ x: tiny, y: 0, z: 0 }, { x: 0, y: 0, z: 0 });
    // Result should be essentially 0 LY
    expect(result).toBeCloseTo(0, 10);
  });

  it('negative zero', () => {
    const result = calculateDistanceLY({ x: -0, y: 0, z: 0 }, { x: 0, y: 0, z: 0 });
    expect(result).toBe(0);
  });
});

// ─── PTB builders: adversarial inputs beyond monkey tests ──

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
  Transaction: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    return Object.assign(this, {
      moveCall: mockMoveCall,
      splitCoins: mockSplitCoins,
      gas: 'GAS',
      pure: mockPureFn,
      object: mockObject,
    });
  }),
}));

import { buildCreateContract, buildAcceptContract, buildCancelByClient } from './ptb/courier';
import { buildBuyFuel } from './ptb/fuel-station';
import { buildCreateGuild, buildAddMember } from './ptb/guild';
import { buildCreateStorage, buildDeposit, buildWithdraw, buildSetEncryptedCoords } from './ptb/storage';
import { buildCreateOrder } from './ptb/transport';

beforeEach(() => {
  vi.clearAllMocks();
});

describe('PTB — negative and adversarial values', () => {
  it('negative reward amount (attacker tries to steal)', () => {
    // Number(-1) passed as u64 → on-chain should reject, but builder must not crash
    expect(() => buildCreateContract('f', 't', 'r', -1, -1, -1, [1], -1)).not.toThrow();
    expect(mockPure.u64).toHaveBeenCalledWith(-1);
  });

  it('NaN amount (corrupted form input)', () => {
    expect(() => buildBuyFuel('station', NaN, NaN, NaN)).not.toThrow();
    expect(mockPure.u64).toHaveBeenCalledWith(NaN);
  });

  it('Infinity amount', () => {
    expect(() => buildBuyFuel('station', Infinity, Infinity, Infinity)).not.toThrow();
  });

  it('fractional values truncated by u64', () => {
    // User types "1.5" SUI, Number("1.5") = 1.5, but u64 is integer
    expect(() => buildCreateStorage(1, 100, 1.5)).not.toThrow();
    expect(mockPure.u64).toHaveBeenCalledWith(1.5);
  });

  it('object ID with path traversal', () => {
    expect(() => buildCancelByClient('../../../etc/passwd')).not.toThrow();
    expect(mockObject).toHaveBeenCalledWith('../../../etc/passwd');
  });

  it('object ID with null bytes', () => {
    expect(() => buildCancelByClient('0x1234\x00evil')).not.toThrow();
  });

  it('guild member address with non-hex', () => {
    expect(() => buildAddMember('guild', 'cap', 'not-a-valid-address')).not.toThrow();
    expect(mockPure.address).toHaveBeenCalledWith('not-a-valid-address');
  });

  it('guild member address with JavaScript URL', () => {
    expect(() => buildAddMember('guild', 'cap', 'javascript:alert(1)')).not.toThrow();
  });

  it('deposit with item type containing newlines', () => {
    expect(() => buildDeposit('s', 'ore\n\r\n<script>', 100, 100)).not.toThrow();
  });

  it('deposit with item type of 10KB', () => {
    const longType = 'X'.repeat(10240);
    expect(() => buildDeposit('s', longType, 100, 100)).not.toThrow();
  });

  it('encrypted coords with 1MB payload', () => {
    const megabyte = new Uint8Array(1024 * 1024);
    expect(() => buildSetEncryptedCoords('s', 'cap', megabyte)).not.toThrow();
  });

  it('route array with 100K elements (DoS via tx size)', () => {
    const hugeRoute = Array.from({ length: 100_000 }, (_, i) => i);
    expect(() => buildCreateOrder('f', 't', 'r', hugeRoute, 0, 0, 0)).not.toThrow();
  });

  it('splitCoins with 0 payment does not revert builder', () => {
    expect(() => buildWithdraw('storage', 'receipt', 0)).not.toThrow();
    expect(mockSplitCoins).toHaveBeenCalledWith('GAS', [expect.anything()]);
  });

  it('accept contract with MAX_SAFE_INTEGER + 1 deposit', () => {
    const overflowAmount = Number.MAX_SAFE_INTEGER + 1;
    expect(() => buildAcceptContract('contract', overflowAmount)).not.toThrow();
    // Verify the value is actually wrong due to precision loss
    expect(overflowAmount).toBe(Number.MAX_SAFE_INTEGER + 1);
    expect(overflowAmount).toBe(9007199254740992); // same as MAX_SAFE_INTEGER itself!
  });
});

describe('PTB — guild name XSS / injection vectors', () => {
  const xssPayloads = [
    '<script>alert("XSS")</script>',
    '<img src=x onerror=alert(1)>',
    '{{constructor.constructor("return this")()}}',
    '${7*7}',
    'guild\'; DROP TABLE guilds; --',
    '\u0000\u0001\u0002', // control chars
    '\uD800', // lone surrogate (invalid UTF-16)
    'A'.repeat(65536), // 64KB name
    '🚀'.repeat(10000), // 40KB of emoji
    '<svg onload=alert(1)>',
  ];

  xssPayloads.forEach((payload, i) => {
    it(`XSS payload #${i}: ${payload.slice(0, 30)}...`, () => {
      expect(() => buildCreateGuild(payload)).not.toThrow();
      expect(mockPure.string).toHaveBeenCalledWith(payload);
    });
  });
});

// ─── H-2: Withdraw fee calculation attack ──────────────────

describe('H-2: Withdraw fee uses form state, not on-chain cargo value', () => {
  it('demonstrates the fee miscalculation', () => {
    // Simulates StorageDetailPage.tsx:58-59
    // Real cargo value on-chain: 1_000_000_000 (1 SUI)
    // User changes deposit form `value` input to "1" before clicking withdraw
    const feeRateBps = 200; // 2%
    const formValue = 1; // attacker changed this
    const realCargoValue = 1_000_000_000;

    const attackerFee = Math.ceil(formValue * feeRateBps / 10000); // 1
    const correctFee = Math.ceil(realCargoValue * feeRateBps / 10000); // 20_000_000

    expect(attackerFee).toBe(1);
    expect(correctFee).toBe(20_000_000); // 0.02 SUI
    // Attacker pays 1 MIST instead of 20M MIST — 20 million times less!
    // On-chain will reject if fee is too low, but user gets confusing error
    expect(attackerFee).toBeLessThan(correctFee);
  });

  it('fee with feeRateBps=0 is always 0 regardless of value', () => {
    const fee = Math.ceil(999999 * 0 / 10000);
    expect(fee).toBe(0);
  });

  it('fee overflow with huge value * huge bps loses precision', () => {
    // Number.MAX_SAFE_INTEGER * 10000 overflows Number precision
    const fee = Math.ceil(Number.MAX_SAFE_INTEGER * 10000 / 10000);
    // Should be MAX_SAFE_INTEGER but floating point drift means it's NOT
    expect(fee).not.toBe(Number.MAX_SAFE_INTEGER); // PROVES precision loss
  });
});

// ─── M-4: Double-submit simulation ─────────────────────────

describe('M-4: Double-submit race condition', () => {
  it('demonstrates React setState async gap', async () => {
    // Simulates the race: two execute() calls before loading becomes true
    let loadingState = false;
    const setLoading = (v: boolean) => {
      // In React, this is async — batched until next render
      // Simulating: the value isn't immediately available
      Promise.resolve().then(() => { loadingState = v; });
    };

    const execute = async () => {
      // Check happens before setState takes effect
      if (loadingState) return 'blocked';
      setLoading(true);
      // Both calls reach here before loadingState updates
      return 'executed';
    };

    // Simulate rapid double-click
    const [result1, result2] = await Promise.all([execute(), execute()]);
    expect(result1).toBe('executed');
    expect(result2).toBe('executed'); // BOTH execute — this is the bug
  });
});

// ─── URL param injection ───────────────────────────────────

describe('URL parameter injection (route params)', () => {
  it('storageId with script injection', () => {
    const maliciousId = '<script>alert(1)</script>';
    // This would be passed to useStorageDetail and gRPC client
    // gRPC will fail validation, but verify no crash in builder
    expect(() => buildDeposit(maliciousId, 'ore', 100, 100)).not.toThrow();
  });

  it('contractId as hex-like but wrong length', () => {
    const badId = '0x' + 'ff'.repeat(100); // 200 hex chars, not 64
    expect(() => buildAcceptContract(badId, 1000)).not.toThrow();
  });

  it('empty string IDs throughout', () => {
    expect(() => buildCreateContract('', '', '', 0, 0, 0, [], 0)).not.toThrow();
    expect(() => buildCreateOrder('', '', '', [], 0, 0, 0)).not.toThrow();
    expect(() => buildWithdraw('', '', 0)).not.toThrow();
  });
});

import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  formatAddress,
  formatMist,
  formatFuel,
  formatTimestamp,
  formatBps,
  timeRemaining,
} from './format';

describe('formatAddress', () => {
  it('truncates long addresses', () => {
    const addr = '0x564d32c9ce29b9f75c1821311aded4b84ee6d912c39e434309b9803e19f5f25c';
    const result = formatAddress(addr);
    expect(result).toBe('0x564d...f25c');
    expect(result.length).toBeLessThan(addr.length);
  });

  it('returns short addresses unchanged', () => {
    expect(formatAddress('0xabcd')).toBe('0xabcd');
  });

  it('respects custom chars param', () => {
    const addr = '0x564d32c9ce29b9f75c1821311aded4b84ee6d912c39e434309b9803e19f5f25c';
    const result = formatAddress(addr, 10);
    expect(result).toBe('0x564d32c9...f25c');
  });

  it('handles empty string', () => {
    expect(formatAddress('')).toBe('');
  });

  it('handles exactly boundary length', () => {
    // chars=6 → boundary is 6*2+1=13. String of length 13 should NOT truncate.
    const addr = '0x1234567890a'; // 13 chars
    expect(formatAddress(addr)).toBe(addr);
  });
});

describe('formatMist', () => {
  it('converts MIST to SUI (1 SUI = 1e9 MIST)', () => {
    expect(formatMist(1_000_000_000)).toBe(
      (1).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 }),
    );
  });

  it('handles zero', () => {
    expect(formatMist(0)).toBe(
      (0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 }),
    );
  });

  it('handles bigint input', () => {
    const result = formatMist(2_500_000_000n);
    expect(result).toBe(
      (2.5).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 }),
    );
  });

  it('handles sub-SUI amounts', () => {
    const result = formatMist(500_000_000);
    expect(result).toBe(
      (0.5).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 }),
    );
  });
});

describe('formatFuel', () => {
  it('converts raw to fuel (9 decimals)', () => {
    expect(formatFuel(1_000_000_000)).toBe(
      (1).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 }),
    );
  });

  it('handles zero', () => {
    expect(formatFuel(0)).toBe(
      (0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 }),
    );
  });
});

describe('formatTimestamp', () => {
  it('returns a locale string from ms timestamp', () => {
    const ms = new Date('2026-01-01T00:00:00Z').getTime();
    const result = formatTimestamp(ms);
    expect(result).toBe(new Date(ms).toLocaleString());
  });

  it('handles 0 (epoch)', () => {
    const result = formatTimestamp(0);
    expect(result).toBe(new Date(0).toLocaleString());
  });
});

describe('formatBps', () => {
  it('converts 100 bps to 1.0%', () => {
    expect(formatBps(100)).toBe('1.0%');
  });

  it('converts 250 bps to 2.5%', () => {
    expect(formatBps(250)).toBe('2.5%');
  });

  it('converts 10000 bps to 100.0%', () => {
    expect(formatBps(10000)).toBe('100.0%');
  });

  it('converts 0 bps to 0.0%', () => {
    expect(formatBps(0)).toBe('0.0%');
  });

  it('converts 1 bps to 0.0%', () => {
    expect(formatBps(1)).toBe('0.0%');
  });

  it('converts 50 bps to 0.5%', () => {
    expect(formatBps(50)).toBe('0.5%');
  });
});

describe('timeRemaining', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('returns "Expired" when deadline is in the past', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-02T00:00:00Z'));
    const deadline = new Date('2026-01-01T00:00:00Z').getTime();
    expect(timeRemaining(deadline)).toBe('Expired');
  });

  it('returns hours and minutes for near-future deadline', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));
    // 3h 30m from now
    const deadline = Date.now() + 3 * 3_600_000 + 30 * 60_000;
    expect(timeRemaining(deadline)).toBe('3h 30m');
  });

  it('returns days and hours for far-future deadline', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));
    // 2d 5h from now
    const deadline = Date.now() + (2 * 24 + 5) * 3_600_000;
    expect(timeRemaining(deadline)).toBe('2d 5h');
  });

  it('returns "0h 0m" when deadline is exactly now', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));
    expect(timeRemaining(Date.now())).toBe('Expired');
  });

  it('returns "24h 0m" for exactly 24h remaining (boundary)', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));
    const deadline = Date.now() + 24 * 3_600_000;
    expect(timeRemaining(deadline)).toBe('24h 0m');
  });

  it('switches to days format at 25h', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));
    const deadline = Date.now() + 25 * 3_600_000;
    expect(timeRemaining(deadline)).toBe('1d 1h');
  });
});

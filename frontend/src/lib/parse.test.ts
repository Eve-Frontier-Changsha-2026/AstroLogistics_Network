import { describe, it, expect } from 'vitest';
import { parseU64 } from './parse';

describe('parseU64', () => {
  it('parses normal integer string', () => {
    expect(parseU64('1000000000')).toBe(1000000000n);
  });

  it('preserves full u64 precision (> 2^53)', () => {
    expect(parseU64('9007199254740993')).toBe(9007199254740993n);
  });

  it('handles u64 MAX', () => {
    expect(parseU64('18446744073709551615')).toBe(18446744073709551615n);
  });

  it('returns 0n for empty string', () => {
    expect(parseU64('')).toBe(0n);
  });

  it('returns 0n for whitespace-only', () => {
    expect(parseU64('   ')).toBe(0n);
  });

  it('returns 0n for non-numeric string', () => {
    expect(parseU64('abc')).toBe(0n);
  });

  it('clamps negative to 0n', () => {
    expect(parseU64('-100')).toBe(0n);
  });

  it('returns 0n for decimal (BigInt rejects "1.5")', () => {
    expect(parseU64('1.5')).toBe(0n);
  });

  it('returns 0n for NaN string', () => {
    expect(parseU64('NaN')).toBe(0n);
  });

  it('returns 0n for Infinity string', () => {
    expect(parseU64('Infinity')).toBe(0n);
  });

  it('handles leading/trailing whitespace', () => {
    expect(parseU64('  42  ')).toBe(42n);
  });

  it('returns 0n for XSS payload', () => {
    expect(parseU64('<script>alert(1)</script>')).toBe(0n);
  });

  it('parses "0" correctly', () => {
    expect(parseU64('0')).toBe(0n);
  });
});

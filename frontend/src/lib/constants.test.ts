import { describe, it, expect } from 'vitest';
import { CONTRACT_STATUS, TRANSPORT_STATUS, TRANSPORT_TIER } from './constants';

describe('CONTRACT_STATUS', () => {
  it('maps all 5 statuses', () => {
    expect(Object.keys(CONTRACT_STATUS)).toHaveLength(5);
    expect(CONTRACT_STATUS[0]).toBe('Open');
    expect(CONTRACT_STATUS[1]).toBe('Accepted');
    expect(CONTRACT_STATUS[2]).toBe('PendingConfirm');
    expect(CONTRACT_STATUS[3]).toBe('Delivered');
    expect(CONTRACT_STATUS[4]).toBe('Disputed');
  });

  it('returns undefined for out-of-range', () => {
    expect(CONTRACT_STATUS[99]).toBeUndefined();
    expect(CONTRACT_STATUS[-1]).toBeUndefined();
  });
});

describe('TRANSPORT_STATUS', () => {
  it('maps all 4 statuses', () => {
    expect(Object.keys(TRANSPORT_STATUS)).toHaveLength(4);
    expect(TRANSPORT_STATUS[0]).toBe('Created');
    expect(TRANSPORT_STATUS[1]).toBe('Paid');
    expect(TRANSPORT_STATUS[2]).toBe('Completed');
    expect(TRANSPORT_STATUS[3]).toBe('Cancelled');
  });
});

describe('TRANSPORT_TIER', () => {
  it('maps all 3 tiers', () => {
    expect(Object.keys(TRANSPORT_TIER)).toHaveLength(3);
    expect(TRANSPORT_TIER[0]).toBe('Instant');
    expect(TRANSPORT_TIER[1]).toBe('Express');
    expect(TRANSPORT_TIER[2]).toBe('Standard');
  });
});

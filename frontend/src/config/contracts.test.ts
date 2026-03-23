import { describe, it, expect } from 'vitest';
import { ORIGINAL_PACKAGE_ID, PACKAGE_ID, MODULE, TYPE, CLOCK } from './contracts';

describe('Package IDs', () => {
  it('ORIGINAL_PACKAGE_ID is a valid 64-char hex address', () => {
    expect(ORIGINAL_PACKAGE_ID).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it('PACKAGE_ID is a valid 64-char hex address', () => {
    expect(PACKAGE_ID).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it('ORIGINAL and PACKAGE are different (upgraded)', () => {
    expect(ORIGINAL_PACKAGE_ID).not.toBe(PACKAGE_ID);
  });
});

describe('MODULE paths', () => {
  const modules = ['storage', 'courier_market', 'guild', 'fuel_station', 'transport', 'fuel', 'threat_oracle', 'seal_policy'] as const;

  for (const mod of modules) {
    it(`MODULE.${mod} points to PACKAGE_ID`, () => {
      expect(MODULE[mod]).toBe(`${PACKAGE_ID}::${mod}`);
    });
  }

  it('has exactly 8 module entries', () => {
    expect(Object.keys(MODULE)).toHaveLength(8);
  });
});

describe('TYPE paths', () => {
  it('all TYPE values use ORIGINAL_PACKAGE_ID', () => {
    for (const [, val] of Object.entries(TYPE)) {
      expect(val).toContain(ORIGINAL_PACKAGE_ID);
    }
  });

  it('TYPE.Storage follows module::struct pattern', () => {
    expect(TYPE.Storage).toBe(`${ORIGINAL_PACKAGE_ID}::storage::Storage`);
  });

  it('TYPE.CourierContract follows module::struct pattern', () => {
    expect(TYPE.CourierContract).toBe(`${ORIGINAL_PACKAGE_ID}::courier_market::CourierContract`);
  });

  it('TYPE.FUEL follows module::struct pattern', () => {
    expect(TYPE.FUEL).toBe(`${ORIGINAL_PACKAGE_ID}::fuel::FUEL`);
  });

  it('has all expected type entries', () => {
    const expected = [
      'Storage', 'AdminCap', 'Cargo', 'DepositReceipt',
      'CourierContract', 'CourierBadge',
      'Guild', 'GuildMemberCap',
      'FuelStation', 'StationCap', 'SupplierReceipt',
      'TransportOrder',
      'ThreatMap', 'OracleCap', 'ReporterCap',
      'FuelTreasuryCap', 'FUEL',
    ];
    for (const key of expected) {
      expect(TYPE).toHaveProperty(key);
    }
    expect(Object.keys(TYPE)).toHaveLength(expected.length);
  });
});

describe('CLOCK', () => {
  it('is the SUI system clock object 0x6', () => {
    expect(CLOCK).toBe('0x6');
  });
});

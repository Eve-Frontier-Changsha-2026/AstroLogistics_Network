// frontend/src/lib/eve-eyes/client.test.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { getSystem, getRoute, searchSystems, calculateDistanceLY } from './client';

const MOCK_SYSTEM = {
  id: 30000142,
  name: 'EHK-KH7',
  constellationId: 20000011,
  regionId: 10000005,
  location: { x: -4552684025457672000, y: -1259408930879045600, z: 715413939445301200 },
  gateLinks: [],
};

describe('getSystem', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns system on 200', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(MOCK_SYSTEM),
    });
    const result = await getSystem(30000142);
    expect(result).toEqual(MOCK_SYSTEM);
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/world/systems/30000142'),
      expect.objectContaining({ signal: expect.any(AbortSignal) }),
    );
  });

  it('returns null on 404', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({ ok: false, status: 404 });
    expect(await getSystem(99999)).toBeNull();
  });

  it('returns null on network error', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockRejectedValue(new TypeError('Failed to fetch'));
    expect(await getSystem(1)).toBeNull();
  });
});

describe('getRoute', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns null on 404 (no gate links)', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({ ok: false, status: 404 });
    expect(await getRoute(30000142, 30000143)).toBeNull();
  });

  it('returns route data on 200', async () => {
    const mockRoute = { origin: MOCK_SYSTEM, destination: MOCK_SYSTEM, jumps: 5, systems: [] };
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockRoute),
    });
    const result = await getRoute(1, 2);
    expect(result).toEqual(mockRoute);
  });
});

describe('searchSystems', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns array from data field', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: [{ id: 1, name: 'Test' }] }),
    });
    const result = await searchSystems('test');
    expect(result).toEqual([{ id: 1, name: 'Test' }]);
  });

  it('returns empty array on error', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockRejectedValue(new Error('fail'));
    expect(await searchSystems('test')).toEqual([]);
  });

  it('encodes query parameter', async () => {
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: [] }),
    });
    await searchSystems('hello world');
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('q=hello%20world'),
      expect.any(Object),
    );
  });
});

describe('calculateDistanceLY', () => {
  it('returns 0 for same coordinates', () => {
    const p = { x: 100, y: 200, z: 300 };
    expect(calculateDistanceLY(p, p)).toBe(0);
  });

  it('calculates distance for known coordinates', () => {
    const a = { x: 0, y: 0, z: 0 };
    const b = { x: 9.461e18, y: 0, z: 0 }; // exactly 1 LY apart on x-axis
    expect(calculateDistanceLY(a, b)).toBeCloseTo(1.0, 5);
  });

  it('calculates 3D distance', () => {
    const a = { x: 0, y: 0, z: 0 };
    // sqrt(1^2 + 1^2 + 1^2) = sqrt(3) ≈ 1.732 LY
    const unit = 9.461e18;
    const b = { x: unit, y: unit, z: unit };
    expect(calculateDistanceLY(a, b)).toBeCloseTo(Math.sqrt(3), 3);
  });
});

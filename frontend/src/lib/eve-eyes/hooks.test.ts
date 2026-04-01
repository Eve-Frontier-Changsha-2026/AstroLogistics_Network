// frontend/src/lib/eve-eyes/hooks.test.ts

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createElement, type ReactNode } from 'react';
import { useSystemName, useRoute } from './hooks';
import * as client from './client';

vi.mock('./client', () => ({
  getSystem: vi.fn(),
  getRoute: vi.fn(),
  calculateDistanceLY: vi.fn(),
}));

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(QueryClientProvider, { client: queryClient }, children);
  };
}

describe('useSystemName', () => {
  beforeEach(() => {
    vi.mocked(client.getSystem).mockReset();
  });

  it('returns name when API succeeds', async () => {
    vi.mocked(client.getSystem).mockResolvedValue({
      id: 30000142,
      name: 'EHK-KH7',
      constellationId: 20000011,
      regionId: 10000005,
      location: { x: 0, y: 0, z: 0 },
      gateLinks: [],
    });

    const { result } = renderHook(() => useSystemName(30000142), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.name).toBe('EHK-KH7');
    expect(result.current.system?.id).toBe(30000142);
  });

  it('returns null when API fails', async () => {
    vi.mocked(client.getSystem).mockResolvedValue(null);

    const { result } = renderHook(() => useSystemName(30000142), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.name).toBeNull();
    expect(result.current.system).toBeNull();
  });

  it('does not fetch when systemId is null', () => {
    renderHook(() => useSystemName(null), { wrapper: createWrapper() });
    expect(client.getSystem).not.toHaveBeenCalled();
  });

  it('does not fetch when systemId is 0', () => {
    renderHook(() => useSystemName(0), { wrapper: createWrapper() });
    expect(client.getSystem).not.toHaveBeenCalled();
  });

  it('does not fetch when systemId is negative', () => {
    renderHook(() => useSystemName(-1), { wrapper: createWrapper() });
    expect(client.getSystem).not.toHaveBeenCalled();
  });
});

describe('useRoute', () => {
  beforeEach(() => {
    vi.mocked(client.getSystem).mockReset();
    vi.mocked(client.getRoute).mockReset();
    vi.mocked(client.calculateDistanceLY).mockReset();
  });

  it('returns distance and names when both systems resolve', async () => {
    const sysA = { id: 1, name: 'Alpha', constellationId: 1, regionId: 1, location: { x: 0, y: 0, z: 0 }, gateLinks: [] };
    const sysB = { id: 2, name: 'Beta', constellationId: 2, regionId: 2, location: { x: 100, y: 0, z: 0 }, gateLinks: [] };

    vi.mocked(client.getSystem).mockImplementation(async (id) => id === 1 ? sysA : sysB);
    vi.mocked(client.getRoute).mockResolvedValue(null);
    vi.mocked(client.calculateDistanceLY).mockReturnValue(5.5);

    const { result } = renderHook(() => useRoute(1, 2), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.originName).toBe('Alpha');
    expect(result.current.destinationName).toBe('Beta');
    expect(result.current.distance).toBe(5.5);
    expect(result.current.jumps).toBeNull();
  });

  it('returns jumps when route API succeeds', async () => {
    const sys = { id: 1, name: 'X', constellationId: 1, regionId: 1, location: { x: 0, y: 0, z: 0 }, gateLinks: [] };
    vi.mocked(client.getSystem).mockResolvedValue(sys);
    vi.mocked(client.getRoute).mockResolvedValue({ origin: sys, destination: sys, jumps: 7, systems: [] });
    vi.mocked(client.calculateDistanceLY).mockReturnValue(0);

    const { result } = renderHook(() => useRoute(1, 2), { wrapper: createWrapper() });
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.jumps).toBe(7);
  });

  it('does not fetch when origin is null', () => {
    renderHook(() => useRoute(null, 2), { wrapper: createWrapper() });
    expect(client.getRoute).not.toHaveBeenCalled();
  });

  it('does not fetch when destination is null', () => {
    renderHook(() => useRoute(1, null), { wrapper: createWrapper() });
    expect(client.getRoute).not.toHaveBeenCalled();
  });
});

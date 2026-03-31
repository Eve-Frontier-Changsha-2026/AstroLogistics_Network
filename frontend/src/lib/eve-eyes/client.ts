// frontend/src/lib/eve-eyes/client.ts

import type { EveSystem, EveRoute, EveSystemSummary } from './types';

const BASE_URL = import.meta.env.VITE_EVE_EYES_URL ?? 'https://eve-eyes.d0v.xyz';
const TIMEOUT_MS = 5000;

async function fetchJson<T>(path: string): Promise<T | null> {
  try {
    const res = await fetch(`${BASE_URL}${path}`, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export async function getSystem(systemId: number): Promise<EveSystem | null> {
  return fetchJson<EveSystem>(`/api/world/systems/${systemId}`);
}

export async function getRoute(originId: number, destinationId: number): Promise<EveRoute | null> {
  return fetchJson<EveRoute>(`/api/world/route?originId=${originId}&destinationId=${destinationId}`);
}

export async function searchSystems(query: string): Promise<EveSystemSummary[]> {
  const result = await fetchJson<{ data: EveSystemSummary[] }>(`/api/world/systems/search?q=${encodeURIComponent(query)}`);
  return result?.data ?? [];
}

/** Euclidean distance in light-years. EVE coords are in meters. */
export function calculateDistanceLY(a: { x: number; y: number; z: number }, b: { x: number; y: number; z: number }): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = a.z - b.z;
  const meters = Math.sqrt(dx * dx + dy * dy + dz * dz);
  return meters / 9.461e18; // meters → light-years
}

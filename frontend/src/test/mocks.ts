// src/test/mocks.ts
import { vi } from 'vitest';

// --- Mock gRPC client ---
export function createMockClient(overrides: Record<string, unknown> = {}) {
  return {
    listOwnedObjects: vi.fn().mockResolvedValue({ objects: [] }),
    getObject: vi.fn().mockResolvedValue({ object: null }),
    getBalance: vi.fn().mockResolvedValue({ balance: { balance: '0' } }),
    getDynamicField: vi.fn().mockResolvedValue({ dynamicField: null }),
    waitForTransaction: vi.fn().mockResolvedValue({}),
    ...overrides,
  };
}

// --- Mock account ---
export const MOCK_ADDRESS = '0x' + 'a'.repeat(64);
export const MOCK_ACCOUNT = { address: MOCK_ADDRESS };

// --- Mock dAppKit instance ---
export function createMockDAppKit(overrides: Record<string, unknown> = {}) {
  return {
    signAndExecuteTransaction: vi.fn().mockResolvedValue({
      Transaction: { digest: 'mock-digest-abc123' },
    }),
    ...overrides,
  };
}

// --- Mock gRPC response shapes ---
export function mockListOwnedObjectsResponse(objects: Array<{ objectId: string; json: Record<string, unknown> }>) {
  return { objects };
}

export function mockGetObjectResponse(id: string, json: Record<string, unknown>, isShared = true) {
  return {
    object: {
      objectId: id,
      json,
      owner: isShared ? { $kind: 'Shared' as const } : { $kind: 'AddressOwner' as const, AddressOwner: MOCK_ADDRESS },
    },
  };
}

import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { readFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

// === Network ===
export const NETWORK = 'testnet' as const;
export const GRPC_URL = 'https://fullnode.testnet.sui.io:443';

// === Package ===
// Original (v1) — used for type references (struct definitions live here)
export const ORIGINAL_PACKAGE_ID = '0x564d32c9ce29b9f75c1821311aded4b84ee6d912c39e434309b9803e19f5f25c';
// Latest (v3, upgraded 2026-03-23) — used for function calls
export const PACKAGE_ID = '0x3407e5c8c245040bb2325dc1f5160188ec5ce811378107f1d2e6e82466bf706a';
export const FUEL_TREASURY_CAP = '0x077592721b6425e85c5c2cfbb8bef7a479719e07b83878a30aa6c07c1428bfbc';
export const METADATA_CAP = '0xcf227ade195ee4d367c633e2a991453f46350348cad1f1fb820fb5180eac2f8d';

// === FUEL coin type (uses original package where type was defined) ===
export const FUEL_TYPE = `${ORIGINAL_PACKAGE_ID}::fuel::FUEL`;

// === Init Parameters ===
export const INIT_PARAMS = {
  // threat_oracle::create_threat_map
  decayLambda: 100, // 0.1 in FP_SCALE(1000) — slow decay

  // storage::create_storage (Station Alpha)
  storage1: {
    systemId: 1,
    maxCapacity: 1_000_000,  // 1M weight units
    feeRateBps: 200,         // 2%
  },

  // storage::create_storage (Station Beta)
  storage2: {
    systemId: 2,
    maxCapacity: 500_000,    // 500K weight units
    feeRateBps: 300,         // 3%
  },

  // fuel_station::create_station
  fuelStation: {
    basePrice: 100,          // 100 per fuel unit
    alpha: 1000,             // 1.0x (linear pricing)
    ownerFeeBps: 500,        // 5%
  },

  // fuel::mint — initial supply
  mintAmount: 1_000_000_000_000n, // 1000 FUEL (9 decimals)
};

// === Keypair from SUI keystore ===
export function loadKeypair(): Ed25519Keypair {
  const keystorePath = join(homedir(), '.sui', 'sui_config', 'sui.keystore');
  const keystore: string[] = JSON.parse(readFileSync(keystorePath, 'utf-8'));

  // Try each key, find the one matching the deployer address
  const deployerAddress = '0x1509b5fdf09296b2cf749a710e36da06f5693ccd5b2144ad643b3a895abcbc4c';

  for (const encodedKey of keystore) {
    try {
      const raw = Buffer.from(encodedKey, 'base64');
      // SUI keystore format: first byte is scheme flag (0=Ed25519), rest is 32-byte secret
      if (raw[0] !== 0) continue; // skip non-Ed25519
      const keypair = Ed25519Keypair.fromSecretKey(raw.slice(1));
      if (keypair.toSuiAddress() === deployerAddress) {
        return keypair;
      }
    } catch {
      continue;
    }
  }
  throw new Error(`Deployer key not found in keystore for ${deployerAddress}`);
}

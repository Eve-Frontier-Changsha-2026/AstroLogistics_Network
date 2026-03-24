// frontend/src/integration/fuel-station.integration.test.ts
import { describe, it, expect } from 'vitest';
import {
  testClient,
  testAddress,
  signAndExec,
  findCreatedId,
  queryObject,
  TESTNET_OBJECTS,
  TYPE,
} from '@/test/integration-setup';
import { buildBuyFuel } from '@/lib/ptb/fuel-station';

describe('FuelStation — testnet integration', () => {
  it('buyFuel creates a FUEL Coin owned by sender', async () => {
    const tx = buildBuyFuel(
      TESTNET_OBJECTS.fuelStation1,
      100,    // amount
      200,    // maxPricePerUnit
      20000,  // paymentAmount (100 * 200)
    );

    const result = await signAndExec(tx);
    const coinId = findCreatedId(result, 'Coin');
    expect(coinId).toBeTruthy();
  });

  it('fuel station object is queryable with pricing fields', async () => {
    const obj = await queryObject(TESTNET_OBJECTS.fuelStation1);
    const json = obj.json as Record<string, unknown>;
    expect(json).toBeDefined();
    expect(json).toHaveProperty('base_price');
    expect(json).toHaveProperty('alpha');
    expect(json).toHaveProperty('total_fuel');
  });

  it('FUEL balance is queryable via getBalance', async () => {
    const res = await testClient.getBalance({
      owner: testAddress,
      coinType: TYPE.FUEL,
    });
    expect(res.balance).toBeDefined();
    expect(typeof res.balance.balance).toBe('string');
    expect(typeof res.balance.coinBalance).toBe('string');
  });
});

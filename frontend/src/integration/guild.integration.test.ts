// frontend/src/integration/guild.integration.test.ts
import { describe, it, expect } from 'vitest';
import {
  signAndExec,
  findCreatedId,
  queryObject,
  queryOwnedObjects,
  TESTNET_OBJECTS,
  TYPE,
} from '@/test/integration-setup';
import { buildCreateGuild } from '@/lib/ptb/guild';

describe('Guild — testnet integration', () => {
  it('createGuild creates a Guild shared object + GuildMemberCap', async () => {
    const uniqueName = `TestGuild_${Date.now()}`;
    const tx = buildCreateGuild(uniqueName);

    const result = await signAndExec(tx);
    const guildId = findCreatedId(result, 'Guild');
    expect(guildId).toBeTruthy();

    // Guild should be queryable
    const obj = await queryObject(guildId);
    expect(obj).toBeDefined();

    const json = obj.json as Record<string, unknown>;
    expect(json).toHaveProperty('name');
    expect(json.name).toBe(uniqueName);
  });

  it('existing guild is queryable with member_count', async () => {
    const obj = await queryObject(TESTNET_OBJECTS.guild);
    const json = obj.json as Record<string, unknown>;
    expect(json).toBeDefined();
    expect(json).toHaveProperty('member_count');
  });

  it('GuildMemberCap is findable in owned objects', async () => {
    const caps = await queryOwnedObjects(TYPE.GuildMemberCap);
    expect(caps.length).toBeGreaterThanOrEqual(1);
  });
});

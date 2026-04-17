import assert from 'node:assert';
import test from 'node:test';
import fs from 'node:fs/promises';
import { readConfig } from '../selector.mjs';

test('readConfig creates config.json with defaults if missing', async () => {
  const configPath = './temp-config.json';
  if (await fs.stat(configPath).catch(() => false)) await fs.unlink(configPath);
  
  const config = await readConfig(configPath);
  assert.strictEqual(config.general.cache_ttl_minutes, 15);
  assert.ok(await fs.stat(configPath));
  await fs.unlink(configPath);
});

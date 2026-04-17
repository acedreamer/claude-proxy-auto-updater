import assert from 'node:assert';
import test from 'node:test';
import fs from 'node:fs/promises';
import { readConfig, DEFAULT_CONFIG, calculateScore } from '../selector.mjs';

test('readConfig creates config.json with defaults if missing', async () => {
  const configPath = './temp-config.json';
  if (await fs.stat(configPath).catch(() => false)) await fs.unlink(configPath);
  
  const config = await readConfig(configPath);
  assert.strictEqual(config.general.cache_ttl_minutes, 15);
  assert.ok(await fs.stat(configPath));
  await fs.unlink(configPath);
});

test('calculateScore applies weights and pin bonus', () => {
  const model = { provider: 'nvidia', swe: 70, stability: 90, avgMs: 300 };
  const weights = DEFAULT_CONFIG.scoring.weights.opus;
  
  // Score = (70 * 0.55) + (90 * 0.20) + (LatScore * 0.05) + (NIMBonus * 1.5)
  // LatScore = 100 - (300 - 1500) * 0.01 = 112 -> capped at 100
  // NIMBonus = 8
  // Score = 38.5 + 18 + 5 + 12 = 73.5
  const score = calculateScore(model, weights, false);
  assert.strictEqual(score, 73.5);
  
  const pinnedScore = calculateScore(model, weights, true);
  assert.strictEqual(pinnedScore, 1073.5);
});

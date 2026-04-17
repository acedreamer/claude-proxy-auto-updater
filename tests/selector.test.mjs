import assert from 'node:assert';
import test from 'node:test';
import fs from 'node:fs/promises';
import { readConfig, DEFAULT_CONFIG, calculateScore, isEligible, isThinkingModel, assignSlots, getShortName } from '../selector.mjs';

test('getShortName formats correctly', () => {
  assert.strictEqual(getShortName('nvidia', 'moonshotai/kimi-k2.5'), 'kimi-k2.5(nvidia)');
  assert.strictEqual(getShortName('openrouter', 'deepseek/deepseek-r1:free'), 'deepseek-r1(openrouter)');
  assert.strictEqual(getShortName('google', 'gemini-pro'), 'gemini-pro(google)');
});

test('assignSlots includes shortName and insights', () => {
  const models = [
    { modelId: 'm1', provider: 'nvidia', status: 'up', verdict: 'Perfect', swe: 100, stability: 100, avgMs: 100, effectiveToolCallOk: true },
    { modelId: 'm2', provider: 'openrouter', status: 'up', verdict: 'Perfect', swe: 90, stability: 90, avgMs: 100, effectiveToolCallOk: true }
  ];
  const config = DEFAULT_CONFIG;
  const result = assignSlots(models, config);
  
  const opusSlot = result.slots.opus;
  assert.strictEqual(opusSlot.winner.shortName, 'm1(nvidia)');
  assert.strictEqual(opusSlot.runner_up.shortName, 'm2(openrouter)');
  assert.ok(opusSlot.insight);
  assert.ok(opusSlot.insight.includes('OPUS'));
  assert.ok(opusSlot.insight.includes('m1(nvidia)'));
});

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
  assert.strictEqual(score.total, 73.5);
  
  const pinnedScore = calculateScore(model, weights, true);
  assert.strictEqual(pinnedScore.total, 1073.5);
});

test('isEligible filters correctly', () => {
  const config = DEFAULT_CONFIG;
  const model = { modelId: 'test-model', provider: 'nvidia', status: 'up', verdict: 'Perfect', effectiveToolCallOk: true, thinking: false };
  
  assert.strictEqual(isEligible(model, 'opus', config), true);
  assert.strictEqual(isEligible({ ...model, status: 'down' }, 'opus', config), false);
  assert.strictEqual(isEligible({ ...model, thinking: true }, 'opus', config), false);
  assert.strictEqual(isEligible({ ...model, effectiveToolCallOk: false }, 'opus', config), false);
  assert.strictEqual(isEligible({ ...model, verdict: 'Spiky' }, 'opus', config), false);
  assert.strictEqual(isEligible(model, 'opus', { ...config, preferences: { bans: ['test-model'] } }), false);
});

test('assignSlots prevents duplicate winners across primary slots', () => {
  const models = [
    { modelId: 'm1', provider: 'nvidia', status: 'up', verdict: 'Perfect', swe: 100, stability: 100, avgMs: 100, effectiveToolCallOk: true },
    { modelId: 'm2', provider: 'nvidia', status: 'up', verdict: 'Perfect', swe: 90, stability: 90, avgMs: 100, effectiveToolCallOk: true }
  ];
  const config = DEFAULT_CONFIG;
  const result = assignSlots(models, config);
  
  assert.strictEqual(result.slots.opus.winner.modelId, 'm1');
  assert.strictEqual(result.slots.sonnet.winner.modelId, 'm2');
  assert.notStrictEqual(result.slots.opus.winner.modelId, result.slots.sonnet.winner.modelId);
});

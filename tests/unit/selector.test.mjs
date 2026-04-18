import assert from 'node:assert';
import test from 'node:test';
import { 
  stripBOM, 
  calculateScore, 
  isThinkingModel, 
  isEligible, 
  getShortName, 
  assignSlots,
  DEFAULT_CONFIG 
} from '../../selector.mjs';

test('stripBOM removes UTF-8 BOM', () => {
  const withBOM = '\uFEFF{"test": true}';
  const withoutBOM = '{"test": true}';
  assert.strictEqual(stripBOM(withBOM), '{"test": true}');
  assert.strictEqual(stripBOM(withoutBOM), '{"test": true}');
});

test('calculateScore applies weights correctly', () => {
  const model = { swe: 70, stability: 90, avgMs: 200, provider: 'nvidia' };
  const weights = { swe: 0.5, stab: 0.2, lat: 0.3, nim: 1.0, target_lat: 500, penalty: 0.1 };
  const result = calculateScore(model, weights, false);
  assert.strictEqual(result.total, 91);
});

test('isThinkingModel detects R1 and thinking models', () => {
  assert.strictEqual(isThinkingModel('deepseek/deepseek-r1'), true);
  assert.strictEqual(isThinkingModel('gpt-4o'), false);
});

test('isEligible filters correctly', () => {
  const config = { general: { tier_filter: 'S' }, preferences: { bans: [] } };
  const model = { status: 'up', tier: 'S', verdict: 'Perfect', effectiveToolCallOk: true };
  
  assert.strictEqual(isEligible(model, 'opus', config), true);
  assert.strictEqual(isEligible({ ...model, status: 'down' }, 'opus', config), false);
  assert.strictEqual(isEligible({ ...model, verdict: 'Slow' }, 'opus', config), false);
});

test('assignSlots prevents duplicate winners', () => {
  const models = [
    { modelId: 'm1', provider: 'p1', swe: 90, stability: 95, avgMs: 100, status: 'up', tier: 'S', verdict: 'Perfect', toolCallProbeStatus: 'pass' },
    { modelId: 'm2', provider: 'p1', swe: 80, stability: 90, avgMs: 150, status: 'up', tier: 'S', verdict: 'Perfect', toolCallProbeStatus: 'pass' }
  ];
  const result = assignSlots(models, DEFAULT_CONFIG);
  assert.strictEqual(result.slots.opus?.winner?.modelId, 'm1');
  assert.strictEqual(result.slots.sonnet?.winner?.modelId, 'm2');
});

test('assignSlots handles empty input', () => {
  const result = assignSlots([], DEFAULT_CONFIG);
  assert.ok(result.slots, 'slots object should exist');
  assert.strictEqual(result.slots.opus?.winner || null, null);
  assert.strictEqual(result.slots.sonnet?.winner || null, null);
});

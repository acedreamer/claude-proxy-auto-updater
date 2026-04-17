# selector.mjs (The Brain) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize all scoring, slot assignment, and user preferences into a single Node.js script (`selector.mjs`) and a `config.json` file.

**Architecture:** Node.js (ESM) script using functional patterns for scoring and selection logic.

**Tech Stack:** Node.js 18+ (ESM), `fs/promises`.

---

### Task 1: Config Management

**Files:**
- Create: `selector.mjs`
- Test: `tests/selector.test.mjs`

- [ ] **Step 1: Write the failing test for Config Manager**
Verify `readConfig()` creates `config.json` if missing and merges defaults.

```javascript
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
```

- [ ] **Step 2: Run test to verify it fails**
Run: `node --test tests/selector.test.mjs`
Expected: FAIL (missing `selector.mjs` or `readConfig` not exported)

- [ ] **Step 3: Implement minimal `readConfig`**
Implement the function that reads/writes `config.json`.

```javascript
import fs from 'node:fs/promises';
import path from 'node:path';

export const DEFAULT_CONFIG = {
  general: {
    cache_ttl_minutes: 15,
    providers: "nvidia,openrouter",
    tier_filter: "S+,S,A+,A",
    timeout_ms: 15000
  },
  preferences: {
    pins: { opus: null, sonnet: null, haiku: null },
    bans: []
  },
  scoring: {
    weights: {
      opus: { swe: 0.55, stab: 0.20, lat: 0.05, nim: 1.5, target_lat: 1500, penalty: 0.01 },
      sonnet: { swe: 0.35, stab: 0.25, lat: 0.25, nim: 1.0, target_lat: 500, penalty: 0.04 },
      haiku: { swe: 0.05, stab: 0.15, lat: 0.70, nim: 0.5, target_lat: 200, penalty: 0.12 },
      fallback: { swe: 0.25, stab: 0.50, lat: 0.10, nim: 1.0, target_lat: 800, penalty: 0.02 }
    }
  }
};

export async function readConfig(configPath) {
  let config = { ...DEFAULT_CONFIG };
  try {
    const data = await fs.readFile(configPath, 'utf8');
    const userConfig = JSON.parse(data);
    config = mergeDeep(config, userConfig);
  } catch (err) {
    // Missing or invalid, just use defaults
  }
  await fs.writeFile(configPath, JSON.stringify(config, null, 2));
  return config;
}

function mergeDeep(target, source) {
  for (const key in source) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
      if (!target[key]) target[key] = {};
      mergeDeep(target[key], source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `node --test tests/selector.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**
`git add selector.mjs tests/selector.test.mjs && git commit -m "feat: implement config manager in selector.mjs"`

---

### Task 2: Scoring Engine

- [ ] **Step 1: Write the failing test for Scoring Engine**
Verify `calculateScore()` correctly weighs attributes and adds pin bonus.

```javascript
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
```

- [ ] **Step 2: Run test to verify it fails**
Expected: FAIL (`calculateScore` not defined)

- [ ] **Step 3: Implement `calculateScore`**

```javascript
export function calculateScore(model, weights, isPinned = false) {
  const avgMs = model.avgMs || 9999.0;
  const latScore = Math.max(0, Math.min(100, 100 - ((avgMs - weights.target_lat) * weights.penalty)));
  
  const sweScore = model.swe || 0;
  const stability = model.stability || 30.0;
  const nimBonus = model.provider === 'nvidia' ? 8 : 0;
  
  let score = (sweScore * weights.swe) + (stability * weights.stab) + (latScore * weights.lat) + (nimBonus * weights.nim);
  if (isPinned) score += 1000;
  
  return Math.round(score * 10) / 10; // Round to 1 decimal place
}
```

- [ ] **Step 4: Run test to verify it passes**
Expected: PASS

---

### Task 3: Eligibility Filtering

- [ ] **Step 1: Write failing test for Eligibility**
Verify `isEligible()` filters by status, bans, thinking, tools, and verdict.

```javascript
test('isEligible filters correctly', () => {
  const config = DEFAULT_CONFIG;
  const model = { modelId: 'test-model', provider: 'nvidia', status: 'up', verdict: 'Perfect', toolCallOk: true, thinking: false };
  
  assert.strictEqual(isEligible(model, 'opus', config), true);
  assert.strictEqual(isEligible({ ...model, status: 'down' }, 'opus', config), false);
  assert.strictEqual(isEligible({ ...model, thinking: true }, 'opus', config), false);
  assert.strictEqual(isEligible({ ...model, toolCallOk: false }, 'opus', config), false);
  assert.strictEqual(isEligible({ ...model, verdict: 'Spiky' }, 'opus', config), false);
  assert.strictEqual(isEligible(model, 'opus', { ...config, preferences: { bans: ['test-model'] } }), false);
});
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement `isEligible` and `isThinkingModel`**

```javascript
export function isThinkingModel(modelId) {
  const patterns = [/deepseek-r1/i, /kimi-k2-thinking/i, /qwq/i, /-thinking$/i, /\b(thinking|r1)\b/i, /thinking-model/i, /reasoning/i];
  return patterns.some(p => p.test(modelId));
}

export function isEligible(model, slot, config) {
  if (model.status !== 'up') return false;
  if (config.preferences.bans.includes(model.modelId)) return false;
  
  const thinking = isThinkingModel(model.modelId);
  const verdict = model.verdict || 'Unknown';
  
  // Slot specific rules
  if (slot === 'opus' || slot === 'sonnet') {
    if (thinking) return false;
    if (!['Perfect', 'Normal'].includes(verdict)) return false;
    if (!model.effectiveToolCallOk) return false;
  } else if (slot === 'haiku') {
    if (thinking) return false;
    if (!['Perfect', 'Normal', 'Slow'].includes(verdict)) return false;
  } else if (slot === 'fallback') {
    if (thinking) return false;
    if (!['Perfect', 'Normal', 'Slow', 'Spiky'].includes(verdict)) return false;
    if (!model.effectiveToolCallOk) return false;
  }
  
  return true;
}
```

- [ ] **Step 4: Run test to verify it passes**

---

### Task 4: Slot Assignment (The Brain)

- [ ] **Step 1: Write failing test for `assignSlots`**
Verify sequential assignment without duplicates for primary slots.

```javascript
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
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement `assignSlots`**

```javascript
export function assignSlots(models, config) {
  const result = { slots: {}, is_degraded: false, is_thinking: false };
  const assigned = new Set();
  
  const slots = ['opus', 'sonnet', 'haiku', 'fallback'];
  
  for (const slot of slots) {
    let eligible = models
      .map(m => ({ ...m, effectiveToolCallOk: getToolCallEffective(m), thinking: isThinkingModel(m.modelId) }))
      .filter(m => isEligible(m, slot, config));
    
    // For primary slots, exclude already assigned
    if (slot !== 'fallback') {
      eligible = eligible.filter(m => !assigned.has(m.modelId));
    }
    
    // Fallback if none eligible
    if (eligible.length === 0) {
      eligible = models.filter(m => m.status === 'up');
    }
    
    const pin = config.preferences.pins[slot];
    const scored = eligible.map(m => ({
      ...m,
      score: calculateScore(m, config.scoring.weights[slot], m.modelId === pin || `${m.provider}/${m.modelId}` === pin)
    })).sort((a, b) => b.score - a.score);
    
    if (scored.length > 0) {
      const winner = scored[0];
      result.slots[slot] = {
        winner,
        runner_up: scored[1] || null,
        breakdown: scored.slice(0, 3)
      };
      if (slot !== 'fallback') assigned.add(winner.modelId);
    }
  }
  
  result.is_thinking = result.slots.sonnet?.winner?.thinking || false;
  result.is_degraded = models.some(m => m.degraded);
  
  return result;
}

function getToolCallEffective(model) {
  if (model.toolCallProbeStatus === 'pass') return true;
  if (model.toolCallProbeStatus === 'fail') return false;
  if (model.toolCallOk !== undefined && model.toolCallOk !== null) return !!model.toolCallOk;
  return ['S+', 'S', 'A+', 'A'].includes(model.tier);
}
```

- [ ] **Step 4: Run test to verify it passes**

---

### Task 5: Main Entry Point & `config.example.json`

- [ ] **Step 1: Implement the main entry point**
Read `model-cache.json`, run `readConfig`, `assignSlots`, and output JSON.

- [ ] **Step 2: Create `config.example.json`**
Provide the `DEFAULT_CONFIG` as a JSON file.

- [ ] **Step 3: Manual verification with real cache**
Run `node selector.mjs` and check JSON output.

- [ ] **Step 4: Commit**
`git add selector.mjs config.example.json && git commit -m "feat: complete Task 1 selector.mjs"`

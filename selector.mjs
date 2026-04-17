import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
  let config = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
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

export function calculateScore(model, weights, isPinned = false) {
  const avgMs = model.avgMs || 9999.0;
  const latScoreRaw = Math.max(0, Math.min(100, 100 - ((avgMs - weights.target_lat) * weights.penalty)));
  
  const sweScore = model.swe || 0;
  const stability = model.stability || 30.0;
  const nimBonus = model.provider === 'nvidia' ? 8 : 0;
  
  const components = {
    swe: Math.round(sweScore * weights.swe * 10) / 10,
    stab: Math.round(stability * weights.stab * 10) / 10,
    lat: Math.round(latScoreRaw * weights.lat * 10) / 10,
    nim: Math.round(nimBonus * weights.nim * 10) / 10
  };
  
  let total = components.swe + components.stab + components.lat + components.nim;
  if (isPinned) total += 1000;
  
  return {
    total: Math.round(total * 10) / 10,
    components
  };
}

export function isThinkingModel(modelId) {
  const patterns = [/deepseek-r1/i, /kimi-k2-thinking/i, /qwq/i, /-thinking$/i, /\b(thinking|r1)\b/i, /thinking-model/i, /reasoning/i];
  return patterns.some(p => p.test(modelId));
}

export function isEligible(model, slot, config) {
  if (model.status !== 'up') return false;
  if (config.preferences.bans.includes(model.modelId)) return false;
  
  const thinking = model.thinking !== undefined ? model.thinking : isThinkingModel(model.modelId);
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

export function assignSlots(models, config) {
  const result = { slots: {}, is_degraded: false, is_thinking: false };
  const assigned = new Set();
  
  // Pre-process all models once
  const processedModels = models.map(m => ({
    ...m,
    effectiveToolCallOk: getToolCallEffective(m),
    thinking: isThinkingModel(m.modelId)
  }));
  
  const slots = ['opus', 'sonnet', 'haiku', 'fallback'];
  
  for (const slot of slots) {
    let eligible = processedModels.filter(m => isEligible(m, slot, config));
    
    // For primary slots, exclude already assigned
    if (slot !== 'fallback') {
      eligible = eligible.filter(m => !assigned.has(m.modelId));
    }
    
    // Fallback if none eligible
    if (eligible.length === 0) {
      eligible = processedModels.filter(m => m.status === 'up');
    }
    
    const pin = config.preferences.pins[slot];
    const scored = eligible.map(m => {
      const scoreObj = calculateScore(m, config.scoring.weights[slot], m.modelId === pin || `${m.provider}/${m.modelId}` === pin);
      return {
        ...m,
        score: scoreObj.total,
        scoreComponents: scoreObj.components
      };
    }).sort((a, b) => b.score - a.score);
    
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
  if (model.effectiveToolCallOk !== undefined) return !!model.effectiveToolCallOk;
  return ['S+', 'S', 'A+', 'A'].includes(model.tier);
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

// Main execution
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const cachePath = path.resolve(process.cwd(), 'model-cache.json');
  const configPath = path.resolve(process.cwd(), 'config.json');
  
  try {
    const cacheData = await fs.readFile(cachePath, 'utf8');
    const models = JSON.parse(cacheData);
    const config = await readConfig(configPath);
    
    const result = assignSlots(models, config);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } catch (err) {
    if (err.code === 'ENOENT') {
      process.stderr.write(`Error: model-cache.json not found at ${cachePath}\n`);
    } else {
      process.stderr.write(`Error: ${err.message}\n`);
    }
    process.exit(1);
  }
}

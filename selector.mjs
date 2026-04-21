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
    show_insights: true,
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

export function stripBOM(content) {
  if (typeof content === 'string' && content.charCodeAt(0) === 0xFEFF) {
    return content.slice(1);
  }
  return content;
}

export async function readConfig(configPath) {
  let config = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  if (!configPath) {
    return config;
  }
  try {
    const data = await fs.readFile(configPath, 'utf8');
    const userConfig = JSON.parse(stripBOM(data));
    config = mergeDeep(config, userConfig);
  } catch (err) {
    // Missing or invalid, just use defaults
  }
  try {
    await fs.writeFile(configPath, JSON.stringify(config, null, 2));
  } catch (err) {
    // Ignore write errors if path is invalid
  }
  return config;
}

export function isThinkingModel(modelId) {
  const patterns = [/deepseek-r1/i, /kimi-k2-thinking/i, /qwq/i, /-thinking$/i, /\b(thinking|r1)\b/i, /thinking-model/i, /reasoning/i];
  return patterns.some(p => p.test(modelId));
}

export function getModelTier(modelId) {
  const m = modelId.toLowerCase();
  if (m.includes('flash') || m.includes('lite') || m.includes('tiny') || m.includes('-8b') || m.includes('mini')) return 'utility';
  // Super-Flagship: High-density giants (>200B) or premium Opus models
  if (m.includes('397b') || m.includes('405b') || m.includes('opus-4-7') || m.includes('opus-5')) return 'super-flagship';
  if (m.includes('thinking') || m.includes('r1') || m.includes('opus') || m.includes('70b') || m.includes('80b')) return 'flagship';
  return 'standard';
}

export function isEligible(model, slot, config) {
  if (model.status !== 'up') return false;
  if (config.preferences.bans.includes(model.modelId)) return false;
  
  const verdict = model.verdict || 'Unknown';
  const tier = getModelTier(model.modelId);
  
  // Slot specific rules - Intelligence Enforcement
  if (slot === 'opus') {
    // OPUS MUST be a Flagship or Super-Flagship. 
    if (tier === 'utility' || tier === 'standard') return false;
    if (!['Perfect', 'Normal'].includes(verdict)) return false;
    if (!model.effectiveToolCallOk) return false;
  } else if (slot === 'sonnet') {
    // SONNET MUST be at least Flagship (70B+). No Lite/Utility models.
    if (tier === 'utility') return false;
    if (!['Perfect', 'Normal'].includes(verdict)) return false;
    if (!model.effectiveToolCallOk) return false;
  } else if (slot === 'haiku') {
    if (!['Perfect', 'Normal', 'Slow'].includes(verdict)) return false;
  } else if (slot === 'fallback') {
    if (!['Perfect', 'Normal', 'Slow', 'Spiky'].includes(verdict)) return false;
    if (!model.effectiveToolCallOk) return false;
  }
  
  return true;
}

export function calculateScore(model, weights, isPinned = false) {
  const avgMs = model.avgMs || 9999.0;
  const latScoreRaw = Math.max(0, Math.min(100, 100 - ((avgMs - weights.target_lat) * weights.penalty)));
  
  const sweScore = model.swe || 0;
  const stability = model.stability || 30.0;
  const nimBonus = model.provider === 'nvidia' ? 12 : 0;
  
  // ROLE AFFINITY BONUSES
  let roleBonus = 0;
  const tier = getModelTier(model.modelId);
  const isThinking = isThinkingModel(model.modelId);

  // Opus Role: Prioritizes Raw Density (Super-Flagships) and Reasoning
  if (weights.swe > 0.5) { 
    if (tier === 'super-flagship') roleBonus += 60; // Ensure 400B models beat 80B models
    if (tier === 'flagship') roleBonus += 25;
    if (isThinking) roleBonus += 30;
  }
  // Haiku Role: Values Flash/Utility speed
  else if (weights.lat > 0.6) { 
    if (tier === 'utility') roleBonus += 50;
  }
  // Sonnet Role: Values MoE Efficiency
  else {
    const isMoE = /deepseek-v3|mixtral|qwen.*-moe|397b|a3b|a17b/i.test(model.modelId);
    if (isMoE) roleBonus += 25;
    if (tier === 'flagship') roleBonus += 15;
  }
  
  const components = {
    swe: Math.round(sweScore * weights.swe * 10) / 10,
    stab: Math.round(stability * weights.stab * 10) / 10,
    lat: Math.round(latScoreRaw * weights.lat * 10) / 10,
    nim: Math.round(nimBonus * weights.nim * 10) / 10,
    role: roleBonus
  };
  
  let total = components.swe + components.stab + components.lat + components.nim + components.role;
  if (isPinned) total += 1000;
  
  return {
    total: Math.round(total * 10) / 10,
    components
  };
}

export function getShortName(provider, modelId) {
  const parts = modelId.split('/');
  const lastPart = parts[parts.length - 1];
  const baseName = lastPart.split(':')[0];
  return `${baseName}(${provider})`;
}

const SLOT_EXPLAINERS = {
  opus: "High-intelligence role. Focused on SWE-bench scores (55%) and stability. Non-reasoning models preferred for direct code output.",
  sonnet: "Balanced coding role. Mix of speed and quality (35% SWE). Standard for daily development tasks.",
  haiku: "Fast response role. Heavily weighted for low latency (70%) and stability. Optimized for lightweight queries.",
  fallback: "Reliability anchor. Prioritizes uptime and stability (50%) to ensure proxy connectivity if primary models fail."
};

export function assignSlots(models, config) {
  const result = { slots: {}, is_degraded: false, is_thinking: false, global_insights: config.preferences.show_insights };
  const assigned = new Set();
  
  // Pre-process all models once
  const processedModels = models.map(m => ({
    ...m,
    effectiveToolCallOk: getToolCallEffective(m),
    thinking: isThinkingModel(m.modelId),
    shortName: getShortName(m.provider, m.modelId)
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
      const runner_up = scored[1] || null;
      
      const insight = `[${slot.toUpperCase()}] ${SLOT_EXPLAINERS[slot]} Selected ${winner.shortName} (Score: ${winner.score}).`;
      
      result.slots[slot] = {
        winner,
        runner_up,
        insight,
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
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const cachePath = path.resolve(scriptDir, 'model-cache.json');
  const configPath = path.resolve(scriptDir, 'config.json');

  try {
    const cacheData = await fs.readFile(cachePath, 'utf8');
    const models = JSON.parse(stripBOM(cacheData));
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


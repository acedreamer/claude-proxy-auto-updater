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

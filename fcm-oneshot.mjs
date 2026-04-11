/**
 * fcm-oneshot.mjs
 * 
 * Uses free-coding-models internals directly to run ONE ping cycle,
 * output rich JSON (verdict, stability, p95, jitter, uptime), then exit.
 * 
 * This replaces the PowerShell runspace ping logic in update-models.ps1
 * with real free-coding-models data including verdicts and stability scores.
 * 
 * Usage:
 *   node fcm-oneshot.mjs [--providers nim,openrouter] [--tier S,A] [--timeout 15000]
 */

import { createRequire } from 'module'
import { fileURLToPath, pathToFileURL } from 'url'
import path from 'path'
import fs from 'fs'
import { execSync } from 'child_process'

// -- Locate free-coding-models package --
const require = createRequire(import.meta.url)
let FCM_ROOT
try {
  // 1. Try local resolution
  FCM_ROOT = path.dirname(require.resolve('free-coding-models/package.json'))
} catch {
  // 2. Try global resolution (npm install -g)
  try {
    const globalRoot = execSync('npm root -g', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
    const globalPath = path.join(globalRoot, 'free-coding-models')
    if (fs.existsSync(path.join(globalPath, 'package.json'))) {
      FCM_ROOT = globalPath
      process.stderr.write(`[fcm-oneshot] Using global package at: ${FCM_ROOT}\n`)
    } else {
      throw new Error('Not found globally')
    }
  } catch (err) {
    process.stderr.write('[fcm-oneshot] ERROR: free-coding-models not found locally or globally.\n')
    process.stderr.write('              Run: npm install free-coding-models\n')
    process.exit(1)
  }
}

// -- Dynamic imports from the package --
const fcmUrl = pathToFileURL(FCM_ROOT).href
const { MODELS, sources } = await import(`${fcmUrl}/sources.js`)
const { ping }            = await import(`${fcmUrl}/src/ping.js`)
const {
  getAvg, getVerdict, getUptime, getP95, getJitter, getStabilityScore
} = await import(`${fcmUrl}/src/utils.js`)

// ============================================================
// CLI ARGS
// ============================================================
const args        = process.argv.slice(2)
const getArg      = (flag) => { const i = args.indexOf(flag); return i !== -1 ? args[i + 1] : null }

const TIMEOUT_MS  = parseInt(getArg('--timeout') || '15000', 10)
const filterProvs = (getArg('--providers') || '').split(',').filter(Boolean)
const filterTiers = (getArg('--tier')      || '').split(',').filter(Boolean)
const MAX_CONCUR  = parseInt(getArg('--concurrency') || '12', 10)

// ============================================================
// KEY RESOLUTION
// ============================================================
const KEY_MAP = {
  nvidia:      process.env.NVIDIA_API_KEY  || process.env.NVIDIA_NIM_API_KEY,
  openrouter:  process.env.OPENROUTER_API_KEY,
}

// ============================================================
// MODEL FILTER
// ============================================================
const enabledProviders = new Set(
  Object.entries(KEY_MAP)
    .filter(([k, v]) => v && (filterProvs.length === 0 || filterProvs.includes(k)))
    .map(([k]) => k)
)

const candidates = MODELS.filter(([modelId, label, tier, sweScore, ctx, providerKey]) => {
  if (!enabledProviders.has(providerKey)) return false
  if (filterTiers.length > 0 && !filterTiers.includes(tier)) return false
  return true
}).map(([modelId, label, tier, sweScore, ctx, providerKey]) => ({
  modelId, label, tier, sweScore, ctx, providerKey,
  pings: [], status: 'pending',
}))

if (candidates.length === 0) {
  process.stdout.write('[]\n')
  process.exit(1)
}

// ============================================================
// PING
// ============================================================
async function pingModel(model) {
  const apiKey = KEY_MAP[model.providerKey]
  const url    = sources[model.providerKey].url
  try {
    const result = await ping(apiKey, model.modelId, model.providerKey, url)
    model.pings.push({ ms: result.ms === 'TIMEOUT' ? TIMEOUT_MS : result.ms, code: result.code })
    model.status = result.code === '200' ? 'up' : 'down'
  } catch (err) {
    model.status = 'down'
  }
}

async function runWithConcurrency(tasks, limit) {
  const queue = [...tasks]; const active = []; const results = []
  while (queue.length > 0 || active.length > 0) {
    while (active.length < limit && queue.length > 0) {
      const task = queue.shift()
      const p = pingModel(task).then(() => active.splice(active.indexOf(p), 1))
      active.push(p)
    }
    if (active.length > 0) await Promise.race(active)
  }
}

await runWithConcurrency(candidates, MAX_CONCUR)

const output = candidates.map(m => {
  const stability = getStabilityScore(m)
  const sweNum = parseFloat((m.sweScore || '0').replace('%', '')) || 0
  return {
    modelId: m.modelId,
    provider: m.providerKey,
    tier: m.tier,
    swe: sweNum,
    status: m.status,
    verdict: getVerdict(m),
    avgMs: getAvg(m),
    stability: Number.isFinite(stability) ? stability : null,
  }
})

process.stdout.write(JSON.stringify(output, null, 2) + '\n')
process.exit(0)

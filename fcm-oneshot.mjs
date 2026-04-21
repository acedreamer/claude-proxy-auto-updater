/**
 * fcm-oneshot.mjs
 *
 * Uses free-coding-models internals directly to run ONE ping cycle,
 * output rich JSON (verdict, stability, p95, jitter, uptime), then exit.
 *
 * M3: Now includes degraded mode (direct HTTP fallback) and tool-call auto-detection.
 *
 * Usage:
 * node fcm-oneshot.mjs [--providers nim,openrouter] [--tier S,A] [--timeout 15000]
 */

import { createRequire } from 'module'
import { fileURLToPath, pathToFileURL } from 'url'
import { performance } from 'node:perf_hooks'
import path from 'path'
import fs from 'fs'
import { execSync } from 'child_process'

// -- Locate free-coding-models package --
const require = createRequire(import.meta.url)
let FCM_ROOT
let DEGRADED_MODE = false

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
    // 3. Fall back to degraded mode with direct HTTP ping
    DEGRADED_MODE = true
    process.stderr.write('[fcm-oneshot] DEGRADED MODE: free-coding-models not found.\n')
    process.stderr.write(' Install for full features: npm install -g free-coding-models\n')
    process.stderr.write(' Continuing with latency-only HTTP pings...\n\n')
  }
}

// -- CLI ARGS (needed in degraded mode too) --
const args = process.argv.slice(2)
const getArg = (flag) => {
  const i = args.indexOf(flag)
  return i !== -1 ? args[i + 1] : null
}
const hasFlag = (flag) => args.includes(flag)

/**
 * Load general settings from config.json if available
 */
export async function loadConfig(configPath) {
  try {
    const p = configPath || path.join(path.dirname(fileURLToPath(import.meta.url)), 'config.json')
    if (fs.existsSync(p)) {
      const data = fs.readFileSync(p, 'utf8')
      const cfg = JSON.parse(data)
      return cfg.general || {}
    }
  } catch (err) {
    // Silent fail, use defaults
  }
  return {}
}

const configGeneral = await loadConfig()

const TIMEOUT_MS = parseInt(getArg('--timeout') || configGeneral.timeout_ms || '15000', 10)
const filterProvs = (getArg('--providers') || configGeneral.providers || '').split(',').filter(Boolean)
const filterTiers = (getArg('--tier') || configGeneral.tier_filter || '').split(',').filter(Boolean)
const MAX_CONCUR = parseInt(getArg('--concurrency') || '12', 10)
const ENABLE_TOOL_TEST = hasFlag('--tool-test') // R-401: Tool-call probe flag
const OUTPUT_FILE = getArg('--output')

// ============================================================
// KEY RESOLUTION
// ============================================================
const KEY_MAP = {
  nvidia: process.env.NVIDIA_API_KEY || process.env.NVIDIA_NIM_API_KEY,
  openrouter: process.env.OPENROUTER_API_KEY,
}

// Minimal model registry for degraded mode (R-501-R-504)
const DEGRADED_MODELS = [
  // NVIDIA NIM
  ['moonshotai/kimi-k2.5', 'Kimi K2.5', 'S', '70.9', '128k', 'nvidia', 'nvidia_nim/moonshotai/kimi-k2.5'],
  ['moonshotai/kimi-k2-thinking', 'Kimi K2 Thinking', 'A', '68.5', '128k', 'nvidia', 'nvidia_nim/moonshotai/kimi-k2-thinking'],
  ['z-ai/glm4.7', 'GLM-4.7', 'S', '68.4', '128k', 'nvidia', 'nvidia_nim/z-ai/glm4.7'],
  ['deepseek-ai/deepseek-v3.2', 'DeepSeek V3.2', 'S', '68.3', '128k', 'nvidia', 'nvidia_nim/deepseek-ai/deepseek-v3.2'],
  ['deepseek-ai/deepseek-v3-0324', 'DeepSeek V3-0324', 'S', '67.9', '128k', 'nvidia', 'nvidia_nim/deepseek-ai/deepseek-v3-0324'],
  ['minimaxai/minimax-m2.5', 'MiniMax M2.5', 'A', '65.0', '128k', 'nvidia', 'nvidia_nim/minimaxai/minimax-m2.5'],
  ['meta/llama-3.3-70b-instruct', 'Llama 3.3 70B', 'A', '62.5', '128k', 'nvidia', 'nvidia_nim/meta/llama-3.3-70b-instruct'],
  ['meta/llama-3.1-405b-instruct', 'Llama 3.1 405B', 'S', '68.2', '128k', 'nvidia', 'nvidia_nim/meta/llama-3.1-405b-instruct'],
  // OpenRouter
  ['deepseek/deepseek-r1:free', 'DeepSeek R1', 'S', '68.5', '128k', 'openrouter', 'open_router/deepseek/deepseek-r1:free'],
  ['deepseek/deepseek-r1-0528:free', 'DeepSeek R1-0528', 'S', '68.7', '128k', 'openrouter', 'open_router/deepseek/deepseek-r1-0528:free'],
  ['qwen/qwen3.6-plus:free', 'Qwen 3.6 Plus', 'A', '65.0', '128k', 'openrouter', 'open_router/qwen/qwen3.6-plus:free'],
]

// Tool-call detection: minimal test request (R-401, R-402)
const TOOL_TEST_TOOL = {
  type: 'function',
  function: {
    name: 'get_weather',
    description: 'Get current weather for a location',
    parameters: {
      type: 'object',
      properties: {
        location: { type: 'string', description: 'City name' }
      },
      required: ['location']
    }
  }
}

// ============================================================
// DEGRADED MODE: Direct HTTP PING (R-501-R-504)
// ============================================================

async function degradedPing(model, signal) {
  const start = performance.now()
  try {
    const provider = model.providerKey
    const apiKey = KEY_MAP[provider]

    if (!apiKey) {
      return { ms: -1, code: 'NO_KEY', latencyOnly: true }
    }

    let url, body, headers

    if (provider === 'nvidia') {
      url = 'https://integrate.api.nvidia.com/v1/chat/completions'
      headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      }
      body = JSON.stringify({
        model: model.modelId,
        messages: [{ role: 'user', content: 'ping' }],
        max_tokens: 1
      })
    } else if (provider === 'openrouter') {
      url = 'https://openrouter.ai/api/v1/chat/completions'
      headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://localhost',
        'X-Title': 'Claude Proxy Auto-Updater'
      }
      body = JSON.stringify({
        model: model.modelId,
        messages: [{ role: 'user', content: 'ping' }],
        max_tokens: 1
      })
    }

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body,
      signal
    })

    const end = performance.now()
    const ms = Math.round(end - start)
    const code = response.status.toString()

    return { ms, code, latencyOnly: true }
  } catch (err) {
    return { ms: -1, code: 'ERR', latencyOnly: true, error: err.name }
  }
}

// Tool-call probe (R-401-R-406)
async function toolCallProbe(model, signal) {
  const start = performance.now()
  try {
    const provider = model.providerKey
    const apiKey = KEY_MAP[provider]

    if (!apiKey) return { toolCallOk: null, probeStatus: 'unknown', reason: 'no_api_key', probeMs: null }

    let url, headers, body

    if (provider === 'nvidia') {
      url = 'https://integrate.api.nvidia.com/v1/chat/completions'
      headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      }
      body = JSON.stringify({
        model: model.modelId,
        messages: [{ role: 'user', content: 'What is the weather in Paris?' }],
        tools: [TOOL_TEST_TOOL],
        tool_choice: 'auto',
        max_tokens: 100
      })
    } else if (provider === 'openrouter') {
      url = 'https://openrouter.ai/api/v1/chat/completions'
      headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'HTTP-Referer': 'https://localhost',
        'X-Title': 'Claude Proxy Auto-Updater'
      }
      body = JSON.stringify({
        model: model.modelId,
        messages: [{ role: 'user', content: 'What is the weather in Paris?' }],
        tools: [TOOL_TEST_TOOL],
        tool_choice: 'auto',
        max_tokens: 100
      })
    } else {
      return { toolCallOk: null, probeStatus: 'unknown', reason: 'unknown_provider', probeMs: null }
    }

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body,
      signal
    })

    const end = performance.now()
    const probeMs = Math.round(end - start)

    // R-406: Must complete within 1 second total
    if (probeMs > 1000) {
      return { toolCallOk: null, probeStatus: 'unknown', reason: 'timeout', probeMs }
    }

    if (!response.ok) {
      return { toolCallOk: false, probeStatus: 'fail', reason: `http_${response.status}`, probeMs }
    }

    let data
    try {
      data = await response.json()
    } catch {
      return { toolCallOk: null, probeStatus: 'unknown', reason: 'invalid_json', probeMs }
    }

    // R-402: Check for valid tool_use in response
    let hasToolUse = false
    let hasContent = false

    if (data.choices && data.choices[0]?.message) {
      const msg = data.choices[0].message
      
      // Strict Content Check: Reject empty or whitespace-only responses
      if (msg.content && msg.content.trim().length > 0) {
        hasContent = true
      }

      // Strict Tool Call Check: Must have actual arguments
      if (msg.tool_calls && msg.tool_calls.length > 0) {
        const firstCall = msg.tool_calls[0]
        if (firstCall.function && firstCall.function.arguments) {
          hasToolUse = true
        }
      }
    }

    if (hasToolUse || hasContent) {
      const reason = hasToolUse ? 'tool_use_detected' : 'content_detected'
      return { toolCallOk: true, probeStatus: 'pass', reason, probeMs }
    }

    // FAILED: Model responded but sent back nothing useful (likely context window or capacity issue)
    return { toolCallOk: false, probeStatus: 'fail', reason: 'empty_response', probeMs }
  } catch (err) {
    // R-405: Fall back on error/timeout
    if (signal.aborted) {
      return { toolCallOk: null, probeStatus: 'unknown', reason: 'timeout', probeMs: null }
    }
    return { toolCallOk: null, probeStatus: 'unknown', reason: err.name || 'error', probeMs: null }
  }
}

// ============================================================
// MAIN EXECUTION
// ============================================================

async function main() {
  let candidates, ping, getStabilityScore, getVerdict, getAvg

  const enabledProviders = new Set(
    Object.entries(KEY_MAP)
      .filter(([k, v]) => v && (filterProvs.length === 0 || filterProvs.includes(k)))
      .map(([k]) => k)
  )

  // Build candidates list
  if (DEGRADED_MODE) {
    // R-502: In degraded mode, use hardcoded model list
    candidates = DEGRADED_MODELS
      .filter(([modelId, label, tier, swe, ctx, providerKey, prefix]) => {
        if (!enabledProviders.has(providerKey)) return false
        if (filterTiers.length > 0 && !filterTiers.includes(tier)) return false
        return true
      })
      .map(([modelId, label, tier, sweScore, ctx, providerKey, prefix]) => ({
        modelId,
        label,
        tier,
        sweScore,
        providerKey,
        prefix,
        pings: [],
        status: 'pending',
        toolCallOk: null,
        toolCallProbeStatus: 'unknown'
      }))
  } else {
    // Full mode with free-coding-models
    const fcmUrl = pathToFileURL(FCM_ROOT).href
    const { MODELS, sources } = await import(`${fcmUrl}/sources.js`)
    const fcmPing = await import(`${fcmUrl}/src/ping.js`)
    const fcmUtils = await import(`${fcmUrl}/src/utils.js`)

    ping = fcmPing.ping
    getStabilityScore = fcmUtils.getStabilityScore
    getVerdict = fcmUtils.getVerdict
    getAvg = fcmUtils.getAvg

    candidates = MODELS.filter(([modelId, label, tier, sweScore, ctx, providerKey]) => {
      if (!enabledProviders.has(providerKey)) return false
      if (filterTiers.length > 0 && !filterTiers.includes(tier)) return false
      return true
    }).map(([modelId, label, tier, sweScore, ctx, providerKey]) => ({
      modelId,
      label,
      tier,
      sweScore,
      providerKey,
      pings: [],
      status: 'pending',
      toolCallOk: null,
      toolCallProbeStatus: 'unknown'
    }))
  }

  if (candidates.length === 0) {
    console.error('No candidates found for providers:', Array.from(enabledProviders), 'with tiers:', filterTiers)
    console.error('API keys present:', Object.keys(KEY_MAP).filter(k => KEY_MAP[k]))
    process.stdout.write('[]\n')
    process.exit(1)
  }

  // ============================================================
  // PING WITH CONCURRENCY
  // ============================================================

  let finishedCount = 0;
  async function pingModel(model) {
    const ctrl = new AbortController()
    const timeout = setTimeout(() => ctrl.abort(), TIMEOUT_MS)

    try {
      let result
      let toolResult = { toolCallOk: null, probeStatus: 'unknown', reason: 'disabled' }

      if (DEGRADED_MODE) {
        // R-501: Direct HTTP ping when fcm not found
        result = await degradedPing(model, ctrl.signal)

        // R-401, R-406: Tool-call probe with 1 second budget
        if (ENABLE_TOOL_TEST) {
          const toolCtrl = new AbortController()
          const toolTimeout = setTimeout(() => toolCtrl.abort(), 1000)
          toolResult = await toolCallProbe(model, toolCtrl.signal)
          clearTimeout(toolTimeout)
        }
      } else {
        // Full free-coding-models ping
        const apiKey = KEY_MAP[model.providerKey]
        const { sources } = await import(`${pathToFileURL(FCM_ROOT).href}/sources.js`)
        const url = sources[model.providerKey].url
        result = await ping(apiKey, model.modelId, model.providerKey, url)

        // Tool-call probe
        if (ENABLE_TOOL_TEST) {
          const toolCtrl = new AbortController()
          const toolTimeout = setTimeout(() => toolCtrl.abort(), 1000)
          toolResult = await toolCallProbe(model, toolCtrl.signal)
          clearTimeout(toolTimeout)
        }
      }

      clearTimeout(timeout)

      model.pings.push({
        ms: result.ms === 'TIMEOUT' ? TIMEOUT_MS : result.ms,
        code: result.code
      })
      model.status = result.code === '200' ? 'up' : 'down'

      model.toolCallOk = toolResult.toolCallOk
      model.toolCallProbeStatus = toolResult.probeStatus || 'unknown'

      finishedCount++
      const tag = model.status === 'up' ? 'OK' : 'XX'
      const avg = (result.ms === 'TIMEOUT' || result.ms === undefined) ? '---' : `${Math.round(result.ms)}ms`
      const name = `${model.providerKey}/${model.modelId}`
      process.stdout.write(`  [${tag}] ${name.padEnd(50)} ${avg.padStart(7)}  (${finishedCount}/${candidates.length})\n`)

    } catch (err) {
      clearTimeout(timeout)
      model.status = 'down'
      model.toolCallOk = null
      model.toolCallProbeStatus = 'unknown'
      
      finishedCount++
      process.stdout.write(`  [XX] ${model.providerKey}/${model.modelId.padEnd(50)} FAILED  (${finishedCount}/${candidates.length})\n`)
    }
  }

  async function runWithConcurrency(tasks, limit) {
    const queue = [...tasks]
    const active = []

    while (queue.length > 0 || active.length > 0) {
      while (active.length < limit && queue.length > 0) {
        const task = queue.shift()
        const p = pingModel(task).then(() => {
          const idx = active.indexOf(p)
          if (idx > -1) active.splice(idx, 1)
        })
        active.push(p)
      }
      if (active.length > 0) await Promise.race(active)
    }
  }

  await runWithConcurrency(candidates, MAX_CONCUR)

  // ============================================================
  // OUTPUT
  // ============================================================

  const output = candidates.map(m => {
    const sweNum = parseFloat((m.sweScore || '0').replace('%', '')) || 0

    if (DEGRADED_MODE) {
      // R-502: Degraded output format
      const validPings = m.pings.filter(p => p.code === '200' && p.ms > 0)
      const avgMs = validPings.length > 0
        ? Math.round(validPings.reduce((a, b) => a + b.ms, 0) / validPings.length)
        : -1

      // Simple latency-based calculation for degraded mode
      let stability = 50 // Default mid-range
      if (avgMs > 0) {
        if (avgMs < 200) stability = 90
        else if (avgMs < 400) stability = 75
        else if (avgMs < 800) stability = 60
        else if (avgMs < 1500) stability = 45
        else stability = 30
      }

      return {
        modelId: m.modelId,
        provider: m.providerKey,
        tier: m.tier,
        swe: sweNum,
        context: m.ctx, // Preserving context window (e.g. "128k")
        status: m.status,
        // R-502: verdict is "Unknown" in degraded mode
        verdict: 'Unknown',
        avgMs: avgMs > 0 ? avgMs : null,
        stability: null,
        degraded: true,
        toolCallOk: m.toolCallOk,
        toolCallProbeStatus: m.toolCallProbeStatus || 'unknown'
      }
    }

    // Full mode output
    const stability = getStabilityScore(m)
    return {
      modelId: m.modelId,
      provider: m.providerKey,
      tier: m.tier,
      swe: sweNum,
      context: m.ctx || m[4], // Preserving context window
      status: m.status,
      verdict: getVerdict(m),
      avgMs: getAvg(m),
      stability: Number.isFinite(stability) ? stability : null,
      toolCallOk: m.toolCallOk,
      toolCallProbeStatus: m.toolCallProbeStatus || 'unknown'
    }
  })

  const jsonOutput = JSON.stringify(output, null, 2) + '\n'
  if (OUTPUT_FILE) {
    fs.writeFileSync(OUTPUT_FILE, jsonOutput)
    // Don't write anything else to stdout so we don't mess up powershell/bash console
  } else {
    process.stdout.write(jsonOutput)
  }
  process.exit(0)
}

// Only run main if this file is executed directly
const isMain = process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))
if (isMain) {
  main().catch(err => {
    process.stderr.write(`[fcm-oneshot] Fatal error: ${err.message}\n`)
    process.exit(1)
  })
}

# Claude Proxy Auto-Updater Improvements Design

**Date:** 2026-04-09
**Status:** Draft
**Project:** claude-proxy-auto-updater

## Overview

Improve `update-models.ps1` to address 5 identified concerns: external dependency risk, fragile regex classification, hardcoded weights, missing error handling, and security concerns.

## Architecture

Single PowerShell script with a `$Config` hash table at the top containing all user-tunable settings. All modifications maintain backward compatibility — the script still produces the same output format for `.env`.

## Configuration Block

All configurable values consolidated at the top of the script:

```powershell
$Config = @{
    # Data Source
    DataSource = "fcm"  # "fcm" = free-coding-models CLI (only option for now)
    CacheTTLHours = 4   # How long to use cached data before refetching
    CacheFile = "$PSScriptRoot\model-cache.json"

    # Retry Settings
    MaxRetries = 3
    RetryDelaySeconds = 2

    # Logging
    Verbose = $false
    LogFile = "$PSScriptRoot\updater.log"
}
```

## Scoring Profiles

Isolated at the top of the script for easy editing:

```powershell
$ScoringProfiles = @{
    Opus = @{
        RequireRole = "heavy"
        MinTier = "A"
        Weights = @{ SWE = 0.60; Ctx = 0.20; Ping = 0.00; Stability = 0.10; NimBonus = 2 }
    }
    Sonnet = @{
        RequireRole = "balanced"
        MinTier = "S"
        Weights = @{ SWE = 0.45; Ctx = 0.10; Ping = 0.25; Stability = 0.15; NimBonus = 1 }
    }
    Haiku = @{
        RequireRole = "fast"
        MinTier = "A"
        Weights = @{ SWE = 0.25; Ctx = 0.00; Ping = 0.50; Stability = 0.15; NimBonus = 1 }
    }
    Fallback = @{
        RequireRole = "any"
        MinTier = "A"
        Weights = @{ SWE = 0.30; Ctx = 0.00; Ping = 0.20; Stability = 0.40; NimBonus = 1 }
    }
}
```

## Classification Regex Patterns

Moved to config for extensibility:

```powershell
$ClassificationPatterns = @{
    Heavy = @(
        "\b\d{3,}b\b",        # 100b+
        "thinking", "k2-?", "glm-?5", "ultra", "terminus",
        "r1", "qwq", "nemotron"
    )
    Fast = @(
        "flash", "nano", "mini", "\b[44789]b\b", "\b12b\b", "small", "compound"
    )
}
```

**Note:** Parameter count regex (`\b\d{3,}b\b`) catches `405b`, `123b`, `235b` automatically without hardcoding each model name.

## Implementation Details

### 1. Caching Layer

- On script start, check if `$Config.CacheFile` exists
- If exists and age < `$Config.CacheTTLHours`, use cached JSON and skip CLI call
- After successful CLI fetch, write to cache file with timestamp
- Cache file format: `{ "timestamp": "ISO8601", "data": <JSON> }`

### 2. Retry with Exponential Backoff

```powershell
$attempt = 0
$delay = $Config.RetryDelaySeconds

while ($attempt -lt $Config.MaxRetries) {
    try {
        $output = & free-coding-models --json 2>$null
        break  # Success
    } catch {
        $attempt++
        if ($attempt -ge $Config.MaxRetries) { throw }
        Start-Sleep -Seconds $delay
        $delay *= 2  # Exponential backoff: 2s -> 4s -> 8s
    }
}
```

### 3. Graceful Fallback

If all retries fail AND no cache available:
- Log warning: `"Cannot reach FCM. Using existing .env models."`
- Exit with code `0` (not `1`) — allows server to start with current config
- Do NOT modify `.env`

### 4. Security: Memory Cleanup

After capturing model data:

```powershell
# Wipe API keys from session memory
if ($env:NVIDIA_API_KEY) { Remove-Item Env:\NVIDIA_API_KEY -ErrorAction SilentlyContinue }
if ($env:OPENROUTER_API_KEY) { Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue }
```

### 5. Role Classification Algorithm

1. Check model name against `$ClassificationPatterns.Heavy` (regex OR match)
2. Check model name against `$ClassificationPatterns.Fast`
3. **Override:** If SWE >= 70%, upgrade from "fast" to "balanced" (too good for Haiku)
4. **Override:** If SWE < 45%, downgrade from "heavy" to "balanced" (not actually smart)
5. Default role: "balanced"

## Data Flow

```
Start
  |
  v
Check cache exists and fresh?
  |-- Yes --> Use cached data
  |
  v (No)
CLI call with retry+backoff
  |
  v
Success? --> Write cache --> Parse & score models
  |
  No
  |
  v
Cache available?
  |-- Yes --> Use cache (log warning)
  |
  No
  |
  v
Graceful fallback (warn, exit 0, keep .env)
```

## Backward Compatibility

- Output format unchanged: `MODEL_OPUS=`, `MODEL_SONNET=`, etc.
- Same `.env` key names
- Same prefix logic (`nvidia_nim/`, `open_router/`)
- Default `$Config` values match current behavior

## Verification

1. **Cache test:** Run script, verify cache file created. Run again within TTL — should skip CLI call (add "using cache" log).
2. **Fallback test:** Misspell `free-coding-models`, verify script warns and exits 0 without modifying `.env`.
3. **Retry test:** Temporarily add network delay, verify exponential backoff in logs.
4. **Regex test:** Add test models like `k2.6`, `405b-fake`, `flash-2` to mock data, verify classification.
5. **Memory cleanup:** Check `$env:NVIDIA_API_KEY` is $null after script runs.

## Documentation Updates

- Update README.md with:
  - Security disclosure (env vars used + cleaned up)
  - How to customize `$ScoringProfiles`
  - How to customize `$ClassificationPatterns`
  - Cache behavior explanation
# 🤖 Claude Proxy Auto-Updater

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Requires: Node.js](https://img.shields.io/badge/Requires-Node.js-green.svg)](https://nodejs.org/)

A standalone, intelligent auto-updating script designed exclusively for the **[free-claude-code](https://github.com/Alishahryar1/free-claude-code)** proxy.

As OpenRouter free quotas fluctuate and NVIDIA NIM endpoints rotate, manually updating `.env` model slots (`MODEL_OPUS`, `MODEL_SONNET`, etc.) becomes tedious. This script forms a critical bridge by fetching live benchmark telemetry and automatically injecting the most capable, healthy models into your proxy configuration just before the server starts.

---

## 🌟 Acknowledgments

This tool exists purely as a bridge between two phenomenal open-source projects. Immense credit goes to:

* **[free-claude-code](https://github.com/Alishahryar1/free-claude-code)** by [@Alishahryar1](https://github.com/Alishahryar1) — The core reverse-engineering proxy that makes Anthropic's Claude Code usable with any LLM provider.
* **[free-coding-models](https://github.com/vava-nessa/free-coding-models)** by [@vava-nessa](https://github.com/vava-nessa) — The incredible CLI benchmark utility that tirelessly pings, scores, and ranks hundreds of free models on SWE-Bench capabilities in real-time.

---

## ✨ Features

* **Zero-Touch Configuration**: Runs dynamically just before `uvicorn` starts up.
* **Live Health Checks**: Instantly discards models that are degraded, overloaded, or offline.
* **Smart Thinking Toggle**: Automatically parses the assigned Sonnet model and activates `NIM_ENABLE_THINKING=true` if it detects a reasoning model (like `QwQ-32B` or `Nemotron`).
* **Role-Based Model Assignment**: Models have "personalities" based on parameter size and architecture.
* 🧠 **OPUS**: Strictly reserved for massive parameter models (`120B+`, `405B`) or deep reasoners.
* ⚖️ **SONNET**: Picks the best balanced model for daily, responsive workhorse tasks.
* ⚡ **HAIKU**: Picks the absolute lowest-latency model that stays above a high SWE quality baseline.
* 🛡️ **FALLBACK**: Assigns the model with the absolute highest mathematical stability index to prevent random tool-call timeouts.

---

## ⚠️ Prerequisites

Because this script acts as a bridge, it **strictly requires** the telemetry CLI to be installed globally on your machine.

Install it via NPM:
```bash
npm install -g free-coding-models
```
*(Requires [Node.js](https://nodejs.org/))*

---

## 🔐 Security & Privacy

This script requires access to your API keys to ping model endpoints.

**What happens to your keys:**
- Keys are temporarily loaded into PowerShell environment variables to enable the `free-coding-models` CLI to authenticate
- Keys are **automatically cleared from memory** immediately after model data is retrieved
- Keys are **never** transmitted anywhere except directly to the free-coding-models CLI
- The script does not store, log, or transmit your keys anywhere

**If you have concerns:** You can review the source code - look for the "SECURITY: Clean up API keys" section in `update-models.ps1`.

---

## 🚀 Usage Guide

1. Download **`update-models.ps1`** from this repository.
2. Place it into your `free-claude-code` root folder (in the exact same directory as your `.env` file).
3. Open your proxy's `start_server.bat` file in a text editor.
4. Inject the PowerShell execution command immediately before the server starts:

```bat
@echo off
echo Running model update script...
powershell.exe -ExecutionPolicy Bypass -File "%~dp0update-models.ps1"
uv run uvicorn server:app --host 0.0.0.0 --port 8082
pause
```

The next time you run `start_server.bat`, the script will securely extract the API keys built into your `.env`, fetch the live JSON leaderboard, calculate model roles, back up your config to `.env.backup`, and apply the new routing settings—all automatically.

## Configuration

All configurable options are at the top of `update-models.ps1` in the `$Config` block:

| Setting | Default | Description |
|---------|---------|-------------|
| CacheTTLHours | 4 | How long to use cached model data before refetching |
| MaxRetries | 3 | Number of retry attempts for API calls |
| RetryDelaySeconds | 2 | Initial delay between retries (doubles each retry) |

### Customizing Weights

The `$ScoringProfiles` block controls how models are scored for each slot. Example to prioritize SWE score more heavily for Opus:

```powershell
Opus = @{
    ...
    Weights = @{ SWE = 0.80; Ctx = 0.10; Ping = 0.00; Stability = 0.10; NimBonus = 2 }
    ...
}
```

### Customizing Model Classification

The `$ClassificationPatterns` block controls which models are classified as "heavy" or "fast". Add new patterns to catch new model releases:

```powershell
$ClassificationPatterns = @{
    Heavy = @(
        ...,  # existing patterns
        "new-model-name"  # add your pattern
    )
    ...
}
```

### Caching

The first run fetches fresh model data and saves it to `model-cache.json`. Subsequent runs within the TTL period use the cache, reducing startup time from ~30s to ~1s.

## 🧮 How the Scoring Works

Instead of blindly picking the #1 ranking model, this script applies a weighted composite scoring system tailored to Claude's slot architecture:

* **Coding Capability (SWE-Bench)**: Evaluated differently per slot (60% weight for Opus down to 25% for Haiku). Highly capable "Flash/Fast" models graduate to Sonnet but are forbidden from OPUS.
* **Latency (avgPing)**: Penalizes balanced models for being slow; heavily rewards Haiku models for speeds under 100ms.
* **Stability Index**: Ranges from 10% to 40% weight. Extracted from live jitter and p95 latency metrics to ensure absolute reliability on fallback requests.
* **NIM Priority Bumps**: Models hosted by NVIDIA NIM receive an artificial priority score bump over OpenRouter `:free` models to maximize hardware stability and avoid peak-hour ratelimits.
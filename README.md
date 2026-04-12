# 🤖 Claude Proxy Auto-Updater v5.0

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Requires: Node.js](https://img.shields.io/badge/Requires-Node.js-green.svg)](https://nodejs.org/)
[![GitHub stars](https://img.shields.io/github/stars/acedreamer/claude-proxy-auto-updater?style=social)](https://github.com/acedreamer/claude-proxy-auto-updater)

A standalone, telemetry-driven auto-updating system designed exclusively for the **[free-claude-code](https://github.com/Alishahryar1/free-claude-code)** proxy.

Version 5.0 introduces **cross-platform bash support**, **transparent scoring with runner-up tracking**, **ranked candidate lists for failover**, and **automatic tool-call detection**.

---

## 🌟 Acknowledgments

This tool exists purely as a bridge between two phenomenal open-source projects:

* **[free-claude-code](https://github.com/Alishahryar1/free-claude-code)** by [@Alishahryar1](https://github.com/Alishahryar1) — The core reverse-engineering proxy.
* **[free-coding-models](https://github.com/vava-nessa/free-coding-models)** by [@vava-nessa](https://github.com/vava-nessa) — The CLI benchmark utility that provides the telemetry data used for scoring.

---

## ✨ What's New in v5.0

### 🔷 Cross-Platform Support (M1)
- **Linux and macOS support** via `update-models.sh` (POSIX-compatible bash)
- **Windows support** via `update-models.ps1` (PowerShell)
- Single `.env` format works across all platforms

### 🔷 Transparency & Score Breakdown (M2)
- **Why, not just what**: Every run shows detailed score breakdowns
  - SWE contribution, Stability, Latency, NIM bonus
  - Verdict classification, average latency
  - Runner-up model with score delta
- **Failover ready**: `model-candidates.json` generated with top-3 candidates per slot

### 🔷 Resilience & Auto-Detection (M3)
- **Graceful degradation**: Works without `free-coding-models` installed (latency-only mode)
- **Automatic tool-call detection**: Live probes determine `toolCallOk` instead of static registry
- Clear warnings and actionable instructions when in degraded mode

---

## ⚠️ Prerequisites

| Component | Purpose | Fallback if Missing |
|-----------|---------|---------------------|
| **Node.js** | Run telemetry helper | Required |
| **free-coding-models** | Full scoring with verdicts/stability | Latency-only mode |
| **bash 3.2+** | Linux/macOS support | Windows users use PowerShell |

```bash
# Optional but recommended
npm install -g free-coding-models
```

---

## 🚀 Usage Guide

### Platform Support

| Platform | Script | Status | Install Command |
|----------|--------|--------|-----------------|
| Windows | `update-models.ps1` | ✅ Available | - |
| Linux | `update-models.sh` | ✅ Available | `chmod +x update-models.sh` |
| macOS | `update-models.sh` | ✅ Available | `chmod +x update-models.sh` |

### Quick Start

1. **Download** the files for your platform:
   - Windows: `update-models.ps1` + `fcm-oneshot.mjs`
   - Linux/macOS: `update-models.sh` + `fcm-oneshot.mjs`

2. **Place** into your `free-claude-code` root folder (where `.env` is)

3. **Configure** API keys in `.env`:
   ```bash
   NVIDIA_NIM_API_KEY=your_key_here
   OPENROUTER_API_KEY=your_key_here
   ```

4. **Run** the script:

#### Windows (PowerShell)
```powershell
.\update-models.ps1
```

Or integrate into `start_server.bat`:
```bat
@echo off
echo Running model update script...
powershell.exe -ExecutionPolicy Bypass -File "%~dp0update-models.ps1"
uv run uvicorn server:app --host 0.0.0.0 --port 8082
pause
```

#### Linux / macOS (Bash)
```bash
chmod +x update-models.sh
./update-models.sh
```

Or integrate into a startup script:
```bash
#!/bin/bash
echo "Running model update script..."
./update-models.sh
uv run uvicorn server:app --host 0.0.0.0 --port 8082
```

---

## 🧪 Dry Run Mode

Preview changes without modifying `.env`:

```powershell
# Windows
.\update-models.ps1 --dry-run

# Linux/macOS
./update-models.sh --dry-run
```

Output shows exactly what would be updated, including:
- Selected models for each slot
- Score breakdowns
- `NIM_ENABLE_THINKING` setting

---

## 🧮 How Scoring Works

The v5 engine uses four weighted profiles:

| Slot | Weight Profile | Best For | Priority |
|------|---------------|----------|----------|
| 🧠 **OPUS** | SWE: 50%, Stab: 25%, Lat: 5%, NIM: 1.5x | Complex tasks | High SWE + tool support |
| ⚖️ **SONNET** | SWE: 35%, Stab: 25%, Lat: 20%, NIM: 1.0x | Daily coding | Balanced |
| ⚡ **HAIKU** | SWE: 10%, Stab: 20%, Lat: 60%, NIM: 0.5x | Fast responses | Sub-200ms latency |
| 🛡️ **FALLBACK** | SWE: 30%, Stab: 40%, Lat: 15%, NIM: 1.0x | Always available | Highest stability |

### Example Output

```
============= MODEL SELECTION ============================
SLOT       | MODEL                                | SCORE  | VERDICT | LAT(ms) | Runner-up
==========================================================================================
OPUS       | nvidia_nim/deepseek-v3-0324        |   87.4 | Normal  |    450 | kimi-k2.5 (Δ-3)
SONNET     | open_router/deepseek-r1:free         |   74.1 | Normal  |    380 | deepseek-v3 (Δ-5)
HAIKU      | nvidia_nim/llama-3.1-8b-instruct   |   58.2 | Normal  |    180 | llama-3.2-3b (Δ-2)
FALLBACK   | nvidia_nim/deepseek-v3-0324        |   82.3 | Normal  |    450 | none

============= SCORE BREAKDOWN ============================
SLOT       |    SWE |   STAB |    LAT |    NIM |  TOTAL
==========================================================
OPUS       |   42.5 |   18.1 |    4.2 |   12.0 |   87.4
SONNET     |   29.0 |   15.0 |   11.3 |    0.0 |   74.1
HAIKU      |    8.0 |   12.0 |   30.0 |    0.0 |   58.2
FALLBACK   |   25.0 |   40.0 |    9.0 |    0.0 |   82.3
```

---

## 📁 Failover with model-candidates.json

Each run generates `model-candidates.json` alongside the `.env`:

```json
{
  "opus": [
    {"idx": 0, "model": "deepseek-v3-0324", "prefix": "nvidia_nim/deepseek-ai/deepseek-v3-0324", "score": 87.4, "verdict": "Normal"},
    {"idx": 3, "model": "kimi-k2.5", "prefix": "nvidia_nim/moonshotai/kimi-k2.5", "score": 84.3, "verdict": "Normal"},
    {"idx": 1, "model": "deepseek-v3.2", "prefix": "nvidia_nim/deepseek-ai/deepseek-v3.2", "score": 82.1, "verdict": "Normal"}
  ],
  "sonnet": [...],
  "haiku": [...],
  "fallback": [...]
}
```

This enables proxy-side failover to #2 or #3 if the primary model degrades.

---

## ♻️ Graceful Degradation

If `free-coding-models` is not installed:

```
[fcm-oneshot] DEGRADED MODE: free-coding-models not found.
 Install for full features: npm install -g free-coding-models
 Continuing with latency-only HTTP pings...

[WARN] free-coding-models not found. Install with: npm install -g free-coding-models for full scoring.
```

The script continues with:
- Direct HTTP ping (no verdict/stability data)
- Latency-only scoring
- `verdict: "Unknown"`, `stability: null`
- Still produces valid `.env` update

---

## 🛠️ Architecture

```
                    ┌─────────────────────────────────────┐
                    │      Claude Proxy Auto-Updater      │
                    │              v5.0                     │
                    └─────────────────────────────────────┘
                                      │
           ┌──────────────────────────┼──────────────────────────┐
           ▼                          ▼                          ▼
   ┌──────────────┐         ┌──────────────────┐      ┌──────────────┐
   │ update-models│         │  fcm-oneshot.mjs │      │ update-models│
   │      .sh     │         │  (Node.js helper)│      │     .ps1     │
   └──────────────┘         └──────────────────┘      └──────────────┘
         │                            │
         └────────────────────────────┘
                      │
         ┌────────────┴────────────┐
         ▼                         ▼
┌─────────────────────┐   ┌───────────────────┐
│ FULL MODE (fcm      │   │ DEGRADED MODE     │
│ installed)          │   │ (direct HTTP)     │
│ • Real telemetry      │   │ • Latency only    │
│ • Stability scores    │   │ • Unknown verdict │
│ • Verdicts            │   │ • Still works     │
│ • Tool-call probes    │   │                   │
└─────────────────────┘   └───────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│ Providers: NVIDIA NIM + OpenRouter (Free) │
└─────────────────────────────────────────────┘
```

---

## 🔐 Security

- **Local Execution**: No API keys sent to external servers
- **Telemetry Isolation**: Keys passed only to configured inference endpoints
- **Cleanup**: API keys unset from memory immediately after use
- **No Data Retention**: `model-cache.json` is local-only, `.gitignore`-d

---

## 📝 Project Structure

```
claude-proxy-auto-updater/
├── README.md                 # This file
├── PRD.md                    # Product Requirements Document
├── update-models.sh          # Linux/macOS entry point (M1)
├── update-models.ps1         # Windows entry point
├── fcm-oneshot.mjs           # Node.js telemetry helper (M3)
├── tests/
│   └── update-models.sh.test # Unit tests for bash functions
├── .env                      # Your API keys (never commit!)
├── .gitignore               # Ignores .env, model-cache.json
├── model-cache.json         # Cached telemetry (auto-generated)
└── model-candidates.json    # Top-3 candidates per slot (M2)
```

---

## ✅ Compliance

| Requirement | Status | Note |
|-------------|--------|------|
| R-101 Cross-platform bash | ✅ | `update-models.sh` on Linux/macOS |
| R-102 fcm-oneshot universal | ✅ | Works on all platforms |
| R-201 Score breakdown | ✅ | Detailed component output |
| R-203 Runner-up tracking | ✅ | Δ shown per slot |
| R-301 Candidates JSON | ✅ | Top-3 per slot, valid JSON |
| R-401 Tool-call probe | ✅ | Minimal request, 1s budget |
| R-501 Degraded mode | ✅ | Works without fcm installed |
| R-503 Degraded warning | ✅ | Install instructions shown |

---

## 🙏 Contributing

This project directly implements the PRD specifications. Feature requests should align with:

1. **G1-G5 goals** from the PRD
2. **P0/P1 priorities** as documented
3. **Success metrics** (≤3 setup steps, 0 manual registry edits)

---

## 📜 License

MIT © 2025 acedreamer

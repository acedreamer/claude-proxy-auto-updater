# 🤖 Claude Proxy Auto-Updater v4.0

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Requires: Node.js](https://img.shields.io/badge/Requires-Node.js-green.svg)](https://nodejs.org/)

A standalone, telemetry-driven auto-updating system designed exclusively for the **[free-claude-code](https://github.com/Alishahryar1/free-claude-code)** proxy.

Version 4.0 introduces a fundamental shift in how models are selected. Instead of simple API list fetching, this script now uses a high-performance Node.js helper (`fcm-oneshot.mjs`) to perform real-time inference pings, allowing it to judge models based on empirical latency, stability, and "verdict" classifications.

---

## 🌟 Acknowledgments

This tool exists purely as a bridge between two phenomenal open-source projects:

* **[free-claude-code](https://github.com/Alishahryar1/free-claude-code)** by [@Alishahryar1](https://github.com/Alishahryar1) — The core reverse-engineering proxy.
* **[free-coding-models](https://github.com/vava-nessa/free-coding-models)** by [@vava-nessa](https://github.com/vava-nessa) — The CLI benchmark utility that provides the telemetry data used for scoring.

---

## ✨ v4.0 New Features

* **Real Telemetry**: Uses `free-coding-models` internals to measure real round-trip inference latency.
* **Stability Scoring**: Models are ranked by a composite stability score (0-100) derived from p95 latency, jitter, and uptime.
* **Verdict Filtering**: Instantly discards models classified as "Spiky", "Overloaded", or "Slow" for tool-sensitive slots.
* **Smart Thinking Mode**: Automatically detects genuine reasoning models (like DeepSeek-R1 or GLM-4-Thinking) and activates `NIM_ENABLE_THINKING=true`.
* **Registry-Driven Registry**: Uses a built-in `$ModelCaps` registry to manage tool-use capability (`toolCallOk`) and reasoning support.

---

## ⚠️ Prerequisites

1. **free-coding-models**: Must be installed globally or locally.
   ```bash
   npm install -g free-coding-models
   ```
2. **Node.js**: Required to run the `fcm-oneshot.mjs` telemetry helper.

---

## 🚀 Usage Guide

1. Download **`update-models.ps1`** and **`fcm-oneshot.mjs`** from this repository.
2. Place both files into your `free-claude-code` root folder (where your `.env` is).
3. Update your `start_server.bat` to run the script:

```bat
@echo off
echo Running model update script...
powershell.exe -ExecutionPolicy Bypass -File "%~dp0update-models.ps1"
uv run uvicorn server:app --host 0.0.0.0 --port 8082
pause
```

---

## 🧮 How Scoring Works

The v4 engine uses four distinct weighing profiles:

* 🧠 **OPUS**: Prioritizes high SWE-Bench score + high context size.
* ⚖️ **SONNET**: Balanced profile for daily coding.
* ⚡ **HAIKU**: Strictly prioritizes the lowest average latency (sub-200ms target).
* 🛡️ **FALLBACK**: Prioritizes the absolute highest stability score to ensure a fallback path is always open.

---

## 🔐 Security

- **Local Execution**: No API keys are sent to external servers; telemetry happens via local Node.js calls.
- **Cleanup**: API keys are cleared from session memory immediately after telemetry is finished.
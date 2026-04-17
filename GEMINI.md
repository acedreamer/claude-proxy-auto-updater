# GEMINI.md - Claude Proxy Auto-Updater

## Project Overview
`claude-proxy-auto-updater` is a robust, cross-platform tool designed to optimize the performance of the `free-claude-code` proxy by automatically selecting the highest-performing AI models available at startup. It replaces static model configurations with dynamic, data-driven selections based on real-time telemetry from providers like NVIDIA NIM and OpenRouter.

The tool categorizes models into four functional slots:
- **OPUS**: Highest quality, heavy reasoning tasks.
- **SONNET**: Balanced performance for general coding.
- **HAIKU**: Low latency for lightweight queries.
- **FALLBACK**: High-stability backup model.

## Key Technologies
- **PowerShell 5.1+**: Primary implementation for Windows environments.
- **Bash 3.2+**: Native implementation for Linux and macOS.
- **Node.js (16+)**: Powers `fcm-oneshot.mjs` for model telemetry and tool-call probing.
- **free-coding-models**: (Optional) npm package used for advanced verdict and stability metrics.

## Architecture
- **Main Drivers**: `update-models.ps1` (PowerShell) and `update-models.sh` (Bash) manage the end-to-end flow: configuration, telemetry triggering, scoring, and `.env` updates.
- **Telemetry Layer**: `fcm-oneshot.mjs` executes pings and capability probes (e.g., tool-calling support) against AI endpoints.
- **Auto-Detection System**: Located in `src/auto-detection/`, this system dynamically evaluates model roles and capabilities, reducing the need for manual registry updates.
- **Data Persistence**:
  - `.env`: Stores the final model selections used by the proxy.
  - `model-cache.json`: Caches telemetry results (default TTL: 45m) to accelerate subsequent runs.
  - `model-candidates.json`: Records the top-3 ranked models per slot for transparency and failover logic.

## Building and Running
This project consists of scripts and does not require a formal build step.

### Key Commands
- **Run Updater (Windows)**: `.\update-models.ps1`
- **Run Updater (Linux/macOS)**: `./update-models.sh`
- **Preview Changes**: Add `--dry-run` or `-DryRun` to avoid modifying `.env`.
- **Tool-Call Probing**: Add `--tool-test` to force live capability verification.
- **Run Tests**: `.\run-tests.ps1` (PowerShell) executes the comprehensive test suite.

## Development Conventions
- **Compatibility**: All changes must maintain compatibility with PowerShell 5.1 (Windows 10/11 defaults) and Bash 3.2 (macOS default).
- **Graceful Degradation**: Ensure scripts remain functional (latency-only mode) even if `free-coding-models` is not installed globally.
- **Score Transparency**: Maintain the score breakdown table output to provide users with clear rationale for model selections.
- **Security**: Never commit `.env` or files containing telemetry data to version control.
- **Testing**: New logic or scoring adjustments should be verified using the existing Pester-based test suite in the `tests/` directory.

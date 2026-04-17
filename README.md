# Claude Proxy Auto-Updater

[![Version](https://img.shields.io/badge/version-5.0-blue.svg)](https://github.com/acedreamer/claude-proxy-auto-updater)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE.svg)](https://docs.microsoft.com/powershell/)
[![Bash](https://img.shields.io/badge/Bash-3.2+-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> **Intelligent model selection for free-claude-code proxy — automatically picks the best available AI models at startup.**

## What It Does

The Claude Proxy Auto-Updater connects to free AI model providers (NVIDIA NIM and OpenRouter) in real-time, measures actual performance metrics (latency, stability, SWE bench scores), and automatically selects the optimal models for each proxy slot:

- **OPUS** — Heavy reasoning tasks requiring the highest quality
- **SONNET** — Balanced performance for general coding work
- **HAIKU** — Fast responses for lightweight queries
- **FALLBACK** — Reliable backup when primary models are unavailable

## Why Use It?

Free AI model availability changes constantly. Instead of manually testing and configuring models every session, this tool:

- Measures real-time latency, stability scores, and verdicts (Perfect/Normal/Slow/Spiky/Overloaded)
- Applies intelligent scoring based on SWE-bench performance, latency, and uptime
- Automatically promotes/demotes models based on live telemetry
- Provides transparent score breakdowns so you know *why* each model was selected
- Works on Windows (PowerShell), Linux, and macOS (Bash)

## Key Features

| Feature | Description |
|---------|-------------|
| Real-Time Telemetry | Pings models via `free-coding-models` to get actual latency, stability, and verdict data |
| Smart Scoring | Data-driven algorithm weighing SWE-bench scores, stability, latency, and provider bonuses |
| Auto-Detection | Dynamically detects tool-call support and role classifications without manual registry edits |
| Cross-Platform | Native PowerShell 5.1+ for Windows, POSIX Bash 3.2+ for Linux/macOS |
| Score Transparency | Prints detailed score breakdown with runner-up models for every slot |
| Dry-Run Mode | Preview selections without modifying your `.env` file |
| Intelligent Caching | Caches results for configurable TTL to reduce startup time from ~30s to ~1s |
| Graceful Degradation | Works even without `free-coding-models` (latency-only mode) |

## Installation

### Prerequisites

- **Windows**: PowerShell 5.1 or later (included in Windows 10+)
- **Linux/macOS**: Bash 3.2 or later
- **Node.js**: 16+ (required for `fcm-oneshot.mjs`)

### Quick Start

1. **Download the latest release:**
   Go to the [Releases](https://github.com/acedreamer/claude-proxy-auto-updater/releases) page and download the ZIP file for your platform:
   - `claude-proxy-auto-updater-windows.zip` (for Windows)
   - `claude-proxy-auto-updater-linux-macos.zip` (for Linux/macOS)
   
   *Alternatively, clone the repository:*
   ```bash
   git clone https://github.com/acedreamer/claude-proxy-auto-updater.git
   cd claude-proxy-auto-updater
   ```

2. **Run the One-Click Launcher (Windows):**
   Simply double-click `@start_server.bat`. It will automatically:
   - Check for your `.env` file (and create a template if missing)
   - Run the model updater to find the best available models
   - Launch the Claude Proxy server using `uv` (or standard Python)

3. **Install free-coding-models (optional but recommended):**
   ```bash
   npm install -g free-coding-models
   ```

3. **Configure your API keys:**
   Create a `.env` file with your API keys:
   ```bash
   NVIDIA_NIM_API_KEY="your-nvidia-nim-key"
   OPENROUTER_API_KEY="your-openrouter-key"
   ```

### Platform-Specific Setup

#### Windows

```powershell
# Run directly
.\update-models.ps1

# Or with dry-run to preview changes
.\update-models.ps1 -DryRun
```

#### Linux / macOS

```bash
# Make executable (first time only)
chmod +x update-models.sh

# Run
./update-models.sh

# Or with dry-run
./update-models.sh --dry-run
```

## Usage

### Basic Usage

The script automatically updates your `.env` file with the best available models:

```powershell
# Windows
.\update-models.ps1

# Linux/macOS
./update-models.sh
```

### Command-Line Options

| Option | Description |
|--------|-------------|
| `--dry-run` or `-DryRun` | Preview scores and selections without modifying `.env` |
| `--tool-test` | Enable tool-call probing for new model validation |

### Example Output

```
============= MODEL SELECTION ===========================================================================
SLOT       | MODEL                                      | THINK |  SCORE | VERDICT | LAT(ms) | Runner-up
=========================================================================================================
OPUS       | nvidia_nim/nvidia/deepseek-ai/deepseek-v3-0324 | No  |   87.4 | Normal  |     824 | kimi-k2.5 (d-3.1)
SONNET     | open_router/deepseek/deepseek-r1:free      | Yes   |   74.1 | Normal  |    1342 | deepseek-v3 (d-5.9)
HAIKU      | nvidia_nim/nvidia/nvidia/llama-3.2-3b-instruct | No  |   92.3 | Perfect |     156 | llama-3.1-8b (d-8.2)
FALLBACK   | nvidia_nim/nvidia/meta/llama-3.1-405b-instruct | No  |   78.9 | Normal  |     612 | glm4.7 (d-4.3)

============= SCORE BREAKDOWN ============================
SLOT       |    SWE |   STAB |    LAT |    NIM |  TOTAL
==========================================================
OPUS       |   42.5 |   18.1 |    4.2 |   12.0 |   87.4
SONNET     |   29.0 |   15.0 |   11.3 |    0.0 |   74.1
HAIKU      |    5.2 |   12.8 |   65.3 |    4.0 |   92.3
FALLBACK   |   22.1 |   42.5 |    6.3 |    8.0 |   78.9

[OK] .env updated via fcm-oneshot telemetry.
```

## Configuration

All configuration options are at the top of each script:

| Setting | Default | Description |
|---------|---------|-------------|
| `CacheTTLMinutes` | 45 | How long to use cached model data before refreshing |
| `PingTimeoutMs` | 15000 | Timeout per model ping (milliseconds) |
| `Providers` | `nvidia,openrouter` | Comma-separated list of providers to query |
| `TierFilter` | `S+,S,A+,A` | Minimum quality tier to consider |

### Scoring Weights

The scoring algorithm balances four factors:

| Slot | SWE | Stability | Latency | NIM Bonus |
|------|-----|-----------|---------|-----------|
| OPUS | 0.55 | 0.20 | 0.05 | 1.5 |
| SONNET | 0.35 | 0.25 | 0.25 | 1.0 |
| HAIKU | 0.05 | 0.15 | 0.70 | 0.5 |
| FALLBACK | 0.25 | 0.50 | 0.10 | 1.0 |

NVIDIA NIM models receive a bonus due to generally better availability and performance.

### Customizing Weights

Edit the `$Weights` hash table in `update-models.ps1` (or the `init_weights` function in `update-models.sh`) to adjust scoring priorities for your use case.

## Testing

Run the test suite to verify functionality:

```powershell
# Windows - run all tests
.\run-tests.ps1
```

Individual test files are located in:
- `tests/` — Core module tests
- `tests/auto-detection/` — Auto-detection system tests
- `src/auto-detection/tests/` — Component unit tests

## Project Structure

```
claude-proxy-auto-updater/
├── update-models.ps1          # Main PowerShell script (Windows)
├── update-models.sh             # Main Bash script (Linux/macOS)
├── fcm-oneshot.mjs              # Node.js model pinger
├── .env                         # Your API keys (not committed)
├── model-cache.json             # Cached model data (auto-generated)
├── model-candidates.json        # Top-3 candidates per slot (auto-generated)
├── src/
│   └── auto-detection/          # Auto-detection modules
│       ├── AutoDetectionManager.ps1
│       ├── CapabilityRegistry.ps1
│       ├── PerformanceCache.ps1
│       ├── RoleDetector.ps1
│       ├── SafetyManager.ps1
│       └── ToolDetector.ps1
├── tests/                       # Test suite
│   ├── auto-detection/
│   └── *.tests.ps1
└── docs/                        # Documentation
    ├── auto-detection-README.md
    └── superpowers/plans/       # Architecture plans
```

## Contributing

Contributions are welcome. Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Ensure your changes:
- Maintain PowerShell 5.1 compatibility
- Maintain Bash 3.2 compatibility
- Include appropriate tests
- Update documentation as needed

## Troubleshooting

### "No API keys in .env"
Create a `.env` file with at least one provider key:
```bash
NVIDIA_NIM_API_KEY="your-key-here"
# or
OPENROUTER_API_KEY="your-key-here"
```

### "Node.js not found"
Install Node.js 16+ from [nodejs.org](https://nodejs.org/)

### "free-coding-models not found"
The script falls back to degraded mode (latency-only). Install the package for full functionality:
```bash
npm install -g free-coding-models
```

### Cache Issues
Delete `model-cache.json` to force a fresh fetch:
```bash
rm model-cache.json  # Linux/macOS
Remove-Item model-cache.json  # PowerShell
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Built for the [free-claude-code](https://github.com/abetlen/free-claude-code) community
- Leverages [free-coding-models](https://www.npmjs.com/package/free-coding-models) for telemetry
- Special thanks to NVIDIA NIM and OpenRouter for providing free model endpoints

---

**Maintained by:** [@acedreamer](https://github.com/acedreamer)

**Repository:** [acedreamer/claude-proxy-auto-updater](https://github.com/acedreamer/claude-proxy-auto-updater)

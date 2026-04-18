# Claude Proxy Auto-Updater

[![Version](https://img.shields.io/badge/version-6.1-blue.svg)](https://github.com/acedreamer/claude-proxy-auto-updater)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE.svg)](https://docs.microsoft.com/powershell/)
[![Bash](https://img.shields.io/badge/Bash-3.2+-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> **Intelligent model selection for free-claude-code proxy â€” automatically picks the best available AI models at startup.**

## What It Does

The Claude Proxy Auto-Updater connects to free AI model providers (NVIDIA NIM and OpenRouter) in real-time, measures actual performance metrics (latency, stability, SWE bench scores), and automatically selects the optimal models for each proxy slot using a unified Node.js decision engine:

- **OPUS** â€” Heavy reasoning tasks requiring the highest quality
- **SONNET** â€” Balanced performance for general coding work
- **HAIKU** â€” Fast responses for lightweight queries
- **FALLBACK** â€” Reliable backup when primary models are unavailable

## Why Use It?

Free AI model availability changes constantly. Instead of manually testing and configuring models every session, this tool:

- Measures real-time latency, stability scores, and verdicts (Perfect/Normal/Slow/Spiky/Overloaded)
- Applies intelligent scoring based on SWE-bench performance, latency, and uptime
- **Centralized Logic**: Uses a single Node.js source of truth for both Windows and Linux/macOS
- **User Tunable**: Change scoring weights, pins, and bans via a simple `config.json` file
- Provides transparent score breakdowns so you know *why* each model was selected
- Works on Windows (PowerShell), Linux, and macOS (Bash)

## Key Features

| Feature | Description |
|---------|-------------|
| Real-Time Telemetry | Pings models via `fcm-oneshot.mjs` (leveraging `free-coding-models` if available) |
| Unified Brain | `selector.mjs` ensures 100% consistent model selection across all platforms |
| Master Config | Centralized `config.json` for all settings, weights, pins, and bans |
| Auto-Detection | Dynamically detects tool-call support and role classifications |
| Cross-Platform | Native wrappers for PowerShell 5.1+ and POSIX Bash 3.2+ |
| Score Transparency | Detailed score breakdown with runner-up tracking for every slot |
| Dry-Run Mode | Preview selections without modifying your `.env` file |
| Intelligent Caching | Caches results for configurable TTL to reduce startup time from ~30s to ~1s |
| Graceful Degradation | Works even without `free-coding-models` (latency-only mode) |

## Installation

### Prerequisites

- **Windows**: PowerShell 5.1 or later (included in Windows 10+)
- **Linux/macOS**: Bash 3.2 or later
- **Node.js**: 16+ (required for `fcm-oneshot.mjs` and `selector.mjs`)

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

4. **Configure your API keys:**
   Create a `.env` file with your API keys:
   ```bash
   NVIDIA_NIM_API_KEY="your-key-here"
   OPENROUTER_API_KEY="your-key-here"
   ```

`n## Example Output`n`nWhen you run the updater, you get a real-time telemetry ping followed by intelligent slot selection based on actual performance and quality scores:`n`n```text`n======== PINGING MODELS VIA FREE-CODING-MODELS ========`n  Running one-shot ping (timeout: 15000ms per model)...`n  Providers: nvidia,openrouter  |  Tier filter: S+,S,A+,A`n`n  MODEL                                                  VERDICT    AVG      STAB     TIER`n  [OK] nvidia/moonshotai/kimi-k2-instruct-0905            Normal     744ms    96       S`n  [OK] nvidia/qwen/qwen3-next-80b-a3b-thinking            Perfect    272ms    98       S`n  [OK] nvidia/openai/gpt-oss-120b                         Perfect    340ms    98       S`n  ...`n`n============= MODEL SELECTION ===========================================================================       `nSLOT       | MODEL (Short)                          | THINK | SCORE  | VERDICT | LAT(ms) | Runner-up`n=========================================================================================================       `nOPUS       | kimi-k2-instruct-0905(nvidia)          | No    |   72.4 | Normal  |     744 | kimi-k2-instruct(nvidia) (d-0.0)`nSONNET     | llama-4-maverick-17b-128e-instruct(nvidia) | No    |   79.2 | Perfect |     263 | gpt-oss-120b(nvidia) (d-0.7)`nHAIKU      | qwen2.5-coder-32b-instruct(nvidia)     | No    |   86.5 | Perfect |     254 | gpt-oss-20b(nvidia) (d-0.5)`nFALLBACK   | kimi-k2.5(nvidia)                      | No    |   82.9 | Slow    |    1216 | kimi-k2-instruct-0905(nvidia) (d-0.4)`n`n============= SCORE BREAKDOWN ============================`nSLOT       |    SWE |   STAB |    LAT |    NIM |  TOTAL`n==========================================================`nOPUS       |   36.2 |   19.2 |    5.0 |   12.0 |   72.4`nSONNET     |   21.7 |   24.5 |   25.0 |    8.0 |   79.2`nHAIKU      |    2.3 |   14.7 |   65.5 |    4.0 |   86.5`nFALLBACK   |   19.2 |   46.5 |    9.2 |    8.0 |   82.9`n```n## Usage

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

## Configuration

All configuration is managed via `config.json`. If missing, it will be auto-generated on the first run using `config.example.json` as a template.

### Config Sections

- **general**: Cache TTL, providers, tier filters, and timeouts.
- **preferences**:
  - **pins**: Pin a specific model to a slot (e.g., `"opus": "nvidia/deepseek-v3"`).
  - **bans**: Prevent specific models from ever being selected.
- **scoring**: Detailed weights for SWE, Stability, Latency, and NIM bonuses for each slot.

### Example `config.json`

```json
{
  "general": {
    "cache_ttl_minutes": 15,
    "providers": "nvidia,openrouter",
    "tier_filter": "S+,S,A+,A"
  },
  "preferences": {
    "pins": { "opus": null, "sonnet": null, "haiku": null },
    "bans": []
  },
  "scoring": {
    "weights": {
      "opus": { "swe": 0.55, "stab": 0.20, "lat": 0.05, "nim": 1.5 },
      ...
    }
  }
}
```

## Testing

Run the test suite to verify functionality:

```powershell
# Windows - run all tests
.\run-tests.ps1
```

**New in v6.0**: Unified Node.js test runner for the decision engine:
```bash
node --test tests/selector.test.mjs
```

## Project Structure

```
claude-proxy-auto-updater/
â”œâ”€â”€ update-models.ps1          # PowerShell UI Wrapper (Windows)
â”œâ”€â”€ update-models.sh           # Bash UI Wrapper (Linux/macOS)
â”œâ”€â”€ setup.ps1                  # Setup Engine (Windows)
â”œâ”€â”€ setup.sh                   # Setup Engine (Linux/macOS)
â”œâ”€â”€ selector.mjs               # The Brain: Unified decision engine
â”œâ”€â”€ fcm-oneshot.mjs            # Data Collector: Real-time telemetry
â”œâ”€â”€ @start_server.bat          # One-Click Launcher (Windows)
â”œâ”€â”€ config.example.json        # Template for user settings
â”œâ”€â”€ .env                       # Your API keys (not committed)
â”œâ”€â”€ docs/                      # Documentation & Archives
â””â”€â”€ tests/                     # Test suite & Runner
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Open a Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.

---

**Maintained by:** [@acedreamer](https://github.com/acedreamer)


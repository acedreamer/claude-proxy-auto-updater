# Claude Proxy Auto-Updater

[![Version](https://img.shields.io/badge/version-6.2-blue.svg)](https://github.com/acedreamer/claude-proxy-auto-updater)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE.svg)](https://docs.microsoft.com/powershell/)
[![Bash](https://img.shields.io/badge/Bash-3.2+-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> **UX-First Model Selection — Intelligent deployment engine that understands model tiers and capabilities.**

![Demo](./f.gif)

## What It Does

The Claude Proxy Auto-Updater is an intelligent deployment engine for the `free-claude-code` proxy. It goes beyond simple benchmarks by understanding the physical differences between model tiers (Flash vs. MoE vs. Flagship), ensuring each proxy slot is filled by a model physically capable of that role.

- **OPUS** — **Flagship Only**: 300B+ giants and heavy reasoning models. "Flash" models are legally barred.
- **SONNET** — **Workhorse**: Balanced performance, with a scoring bonus for MoE (Mixture-of-Experts) models.
- **HAIKU** — **Near-Instant**: Heavily prioritizes low-latency "Flash" models for lightweight queries.
- **FALLBACK** — **High Stability**: Reliable backup with a focus on uptime and consistency.

## Why Use It?

Free AI model availability is volatile. This tool replaces "benchmark chasing" with "UX-First Engineering":

- **Tier Enforcement**: Hard bans prevent weak "Flash" models from occupying the Opus/Sonnet slots, even if they have high benchmark scores.
- **Auto-Thinking**: Automatically detects reasoning models and toggles `ENABLE_THINKING` in your `.env` file—zero configuration required.
- **Density Preference**: Grants a **+60 pts bonus** to "Super-Flagship" models in the Opus slot for maximum intelligence.
- **Mean Probing**: Validates tool-call capabilities by rejecting empty responses and malformed JSON, preventing infinite loops.
- **Context Aware**: Captures and respects `context_window` limits (e.g., 128k) during selection.

## Key Features

| Feature | Description |
|---------|-------------|
| Slot-Role Intelligence | `selector.mjs` enforces tier-based selection (Utility vs. Standard vs. Flagship) |
| Automated Thinking | Auto-toggle for `ENABLE_THINKING` when a reasoning model wins the Opus slot |
| Anti-Hallucination | Strict functional validation rejects models that fail live tool-call probes |
| MoE/Flash Bonuses | Architecture-aware scoring prioritizes the right model types for each slot |
| Unified Brain | Single Node.js source of truth for consistent selection across Windows/Linux/macOS |
| Score Transparency | Detailed breakdown showing why a model was chosen (SWE, Stab, Lat, Tier bonuses) |
| Intelligent Caching | 45m default TTL reduces startup time from ~30s to ~1s |
| Master Config | Centralized `config.json` for all settings, weights, pins, and bans |

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

## Example Output

The updater provides a real-time telemetry ping followed by intelligent slot selection. Note the automatic detection of "Thinking" capabilities:

```text
======== PINGING MODELS VIA FREE-CODING-MODELS ========
  Running one-shot ping (timeout: 15000ms per model)...
  Providers: nvidia,openrouter  |  Tier filter: S+,S,A+,A

  MODEL                                                  VERDICT    AVG      STAB     TIER
  [OK] nvidia/moonshotai/kimi-k2-instruct-0905            Normal     744ms    96       S
  [OK] nvidia/qwen/qwen3-next-80b-a3b-thinking            Perfect    272ms    98       S
  [OK] nvidia/openai/gpt-oss-120b                         Perfect    340ms    98       S
  ...

============= MODEL SELECTION ===========================================================================       
SLOT       | MODEL (Short)                          | THINK | SCORE  | VERDICT | LAT(ms) | Runner-up
=========================================================================================================       
OPUS       | qwen3-next-80b(nvidia)                 | YES   |  132.4 | Perfect |     272 | gpt-oss-120b(nvidia) (d-10.0)
SONNET     | deepseek-v3(nvidia)                    | No    |   94.2 | Perfect |     310 | mixtral-8x22b(nvidia) (d-2.7)
HAIKU      | qwen2.5-coder-32b(nvidia)              | No    |   86.5 | Perfect |     254 | gpt-oss-20b(nvidia) (d-0.5)
FALLBACK   | llama-3.3-70b-instruct(nvidia)         | No    |   82.9 | Normal  |     416 | kimi-k2-instruct(nvidia) (d-0.4)

============= SCORE BREAKDOWN ============================
SLOT       |    SWE |   STAB |    LAT |    TIER |  TOTAL
==========================================================
OPUS       |   36.2 |   19.2 |   17.0 |   60.0* |  132.4  (*Super-Flagship Bonus)
SONNET     |   35.7 |   24.5 |   24.0 |   10.0^ |   94.2  (^MoE Architecture Bonus)
HAIKU      |    2.3 |   14.7 |   65.5 |    4.0  |   86.5
FALLBACK   |   19.2 |   46.5 |    9.2 |    8.0  |   82.9
```

## Migration Note: ENABLE_THINKING
As of v6.2, the legacy `NIM_ENABLE_THINKING` has been fully migrated to the new `ENABLE_THINKING` standard. The updater now handles this toggle automatically based on the Opus slot selection.

## Usage
### Basic Usage

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
| `--tool-test` | Force live tool-call capability verification (bypasses cache) |

## Configuration

All configuration is managed via `config.json`.

- **general**: Cache TTL (default 45m), providers, and tier filters.
- **preferences**:
  - **pins**: Pin a specific model to a slot.
  - **bans**: Prevent specific models from ever being selected.
- **scoring**: Detailed weights for SWE, Stability, Latency, and Architecture bonuses.

## Testing

```powershell
# Windows
.\run-tests.ps1

# Decision Engine
node --test tests/selector.test.mjs
```

## License

MIT License. See [LICENSE](LICENSE) for details.

---

**Maintained by:** [@acedreamer](https://github.com/acedreamer)


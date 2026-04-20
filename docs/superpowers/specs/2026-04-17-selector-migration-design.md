# Design Spec: Claude Proxy Auto-Updater v6.0 (The Brain Migration)

**Status:** Approved  
**Version:** 6.0  
**Author:** Gemini CLI  

## 1. Overview
v6.0 refactors the project from "Shell-managed intelligence" to "Node-managed intelligence." The goal is to eliminate desync between PowerShell and Bash by moving all scoring, slot assignment, and user preference logic into a single Node.js source of truth: `selector.mjs`.

## 2. Architecture
The system follows a three-stage pipeline:
1.  **Collector (`fcm-oneshot.mjs`)**: Fetches raw telemetry and writes `model-cache.json`.
2.  **The Brain (`selector.mjs`)**: Reads `model-cache.json` and `config.json`. Performs eligibility filtering, scoring, and slot assignment. Outputs a unified `selection-result.json` (to stdout).
3.  **UI/Apply (Shell Wrappers)**: Captures JSON from the brain, prints tables, and updates the `.env` file.
## 3. The Master Config (`config.json`)
The central settings file for the entire application. A `config.example.json` will be provided for reference.

```json
{
  "general": {
    "cache_ttl_minutes": 15,
    "providers": "nvidia,openrouter",
    "tier_filter": "S+,S,A+,A",
    "timeout_ms": 15000
  },
  "preferences": {
    "pins": { "opus": null, "sonnet": null, "haiku": null },
    "bans": []
  },
  "scoring": {
    "weights": {
      "opus": { "swe": 0.55, "stab": 0.20, "lat": 0.05, "nim": 1.5, "target_lat": 1500, "penalty": 0.01 },
      "sonnet": { "swe": 0.35, "stab": 0.25, "lat": 0.25, "nim": 1.0, "target_lat": 500, "penalty": 0.04 },
      "haiku": { "swe": 0.05, "stab": 0.15, "lat": 0.70, "nim": 0.5, "target_lat": 200, "penalty": 0.12 },
      "fallback": { "swe": 0.25, "stab": 0.50, "lat": 0.10, "nim": 1.0, "target_lat": 800, "penalty": 0.02 }
    }
  }
}
```

## 4. `selector.mjs` Functional Requirements
- **Auto-Config & Healing**: 
    - Create `config.json` with defaults if it doesn't exist.
    - If `config.json` exists but is missing keys (e.g. from a version update), automatically merge missing defaults into the user's file.
- **Eligibility Filter**:
...
    - Remove models in the `bans` list.
    - Slot-specific rules (e.g., Opus/Sonnet must not be "Thinking" models).
    - Status must be "up".
- **Scoring Engine**:
    - Calculate scores based on the weights in `config.json`.
    - **Pins**: Add a +1000 score bonus to any model pinned for that slot (if it's Up).
- **Slot Assignment**:
    - Pick winner for Opus.
    - Pick winner for Sonnet (must not be the Opus winner).
    - Pick winner for Haiku (must not be Opus/Sonnet winner).
    - Pick winner for Fallback (must meet stability threshold).
- **Output**: JSON string to stdout with the following structure:
  ```json
  {
    "slots": {
      "opus": { "winner": {}, "runner_up": {}, "breakdown": {} },
      ...
    },
    "is_degraded": false,
    "is_thinking": true
  }
  ```

## 5. UI Requirements
Shell scripts will remain responsible for:
- Printing the colorful tables (Model Selection & Score Breakdown).
- Updating the `.env` file keys: `MODEL_OPUS`, `MODEL_SONNET`, `MODEL_HAIKU`, `MODEL`, `ENABLE_THINKING`.

## 6. Success Criteria
- v6.0 produces identical selections on Windows and Linux for the same cache/config data.
- User can change the winning model by editing `config.json` without touching script code.
- Tool-call probe values from telemetry are used for eligibility.

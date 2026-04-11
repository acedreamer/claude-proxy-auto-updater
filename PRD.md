# Product Requirements Document
## Claude Proxy Auto-Updater — v5.0

**Status:** Draft  
**Date:** 2026-04-11  
**Author:** acedreamer  
**Repo:** `acedreamer/claude-proxy-auto-updater`

---

## 1. Problem Statement

`claude-proxy-auto-updater` intelligently selects the best free AI models for the `free-claude-code` proxy at server startup. While v4.0 introduced real telemetry and stability scoring, several friction points limit its usefulness:

- **Windows-only** — PowerShell locks out Linux/macOS users entirely
- **Opaque decisions** — users see *what* model was chosen but not *why*
- **Single-winner selection** — no failover path if the chosen model degrades mid-session
- **Manual capability registry** — every new model requires editing `$ModelCaps` by hand
- **Static at startup** — models aren't re-evaluated while the server is running
- **Hard dependency** on `free-coding-models` npm package causes setup failures

---

## 2. Goals

| # | Goal |
|---|---|
| G1 | Make the tool cross-platform (Windows + Linux + macOS) |
| G2 | Surface *why* each model was selected, not just which one |
| G3 | Enable proxy self-healing via ranked candidate lists per slot |
| G4 | Eliminate manual `$ModelCaps` maintenance |
| G5 | Reduce required setup steps to get started |

---

## 3. Non-Goals

- Building a UI dashboard (deferred to a future version)
- Replacing or forking `free-claude-code` or `free-coding-models`
- Supporting providers beyond NVIDIA NIM and OpenRouter in this version
- Running as a persistent background daemon

---

## 4. User Personas

### 4a. "Quick-start User" — Alex
Wants to clone, drop in two files, and have it work. Doesn't want to install npm packages or edit config. Will abandon setup if it requires more than 3 steps.

### 4b. "Power User" — Sam
Runs the proxy daily for coding sessions. Wants to know which model is being used and why. Wants to tune weights, add new models without editing source code, and see when their preferred model degrades.

### 4c. "Linux/Mac User" — Jordan
Uses `free-claude-code` on Ubuntu or macOS. Currently completely blocked — no PowerShell, no path forward.

---

## 5. Requirements

### 5.1 Cross-Platform Support *(G1, Jordan)*
**Priority: P0**

| ID | Requirement |
|---|---|
| R-101 | A `update-models.sh` bash script must be provided with feature parity to `update-models.ps1` |
| R-102 | `fcm-oneshot.mjs` must work unchanged on all three platforms (it already does — no changes needed) |
| R-103 | README must document platform-specific setup steps for Windows (PowerShell), Linux (bash), and macOS (bash) |
| R-104 | Both scripts must read from the same `.env` file format and write the same output keys |

**Acceptance criteria:** A fresh Ubuntu 22.04 machine can run `update-models.sh` and produce a valid updated `.env` with no additional steps beyond `npm install -g free-coding-models`.

---

### 5.2 Score Breakdown & Explanation Output *(G2, Sam)*
**Priority: P0**

| ID | Requirement |
|---|---|
| R-201 | After model selection, print a summary table showing the score breakdown for the chosen model in each slot |
| R-202 | Breakdown must show individual score components: SWE contribution, stability contribution, latency contribution, NIM bonus |
| R-203 | Print the runner-up model for each slot with its score delta vs. the winner |
| R-204 | Output must include the verdict, avg latency, and stability score for each winner |

**Example output:**
```
OPUS   → nvidia/deepseek-ai/deepseek-v3-0324   score=87.4
         SWE=42.5  Stab=18.1  Lat=4.2  NIM=12.0  | Runner-up: kimi-k2.5 (Δ-3.1)

SONNET → openrouter/deepseek/deepseek-r1:free  score=74.1
         SWE=29.0  Stab=15.0  Lat=11.3  NIM=0    | Runner-up: deepseek-v3 (Δ-5.9)
```

**Acceptance criteria:** Running the script always produces the breakdown table; no flags required to see it.

---

### 5.3 Ranked Candidate List (Top-3 Per Slot) *(G3, Sam)*
**Priority: P1**

| ID | Requirement |
|---|---|
| R-301 | In addition to updating the `.env`, write a `model-candidates.json` sidecar file with the top-3 candidates for each slot, including scores |
| R-302 | JSON schema: `{ "opus": [{ "model": "...", "prefix": "...", "score": 87.4, "verdict": "Normal" }, ...], "sonnet": [...], ... }` |
| R-303 | If the proxy or external tooling wants to fail over, it reads `model-candidates.json` for the #2 or #3 option |
| R-304 | `model-candidates.json` must be updated on every successful run (cache hits included) |
| R-305 | `model-candidates.json` must be listed in `.gitignore` (it contains local telemetry, not source) |

**Acceptance criteria:** After a run, `model-candidates.json` exists, is valid JSON, and contains at least the top-1 entry per slot (top-3 when enough qualifying models exist).

---

### 5.4 Auto-Detection of Tool-Call Support *(G4, Sam)*
**Priority: P1**

| ID | Requirement |
|---|---|
| R-401 | During the ping phase, `fcm-oneshot.mjs` must send a minimal tool-call test request alongside the latency ping |
| R-402 | A model passes tool-call detection if the response includes a valid `tool_use` block with no error |
| R-403 | The `toolCallOk` field in the JSON output from `fcm-oneshot.mjs` must be set based on this live probe, not the static registry |
| R-404 | The static `$ModelCaps` registry in `update-models.ps1` must be retained as an **override/hint layer** only — auto-detected values take precedence |
| R-405 | If the tool-call probe times out or errors, fall back to the static registry value (if present) or assume `toolCallOk=false` |
| R-406 | The tool-call probe must add no more than 1 additional second per model to the total ping time (reuse the existing connection where possible) |

**Acceptance criteria:** Adding a brand-new model to `MODELS` in `free-coding-models/sources.js` (without touching `$ModelCaps`) results in correct `toolCallOk` detection without any script edits.

---

### 5.5 Reduced Setup Friction *(G5, Alex)*
**Priority: P1**

| ID | Requirement |
|---|---|
| R-501 | If `free-coding-models` is not installed, `fcm-oneshot.mjs` must gracefully degrade to a direct HTTP ping (measuring latency only, no verdict/stability) |
| R-502 | In degraded mode, verdict is set to `"Unknown"`, stability to `null`, and only latency-based scoring is used |
| R-503 | Both scripts must print a clear, actionable warning when running in degraded mode: `"[WARN] free-coding-models not found. Install with: npm install -g free-coding-models for full scoring."` |
| R-504 | In degraded mode, the script must still succeed and write a best-effort `.env` update |

**Acceptance criteria:** Running `update-models.ps1` on a machine with only Node.js (no `free-coding-models`) produces a valid `.env` update and a non-fatal warning, not a crash.

---

### 5.6 `--dry-run` Mode *(G2, Sam)*
**Priority: P2**

| ID | Requirement |
|---|---|
| R-601 | Both scripts must accept a `--dry-run` flag |
| R-602 | In dry-run mode, all scoring and selection runs normally but `.env` is NOT modified |
| R-603 | Output must clearly state `"[DRY RUN] .env not modified"` at the end |
| R-604 | `model-candidates.json` IS written in dry-run mode (it's not sensitive) |
| R-605 | Cache IS written/used in dry-run mode |

**Acceptance criteria:** `.\update-models.ps1 --dry-run` leaves `.env` unchanged but prints the full score table and winner selections.

---

## 6. Out-of-Scope (Explicitly Deferred)

| Feature | Reason |
|---|---|
| Web dashboard | Adds a runtime server dependency; significant effort for niche benefit |
| Discord/desktop notifications | Platform-specific, lower priority than core reliability |
| Background daemon / hot-swap | Requires persistent process management; out of scope for a startup script |
| CI/CD nightly model PR | Nice-to-have; depends on repo-specific GitHub Actions setup |
| Additional providers (Groq, Together, etc.) | Requires upstream `free-coding-models` support first |

---

## 7. Technical Constraints

- `update-models.ps1` must stay compatible with PowerShell 5.1+ (no PS7-only syntax)
- `update-models.sh` must be POSIX-compatible bash (no bashisms beyond `bash 3.2` for macOS support)
- `fcm-oneshot.mjs` must stay as a single file (no new npm dependencies added)
- All changes must be backward-compatible: existing `.env` keys and value format unchanged
- No new files committed to the repo that contain user API keys or telemetry data

---

## 8. Success Metrics

| Metric | Target |
|---|---|
| Linux/macOS users unblocked | 100% of `free-claude-code` platforms supported |
| Setup steps for new user | ≤ 3 steps to first successful run |
| Time to understand model selection | < 30 seconds (readable from score breakdown table) |
| Manual `$ModelCaps` edits needed for new models | 0 (auto-detected) |
| Script crash rate when `free-coding-models` missing | 0% (graceful degradation) |

---

## 9. Milestones

| Milestone | Scope | Priority |
|---|---|---|
| **M1 — Foundation** | Cross-platform bash script (R-101–104) + dry-run mode (R-601–605) | P0 |
| **M2 — Transparency** | Score breakdown output (R-201–204) + ranked candidates JSON (R-301–305) | P0/P1 |
| **M3 — Resilience** | Graceful degraded mode (R-501–504) + auto tool-call detection (R-401–406) | P1 |

---

## 10. Open Questions

| # | Question | Owner |
|---|---|---|
| OQ-1 | Should `model-candidates.json` be read by `free-claude-code` directly, or is it purely for future tooling? Determines if a schema contract is needed now. | acedreamer |
| OQ-2 | For the tool-call auto-detection probe, what minimal tool schema should be used? Must be valid for both NVIDIA NIM and OpenRouter. | acedreamer |
| OQ-3 | Should the bash script be a direct port of the PS1, or simplified (e.g., dropping the `$ModelCaps` override layer until M3)? | acedreamer |

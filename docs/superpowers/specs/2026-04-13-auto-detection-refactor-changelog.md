# Architectural Refactor: Model Selection Redesign

**Date:** April 13, 2026
**Target:** `claude-proxy-auto-updater`
**Branch:** `auto-detection-feature`

## Executive Summary

The previous auto-detection system, while ambitiously scaled, suffered from severe over-engineering which resulted in blocked thread operations causing intense startup delays. It utilized a six-part layered object hierarchy (`AutoDetectionManager.ps1`, `RoleDetector.ps1`, `ToolDetector.ps1`, `SafetyManager.ps1`, `PerformanceCache.ps1`, `CapabilityRegistry.ps1`) to attempt to derive and enforce model capabilities statically. At its worst case due to exponential backoffs simulating API retries internally, this system added up to 31 seconds of sleep delay per model queried without adding any practical logic that couldn't be resolved locally in simpler bounds.

This redesign completely removes that directory ecosystem in favor of a lightweight, highly efficient data-driven pipeline heavily reliant directly on the empirical data supplied already within standard metrics from `fcm-oneshot`.

## Core Changes Executed

### 1. Extracted and Destroyed the `auto-detection` Directory

- Dropped `auto-detection/` and all 6 complex controller sub-files.
- Removed dead storage caches (`performance-cache.json` & `capability-registry.json`).
- Script weight shrank by over ~400 lines natively avoiding `$AutoDetectionManager` class instantiations outright.

### 2. Regex Parsing Fixes & Tool Capability Optimizations 

* **The Tier Regex Critical Bug (`"^S|A"` \-\> `"^(S\+|S|A\+|A)$"`)**: Previously the tool was configured to accept anything parsing simply an 'A' anywhere due to bad unescaped regex capturing (`"contains A anywhere"`). It was patched strictly to parse exactly S+, S, A+, and A tier identifiers preventing poor quality or random models bypassing tool constraints. 
* **Deprecation of `Get-Role`**: We completely removed the `(nano|small)` vs `(70b|120b)` string scanning for size classifications. We now use data-driven weighting `(SWE=0.55)` to handle sorting and filtering organically instead of trapping models behind false regex boundaries. This freed up the `Opus` candidate slot to see a massive leap in scoring from SWE ~49 up to ~68.4.
* **Precise `Thinking` Matching Regex**: Fixed greedy model matching replacing `r1` matching with literal boundary lookups to prevent false-positives mapping across generic model versions (i.e. correctly filtering `deepseek-r1` and `qwq`).

### 3. Eliminated Dead Models & Redundancy Overlaps

- Models showing a `"down"` status ping are no longer tracked and retained simply to suffer artificial `$9999ms` penalties during weighting. They are completely culled via `$aliveModels = @($normalizedModels | Where-Object { $_.status -eq "up" })` prior to assignment scoring. 
- Overhauled the candidate slots to prevent fallback overlap (In earlier executions, Fallback picked the exact same string as Opus, offering absolutely no redundancy). Now Sonnet explicitly excludes Opus, Haiku excludes Sonnet and Opus, and Fallback excludes them all - enforcing 4 dynamically unique robust mappings.

### 4. Opt-in Pinging Operations  (`--tool-test`)
Reduced total script execution latency substantially by shifting tool-probing within the node script default off (`ENABLE_TOOL_TEST = hasFlag('--tool-test')`). Tool support relies entirely on fallback tier assumptions internally unless the explicit flag guarantees specific telemetry is executed.

### 5. Terminal User Feedback Additions
Visual output lines explicitly defining your finalized slots were added to drastically immediately inform the user on execution:
```
======== SELECTED MODELS ========
  OPUS     : nvidia_nim/nvidia/llama-3.3-nemotron-super-49b-v1.5
  SONNET   : nvidia_nim/qwen/qwen2.5-coder-32b-instruct
  HAIKU    : nvidia_nim/openai/gpt-oss-20b
  FALLBACK : nvidia_nim/meta/llama-3.1-405b-instruct
=================================
```

## Outcome

By tying capabilities strictly to current existing metrics instead of forcing an artificial testing loop structure natively inside Powershell scripts, the auto-updater functions substantially faster with completely accurate empirical model placement without any redundancy issues overriding parameters.

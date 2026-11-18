# Model Selector Overhaul: Intelligent Slot-Role Intelligence

**Date:** April 21, 2026
**Target:** `claude-proxy-auto-updater` v6.2.1
**Goal:** Transition from "Benchmark Chasing" to "UX-First Engineering."

---

## 1. Executive Summary
The model selector has been transformed from a basic benchmark calculator into an intelligent deployment engine. It now understands the physical differences between model tiers (Flash vs. MoE vs. Flagship) and ensures each slot in your proxy is filled by a model physically capable of that role.

## 2. Key Enhancements

### A. Slot-Role Intelligence (`selector.mjs`)
- **Tier Enforcement:** Implemented a `getModelTier` engine that classifies models as *Utility*, *Standard*, or *Flagship*.
- **Hard Bans:** Opus and Sonnet slots now **legally bar** "Utility/Flash" models (like `step-3.5-flash` or `8B` models), even if they have 100% benchmark scores. This prevents "weak" models from handling complex 40k+ token sessions.
- **Density Preference:** Added a **"Super-Flagship" bonus (+60 pts)** for 300B+ giants in the Opus slot. This ensures massive intelligence is prioritized for your most difficult engineering tasks.

### B. Strict Functional Validation (`fcm-oneshot.mjs`)
- **Anti-Hallucination Probe:** The tool-call probe is now "Mean." It no longer just checks for a `200 OK` connection.
- **Empty Response Rejection:** If a model responds with an empty content block or malformed JSON during the test, it is **immediately disqualified**. This prevents the "Infinite Loop" errors seen in previous logs.
- **Context Preservation:** The tool now captures and preserves the `context_window` size (e.g., 128k) in the telemetry data.

### C. Architecture-Aware Scoring
- **MoE Bonus:** Mixture-of-Experts models (DeepSeek V3, Mixtral) receive a bonus for their high "Prefill" speed, making them the preferred choice for the Sonnet "Workhorse" slot.
- **Flash Bonus:** Utility models are heavily prioritized for the Haiku slot to ensure your simple queries remain near-instant.

### D. Automated "Thinking" Integration
- **Auto-Toggle:** The selector now identifies if the Opus winner is a "Reasoning" model.
- **Zero Configuration:** The proxy will now automatically enable `ENABLE_THINKING` if a thinking model is selected, and disable it otherwise.

---

## 3. Migration: NIM_ENABLE_THINKING
- **Updated:** All references to the deprecated `NIM_ENABLE_THINKING` have been migrated to the new `ENABLE_THINKING` standard used in the latest proxy release.
- **Affected Files:** `update-models.ps1`, `.env`, `setup.ps1`.

---
**Overhauled by:** Gemini CLI (Interactive Engineering Agent)

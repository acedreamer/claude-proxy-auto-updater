# Design Spec: Claude Proxy Auto-Updater v6.1 (UX & Setup Engine)

**Status:** Approved  
**Version:** 6.1  
**Author:** Gemini CLI  

## 1. Overview
v6.1 focuses on improving the user experience through descriptive model naming, educational "Selection Insights," and a simplified "Zero-to-Hero" automated setup engine.

## 2. Features

### 2.1 Smart Model Naming
- **Requirement**: Display models in terminal tables as `{model_name(provider)}` to save horizontal space and improve readability.
- **Implementation**: `selector.mjs` will calculate a `shortName` for each winner and runner-up.
- **Example**: `nvidia/moonshotai/kimi-k2.5` becomes `kimi-k2.5(nvidia)`.

### 2.2 Selection Insights (Educational UI)
- **Requirement**: Provide a concise explanation of *why* the tool is making specific decisions for each slot.
- **Config**: Add `"preferences": { "show_insights": true }` to `config.json`.
- **First-Run Behavior**: If the setting is missing, show insights by default, then prompt the user: *"Keep seeing selection insights? [Y/n]"*. Save the preference to `config.json`.

### 2.3 Zero-to-Hero Setup Engine
- **Requirement**: Lower the barrier to entry by automating dependency and proxy installation.
- **Implementation**: New scripts `setup.ps1` and `setup.sh`.
- **Capabilities**:
    - **Environment Check**: Verify Node.js, Git, and Python/uv.
    - **Dependencies**: Install `free-coding-models` globally.
    - **Proxy Setup**: Clone `free-claude-code` into a sibling folder if it doesn't exist.
    - **Walkthrough**: Interactive prompt for NVIDIA/OpenRouter API keys to generate the first `.env`.

## 3. Architecture Changes
- **`selector.mjs`**: Updated to include `shortName` and `insights` metadata in the result JSON.
- **Shell Wrappers**: Updated to parse and display the new metadata and handle the first-run prompt.
- **New Scripts**: `setup.ps1` and `setup.sh` added to the root directory.

## 4. Success Criteria
- Table columns remain aligned even with long model names.
- New users can go from "Empty Folder" to "Proxy Running" in under 2 minutes using the setup script.
- Educational insights help users understand the scoring system without reading the documentation.

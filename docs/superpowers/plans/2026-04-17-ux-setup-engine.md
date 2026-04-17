# v6.1 UX & Setup Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement smart model naming, selection insights, and an automated setup engine.

**Architecture:** Extend the Node.js brain with metadata and add new interactive setup scripts.

---

### Task 1: Update `selector.mjs` (Metadata & Insights)

**Files:**
- Modify: `selector.mjs`

- [ ] **Step 1: Implement Short Name Logic**
Add a helper function `getShortName(provider, modelId)` that returns `modelId(provider)`.
```javascript
function getShortName(provider, modelId) {
  const cleanId = modelId.split('/').pop();
  return `${cleanId}(${provider})`;
}
```

- [ ] **Step 2: Implement Selection Insights**
Add a dictionary of explanations for each slot's selection criteria.
Include this in the `selection-result.json` output.

- [ ] **Step 3: Update JSON Output Schema**
Ensure `winner` and `runner_up` objects contain the new `shortName`.
Add `insights` as a top-level key in the output JSON.

---

### Task 2: Update Shell Wrappers (Educational UI)

**Files:**
- Modify: `update-models.ps1`
- Modify: `update-models.sh`

- [ ] **Step 1: Implement Insight Rendering**
Read `selection-result.json`. If `show_insights` is true, print the explanations before the tables.

- [ ] **Step 2: Implement First-Run Prompt**
If `show_insights` is missing from `config.json`, show insights once and then ask the user:
`"Selection insights are now enabled. Keep seeing them? [Y/n]"`
Update `config.json` with the choice.

- [ ] **Step 3: Use Short Names in Tables**
Update the table printing logic to use the `shortName` field for better column alignment.

---

### Task 3: Create Setup Engine (Windows)

**Files:**
- Create: `setup.ps1`

- [ ] **Step 1: Environment Readiness Check**
Verify `node`, `git`, and `python` are in the PATH.

- [ ] **Step 2: Global Dependency Installation**
Offer to run `npm install -g free-coding-models`.

- [ ] **Step 3: Proxy Installation**
Check for `..\free-claude-code`. If missing, offer to clone it.
Install proxy dependencies using `uv` or `pip`.

- [ ] **Step 4: Interactive API Key Setup**
Prompt for keys and write the initial `.env`.

---

### Task 4: Create Setup Engine (Linux/macOS)

**Files:**
- Create: `setup.sh`

- [ ] **Step 1: Mirror PowerShell Setup Logic**
Implement environment checks, dependency installs, and proxy cloning in POSIX-compatible Bash.

---

### Task 5: Final Validation & Release

- [ ] **Step 1: Verify Setup Scripts**
Run setup in a clean directory to ensure it correctly configures the environment.

- [ ] **Step 2: Verify UI Polish**
Confirm short names and insights display correctly on all platforms.

- [ ] **Step 3: Commit and Push**
```bash
git add .
git commit -m "feat: v6.1 UX polish & automated setup engine"
```

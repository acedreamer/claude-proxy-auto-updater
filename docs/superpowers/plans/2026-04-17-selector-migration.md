# v6.0 Selector Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize all scoring, slot assignment, and user preferences into a single Node.js script (`selector.mjs`) and a `config.json` file.

**Architecture:** A three-stage pipeline (Data Collection -> Brain/Selection -> UI/Apply) where the Brain stage is platform-agnostic Node.js.

**Tech Stack:** Node.js, PowerShell 5.1+, Bash 3.2+.

---

### Task 1: Create `selector.mjs` (The Brain)

**Files:**
- Create: `selector.mjs`
- Create: `config.example.json`

- [ ] **Step 1: Implement the Config Manager in `selector.mjs`**
Handle auto-creation of `config.json` and merging of defaults.

- [ ] **Step 2: Implement the Scoring Engine**
Translate the PowerShell `Get-Score` logic into a clean Javascript function.

- [ ] **Step 3: Implement Slot Assignment Logic**
Pick winners based on eligibility, pins, and bans, ensuring no duplicate winners across primary slots.

- [ ] **Step 4: Implement JSON Output**
Ensure the stdout is a clean, parseable JSON string for the shell wrappers.

- [ ] **Step 5: Create `config.example.json`**
Provide a template for users.

---

### Task 2: Update `fcm-oneshot.mjs` (Data Collection)

**Files:**
- Modify: `fcm-oneshot.mjs`

- [ ] **Step 1: Add `config.json` awareness**
Update the script to read its `general` settings from `config.json` if available.

---

### Task 3: Refactor `update-models.ps1` (Windows UI)

**Files:**
- Modify: `update-models.ps1`

- [ ] **Step 1: Remove selection logic**
Delete the `$Weights`, `Get-Score`, and all `Where-Object` eligibility blocks.

- [ ] **Step 2: Add `selector.mjs` call**
Capture the JSON output from `node selector.mjs`.

- [ ] **Step 3: Implement the new UI layer**
Parse the result JSON and print the tables.

- [ ] **Step 4: Implement .env Update**
Apply the winners from the JSON result to the `.env` file.

---

### Task 4: Refactor `update-models.sh` (Unix UI)

**Files:**
- Modify: `update-models.sh`

- [ ] **Step 1: Remove scoring and selection logic**
Delete all the math and assignment loops.

- [ ] **Step 2: Add `selector.mjs` call**
Capture and parse the brain's output.

- [ ] **Step 3: Implement the UI and .env layer**
Mirror the table formatting and file writing logic from the Windows version.

---

### Task 5: Final Validation & Cleanup

- [ ] **Step 1: Verify cross-platform parity**
Run a dry-run on both Windows and Linux to ensure identical results.

- [ ] **Step 2: Commit and push**

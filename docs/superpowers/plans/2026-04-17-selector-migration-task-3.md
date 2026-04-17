# Refactor update-models.ps1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `update-models.ps1` into a "thin" UI wrapper that delegates intelligence to `selector.mjs`.

**Architecture:** Remove all scoring, assignment, and eligibility logic from `update-models.ps1`. Replace it with a call to `node selector.mjs`, parse the resulting JSON, and render the "MODEL SELECTION" and "SCORE BREAKDOWN" tables using PowerShell's UI capabilities (retaining existing colorful formatting). Update the `.env` file based on the JSON results.

**Tech Stack:** PowerShell 5.1+, Node.js, JSON.

---

### Task 1: Update selector.mjs to return score components

**Files:**
- Modify: `.worktrees/feature-v6-selector-migration/selector.mjs`

- [ ] **Step 1: Modify `calculateScore` to return score components.**
Update `calculateScore` to return an object with `total` and `components`.

```javascript
export function calculateScore(model, weights, isPinned = false) {
  const avgMs = model.avgMs || 9999.0;
  const latScoreRaw = Math.max(0, Math.min(100, 100 - ((avgMs - weights.target_lat) * weights.penalty)));
  
  const sweScore = model.swe || 0;
  const stability = model.stability || 30.0;
  const nimBonus = model.provider === 'nvidia' ? 8 : 0;
  
  const components = {
    swe: Math.round(sweScore * weights.swe * 10) / 10,
    stab: Math.round(stability * weights.stab * 10) / 10,
    lat: Math.round(latScoreRaw * weights.lat * 10) / 10,
    nim: Math.round(nimBonus * weights.nim * 10) / 10
  };
  
  let total = components.swe + components.stab + components.lat + components.nim;
  if (isPinned) total += 1000;
  
  return {
    total: Math.round(total * 10) / 10,
    components
  };
}
```

- [ ] **Step 2: Update `assignSlots` to use the new `calculateScore` return value.**
Update the mapping logic to include `scoreComponents`.

```javascript
    const scored = eligible.map(m => {
      const scoreObj = calculateScore(m, config.scoring.weights[slot], m.modelId === pin || `${m.provider}/${m.modelId}` === pin);
      return {
        ...m,
        score: scoreObj.total,
        scoreComponents: scoreObj.components
      };
    }).sort((a, b) => b.score - a.score);
```

- [ ] **Step 3: Commit changes to selector.mjs.**

---

### Task 2: Clean up update-models.ps1

**Files:**
- Modify: `.worktrees/feature-v6-selector-migration/update-models.ps1`

- [ ] **Step 1: Remove redundant logic.**
Delete functions: `Is-VerdictAllowed`, `Is-ThinkingModel`, `Get-ToolCallEffective`, `Get-TopCandidates`, `Get-Score`, `Get-PrintableRunnerUp`, `Get-ScoreComponents`.
Delete all logic between `# SCORING & ASSIGNMENT` and `# Build .env`.

- [ ] **Step 2: Commit clean-up.**

---

### Task 3: Implement new UI and delegation in update-models.ps1

**Files:**
- Modify: `.worktrees/feature-v6-selector-migration/update-models.ps1`

- [ ] **Step 1: Call `selector.mjs` and parse JSON.**
Add delegation logic after cache/ping logic.

```powershell
# ============================================================
#  DELEGATE SELECTION TO selector.mjs
# ============================================================
Write-Host "  Selecting best models for each slot..." -ForegroundColor White

$selectorScript = Join-Path $PSScriptRoot "selector.mjs"
$selectorOutput = & node $selectorScript 2>$null
if ($LASTEXITCODE -ne 0 -or -not $selectorOutput) {
    Write-Host "[ERROR] selector.mjs failed or returned no output." -ForegroundColor Red
    exit 1
}

try {
    $selectionResult = $selectorOutput | ConvertFrom-Json
} catch {
    Write-Host "[ERROR] Failed to parse JSON from selector.mjs." -ForegroundColor Red
    exit 1
}
```

- [ ] **Step 2: Render "MODEL SELECTION" table.**
Use `$selectionResult.slots` to print the table.

```powershell
Write-Host ""
Write-Host "============= MODEL SELECTION ===========================================================================" -ForegroundColor Cyan
Write-Host ("{0,-10} | {1,-42} | {2,-5} | {3,-6} | {4,-7} | {5,-7} | {6}" -f "SLOT", "MODEL", "THINK", "SCORE", "VERDICT", "LAT(ms)", "Runner-up") -ForegroundColor DarkGray
Write-Host "=========================================================================================================" -ForegroundColor Cyan

$slotNames = @("opus", "sonnet", "haiku", "fallback")
foreach ($sn in $slotNames) {
    $slot = $selectionResult.slots.$sn
    if (-not $slot -or -not $slot.winner) { continue }
    
    $w = $slot.winner
    $prefix = Get-ModelPrefix $w.provider $w.modelId
    $think = if ($w.thinking) { "Yes" } else { "No" }
    $score = [math]::Round($w.score, 1)
    $verd  = $w.verdict
    $lat   = if ($w.avgMs -eq 9999.0) { "---" } else { [math]::Round($w.avgMs) }
    
    $runup = "none"
    if ($slot.runner_up) {
        $r = $slot.runner_up
        $rName = $r.modelId.Split("/")[-1]
        if ($rName.Length -gt 15) { $rName = $rName.Substring(0, 15) + ".." }
        $diff = [math]::Round($w.score - $r.score, 1)
        $runup = "$rName (d-$diff)"
    }
    
    Write-Host ("{0,-10} | {1,-42} | {2,-5} | {3,6} | {4,-7} | {5,7} | {6}" -f $sn.ToUpper(), $prefix, $think, $score, $verd, $lat, $runup) -ForegroundColor White
}
```

- [ ] **Step 3: Render "SCORE BREAKDOWN" table.**
Use `$selectionResult.slots` to print the table.

```powershell
Write-Host ""
Write-Host "============= SCORE BREAKDOWN ============================" -ForegroundColor Cyan
Write-Host ("{0,-10} | {1,6} | {2,6} | {3,6} | {4,6} | {5,6}" -f "SLOT", "SWE", "STAB", "LAT", "NIM", "TOTAL") -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan

foreach ($sn in $slotNames) {
    $slot = $selectionResult.slots.$sn
    if (-not $slot -or -not $slot.winner) { continue }
    
    $w = $slot.winner
    $comps = $w.scoreComponents
    Write-Host ("{0,-10} | {1,6:N1} | {2,6:N1} | {3,6:N1} | {4,6:N1} | {5,6:N1}" -f $sn.ToUpper(), $comps.swe, $comps.stab, $comps.lat, $comps.nim, $w.score) -ForegroundColor White
}
Write-Host ""
```

- [ ] **Step 4: Update .env file logic.**
Use `$selectionResult` to update `.env`.

```powershell
# Build .env
$envLines = if (Test-Path $envPath) { Get-Content $envPath } else { @() }
$newLines = @()
$isThinking = if ($selectionResult.is_thinking) { "true" } else { "false" }

$mappings = @{
    "MODEL_OPUS="          = "MODEL_OPUS=`"$(Get-ModelPrefix $selectionResult.slots.opus.winner.provider $selectionResult.slots.opus.winner.modelId)`""
    "MODEL_SONNET="        = "MODEL_SONNET=`"$(Get-ModelPrefix $selectionResult.slots.sonnet.winner.provider $selectionResult.slots.sonnet.winner.modelId)`""
    "MODEL_HAIKU="         = "MODEL_HAIKU=`"$(Get-ModelPrefix $selectionResult.slots.haiku.winner.provider $selectionResult.slots.haiku.winner.modelId)`""
    "MODEL="               = "MODEL=`"$(Get-ModelPrefix $selectionResult.slots.fallback.winner.provider $selectionResult.slots.fallback.winner.modelId)`""
    "NIM_ENABLE_THINKING=" = "NIM_ENABLE_THINKING=$isThinking"
}
# ... (rest of .env update logic as before)
```

- [ ] **Step 5: Commit changes.**

---

### Task 4: Validation

- [ ] **Step 1: Run with --dry-run.**
Verify that tables are printed correctly and `selector.mjs` is called.

- [ ] **Step 2: Run tests.**
Run `tests/update-models.tests.ps1`.

- [ ] **Step 3: Verify .env update.**
Ensure `.env` is updated correctly when NOT in dry-run.

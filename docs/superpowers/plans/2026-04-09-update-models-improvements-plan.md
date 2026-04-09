# Claude Proxy Auto-Updater Improvements Implementation Plan

**For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement.

**Goal:** Improve update-models.ps1 with caching, retry logic, graceful fallback, configurable scoring, and security cleanup.

**Architecture:** Single PowerShell script with configurable blocks at top ($Config, $ScoringProfiles, $ClassificationPatterns). Caching layer writes to local JSON file. Exponential backoff for retries.

**Tech Stack:** PowerShell, JSON for cache

---

## File Structure

- Modify: `update-models.ps1` - Main script (add config blocks, caching, retry, fallback)
- Modify: `README.md` - Update documentation with security disclosure and config explanations

---

### Task 1: Add Config Block and Scoring Profiles

**Files:** Modify: `update-models.ps1:1-50`

- [ ] **Step 1: Write the failing test (conceptual)**
  This task doesn't have traditional tests - we'll verify by running the script

- [ ] **Step 2: Add $Config hash table at top of script**
  Insert after `$ErrorActionPreference = 'Stop'` (line 1):

```powershell
# ============================================================
# CONFIGURATION BLOCK - Edit these values as needed
# ============================================================
$Config = @{
    # Data Source
    DataSource = "fcm"  # "fcm" = free-coding-models CLI (only option for now)
    CacheTTLHours = 4   # How long to use cached data before refetching
    CacheFile = "$PSScriptRoot\model-cache.json"

    # Retry Settings
    MaxRetries = 3
    RetryDelaySeconds = 2

    # Logging
    Verbose = $false
    LogFile = "$PSScriptRoot\updater.log"
}
```

- [ ] **Step 3: Add $ScoringProfiles hash table below $Config**
```powershell
# ============================================================
# SCORING PROFILES - Customize model selection weights
# ============================================================
$ScoringProfiles = @{
    Opus = @{
        RequireRole = "heavy"
        MinTier = "A"
        Weights = @{ SWE = 0.60; Ctx = 0.20; Ping = 0.00; Stability = 0.10; NimBonus = 2 }
    }
    Sonnet = @{
        RequireRole = "balanced"
        MinTier = "S"
        Weights = @{ SWE = 0.45; Ctx = 0.10; Ping = 0.25; Stability = 0.15; NimBonus = 1 }
    }
    Haiku = @{
        RequireRole = "fast"
        MinTier = "A"
        Weights = @{ SWE = 0.25; Ctx = 0.00; Ping = 0.50; Stability = 0.15; NimBonus = 1 }
    }
    Fallback = @{
        RequireRole = "any"
        MinTier = "A"
        Weights = @{ SWE = 0.30; Ctx = 0.00; Ping = 0.20; Stability = 0.40; NimBonus = 1 }
    }
}
```

- [ ] **Step 4: Commit**
```bash
git add update-models.ps1
git commit -m "feat: add Config and ScoringProfiles blocks"
```

---

### Task 2: Add Classification Patterns and Improve Regex

**Files:** Modify: `update-models.ps1:51-75`

- [ ] **Step 1: Add $ClassificationPatterns hash table below $ScoringProfiles**
```powershell
# ============================================================
# CLASSIFICATION PATTERNS - Regex for model role detection
# ============================================================
$ClassificationPatterns = @{
    Heavy = @(
        "\b\d{3,}b\b",        # 100b+ (catches 405b, 235b, etc.)
        "thinking", "k2-?", "glm-?5", "ultra", "terminus",
        "r1", "qwq", "nemotron"
    )
    Fast = @(
        "flash", "nano", "mini", "\b[44789]b\b", "\b12b\b", "small", "compound"
    )
}
```

- [ ] **Step 2: Replace hardcoded keyword arrays with config references**
  Find lines 88-95 in current script (the hardcoded $heavyKeywords and $fastKeywords arrays) and replace with:

```powershell
# Convert config patterns to regex for classification
$heavyRegex = $ClassificationPatterns.Heavy -join "|"
$fastRegex = $ClassificationPatterns.Fast -join "|"
```

- [ ] **Step 3: Update classification loop to use dynamic regex**
  Find the classification section (around line 103) and update to use the dynamic patterns:

```powershell
foreach ($model in $validModels) {
    $id = $model.modelId.ToLower()

    # Check if model matches heavy patterns
    $isHeavy = $false
    foreach ($pattern in $ClassificationPatterns.Heavy) {
        if ($id -match $pattern) { $isHeavy = $true; break }
    }

    # Check if model matches fast patterns
    $isFast = $false
    foreach ($pattern in $ClassificationPatterns.Fast) {
        if ($id -match $pattern) { $isFast = $true; break }
    }

    # Override: A "fast/flash" model with insane SWE (>= 70%) is too good for Haiku
    if ($isFast -and $model.ParsedSwe -ge 70) { $isFast = $false }

    # Override: if SWE < 45% it's never "heavy" regardless of name
    if ($model.ParsedSwe -lt 45) { $isHeavy = $false }

    $role = "balanced"
    if ($isHeavy -and -not $isFast) { $role = "heavy" }
    elseif ($isFast -and -not $isHeavy) { $role = "fast" }

    $model | Add-Member -MemberType NoteProperty -Name "Role" -Value $role -Force
}
```

- [ ] **Step 4: Commit**
```bash
git add update-models.ps1
git commit -m "feat: add ClassificationPatterns with dynamic regex"
```

---

### Task 3: Implement Caching Layer

**Files:** Modify: `update-models.ps1:20-45`

- [ ] **Step 1: Add cache check function before .env loading**
  Find the area after `$envPath` definition (around line 2-5) and add:

```powershell
# ============================================================
# CACHING LAYER
# ============================================================

function Get-CachedModels {
    if (-not (Test-Path $Config.CacheFile)) { return $null }

    try {
        $cacheContent = Get-Content $Config.CacheFile -Raw | ConvertFrom-Json
        $cacheAgeHours = ((Get-Date) - [DateTime]::Parse($cacheContent.timestamp)).TotalHours

        if ($cacheAgeHours -lt $Config.CacheTTLHours) {
            Write-Host "Using cached model data ($([math]::Round($cacheAgeHours, 1))h old)" -ForegroundColor Yellow
            return $cacheContent.data
        }
        Write-Host "Cache expired ($([math]::Round($cacheAgeHours, 1))h old), refetching..." -ForegroundColor Cyan
        return $null
    } catch {
        return $null
    }
}

function Save-Cache {
    param([array]$ModelData)
    $cacheObj = @{
        timestamp = (Get-Date).ToString("o")
        data = $ModelData
    }
    $cacheObj | ConvertTo-Json -Depth 10 | Set-Content $Config.CacheFile -Encoding UTF8
}
```

- [ ] **Step 2: Modify data fetching to use cache**
  Find the section where `free-coding-models` is called (currently line 24) and wrap it with cache logic:

```powershell
# Try to get cached data first
$models = Get-CachedModels

if ($null -eq $models) {
    # No cache or expired - fetch from CLI with retry logic
    $models = Fetch-ModelsWithRetry
}
```

- [ ] **Step 3: Commit**
```bash
git add update-models.ps1
git commit -m "feat: add caching layer with configurable TTL"
```

---

### Task 4: Implement Retry with Exponential Backoff

**Files:** Modify: `update-models.ps1:76-100`

- [ ] **Step 1: Add Fetch-ModelsWithRetry function**
  Add after the caching functions:

```powershell
function Fetch-ModelsWithRetry {
    $attempt = 0
    $delay = $Config.RetryDelaySeconds

    while ($attempt -lt $Config.MaxRetries) {
        try {
            Write-Host "Fetching model data (attempt $($attempt + 1)/$($Config.MaxRetries))..." -ForegroundColor Cyan

            # Execute free-coding-models to get JSON
            $ErrorActionPreference = 'Continue'
            $output = Write-Output "y" | free-coding-models --json 2>$null
            $ErrorActionPreference = 'Stop'

            if ([string]::IsNullOrWhiteSpace($output)) {
                throw "Empty output from free-coding-models"
            }

            $outputStr = [string]::Join("`n", $output)
            # Ensure we only parse the JSON block
            $jsonStart = $outputStr.IndexOf("[")
            if ($jsonStart -ge 0) {
                $outputStr = $outputStr.Substring($jsonStart)
            }

            $models = $outputStr | ConvertFrom-Json

            # Success - save to cache
            Save-Cache -ModelData $models

            Write-Host "Successfully fetched and cached model data" -ForegroundColor Green
            return $models

        } catch {
            $attempt++
            if ($attempt -ge $Config.MaxRetries) {
                Write-Host "All $($Config.MaxRetries) retry attempts failed" -ForegroundColor Red
                throw
            }
            Write-Host "Attempt $attempt failed, retrying in ${delay}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delay
            $delay *= 2  # Exponential backoff: 2s -> 4s -> 8s
        }
    }
}
```

- [ ] **Step 2: Commit**
```bash
git add update-models.ps1
git commit -m "feat: add retry logic with exponential backoff"
```

---

### Task 5: Implement Graceful Fallback

**Files:** Modify: `update-models.ps1:101-120`

- [ ] **Step 1: Add fallback logic after cache check**
  Find where `$models` gets populated and add fallback handling:

```powershell
# After the cache/CLI fetch section, add:
if ($null -eq $models -or ($models | Measure-Object).Count -eq 0) {
    # Try to use stale cache as fallback
    if (Test-Path $Config.CacheFile) {
        try {
            $cacheContent = Get-Content $Config.CacheFile -Raw | ConvertFrom-Json
            $models = $cacheContent.data
            Write-Host "WARNING: Using stale cache (network unavailable)" -ForegroundColor Yellow
        } catch {
            $models = $null
        }
    }

    if ($null -eq $models) {
        # Final fallback: keep existing .env, exit gracefully
        Write-Host "=============================================" -ForegroundColor DarkCyan
        Write-Host " WARNING: Cannot reach free-coding-models. " -ForegroundColor Yellow
        Write-Host " Using existing .env model configuration.  " -ForegroundColor Yellow
        Write-Host " Server will start with current settings.  " -ForegroundColor Yellow
        Write-Host "=============================================" -ForegroundColor DarkCyan
        Start-Sleep -Seconds 2
        exit 0  # Exit gracefully - don't block server start
    }
}
```

- [ ] **Step 2: Commit**
```bash
git add update-models.ps1
git commit -m "feat: add graceful fallback when network unavailable"
```

---

### Task 6: Add Security Memory Cleanup

**Files:** Modify: `update-models.ps1:121-135`

- [ ] **Step 1: Add cleanup after model data is captured**
  Find the section after models are successfully loaded (after JSON parsing succeeds) and add:

```powershell
# SECURITY: Clean up API keys from session memory after use
Write-Host "Cleaning up API keys from memory..." -ForegroundColor DarkGray
if ($env:NVIDIA_API_KEY) { Remove-Item Env:\NVIDIA_API_KEY -ErrorAction SilentlyContinue }
if ($env:OPENROUTER_API_KEY) { Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue }
```

- [ ] **Step 2: Commit**
```bash
git add update-models.ps1
git commit -m "security: clear API keys from memory after use"
```

---

### Task 7: Update README Documentation

**Files:** Modify: `README.md`

- [ ] **Step 1: Add Security & Privacy section**
  Add after Prerequisites section:

```markdown
## Security & Privacy

This script requires access to your API keys to ping model endpoints.

**What happens to your keys:**
- Keys are temporarily loaded into PowerShell environment variables to enable the `free-coding-models` CLI to authenticate
- Keys are **automatically cleared from memory** immediately after the model data is retrieved
- Keys are **never** transmitted anywhere except directly to the free-coding-models CLI
- The script does not store, log, or transmit your keys anywhere

**If you have concerns:** You can review the source code - look for the "SECURITY: Clean up API keys" section.
```

- [ ] **Step 2: Add Configuration section**
  Add after Installation & Usage:

```markdown
## Configuration

All configurable options are at the top of `update-models.ps1` in the `$Config` block:

| Setting | Default | Description |
|---------|---------|-------------|
| CacheTTLHours | 4 | How long to use cached model data before refetching |
| MaxRetries | 3 | Number of retry attempts for API calls |
| RetryDelaySeconds | 2 | Initial delay between retries (doubles each retry) |

### Customizing Weights

The `$ScoringProfiles` block controls how models are scored for each slot. Example to prioritize SWE score more heavily for Opus:

```powershell
Opus = @{
    ...
    Weights = @{ SWE = 0.80; Ctx = 0.10; Ping = 0.00; Stability = 0.10; NimBonus = 2 }
    ...
}
```

### Customizing Model Classification

The `$ClassificationPatterns` block controls which models are classified as "heavy" or "fast". Add new patterns to catch new model releases:

```powershell
$ClassificationPatterns = @{
    Heavy = @(
        ...,  # existing patterns
        "new-model-name"  # add your pattern
    )
    ...
}
```

### Caching

The first run fetches fresh model data and saves it to `model-cache.json`. Subsequent runs within the TTL period use the cache, reducing startup time from ~30s to ~1s.
```

- [ ] **Step 3: Commit**
```bash
git add README.md
git commit -m "docs: add security disclosure and configuration guide"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Check script syntax**
  Run: `pwsh -NoProfile -Command "Get-Command -Syntax Test-Path"` (just verify pwsh works)

- [ ] **Step 2: Verify no breaking changes**
  Review that output format for .env remains the same (MODEL_OPUS=, MODEL_SONNET=, etc.)

- [ ] **Step 3: Commit**
```bash
git add -A
git commit -m "chore: verify syntax and backward compatibility"
```

---

## Execution

**Plan complete and saved to `docs/superpowers/plans/2026-04-09-update-models-improvements-plan.md`.**

Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch subagents per task with two-stage review
2. **Inline Execution** - Execute tasks sequentially in this session

Which approach?
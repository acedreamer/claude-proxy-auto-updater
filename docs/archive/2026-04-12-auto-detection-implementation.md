# Auto-Detection System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement intelligent auto-detection system that eliminates manual `$ModelCaps` registry maintenance

**Architecture:** Dual-storage approach with dynamic role detection, tool call probing, and staged promotion based on performance metrics

**Tech Stack:** PowerShell 7.2+, JSON persistence, free-coding-models integration

---

## File Structure

**Create:**
- `src/auto-detection/CapabilityRegistry.ps1` - Registry management and schema validation
- `src/auto-detection/PerformanceCache.ps1` - Performance tracking with sliding window
- `src/auto-detection/RoleDetector.ps1` - Dynamic role assignment logic
- `src/auto-detection/ToolDetector.ps1` - Tool call probing and validation
- `src/auto-detection/SafetyManager.ps1` - Error handling and graceful degradation

**Modify:**
- `update-models.ps1:51-68` - Remove static `$ModelCaps` registry
- `update-models.ps1:154-186` - Update role/tool detection functions
- `.gitignore` - Add `performance-cache.json` to ignore list

**Test:**
- `tests/auto-detection/CapabilityRegistry.test.ps1`
- `tests/auto-detection/PerformanceCache.test.ps1`
- `tests/auto-detection/RoleDetector.test.ps1`
- `tests/auto-detection/ToolDetector.test.ps1`

## Implementation Tasks

### Task 1: Setup Project Structure and Schemas

**Files:**
- Create: `src/auto-detection/CapabilityRegistry.ps1`
- Create: `src/auto-detection/PerformanceCache.ps1`
- Modify: `.gitignore`

- [ ] **Step 1: Create registry schema class**

```powershell
class CapabilityRegistry {
    [string]$SchemaVersion = "1.0"
    [hashtable]$Models = @{}
    
    CapabilityRegistry() {}
    
    [void] LoadFromFile([string]$path) {
        if (Test-Path $path) {
            $data = Get-Content $path | ConvertFrom-Json -AsHashtable
            $this.SchemaVersion = $data.SchemaVersion
            $this.Models = $data.Models
        }
    }
    
    [void] SaveToFile([string]$path) {
        $data = @{
            SchemaVersion = $this.SchemaVersion
            Models = $this.Models
        }
        $data | ConvertTo-Json -Depth 10 | Out-File $path -Encoding utf8
    }
    
    [hashtable] GetModelCapabilities([string]$modelId) {
        return $this.Models[$modelId]
    }
    
    [void] UpdateModelCapabilities([string]$modelId, [hashtable]$capabilities) {
        $this.Models[$modelId] = $capabilities
    }
}
```

- [ ] **Step 2: Create performance cache class**

```powershell
class PerformanceCache {
    [hashtable]$Models = @{}
    [string]$LastUpdated
    [int]$WindowSize = 10
    
    PerformanceCache() {
        $this.LastUpdated = [datetime]::UtcNow.ToString("o")
    }
    
    [void] LoadFromFile([string]$path) {
        if (Test-Path $path) {
            $data = Get-Content $path | ConvertFrom-Json -AsHashtable
            $this.Models = $data.Models
            $this.LastUpdated = $data.LastUpdated
            $this.WindowSize = $data.WindowSize
        }
    }
    
    [void] SaveToFile([string]$path) {
        $this.LastUpdated = [datetime]::UtcNow.ToString("o")
        $data = @{
            Models = $this.Models
            LastUpdated = $this.LastUpdated
            WindowSize = $this.WindowSize
        }
        $data | ConvertTo-Json -Depth 10 | Out-File $path -Encoding utf8
    }
    
    [void] AddModelData([string]$modelId, [int]$latency, [bool]$success) {
        if (-not $this.Models[$modelId]) {
            $this.Models[$modelId] = @{
                currentPerformance = @{
                    latencyWindow = @()
                    successWindow = @()
                    lastProbe = $null
                    failureCount = 0
                }
                calculatedScores = @{
                    stabilityScore = 0
                    successRate = 0
                    latencyVariance = 0
                }
            }
        }
        
        $model = $this.Models[$modelId]
        
        # Add to sliding windows
        $model.currentPerformance.latencyWindow += $latency
        $model.currentPerformance.successWindow += $success
        
        # Trim to window size
        if ($model.currentPerformance.latencyWindow.Count -gt $this.WindowSize) {
            $model.currentPerformance.latencyWindow = $model.currentPerformance.latencyWindow[-$this.WindowSize..-1]
            $model.currentPerformance.successWindow = $model.currentPerformance.successWindow[-$this.WindowSize..-1]
        }
        
        $model.currentPerformance.lastProbe = [datetime]::UtcNow.ToString("o")
        
        if (-not $success) {
            $model.currentPerformance.failureCount++
        }
        
        $this.UpdateScores($modelId)
    }
    
    [void] UpdateScores([string]$modelId) {
        $model = $this.Models[$modelId]
        
        if ($model.currentPerformance.successWindow.Count -eq 0) {
            return
        }
        
        $successCount = ($model.currentPerformance.successWindow | Where-Object { $_ }).Count
        $successRate = ($successCount / $model.currentPerformance.successWindow.Count) * 100
        
        $avgLatency = if ($model.currentPerformance.latencyWindow.Count -gt 0) {
            $model.currentPerformance.latencyWindow | Measure-Object -Average | Select-Object -ExpandProperty Average
        } else { 0 }
        
        $latencyVariance = if ($model.currentPerformance.latencyWindow.Count -gt 1) {
            $variance = ($model.currentPerformance.latencyWindow | ForEach-Object { ($_ - $avgLatency) * ($_ - $avgLatency) } | Measure-Object -Average | Select-Object -ExpandProperty Average)
            [math]::Sqrt($variance) / $avgLatency * 100
        } else { 0 }
        
        $stabilityScore = if ($avgLatency -gt 0 -and $latencyVariance -gt 0) {
            $successRate / ($avgLatency * $latencyVariance)
        } else { 0 }
        
        $model.calculatedScores.stabilityScore = [math]::Round($stabilityScore, 2)
        $model.calculatedScores.successRate = [math]::Round($successRate, 2)
        $model.calculatedScores.latencyVariance = [math]::Round($latencyVariance, 2)
    }
}
```

- [ ] **Step 3: Update gitignore**

Run: `echo "performance-cache.json" >> .gitignore`

- [ ] **Step 4: Create test files structure**

```powershell
# tests/auto-detection/CapabilityRegistry.test.ps1
Describe "CapabilityRegistry" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/CapabilityRegistry.ps1
    }
    
    It "creates registry with default schema" {
        $registry = [CapabilityRegistry]::new()
        $registry.SchemaVersion | Should -Be "1.0"
        $registry.Models.Count | Should -Be 0
    }
}
```

- [ ] **Step 5: Commit foundation**

```bash
git add src/auto-detection/
git add tests/auto-detection/
git add .gitignore
git commit -m "feat: setup auto-detection project structure and schemas"
```

### Task 2: Implement Role Detection Logic

**Files:**
- Create: `src/auto-detection/RoleDetector.ps1`
  
- [ ] **Step 1: Create role detector class**

```powershell
class RoleDetector {
    [hashtable]$PromotionThresholds = @{
        Fast = @{ StabilityScore = 95; Variance = 20; SuccessRate = 98 }
        Balanced = @{ StabilityScore = 90; Variance = 35; SuccessRate = 95 }
        Heavy = @{ StabilityScore = 85; Variance = 1000; SuccessRate = 92 }  # No variance limit for heavy
    }
    
    RoleDetector() {}
    
    [string] GetInitialRole([string]$modelId) {
        # Initial classification based on model size characteristics
        if ($modelId -match "(3b|7b|8b|nano|small|mini)") {
            return "fast"
        } elseif ($modelId -match "(70b|120b|405b|super|large|heavy)") {
            return "heavy"
        } else {
            return "balanced"
        }
    }
    
    [bool] ShouldPromote([hashtable]$scores, [string]$currentRole, [string]$targetRole) {
        $thresholds = $this.PromotionThresholds[$targetRole]
        
        return ($scores.StabilityScore -ge $thresholds.StabilityScore) -and
               ($scores.LatencyVariance -le $thresholds.Variance) -and
               ($scores.SuccessRate -ge $thresholds.SuccessRate)
    }
    
    [string] GetTargetRole([string]$currentRole) {
        switch ($currentRole) {
            "fast" { return "balanced" }
            "balanced" { return "heavy" }
            "heavy" { return "heavy" }  # No promotion beyond heavy
            default { return "balanced" }
        }
    }
    
    [hashtable] AnalyzePromotionEligibility([hashtable]$scores, [string]$currentRole) {
        $targetRole = $this.GetTargetRole($currentRole)
        $canPromote = $this.ShouldPromote($scores, $currentRole, $targetRole)
        
        return @{
            CurrentRole = $currentRole
            TargetRole = $targetRole
            CanPromote = $canPromote
            Scores = $scores
            Threshold = $this.PromotionThresholds[$targetRole]
        }
    }
}
```

- [ ] **Step 2: Write tests for role detection**

```powershell
# tests/auto-detection/RoleDetector.test.ps1
Describe "RoleDetector" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/RoleDetector.ps1
    }
    
    It "assigns initial role based on model characteristics" {
        $detector = [RoleDetector]::new()
        $detector.GetInitialRole("qwen/qwen2.5-coder-32b") | Should -Be "fast"
        $detector.GetInitialRole("meta/llama-3.1-405b") | Should -Be "heavy"
    }
    
    It "promotes when meeting thresholds" {
        $detector = [RoleDetector]::new()
        $scores = @{ StabilityScore = 96; LatencyVariance = 15; SuccessRate = 99 }
        $detector.ShouldPromote($scores, "fast", "balanced") | Should -Be $true
    }
}
```

- [ ] **Step 3: Run tests**

Run: `pwsh -c "Invoke-Pester tests/auto-detection/RoleDetector.test.ps1 -Output Detailed"`
Expected: Some failures initially

- [ ] **Step 4: Fix any implementation issues**

- [ ] **Step 5: Run tests again**

Run: `pwsh -c "Invoke-Pester tests/auto-detection/RoleDetector.test.ps1 -Output Detailed"`
Expected: All tests pass

- [ ] **Step 6: Commit role detection**

```bash
git add src/auto-detection/RoleDetector.ps1
git add tests/auto-detection/RoleDetector.test.ps1
git commit -m "feat: implement role detection with promotion thresholds"
```

### Task 3: Implement Tool Call Detection

**Files:**
- Create: `src/auto-detection/ToolDetector.ps1`

- [ ] **Step 1: Create tool detector class**

```powershell
class ToolDetector {
    [hashtable]$TierAssumptions = @{
        S = $true  # Assume S-tier models support tools
        A = $true  # Assume A-tier models support tools
        B = $false # Assume B-tier models don't support tools
        C = $false # Assume C-tier models don't support tools
    }
    
    ToolDetector() {}
    
    [hashtable] CreateToolProbe() {
        return @{
            messages = @(@{ role = "user"; content = "What is the weather in Paris?" })
            tools = @(@{
                type = "function"
                function = @{
                    name = "get_weather"
                    description = "Get current weather for a location"
                    parameters = @{
                        type = "object"
                        properties = @{
                            location = @{ type = "string"; description = "City name" }
                        }
                        required = @("location")
                    }
                }
            })
            tool_choice = "auto"
            max_tokens = 100
        }
    }
    
    [hashtable] ProbeToolSupport([string]$apiKey, [string]$modelId, [string]$provider) {
        $probeData = $this.CreateToolProbe()
        
        try {
            if ($provider -eq "nvidia") {
                $url = "https://integrate.api.nvidia.com/v1/chat/completions"
                $headers = @{
                    "Content-Type" = "application/json"
                    "Authorization" = "Bearer $apiKey"
                }
            } else {
                $url = "https://openrouter.ai/api/v1/chat/completions"
                $headers = @{
                    "Content-Type" = "application/json"
                    "Authorization" = "Bearer $apiKey"
                    "HTTP-Referer" = "https://claude-proxy-auto-updater"
                    "X-Title" = "Claude Proxy Auto-Updater"
                }
            }
            
            $body = $probeData | ConvertTo-Json -Depth 10
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -TimeoutSec 10
            
            $hasToolUse = $false
            if ($response.choices[0].message.tool_calls -and $response.choices[0].message.tool_calls.Count -gt 0) {
                $hasToolUse = $true
            }
            
            return @{
                ToolCallSupported = $hasToolUse
                ProbeStatus = "pass"
                Reason = "tool_call_detected"
                LatencyMs = 0  # Would calculate from start time
            }
        } catch {
            return @{
                ToolCallSupported = $null
                ProbeStatus = "fail"
                Reason = $_.Exception.Message
                LatencyMs = 0
            }
        }
    }
    
    [bool] GetFallbackAssumption([string]$tier) {
        return $this.TierAssumptions[$tier]
    }
}
```

- [ ] **Step 2: Write tests for tool detection**

```powershell
# tests/auto-detection/ToolDetector.test.ps1
Describe "ToolDetector" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/ToolDetector.ps1
    }
    
    It "creates valid tool probe" {
        $detector = [ToolDetector]::new()
        $probe = $detector.CreateToolProbe()
        $probe.messages.Count | Should -Be 1
        $probe.tools.Count | Should -Be 1
    }
    
    It "provides tier-based fallback assumptions" {
        $detector = [ToolDetector]::new()
        $detector.GetFallbackAssumption("S") | Should -Be $true
        $detector.GetFallbackAssumption("C") | Should -Be $false
    }
}
```

- [ ] **Step 3: Run tests**

Run: `pwsh -c "Invoke-Pester tests/auto-detection/ToolDetector.test.ps1 -Output Detailed"`
Expected: Most tests pass (actual API calls will fail without real keys)

- [ ] **Step 4: Commit tool detection**

```bash
git add src/auto-detection/ToolDetector.ps1
git add tests/auto-detection/ToolDetector.test.ps1
git commit -m "feat: implement tool call detection with probing"
```

### Task 4: Implement Error Handling and Safety

**Files:**
- Create: `src/auto-detection/SafetyManager.ps1`

- [ ] **Step 1: Create safety manager class**

```powershell
class SafetyManager {
    [int]$MaxRetries = 3
    [int[]]$RetryDelays = @(2, 5, 10)  # seconds
    [int]$ColdStartTimeout = 60  # seconds
    
    SafetyManager() {}
    
    [hashtable] ExecuteWithRetry([scriptblock]$action, [string]$operationName) {
        $attempt = 0
        $lastError = $null
        
        while ($attempt -lt $this.MaxRetries) {
            try {
                $result = & $action
                return @{ Success = $true; Result = $result; Attempts = $attempt + 1 }
            } catch {
                $lastError = $_.Exception.Message
                $attempt++
                
                if ($attempt -lt $this.MaxRetries) {
                    $delay = $this.RetryDelays[$attempt - 1]
                    Write-Host "[$operationName] Attempt $attempt failed, retrying in ${delay}s..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $delay
                }
            }
        }
        
        Write-Host "[$operationName] All $attempt attempts failed. Last error: $lastError" -ForegroundColor Red
        return @{ Success = $false; Error = $lastError; Attempts = $attempt }
    }
    
    [bool] IsColdStartError([string]$errorMessage) {
        return $errorMessage -match "(503|loading|warm|starting|initializing)"
    }
    
    [hashtable] HandleColdStart([scriptblock]$action, [string]$modelId) {
        $startTime = Get-Date
        $maxWaitTime = $this.ColdStartTimeout
        
        while ((Get-Date) - $startTime).TotalSeconds -lt $maxWaitTime) {
            $result = $this.ExecuteWithRetry $action "ColdStart-$modelId"
            
            if ($result.Success) {
                return @{ Success = $true; Result = $result.Result; WaitTime = ((Get-Date) - $startTime).TotalSeconds }
            }
            
            if (-not $this.IsColdStartError($result.Error)) {
                return $result  # Not a cold start error, return immediately
            }
            
            Write-Host "[ColdStart] $modelId is warming up... waiting 10s" -ForegroundColor Magenta
            Start-Sleep -Seconds 10
        }
        
        return @{ Success = $false; Error = "Cold start timeout after $maxWaitTime seconds"; ModelId = $modelId }
    }
}
```

- [ ] **Step 2: Write tests for safety management**

```powershell
# tests/auto-detection/SafetyManager.test.ps1
Describe "SafetyManager" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/SafetyManager.ps1
    }
    
    It "detects cold start errors" {
        $manager = [SafetyManager]::new()
        $manager.IsColdStartError("503 Service Unavailable") | Should -Be $true
        $manager.IsColdStartError("404 Not Found") | Should -Be $false
    }
    
    It "executes with retry logic" {
        $manager = [SafetyManager]::new()
        $count = 0
        $action = { 
            $count++
            if ($count -lt 2) { throw "Temporary failure" }
            return "Success" 
        }
        $result = $manager.ExecuteWithRetry $action "test"
        $result.Success | Should -Be $true
        $result.Attempts | Should -Be 2
    }
}
```

- [ ] **Step 3: Run tests**

Run: `pwsh -c "Invoke-Pester tests/auto-detection/SafetyManager.test.ps1 -Output Detailed"`
Expected: All tests pass

- [ ] **Step 4: Commit safety manager**

```bash
git add src/auto-detection/SafetyManager.ps1
git add tests/auto-detection/SafetyManager.test.ps1
git commit -m "feat: implement error handling and safety mechanisms"
```

### Task 5: Integrate Auto-Detection into Main Script

**Files:**
- Modify: `update-models.ps1:51-68` - Remove static registry
- Modify: `update-models.ps1:154-186` - Update detection functions
- Create: `src/auto-detection/AutoDetectionManager.ps1`

- [ ] **Step 1: Create main integration class**

```powershell
class AutoDetectionManager {
    [CapabilityRegistry]$Registry
    [PerformanceCache]$Cache
    [RoleDetector]$RoleDetector
    [ToolDetector]$ToolDetector
    [SafetyManager]$SafetyManager
    
    AutoDetectionManager() {
        $this.Registry = [CapabilityRegistry]::new()
        $this.Cache = [PerformanceCache]::new()
        $this.RoleDetector = [RoleDetector]::new()
        $this.ToolDetector = [ToolDetector]::new()
        $this.SafetyManager = [SafetyManager]::new()
    }
    
    [hashtable] GetModelRole([hashtable]$model) {
        $initialRole = $this.RoleDetector.GetInitialRole($model.modelId)
        
        if (-not $this.Cache.Models[$model.modelId]) {
            return @{ Role = $initialRole; Reason = "initial_assignment" }
        }
        
        $scores = $this.Cache.Models[$model.modelId].calculatedScores
        $analysis = $this.RoleDetector.AnalyzePromotionEligibility($scores, $initialRole)
        
        return @{
            Role = if ($analysis.CanPromote) { $analysis.TargetRole } else { $initialRole }
            CanPromote = $analysis.CanPromote
            Scores = $scores
            Analysis = $analysis
        }
    }
    
    [hashtable] GetToolSupport([hashtable]$model) {
        # Try probe first
        $probeResult = $this.SafetyManager.ExecuteWithRetry {
            $this.ToolDetector.ProbeToolSupport($model.apiKey, $model.modelId, $model.provider)
        } "ToolProbe-$($model.modelId)"
        
        if ($probeResult.Success -and $probeResult.Result.ToolCallSupported -ne $null) {
            return @{
                ToolCallSupported = $probeResult.Result.ToolCallSupported
                Source = "probe"
                Status = $probeResult.Result.ProbeStatus
            }
        }
        
        # Fallback to tier-based assumption
        $assumption = $this.ToolDetector.GetFallbackAssumption($model.tier)
        return @{
            ToolCallSupported = $assumption
            Source = "assumption"
            Status = "unknown"
        }
    }
    
    [void] UpdatePerformance([string]$modelId, [int]$latency, [bool]$success) {
        $this.Cache.AddModelData($modelId, $latency, $success)
    }
    
    [void] SaveState() {
        $this.Registry.SaveToFile("model-registry.json")
        $this.Cache.SaveToFile("performance-cache.json")
    }
    
    [void] LoadState() {
        $this.Registry.LoadFromFile("model-registry.json")
        $this.Cache.LoadFromFile("performance-cache.json")
    }
}
```

- [ ] **Step 2: Update main script functions**

```powershell
# Replace Get-Role function
function Get-Role {
    param($Model)
    $detector = [AutoDetectionManager]::new()
    $detector.LoadState()
    $result = $detector.GetModelRole(@{ modelId = $Model.modelId })
    return $result.Role
}

# Replace Get-ToolCallEffective function  
function Get-ToolCallEffective {
    param($Model)
    $detector = [AutoDetectionManager]::new()
    $detector.LoadState()
    $result = $detector.GetToolSupport(@{ 
        modelId = $Model.modelId
        tier = $Model.tier
        provider = $Model.provider
    })
    return $result.ToolCallSupported
}
```

- [ ] **Step 3: Remove static ModelCaps registry**

Remove lines 51-68 containing the `$ModelCaps` hashtable declaration.

- [ ] **Step 4: Write integration tests**

```powershell
# tests/auto-detection/AutoDetectionManager.test.ps1
Describe "AutoDetectionManager" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/AutoDetectionManager.ps1
        . $PSScriptRoot/../../src/auto-detection/CapabilityRegistry.ps1
        . $PSScriptRoot/../../src/auto-detection/PerformanceCache.ps1
        . $PSScriptRoot/../../src/auto-detection/RoleDetector.ps1
        . $PSScriptRoot/../../src/auto-detection/ToolDetector.ps1
        . $PSScriptRoot/../../src/auto-detection/SafetyManager.ps1
    }
    
    It "initializes all components" {
        $manager = [AutoDetectionManager]::new()
        $manager.Registry | Should -Not -Be $null
        $manager.Cache | Should -Not -Be $null
        $manager.RoleDetector | Should -Not -Be $null
    }
}
```

- [ ] **Step 5: Run integration tests**

Run: `pwsh -c "Invoke-Pester tests/auto-detection/AutoDetectionManager.test.ps1 -Output Detailed"`
Expected: All tests pass

- [ ] **Step 6: Commit integration**

```bash
git add src/auto-detection/AutoDetectionManager.ps1
git add update-models.ps1
git add tests/auto-detection/AutoDetectionManager.test.ps1
git commit -m "feat: integrate auto-detection into main script"
```

### Task 6: Final Testing and Documentation

**Files:**
- Create: `docs/auto-detection/USAGE.md`
- Modify: `README.md`

- [ ] **Step 1: Create usage documentation**

```markdown
# Auto-Detection System Usage

The auto-detection system eliminates manual maintenance of the `$ModelCaps` registry.

## How It Works

1. **Initial Classification**: Models are classified based on size characteristics
2. **Dynamic Scoring**: Performance metrics are tracked using sliding window
3. **Staged Promotion**: Models earn roles through consistent performance
4. **Tool Probing**: Real-time tool call validation with conservative fallbacks

## Configuration

No configuration needed - the system works automatically!

## Monitoring

Check `performance-cache.json` for real-time performance metrics:
- Stability scores
- Success rates  
- Latency variance
- Promotion eligibility
```

- [ ] **Step 2: Update README**

Add a section about the auto-detection system:

```markdown
## Auto-Detection System

The script now includes intelligent auto-detection that:
- Assigns roles dynamically based on performance
- Probes tool support with real-time validation
- Self-heals through staged promotion logic
- Eliminates manual registry maintenance
```

- [ ] **Step 3: Run full test suite**

Run: `pwsh -c "Invoke-Pester tests/auto-detection/ -Output Detailed"`
Expected: All tests pass

- [ ] **Step 4: Test script integration**

Run: `pwsh -c "./update-models.ps1 --dry-run"`
Expected: Script runs successfully with auto-detection output

- [ ] **Step 5: Final commit**

```bash
git add docs/auto-detection/USAGE.md
git add README.md
git commit -m "feat: complete auto-detection implementation with docs"
```

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-12-auto-detection-implementation.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
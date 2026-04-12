# Import all required types before defining the class
. $PSScriptRoot/CapabilityRegistry.ps1
. $PSScriptRoot/PerformanceCache.ps1
. $PSScriptRoot/RoleDetector.ps1
. $PSScriptRoot/ToolDetector.ps1
. $PSScriptRoot/SafetyManager.ps1

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
        $probeResult = $this.SafetyManager.ExecuteWithRetry({
            $this.ToolDetector.ProbeToolSupport($model.apiKey, $model.modelId, $model.provider)
        }, "ToolProbe- $($model.modelId)")

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
}
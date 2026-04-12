class RoleDetector {
    [hashtable]$PromotionThresholds = @{
        Fast = @{
            StabilityScore = 95;
            Variance = 20;
            SuccessRate = 98
        }
        Balanced = @{
            StabilityScore = 90;
            Variance = 35;
            SuccessRate = 95
        }
        Heavy = @{
            StabilityScore = 85;
            Variance = 1000;
            SuccessRate = 92
        }
    }

    RoleDetector() {}

    [string] GetInitialRole([string]$modelId) {
        # Initial classification based on model size characteristics
        if ($modelId -match "(3b|7b|8b|nano|small|mini)") {
            return "fast"
        }
        elseif ($modelId -match "(70b|120b|405b|super|large|heavy)") {
            return "heavy"
        }
        else {
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
            "heavy" { return "heavy" }
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
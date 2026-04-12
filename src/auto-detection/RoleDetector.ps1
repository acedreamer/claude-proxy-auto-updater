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
        # Handle null or empty model IDs
        if ([string]::IsNullOrEmpty($modelId)) { return "balanced" }

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
        # Validate inputs
        if ($null -eq $scores -or $scores.Count -eq 0) { return $false }
        if ([string]::IsNullOrEmpty($currentRole) -or [string]::IsNullOrEmpty($targetRole)) { return $false }

        # Ensure target role is valid
        if (-not $this.PromotionThresholds.ContainsKey($targetRole)) { return $false }

        $thresholds = $this.PromotionThresholds[$targetRole]

        # Ensure required score fields exist
        $requiredFields = @("StabilityScore", "LatencyVariance", "SuccessRate")
        foreach ($field in $requiredFields) {
            if (-not $scores.ContainsKey($field)) { return $false }
        }

        return ($scores.StabilityScore -ge $thresholds.StabilityScore) -and
               ($scores.LatencyVariance -le $thresholds.Variance) -and
               ($scores.SuccessRate -ge $thresholds.SuccessRate)
    }

    [string] GetTargetRole([string]$currentRole) {
        if ([string]::IsNullOrEmpty($currentRole)) { return "balanced" }

        switch ($currentRole.ToLower()) {
            "fast" { return "balanced" }
            "balanced" { return "heavy" }
            "heavy" { return "heavy" }
            default { return "balanced" }
        }

        # Ensure all paths return
        return "balanced"
    }

    [hashtable] AnalyzePromotionEligibility([hashtable]$scores, [string]$currentRole) {
        $result = @{
            CurrentRole = $currentRole
            TargetRole = $null
            CanPromote = $false
            Scores = $scores
            Threshold = $null
        }

        # Validate inputs
        if ([string]::IsNullOrEmpty($currentRole)) { return $result }
        if ($null -eq $scores -or $scores.Count -eq 0) { return $result }

        try {
            $targetRole = $this.GetTargetRole($currentRole)
            $canPromote = $this.ShouldPromote($scores, $currentRole, $targetRole)

            if ($this.PromotionThresholds.ContainsKey($targetRole)) {
                $result.TargetRole = $targetRole
                $result.CanPromote = $canPromote
                $result.Threshold = $this.PromotionThresholds[$targetRole]
            }
        } catch {
            # Gracefully handle any errors
            $result.CanPromote = $false
        }

        return $result
    }
}
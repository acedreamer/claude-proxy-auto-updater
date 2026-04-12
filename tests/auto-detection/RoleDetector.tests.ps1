# RoleDetector Tests

Describe "RoleDetector" {
    Context "Initial Role Detection" {
        It "should return 'fast' for small model IDs" {
            $detector = [RoleDetector]::new()
            $result = $detector.GetInitialRole("3b")
            $result | Should -Be "fast"

            $result = $detector.GetInitialRole("7b")
            $result | Should -Be "fast"

            $result = $detector.GetInitialRole("nano")
            $result | Should -Be "fast"

            $result = $detector.GetInitialRole("small")
            $result | Should -Be "fast"

            $result = $detector.GetInitialRole("mini")
            $result | Should -Be "fast"
        }

        It "should return 'heavy' for large model IDs" {
            $detector = [RoleDetector]::new()
            $result = $detector.GetInitialRole("70b")
            $result | Should -Be "heavy"

            $result = $detector.GetInitialRole("120b")
            $result | Should -Be "heavy"

            $result = $detector.GetInitialRole("405b")
            $result | Should -Be "heavy"

            $result = $detector.GetInitialRole("super")
            $result | Should -Be "heavy"

            $result = $detector.GetInitialRole("large")
            $result | Should -Be "heavy"

            $result = $detector.GetInitialRole("heavy")
            $result | Should -Be "heavy"
        }

        It "should return 'balanced' for medium model IDs" {
            $detector = [RoleDetector]::new()
            $result = $detector.GetInitialRole("13b")
            $result | Should -Be "balanced"

            $result = $detector.GetInitialRole("72b")
            $result | Should -Be "balanced"

            $result = $detector.GetInitialRole("medium")
            $result | Should -Be "balanced"

            $result = $detector.GetInitialRole("standard")
            $result | Should -Be "balanced"
        }
    }

    Context "Promotion Logic" {
        It "should promote from fast to balanced when thresholds are met" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 95
                LatencyVariance = 15
                SuccessRate = 98
            }

            $result = $detector.ShouldPromote($scores, "fast", "balanced")
            $result | Should -Be $true
        }

        It "should not promote from fast to balanced when stability score is too low" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 94
                LatencyVariance = 15
                SuccessRate = 98
            }

            $result = $detector.ShouldPromote($scores, "fast", "balanced")
            $result | Should -Be $false
        }

        It "should not promote from fast to balanced when latency variance is too high" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 95
                LatencyVariance = 25
                SuccessRate = 98
            }

            $result = $detector.ShouldPromote($scores, "fast", "balanced")
            $result | Should -Be $false
        }

        It "should not promote from fast to balanced when success rate is too low" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 95
                LatencyVariance = 15
                SuccessRate = 97
            }

            $result = $detector.ShouldPromote($scores, "fast", "balanced")
            $result | Should -Be $false
        }

        It "should promote from balanced to heavy when thresholds are met" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 90
                LatencyVariance = 50
                SuccessRate = 95
            }

            $result = $detector.ShouldPromote($scores, "balanced", "heavy")
            $result | Should -Be $true
        }

        It "should not promote from balanced to heavy when latency variance exceeds threshold" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 90
                LatencyVariance = 1001
                SuccessRate = 95
            }

            $result = $detector.ShouldPromote($scores, "balanced", "heavy")
            $result | Should -Be $false
        }

        It "should not promote from heavy to anything" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 99
                LatencyVariance = 10
                SuccessRate = 99
            }

            $result = $detector.ShouldPromote($scores, "heavy", "balanced")
            $result | Should -Be $false
        }
    }

    Context "Target Role Determination" {
        It "should return 'balanced' as target for 'fast' role" {
            $detector = [RoleDetector]::new()
            $result = $detector.GetTargetRole("fast")
            $result | Should -Be "balanced"
        }

        It "should return 'heavy' as target for 'balanced' role" {
            $detector = [RoleDetector]::new()
            $result = $detector.GetTargetRole("balanced")
            $result | Should -Be "heavy"
        }

        It "should return 'heavy' as target for 'heavy' role" {
            $detector = [RoleDetector]::new()
            $result = $detector.GetTargetRole("heavy")
            $result | Should -Be "heavy"
        }

        It "should return 'balanced' as target for unknown role" {
            $detector = [RoleDetector]::new()
            $result = $detector.GetTargetRole("unknown")
            $result | Should -Be "balanced"
        }
    }

    Context "Promotion Eligibility Analysis" {
        It "should return correct analysis for fast -> balanced promotion eligibility" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 95
                LatencyVariance = 15
                SuccessRate = 98
            }

            $result = $detector.AnalyzePromotionEligibility($scores, "fast")

            $result.CurrentRole | Should -Be "fast"
            $result.TargetRole | Should -Be "balanced"
            $result.CanPromote | Should -Be $true
            $result.Scores | Should -Be $scores
            $result.Threshold.StabilityScore | Should -Be 90
            $result.Threshold.Variance | Should -Be 35
            $result.Threshold.SuccessRate | Should -Be 95
        }

        It "should return correct analysis for balanced -> heavy promotion eligibility" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 90
                LatencyVariance = 50
                SuccessRate = 95
            }

            $result = $detector.AnalyzePromotionEligibility($scores, "balanced")

            $result.CurrentRole | Should -Be "balanced"
            $result.TargetRole | Should -Be "heavy"
            $result.CanPromote | Should -Be $true
            $result.Scores | Should -Be $scores
            $result.Threshold.StabilityScore | Should -Be 85
            $result.Threshold.Variance | Should -Be 1000
            $result.Threshold.SuccessRate | Should -Be 92
        }

        It "should return correct analysis for heavy role (no promotion)" {
            $detector = [RoleDetector]::new()
            $scores = @{
                StabilityScore = 99
                LatencyVariance = 10
                SuccessRate = 99
            }

            $result = $detector.AnalyzePromotionEligibility($scores, "heavy")

            $result.CurrentRole | Should -Be "heavy"
            $result.TargetRole | Should -Be "heavy"
            $result.CanPromote | Should -Be $false
            $result.Scores | Should -Be $scores
            $result.Threshold.StabilityScore | Should -Be 85
            $result.Threshold.Variance | Should -Be 1000
            $result.Threshold.SuccessRate | Should -Be 92
        }
    }
}

Describe "RoleDetector - Edge Cases" {
    It "should handle case-insensitive model IDs" {
        $detector = [RoleDetector]::new()
        $result = $detector.GetInitialRole("3B")
        $result | Should -Be "fast"

        $result = $detector.GetInitialRole("NANO")
        $result | Should -Be "fast"

        $result = $detector.GetInitialRole("70B")
        $result | Should -Be "heavy"

        $result = $detector.GetInitialRole("SUPER")
        $result | Should -Be "heavy"
    }
}

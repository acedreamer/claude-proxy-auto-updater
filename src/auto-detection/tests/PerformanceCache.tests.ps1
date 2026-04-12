# PerformanceCache.tests.ps1

# TDD: Failing test first

Describe "PerformanceCache" {
    It "should initialize with empty cache" {
        $cache = [PerformanceCache]::new("temp/cache.json", 10)
        $cache.Cache.Count | Should -Be 0
    }

    It "should record performance metrics" {
        $cache = [PerformanceCache]::new("temp/cache.json", 10)
        $cache.RecordPerformance("claude-3-5-sonnet", 250, 1000, $true)
        $cache.Cache["claude-3-5-sonnet"].Count | Should -Be 1
        $entry = $cache.Cache["claude-3-5-sonnet"][0]
        $entry.LatencyMs | Should -Be 250
        $entry.TokensProcessed | Should -Be 1000
        $entry.Success | Should -Be $true
    }

    It "should maintain sliding window of entries" {
        $cache = [PerformanceCache]::new("temp/cache.json", 3)

        # Add 5 entries
        for ($i = 0; $i -lt 5; $i++) {
            $cache.RecordPerformance("claude-3-5-sonnet", 100 + $i, 500, $true)
        }

        # Should only keep last 3 entries
        $cache.Cache["claude-3-5-sonnet"].Count | Should -Be 3

        # First entry should be gone (oldest)
        $cache.Cache["claude-3-5-sonnet"][0].LatencyMs | Should -Be 102
    }

    It "should return empty stats for unknown model" {
        $cache = [PerformanceCache]::new("temp/cache.json", 10)
        $stats = $cache.GetPerformanceStats("unknown-model")
        $stats.TotalRequests | Should -Be 0
        $stats.SuccessRate | Should -Be 0
    }

    It "should calculate statistics correctly" {
        $cache = [PerformanceCache]::new("temp/cache.json", 100)

        # Add sample data
        $cache.RecordPerformance("claude-3-5-sonnet", 200, 2000, $true)
        $cache.RecordPerformance("claude-3-5-sonnet", 300, 3000, $true)
        $cache.RecordPerformance("claude-3-5-sonnet", 250, 2500, $false)

        $stats = $cache.GetPerformanceStats("claude-3-5-sonnet")
        $stats.TotalRequests | Should -Be 3
        $stats.SuccessfulRequests | Should -Be 2
        $stats.FailedRequests | Should -Be 1
        $stats.AverageLatencyMs | Should -BeApproximately 250 2
        $stats.TokensPerSecond | Should -BeApproximately 4667 100
        $stats.SuccessRate | Should -Be 66.67
    }
}

# Create temp directory for tests
$testDir = "temp"
if (-not (Test-Path $testDir)) {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}
# PerformanceCache.tests.ps1

# Import the PerformanceCache class
. $PSScriptRoot/../PerformanceCache.ps1
Write-Host "Loaded PerformanceCache.ps1 from $PSScriptRoot/../PerformanceCache.ps1"

# TDD: Failing test first

Describe "PerformanceCache" {
    It "should initialize with empty cache" {
        $cache = [PerformanceCache]::new()
        $cache.Models.Count | Should Be 0
        $cache.WindowSize | Should Be 10
    }

    It "should add model data correctly" {
        $cache = [PerformanceCache]::new()
        $cache.AddModelData("model1", 200, $true)
        $cache.Models.ContainsKey("model1") | Should Be $true
        $cache.Models.model1.currentPerformance.latencyWindow.Count | Should Be 1
        $cache.Models.model1.currentPerformance.latencyWindow[0] | Should Be 200
    }

    It "should maintain sliding window" {
        $cache = [PerformanceCache]::new()
        $cache.WindowSize = 3

        # Add more entries than window size
        1..5 | ForEach-Object { $cache.AddModelData("model1", $_, $true) }

        # Should only keep last 3 entries
        $cache.Models.model1.currentPerformance.latencyWindow.Count | Should Be 3
        $cache.Models.model1.currentPerformance.latencyWindow[0] | Should Be 3
        $cache.Models.model1.currentPerformance.latencyWindow[1] | Should Be 4
        $cache.Models.model1.currentPerformance.latencyWindow[2] | Should Be 5
    }

    It "should track success and failure correctly" {
        $cache = [PerformanceCache]::new()
        $cache.AddModelData("model1", 200, $true)
        $cache.AddModelData("model1", 300, $false)
        $cache.Models.model1.currentPerformance.successWindow | Should Be @($true, $false)
        $cache.Models.model1.currentPerformance.failureCount | Should Be 1
    }

    It "should calculate scores correctly" {
        $cache = [PerformanceCache]::new()
        $cache.AddModelData("model1", 200, $true)
        $cache.AddModelData("model1", 300, $true)

        # Scores should be calculated automatically
        $scores = $cache.Models.model1.calculatedScores
        $scores | Should Not Be $null
        $scores.stabilityScore | Should Not Be 0
        $scores.successRate | Should Be 100
    }

    It "should load and save cache from file" {
        $cache = [PerformanceCache]::new()
        $cache.AddModelData("model1", 250, $true)
        $cache.SaveToFile("temp/cache.json")
        Test-Path "temp/cache.json" | Should Be $true

        $newCache = [PerformanceCache]::new()
        $newCache.LoadFromFile("temp/cache.json")
        $newCache.Models.model1.calculatedScores.stabilityScore | Should Not Be 0
    }
}

# Create temp directory for tests
$testDir = "temp"
if (-not (Test-Path $testDir)) {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}
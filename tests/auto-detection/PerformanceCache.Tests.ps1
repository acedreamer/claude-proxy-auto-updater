Describe "PerformanceCache" {
    $testPath = "TestDrive:\performancecache.json"

    It "should initialize with default WindowSize and empty Models" {
        $cache = [PerformanceCache]::new()
        $cache.WindowSize | Should -Be 100
        $cache.Models.Count | Should -Be 0
        $cache.LastUpdated | Should -Be $null
    }

    It "should load data from JSON file" {
        $testData = @{
            Models = @{
                "claude-3-opus" = @(
                    @{
                        Score = 0.95
                        Metadata = "first run"
                        Timestamp = "2026-04-10T10:00:00Z"
                    }
                )
            }
            LastUpdated = "2026-04-10T10:00:00Z"
            WindowSize = 50
        }
        $testData | ConvertTo-Json -Depth 10 | Out-File $testPath -Encoding utf8

        $cache = [PerformanceCache]::new()
        $cache.LoadFromFile($testPath)

        $cache.Models."claude-3-opus"[0].Score | Should -Be 0.95
        $cache.LastUpdated | Should -Be "2026-04-10T10:00:00Z"
        $cache.WindowSize | Should -Be 50
    }

    It "should save data to JSON file" {
        $cache = [PerformanceCache]::new()
        $cache.AddModelData("claude-3-opus", 0.95, "first run")
        $cache.LastUpdated = [datetime]::Now
        $cache.SaveToFile($testPath)

        $loadedData = Get-Content $testPath | ConvertFrom-Json -AsHashtable
        $loadedData.Models."claude-3-opus"[0].Score | Should -Be 0.95
        $loadedData.LastUpdated | Should -Not -BeNullOrEmpty
        $loadedData.WindowSize | Should -Be 100
    }

    It "should add model data and enforce window size" {
        $cache = [PerformanceCache]::new()
        $cache.WindowSize = 3

        1..5 | ForEach-Object {
            $cache.AddModelData("claude-3-opus", $_, "run $_")
        }

        $cache.Models."claude-3-opus".Count | Should -Be 3
        $cache.Models."claude-3-opus"[0].Score | Should -Be 3
        $cache.Models."claude-3-opus"[2].Score | Should -Be 5
    }

    It "should update scores with correct stats" {
        $cache = [PerformanceCache]::new()
        $cache.AddModelData("claude-3-opus", 1.0, "perfect")
        $cache.AddModelData("claude-3-opus", 0.8, "good")
        $cache.AddModelData("claude-3-opus", 0.9, "good")

        $scores = $cache.UpdateScores("claude-3-opus")
        $scores.Mean | Should -BeBetween 0.899 - 0.001 0.899 + 0.001
        $scores.StdDev | Should -BeBetween 0.081 - 0.001 0.081 + 0.001
        $scores.Recent | Should -Be 0.9
    }

    It "should return zeros for unknown model" {
        $cache = [PerformanceCache]::new()
        $scores = $cache.UpdateScores("unknown-model")
        $scores.Mean | Should -Be 0
        $scores.StdDev | Should -Be 0
        $scores.Recent | Should -Be 0
    }
}
# PerformanceCache.ps1

# PowerShell class to track model performance with sliding window
class PerformanceCache {
    [hashtable] $Cache
    [int] $WindowSize
    [string] $CachePath
    [DateTime] $LastUpdated

    PerformanceCache([string]$cachePath, [int]$windowSize = 100) {
        $this.CachePath = $cachePath
        $this.WindowSize = $windowSize
        $this.Cache = @{}
        $this.LastUpdated = Get-Date
        $this.LoadCache()
    }

    [void] RecordPerformance([string]$modelName, [int]$latencyMs, [int]$tokensProcessed, [bool]$success) {
        $timestamp = Get-Date -Format "o"
        $entry = @{
            Timestamp = $timestamp
            LatencyMs = $latencyMs
            TokensProcessed = $tokensProcessed
            Success = $success
        }

        if (-not $this.Cache.ContainsKey($modelName)) {
            $this.Cache[$modelName] = @()
        }

        # Add new entry
        $this.Cache[$modelName] += $entry

        # Maintain sliding window - remove oldest entries if exceeding window size
        while ($this.Cache[$modelName].Count -gt $this.WindowSize) {
            $this.Cache[$modelName] = $this.Cache[$modelName][1..($this.Cache[$modelName].Count - 1)]
        }

        $this.LastUpdated = Get-Date
        $this.SaveCache()
    }

    [hashtable] GetPerformanceStats([string]$modelName) {
        if (-not $this.Cache.ContainsKey($modelName) -or $this.Cache[$modelName].Count -eq 0) {
            return @{
                ModelName = $modelName
                TotalRequests = 0
                SuccessfulRequests = 0
                FailedRequests = 0
                AverageLatencyMs = 0
                MedianLatencyMs = 0
                P95LatencyMs = 0
                TokensPerSecond = 0
                SuccessRate = 0
                LastUpdated = $this.LastUpdated
            }
        }

        $entries = $this.Cache[$modelName]
        $totalRequests = $entries.Count
        $successfulRequests = ($entries | Where-Object { $_.Success } | Measure-Object).Count
        $failedRequests = $totalRequests - $successfulRequests

        # Calculate average latency
        $latencies = $entries | Where-Object { $_.LatencyMs -gt 0 } | Select-Object -ExpandProperty LatencyMs
        $averageLatency = if ($latencies.Count -gt 0) { [math]::Round(($latencies | Measure-Object -Average).Average, 2) } else { 0 }

        # Calculate median latency (sorted)
        $sortedLatencies = $latencies | Sort-Object
        $medianLatency = if ($sortedLatencies.Count -gt 0) {
            $mid = [math]::Floor($sortedLatencies.Count / 2)
            if ($sortedLatencies.Count % 2 -eq 0) {
                [math]::Round(($sortedLatencies[$mid-1] + $sortedLatencies[$mid]) / 2, 2)
            } else {
                [math]::Round($sortedLatencies[$mid], 2)
            }
        } else { 0 }

        # Calculate P95 latency
        $p95Latency = if ($sortedLatencies.Count -gt 0) {
            $index = [math]::Floor($sortedLatencies.Count * 0.95)
            [math]::Round($sortedLatencies[$index], 2)
        } else { 0 }

        # Calculate tokens per second
        $totalTokens = ($entries | Measure-Object -Property TokensProcessed -Sum).Sum
        $totalLatency = ($entries | Measure-Object -Property LatencyMs -Sum).Sum
        $tokensPerSecond = if ($totalLatency -gt 0) { [math]::Round($totalTokens / ($totalLatency / 1000), 2) } else { 0 }

        # Calculate success rate
        $successRate = if ($totalRequests -gt 0) { [math]::Round(($successfulRequests / $totalRequests) * 100, 2) } else { 0 }

        return @{
            ModelName = $modelName
            TotalRequests = $totalRequests
            SuccessfulRequests = $successfulRequests
            FailedRequests = $failedRequests
            AverageLatencyMs = $averageLatency
            MedianLatencyMs = $medianLatency
            P95LatencyMs = $p95Latency
            TokensPerSecond = $tokensPerSecond
            SuccessRate = $successRate
            LastUpdated = $this.LastUpdated
        }
    }

    [hashtable[]] GetAllPerformanceStats() {
        $results = @()
        foreach ($modelName in $this.Cache.Keys) {
            $results += $this.GetPerformanceStats($modelName)
        }
        return $results
    }

    [void] SaveCache() {
        # Convert hashtable to JSON and save
        # Create directory if it doesn't exist
        $dir = Split-Path $this.CachePath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $this.Cache | ConvertTo-Json -Depth 10 | Set-Content -Path $this.CachePath -Encoding UTF8
    }

    [void] LoadCache() {
        if (Test-Path $this.CachePath) {
            $content = Get-Content -Path $this.CachePath -Encoding UTF8 -Raw
            if ($content -ne "") {
                $json = $content | ConvertFrom-Json -Depth 10
                $this.Cache = @{}
                foreach ($key in $json.PSObject.Properties.Name) {
                    $this.Cache[$key] = @()
                    foreach ($entry in $json.$key) {
                        $this.Cache[$key] += $entry
                    }
                }
            }
        }
    }

    [void] ClearCache() {
        $this.Cache = @{}
        $this.SaveCache()
    }
}

# Export functions for module
Export-ModuleMember -Class PerformanceCache
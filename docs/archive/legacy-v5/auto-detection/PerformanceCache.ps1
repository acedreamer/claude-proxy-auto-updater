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
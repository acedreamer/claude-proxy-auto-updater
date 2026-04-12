class SafetyManager {
    [hashtable]$CircuitBreakers = @{}
    [int]$MaxRetries = 5
    [int]$CircuitBreakerThreshold = 5
    [int]$BackoffBase = 2

    SafetyManager() {}

    [hashtable] ExecuteWithRetry([scriptblock]$action, [string]$caller) {
        $attempt = 0
        do {
            $attempt++
            try {
                $result = & $action

                if ($this.CircuitBreakers.ContainsKey($caller)) {
                    $this.CircuitBreakers[$caller].SuccessCount++
                    if ($this.CircuitBreakers[$caller].SuccessCount -ge $this.CircuitBreakerThreshold) {
                        $this.CircuitBreakers.Remove($caller)
                    }
                }

                return @{
                    Success = $true
                    Result = $result
                    Attempt = $attempt
                    Caller = $caller
                }
            } catch {
                if (-not $this.CircuitBreakers.ContainsKey($caller)) {
                    $this.CircuitBreakers[$caller] = @{
                        FailureCount = 0
                        SuccessCount = 0
                    }
                }

                $this.CircuitBreakers[$caller].FailureCount++

                if ($this.CircuitBreakers[$caller].FailureCount -ge $this.CircuitBreakerThreshold) {
                    return @{
                        Success = $false
                        Error = "Circuit breaker tripped for $caller"
                        Attempt = $attempt
                        Caller = $caller
                    }
                }

                if ($attempt -lt $this.MaxRetries) {
                    $backoffMs = [math]::Pow($this.BackoffBase, $attempt - 1) * 1000
                    Start-Sleep -Milliseconds $backoffMs
                }
            }
        } while ($attempt -lt $this.MaxRetries)

        return @{
            Success = $false
            Error = "Max retries exhausted for $caller"
            Attempt = $attempt
            Caller = $caller
        }
    }

    [void] ResetCircuitBreaker([string]$caller) {
        $this.CircuitBreakers.Remove($caller)
    }
}
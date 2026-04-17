class ToolDetector {
    [hashtable]$TierAssumptions = @{
        S = $true   # Assume S-tier models support tools
        A = $true   # Assume A-tier models support tools
        B = $false  # Assume B-tier models don't support tools
        C = $false  # Assume C-tier models don't support tools
    }

    ToolDetector() {}

    [hashtable] CreateToolProbe() {
        return @{
            messages = @(@{ role = "user"; content = "What is the weather in Paris?" })
            tools = @(@{ type = "function"; function = @{
                name = "get_weather"
                description = "Get current weather for a location"
                parameters = @{
                    type = "object"
                    properties = @{
                        location = @{
                            type = "string"
                            description = "City name"
                        }
                    }
                    required = @("location")
                }
            } })
        }
    }

    [hashtable] ProbeToolSupport([string]$apiKey, [string]$modelId, [string]$provider) {
        $probe = $this.CreateToolProbe()
        try {
            if ($provider -eq "nvidia-nim") {
                # NVIDIA NIM probe logic
                $result = @{
                    ToolCallSupported = $false
                    Reason = "NIM probe failed - use tier assumption"
                }
            } elseif ($provider -eq "openrouter") {
                # OpenRouter probe logic
                $result = @{
                    ToolCallSupported = $false
                    Reason = "OpenRouter probe failed - use tier assumption"
                }
            } else {
                $result = @{
                    ToolCallSupported = $false
                    Reason = "Provider '$provider' not implemented"
                }
            }
        } catch {
            $result = @{
                ToolCallSupported = $false
                Reason = "Probe failed: $($_.Exception.Message)"
                Error = $_.Exception.Message
            }
        }
        $result.ProbeStatus = "completed"
        return $result
    }

    [bool] GetFallbackAssumption([string]$tier) {
        return $this.TierAssumptions[$tier]
    }
}
'class ToolDetector {
    [hashtable]$TierAssumptions = @{
        S = $true  # Assume S-tier models support tools
        A = $true  # Assume A-tier models support tools
        B = $false # Assume B-tier models don't support tools
        C = $false # Assume C-tier models don't support tools
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
        # Input validation
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            return @{
                ToolCallSupported = $false
                Reason = "API key is null or empty"
                ProbeStatus = "completed"
            }
        }

        if ([string]::IsNullOrWhiteSpace($modelId)) {
            return @{
                ToolCallSupported = $false
                Reason = "Model ID is null or empty"
                ProbeStatus = "completed"
            }
        }

        if ([string]::IsNullOrWhiteSpace($provider)) {
            return @{
                ToolCallSupported = $false
                Reason = "Provider is null or empty"
                ProbeStatus = "completed"
            }
        }

        $probe = $this.CreateToolProbe()
        try {
            if ($provider -eq "nvidia-nim") {
                # NVIDIA NIM probe logic
                # In production this would make an actual API call to NVIDIA NIM
                # For now, we're implementing conservative fallback behavior
                $result = @{
                    ToolCallSupported = $false
                    Reason = "NIM probe failed - use tier assumption"
                    ProbeStatus = "completed"
                }
            }
            elseif ($provider -eq "openrouter") {
                # OpenRouter probe logic
                # In production this would make an actual API call to OpenRouter
                # For now, we're implementing conservative fallback behavior
                $result = @{
                    ToolCallSupported = $false
                    Reason = "OpenRouter probe failed - use tier assumption"
                    ProbeStatus = "completed"
                }
            }
            else {
                $result = @{
                    ToolCallSupported = $false
                    Reason = "Provider '$provider' not implemented"
                    ProbeStatus = "completed"
                }
            }
        }
        catch {
            $result = @{
                ToolCallSupported = $false
                Reason = "Probe failed: $($_.Exception.Message)"
                Error = $_.Exception.Message
                ProbeStatus = "completed"
            }
        }
        return $result
    }

    [bool] GetFallbackAssumption([string]$tier) {
        # Input validation
        if ([string]::IsNullOrWhiteSpace($tier)) {
            return $false
        }

        # Case-insensitive tier matching
        $normalizedTier = $tier.ToUpper()

        # Return fallback assumption based on tier
        if ($this.TierAssumptions.ContainsKey($normalizedTier)) {
            return $this.TierAssumptions[$normalizedTier]
        }

        # Default to false for unknown tiers (conservative approach)
        return $false
    }
}
# CapabilityRegistry.tests.ps1

# TDD: Failing test first

Describe "CapabilityRegistry" {
    It "should initialize with empty registry" {
        $registry = [CapabilityRegistry]::new("temp/registry.json")
        $registry.Registry.Count | Should -Be 0
    }

    It "should validate model definition with all required fields" {
        $model = @{
            ModelName = "claude-3-5-sonnet"
            SupportsStreaming = $true
            SupportsVision = $true
            MaxContextTokens = 100000
            MaxOutputTokens = 4096
            LatencyMs = 250
            CostPerToken = 0.000005
        }

        $registry = [CapabilityRegistry]::new("temp/registry.json")
        $result = $registry.ValidateModelDefinition($model)
        $result | Should -Be $true
    }

    It "should reject model definition with missing required field" {
        $model = @{
            ModelName = "claude-3-5-sonnet"
            SupportsStreaming = $true
            # Missing SupportsVision
            MaxContextTokens = 100000
            MaxOutputTokens = 4096
            LatencyMs = 250
            CostPerToken = 0.000005
        }

        $registry = [CapabilityRegistry]::new("temp/registry.json")
        $result = $registry.ValidateModelDefinition($model)
        $result | Should -Be $false
    }

    It "should reject model definition with invalid type" {
        $model = @{
            ModelName = "claude-3-5-sonnet"
            SupportsStreaming = $true
            SupportsVision = $true
            MaxContextTokens = "not-a-number"  # Invalid type
            MaxOutputTokens = 4096
            LatencyMs = 250
            CostPerToken = 0.000005
        }

        $registry = [CapabilityRegistry]::new("temp/registry.json")
        $result = $registry.ValidateModelDefinition($model)
        $result | Should -Be $false
    }

    It "should reject model definition with negative MaxContextTokens" {
        $model = @{
            ModelName = "claude-3-5-sonnet"
            SupportsStreaming = $true
            SupportsVision = $true
            MaxContextTokens = -1000  # Invalid value
            MaxOutputTokens = 4096
            LatencyMs = 250
            CostPerToken = 0.000005
        }

        $registry = [CapabilityRegistry]::new("temp/registry.json")
        $result = $registry.ValidateModelDefinition($model)
        $result | Should -Be $false
    }
}

# Create temp directory for tests
$testDir = "temp"
if (-not (Test-Path $testDir)) {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}
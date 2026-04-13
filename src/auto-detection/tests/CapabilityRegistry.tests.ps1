# CapabilityRegistry.tests.ps1

# Import the CapabilityRegistry class
. $PSScriptRoot/../CapabilityRegistry.ps1
Write-Host "Loaded CapabilityRegistry.ps1 from $PSScriptRoot/../CapabilityRegistry.ps1"

# TDD: Failing test first

Describe "CapabilityRegistry" {
    It "should initialize with empty registry" {
        $registry = [CapabilityRegistry]::new()
        $registry.Models.Count | Should -Be 0
        $registry.SchemaVersion | Should -Be "1.0"
    }

    It "should load and save registry from file" {
        $registry = [CapabilityRegistry]::new()
        $registry.Models["model1"] = @{ capability = "test" }
        $registry.SaveToFile("temp/registry.json")
        Test-Path "temp/registry.json" | Should -Be $true

        $newRegistry = [CapabilityRegistry]::new()
        $newRegistry.LoadFromFile("temp/registry.json")
        $newRegistry.Models["model1"].capability | Should -Be "test"
    }

    It "should get model capabilities" {
        $registry = [CapabilityRegistry]::new()
        $registry.Models["model1"] = @{ toolCallOk = $true }
        $capabilities = $registry.GetModelCapabilities("model1")
        $capabilities.toolCallOk | Should -Be $true
    }

    It "should update model capabilities" {
        $registry = [CapabilityRegistry]::new()
        $registry.UpdateModelCapabilities("model2", @{ thinking = $true })
        $registry.Models["model2"].thinking | Should -Be $true
    }
}

# Create temp directory for tests
$testDir = "temp"
if (-not (Test-Path $testDir)) {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}
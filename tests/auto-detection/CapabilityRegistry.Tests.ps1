Describe "CapabilityRegistry" {
    $testPath = "TestDrive:\capabilityregistry.json"

    It "should initialize with default SchemaVersion and empty Models" {
        $registry = [CapabilityRegistry]::new()
        $registry.SchemaVersion | Should -Be "1.0"
        $registry.Models.Count | Should -Be 0
    }

    It "should load data from JSON file" {
        $testData = @{
            SchemaVersion = "1.0"
            Models = @{
                "claude-3-opus" = @{
                    capabilities = @("text", "vision")
                }
            }
        }
        $testData | ConvertTo-Json -Depth 10 | Out-File $testPath -Encoding utf8

        $registry = [CapabilityRegistry]::new()
        $registry.LoadFromFile($testPath)

        $registry.SchemaVersion | Should -Be "1.0"
        $registry.Models["claude-3-opus"].capabilities | Should -Be @("text", "vision")
    }

    It "should save data to JSON file" {
        $registry = [CapabilityRegistry]::new()
        $registry.UpdateModelCapabilities("claude-3-opus", @{ capabilities = @("text", "vision") })
        $registry.SaveToFile($testPath)

        $loadedData = Get-Content $testPath | ConvertFrom-Json -AsHashtable
        $loadedData.SchemaVersion | Should -Be "1.0"
        $loadedData.Models."claude-3-opus".capabilities | Should -Be @("text", "vision")
    }

    It "should get model capabilities" {
        $registry = [CapabilityRegistry]::new()
        $registry.UpdateModelCapabilities("claude-3-opus", @{ capabilities = @("text", "vision") })

        $capabilities = $registry.GetModelCapabilities("claude-3-opus")
        $capabilities.capabilities | Should -Be @("text", "vision")
    }

    It "should update model capabilities" {
        $registry = [CapabilityRegistry]::new()
        $registry.UpdateModelCapabilities("claude-3-opus", @{ capabilities = @("text") })
        $registry.UpdateModelCapabilities("claude-3-opus", @{ capabilities = @("text", "vision") })

        $capabilities = $registry.GetModelCapabilities("claude-3-opus")
        $capabilities.capabilities | Should -Be @("text", "vision")
    }
}
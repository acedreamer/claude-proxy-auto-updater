Import-Module Pester

Describe "update-models.ps1 Tests" {
    BeforeAll {
        . $PSScriptRoot/../update-models.ps1
    }

    Describe "Get-EstimatedLatency" {
        It "Returns 3000ms for context window under 20000" {
            Get-EstimatedLatency 15000 | Should -Be 3000
        }
        It "Returns 10000ms for context window between 20000 and 100000" {
            Get-EstimatedLatency 50000 | Should -Be 10000
        }
        It "Returns 30000ms for context window over 100000" {
            Get-EstimatedLatency 150000 | Should -Be 30000
        }
    }

    Describe "Get-OpenRouterModels" {
        BeforeEach {
            Mock Invoke-RestMethod {
                return @{
                    data = @(
                        @{
                            id = "claude-3-5-sonnet-latest"
                            context_window = 200000
                            info = @{ free = $true }
                        },
                        @{
                            id = "nemotron-4-340b"
                            context_window = 32768
                            info = @{ free = $true }
                        }
                    )
                }
            }
        }

        It "Returns a list of free models" {
            $models = Get-OpenRouterModels -apiKey "test-key"
            $models.Count | Should -Be 2
            $models[0].id | Should -Be "claude-3-5-sonnet-latest"
            $models[0].context_window | Should -Be 200000
        }
    }

    Describe "API Key Check" {
        It "Exits with error when OPENROUTER_API_KEY is missing" {
            $env:OPENROUTER_API_KEY = $null
            $error = $null
            try {
                Main
            } catch {
                $error = $_
            }
            $error.Exception.Message | Should -Match "OPENROUTER_API_KEY environment variable is missing"
        }
    }
}
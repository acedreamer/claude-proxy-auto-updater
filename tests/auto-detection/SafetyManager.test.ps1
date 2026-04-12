Describe "SafetyManager" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/SafetyManager.ps1
    }

    It "initializes circuit breakers correctly" {
        $manager = [SafetyManager]::new()
        $manager.CircuitBreakers.Count | Should Be 0
        $manager.MaxRetries | Should Be 5
    }

    It "handles successful execution" {
        $manager = [SafetyManager]::new()
        $result = $manager.ExecuteWithRetry({ return "success" }, "test-caller")
        $result.Success | Should Be $true
        $result.Result | Should Be "success"
    }
}
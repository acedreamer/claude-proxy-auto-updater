Describe "SafetyManager" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/SafetyManager.ps1
    }

    It "initializes circuit breakers correctly" {
        $manager = [SafetyManager]::new()
        if ($manager.CircuitBreakers.Count -ne 0) {
            Write-Error "Expected CircuitBreakers.Count to be 0, but got $($manager.CircuitBreakers.Count)"
        }
        if ($manager.MaxRetries -ne 5) {
            Write-Error "Expected MaxRetries to be 5, but got $($manager.MaxRetries)"
        }
    }

    It "handles successful execution" {
        $manager = [SafetyManager]::new()
        $result = $manager.ExecuteWithRetry({ return "success" }, "test-caller")
        if ($result.Success -ne $true) {
            Write-Error "Expected Success to be $true, but got $($result.Success)"
        }
        if ($result.Result -ne "success") {
            Write-Error "Expected Result to be \"success\", but got \"$($result.Result)\""
        }
    }
}
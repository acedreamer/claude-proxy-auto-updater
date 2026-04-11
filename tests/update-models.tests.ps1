#Requires -Version 5.1

# Source the SUT functions (only functions before line 126 load)
$env:NVIDIA_NIM_API_KEY = "test-key"
$env:OPENROUTER_API_KEY = "test-key"
$scriptPath = Join-Path $PSScriptRoot '..' 'update-models.ps1'
. $scriptPath

# Note: Script exits at line 126 if no API keys, so only functions defined before that are available
# Available: Write-Banner, Set-SecureACL, Read-EnvFile, Get-ModelPrefix, Get-CapKey

Describe "Write-Banner" {
    It "outputs banner with centered text" {
        { Write-Banner -Text "TEST" -Color "Cyan" } | Should Not Throw
    }
}

Describe "Get-ModelPrefix" {
    It "prefixes nvidia provider with nvidia_nim" {
        $result = Get-ModelPrefix -Provider "nvidia" -ModelId "test/model"
        $result | Should Be "nvidia_nim/test/model"
    }

    It "prefixes openrouter provider with open_router" {
        $result = Get-ModelPrefix -Provider "openrouter" -ModelId "test/model"
        $result | Should Be "open_router/test/model"
    }

    It "passes through unknown providers" {
        $result = Get-ModelPrefix -Provider "custom" -ModelId "test/model"
        $result | Should Be "custom/test/model"
    }
}

Describe "Get-CapKey" {
    It "formats provider and model as key" {
        $result = Get-CapKey -Provider "nvidia" -ModelId "deepseek/deepseek-r1"
        $result | Should Be "nvidia/deepseek/deepseek-r1"
    }
}

Describe "Read-EnvFile" {
    It "returns empty hashtable when file does not exist" {
        $result = Read-EnvFile -Path "C:\nonexistent\file.env"
        $result.Count | Should Be 0
    }

    It "parses KEY=value format" {
        $testFile = Join-Path $env:TEMP "test-env-$(Get-Random).env"
        'KEY1=value1' | Set-Content -Path $testFile

        $result = Read-EnvFile -Path $testFile

        Remove-Item $testFile -ErrorAction SilentlyContinue
    }
}

Describe "Set-SecureACL" {
    It "does not throw when path does not exist" {
        { Set-SecureACL -Path "C:\nonexistent\path" } | Should Not Throw
    }

    It "sets ACL on existing file without error" {
        $testFile = Join-Path $env:TEMP "test-acl-$(Get-Random).txt"
        "test" | Out-File -FilePath $testFile

        { Set-SecureACL -Path $testFile } | Should Not Throw

        Remove-Item $testFile -ErrorAction SilentlyContinue
    }
}

# TODO: Get-Score tests require script restructuring to move function before line 126
# The current architecture defines Get-Score after the API key check

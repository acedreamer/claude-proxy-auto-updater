#Requires -Version 5.1

# Source the script - but only functions (execution block is bypassed)
$scriptPath = Join-Path $PSScriptRoot '../../update-models.ps1'
. $scriptPath

Describe "Write-Banner" {
    It "runs without throwing" {
        { Write-Banner -Text "TEST" } | Should Not Throw
    }
}

Describe "Get-ModelPrefix" {
    It "prefixes nvidia correctly" {
        Get-ModelPrefix "nvidia" "model1" | Should Be "nvidia_nim/model1"
    }
    It "prefixes openrouter correctly" {
        Get-ModelPrefix "openrouter" "model1" | Should Be "open_router/model1"
    }
}

# Run all auto-detection tests with proper module loading

# Import all required classes before running tests
. "$PSScriptRoot/src/auto-detection/CapabilityRegistry.ps1"
. "$PSScriptRoot/src/auto-detection/PerformanceCache.ps1"
. "$PSScriptRoot/src/auto-detection/RoleDetector.ps1"
. "$PSScriptRoot/src/auto-detection/ToolDetector.ps1"

# Ensure the temp directory exists for tests
$testDir = "$PSScriptRoot/temp"
if (-not (Test-Path $testDir)) {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}

# Run the tests
Invoke-Pester "$PSScriptRoot/tests/auto-detection" -OutputFormat LegacyNUnitXml -OutputFile "$PSScriptRoot/test-results.xml"
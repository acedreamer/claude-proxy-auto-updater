# Run all auto-detection tests with proper module loading

# Import all required classes before running tests
. $PSScriptRoot/src/auto-detection/CapabilityRegistry.ps1
. $PSScriptRoot/src/auto-detection/PerformanceCache.ps1
. $PSScriptRoot/src/auto-detection/RoleDetector.ps1
. $PSScriptRoot/src/auto-detection/ToolDetector.ps1

# Run the tests
Invoke-Pester tests/auto-detection -OutputFormat LegacyNUnitXml -OutputFile test-results.xml
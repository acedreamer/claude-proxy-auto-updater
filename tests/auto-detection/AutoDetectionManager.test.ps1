Describe "AutoDetectionManager" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/CapabilityRegistry.ps1
        . $PSScriptRoot/../../src/auto-detection/PerformanceCache.ps1
        . $PSScriptRoot/../../src/auto-detection/RoleDetector.ps1
        . $PSScriptRoot/../../src/auto-detection/ToolDetector.ps1
        . $PSScriptRoot/../../src/auto-detection/SafetyManager.ps1
        . $PSScriptRoot/../../src/auto-detection/AutoDetectionManager.ps1
    }

    It "initializes all components" {
        $manager = [AutoDetectionManager]::new()
        $manager.Registry | Should Not Be $null
        $manager.Cache | Should Not Be $null
        $manager.RoleDetector | Should Not Be $null
    }
}
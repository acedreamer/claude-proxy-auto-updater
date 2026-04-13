Describe "ToolDetector" {
    BeforeAll {
        . $PSScriptRoot/../../src/auto-detection/ToolDetector.ps1
    }

    It "creates valid tool probe" {
        $detector = [ToolDetector]::new()
        $probe = $detector.CreateToolProbe()
        $probe.messages.Count | Should Be 1
        $probe.tools.Count | Should Be 1
    }

    It "provides tier-based fallback assumptions" {
        $detector = [ToolDetector]::new()
        $detector.GetFallbackAssumption("S") | Should Be $true
        $detector.GetFallbackAssumption("C") | Should Be $false
    }
}
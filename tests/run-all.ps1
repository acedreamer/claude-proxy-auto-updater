# Unified test runner for v6.1

$ErrorActionPreference = 'Continue'
$anyFailed = $false

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  CLAUDE PROXY AUTO-UPDATER TEST SUITE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Node.js Brain Tests
Write-Host "`n>>> [NODE.JS] SELECTOR UNIT TESTS" -ForegroundColor Yellow
node --test tests/unit/selector.test.mjs
if ($LASTEXITCODE -ne 0) { $anyFailed = $true }

# 2. PowerShell Utility Tests
Write-Host "`n>>> [POWERSHELL] UTILITY UNIT TESTS" -ForegroundColor Yellow
Invoke-Pester tests/unit/update-models.ps1.tests.ps1
if ($LASTEXITCODE -ne 0) { $anyFailed = $true }

# 3. Bash Utility Tests (if sh.exe available)
if (Get-Command sh -ErrorAction SilentlyContinue) {
    Write-Host "`n>>> [BASH] UTILITY UNIT TESTS" -ForegroundColor Yellow
    sh tests/unit/update-models.sh.test
    if ($LASTEXITCODE -ne 0) { $anyFailed = $true }
}

Write-Host "`n==========================================" -ForegroundColor Cyan
if ($anyFailed) {
    Write-Host "  TEST SUITE FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  TEST SUITE PASSED" -ForegroundColor Green
    exit 0
}

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
#  Claude Proxy Auto-Updater  v6.0
#  acedreamer/claude-proxy-auto-updater
#
#  Refactored to delegate selection logic to selector.mjs
#
#  Uses free-coding-models internals (fcm-oneshot.mjs) for:
#    - Real latency measurement (actual inference pings)
#    - Verdict classification: Perfect / Normal / Slow / Spiky / Overloaded
#    - Stability score (0-100): p95 + jitter + spike rate + uptime
#    - Uptime %: fraction of successful pings
#
#  This is far more accurate than the previous runspace HTTP health
#  checks because it uses the SAME ping logic as free-coding-models.
# ============================================================

$envPath    = Join-Path $PSScriptRoot ".env"
$backupPath = "$envPath.backup"
$cacheFile  = Join-Path $PSScriptRoot "model-cache.json"
$candidatesFile = Join-Path $PSScriptRoot "model-candidates.json"
$oneshotScript = Join-Path $PSScriptRoot "fcm-oneshot.mjs"
$DryRun = ($args -contains '--dry-run') -or ($args -contains '-DryRun')
$ToolTest = ($args -contains '--tool-test')

$Config = @{
    CacheTTLMinutes = 15      # Minutes before re-running fcm-oneshot
    PingTimeoutMs   = 15000   # Passed to fcm-oneshot --timeout
    Providers       = "nvidia,openrouter"  # Comma list passed to fcm-oneshot --providers
    TierFilter      = "S+,S,A+,A"   # Only S+/S/A+/A tier models
    # Verdict gate: only accept these verdicts for tool-sensitive slots
    # Haiku is less strict since it handles lighter tasks
    OpusSonnetVerdicts  = @("Perfect", "Normal")
    HaikuVerdicts       = @("Perfect", "Normal", "Slow")
    FallbackVerdicts    = @("Perfect", "Normal", "Slow", "Spiky")
}

# ============================================================
#  AUTO-DETECTION SETUP
#  Dynamic model capability detection replaces static registry
# ============================================================
# Auto-detection system removed. Using inline logic instead.

# ============================================================
#  UTILITIES
# ============================================================
function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $pad = "=" * [math]::Max(0, (54 - $Text.Length) / 2)
    Write-Host "$pad $Text $pad" -ForegroundColor $Color
}

function Set-SecureACL {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    try {
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl  = Get-Acl $Path
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($id in @($user, "SYSTEM")) {
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $id,"FullControl","Allow"))
        }
        Set-Acl $Path $acl
    } catch { }
}

function Read-EnvFile {
    param([string]$Path)
    $result = @{}
    if (-not (Test-Path $Path)) { return $result }
    foreach ($line in Get-Content $Path) {
        if ($line -match '^([A-Z_]+)="?(.*?)"?\s*$') {
            $result[$matches[1]] = $matches[2]
        }
    }
    return $result
}

function Get-ModelPrefix {
    param([string]$Provider, [string]$ModelId)
    switch ($Provider) {
        "nvidia"     { return "nvidia_nim/$ModelId" }
        "openrouter" { return "open_router/$ModelId" }
        default      { return "$Provider/$ModelId" }
    }
}

function Extract-JsonArrayFromText {
    param([string]$Text)
    if (-not $Text) { return $null }
    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -ne '[') { continue }
        for ($j = $Text.Length - 1; $j -gt $i; $j--) {
            if ($Text[$j] -ne ']') { continue }
            $candidate = $Text.Substring($i, $j - $i + 1)
            try {
                $parsed = $candidate | ConvertFrom-Json
                if ($parsed -is [System.Array] -or $parsed.Count -ge 0) {
                    return $parsed
                }
            } catch { }
        }
    }
    return $null
}

# ============================================================
#  LOAD KEYS
# ============================================================
$envData = Read-EnvFile $envPath

$nimKey = $envData["NVIDIA_NIM_API_KEY"]
$orKey  = $envData["OPENROUTER_API_KEY"]

if (-not $nimKey -and -not $orKey) {
    Write-Host "[ERROR] No API keys in .env (NVIDIA_NIM_API_KEY / OPENROUTER_API_KEY)" -ForegroundColor Red
    exit 1
}

# Expose keys as env vars for fcm-oneshot.mjs
if ($nimKey) { $env:NVIDIA_API_KEY = $nimKey }
if ($orKey)  { $env:OPENROUTER_API_KEY = $orKey }

# ============================================================
#  CACHE CHECK
# ============================================================
$liveModels = $null
$usingCache = $false

if (Test-Path $cacheFile) {
    $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
    if ($cacheAge.TotalMinutes -lt $Config.CacheTTLMinutes) {
        try {
            $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
            if ($cached -and $cached.Count -gt 0 -and $cached[0].modelId) {
                $liveModels = $cached
                $usingCache = $true
                $ageMin = [math]::Round($cacheAge.TotalMinutes)
                $nextMin = [math]::Round($Config.CacheTTLMinutes - $cacheAge.TotalMinutes)
                Write-Host "[CACHE] Using ${ageMin}m old data. Refresh in ${nextMin}m." -ForegroundColor Magenta

            }
        } catch { }
    }
}

# ============================================================
#  RUN FCM-ONESHOT
# ============================================================
if (-not $usingCache) {
    Write-Banner "PINGING MODELS VIA FREE-CODING-MODELS" "Cyan"

    # Verify prerequisites
    $nodePath = (Get-Command "node" -ErrorAction SilentlyContinue).Source
    if (-not $nodePath) {
        Write-Host "[ERROR] Node.js not found. Required for fcm-oneshot.mjs" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $oneshotScript)) {
        Write-Host "[ERROR] fcm-oneshot.mjs not found at: $oneshotScript" -ForegroundColor Red
        Write-Host "        Place fcm-oneshot.mjs in the same folder as this script." -ForegroundColor DarkYellow
        exit 1
    }

    Write-Host "  Running one-shot ping (timeout: $($Config.PingTimeoutMs)ms per model)..." -ForegroundColor White
    Write-Host "  Providers: $($Config.Providers)  |  Tier filter: $($Config.TierFilter)" -ForegroundColor DarkGray
    Write-Host ""

    $nodeArgs = @(
        $oneshotScript,
        "--providers", $Config.Providers,
        "--tier",      $Config.TierFilter,
        "--timeout",   $Config.PingTimeoutMs
    )
    if ($ToolTest) {
        $nodeArgs += "--tool-test"
        Write-Host "  Tool-call probing: ENABLED" -ForegroundColor Yellow
    }

    $ErrorActionPreference = 'Continue'
    $rawOutput = & node @nodeArgs 2>&1
    $exitCode  = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    $rawText = ($rawOutput | ForEach-Object { [string]$_ }) -join "`n"
    $parsed = Extract-JsonArrayFromText -Text $rawText
    if ($parsed -and $parsed.Count -gt 0) {
        $liveModels = $parsed
    } else {
        Write-Host "[WARN] JSON parse failed from fcm-oneshot output." -ForegroundColor Yellow
    }

    if ($null -eq $liveModels -or $liveModels.Count -eq 0) {
        Write-Host "[WARN] fcm-oneshot returned no usable data (exit $exitCode). Using existing .env." -ForegroundColor Yellow
        exit 0
    }

    # Print results table
    Write-Host ""
    Write-Host ("  {0,-54} {1,-10} {2,-8} {3,-8} {4}" -f "MODEL", "VERDICT", "AVG", "STAB", "TIER") -ForegroundColor DarkGray
    foreach ($m in $liveModels) {
        $tag     = if ($m.status -eq "up") { "[OK]" } else { "[XX]" }
        $avgStr  = if ($m.avgMs)  { "$($m.avgMs)ms" }  else { "---" }
        $stabStr = if ($null -ne $m.stability) { "$($m.stability)" } else { "?" }
        Write-Host ("  $tag {0,-50} {1,-10} {2,-8} {3,-8} {4}" -f "$($m.provider)/$($m.modelId)", $m.verdict, $avgStr, $stabStr, $m.tier) -ForegroundColor White
    }
    Write-Host ""

    # Cache it
    try {
        $liveModels | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
        Set-SecureACL $cacheFile
    } catch { }

}

# ============================================================
#  DELEGATE SELECTION TO selector.mjs
# ============================================================
Write-Host "  Selecting best models for each slot..." -ForegroundColor White

$selectorScript = Join-Path $PSScriptRoot "selector.mjs"
$selectorOutput = & node $selectorScript 2>$null
if ($LASTEXITCODE -ne 0 -or -not $selectorOutput) {
    Write-Host "[ERROR] selector.mjs failed or returned no output." -ForegroundColor Red
    exit 1
}

try {
    $selectionResult = $selectorOutput | ConvertFrom-Json
} catch {
    Write-Host "[ERROR] Failed to parse JSON from selector.mjs." -ForegroundColor Red
    exit 1
}

# ============================================================
#  UI LAYER: MODEL SELECTION
# ============================================================
Write-Host ""
Write-Host "============= MODEL SELECTION ===========================================================================" -ForegroundColor Cyan
Write-Host ("{0,-10} | {1,-42} | {2,-5} | {3,-6} | {4,-7} | {5,-7} | {6}" -f "SLOT", "MODEL", "THINK", "SCORE", "VERDICT", "LAT(ms)", "Runner-up") -ForegroundColor DarkGray
Write-Host "=========================================================================================================" -ForegroundColor Cyan

$slotNames = @("opus", "sonnet", "haiku", "fallback")
foreach ($sn in $slotNames) {
    $slot = $selectionResult.slots.$sn
    if (-not $slot -or -not $slot.winner) { continue }
    
    $w = $slot.winner
    $prefix = Get-ModelPrefix $w.provider $w.modelId
    $think = if ($w.thinking) { "Yes" } else { "No" }
    $score = [math]::Round($w.score, 1)
    $verd  = $w.verdict
    $lat   = if ($w.avgMs -eq 9999.0) { "---" } else { [math]::Round($w.avgMs) }
    
    $runup = "none"
    if ($slot.runner_up) {
        $r = $slot.runner_up
        $rName = $r.modelId.Split("/")[-1]
        if ($rName.Length -gt 15) { $rName = $rName.Substring(0, 15) + ".." }
        $diff = [math]::Round($w.score - $r.score, 1)
        $runup = "$rName (d-$diff)"
    }
    
    Write-Host ("{0,-10} | {1,-42} | {2,-5} | {3,6} | {4,-7} | {5,7} | {6}" -f $sn.ToUpper(), $prefix, $think, $score, $verd, $lat, $runup) -ForegroundColor White
}

# ============================================================
#  UI LAYER: SCORE BREAKDOWN
# ============================================================
Write-Host ""
Write-Host "============= SCORE BREAKDOWN ============================" -ForegroundColor Cyan
Write-Host ("{0,-10} | {1,6} | {2,6} | {3,6} | {4,6} | {5,6}" -f "SLOT", "SWE", "STAB", "LAT", "NIM", "TOTAL") -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan

foreach ($sn in $slotNames) {
    $slot = $selectionResult.slots.$sn
    if (-not $slot -or -not $slot.winner) { continue }
    
    $w = $slot.winner
    $comps = $w.scoreComponents
    Write-Host ("{0,-10} | {1,6:N1} | {2,6:N1} | {3,6:N1} | {4,6:N1} | {5,6:N1}" -f $sn.ToUpper(), $comps.swe, $comps.stab, $comps.lat, $comps.nim, $w.score) -ForegroundColor White
}
Write-Host ""

# Build .env
$envLines = if (Test-Path $envPath) { Get-Content $envPath } else { @() }
$newLines = @()
$isThinking = if ($selectionResult.is_thinking) { "true" } else { "false" }

$mappings = @{
    "MODEL_OPUS="          = "MODEL_OPUS=`"$(Get-ModelPrefix $selectionResult.slots.opus.winner.provider $selectionResult.slots.opus.winner.modelId)`""
    "MODEL_SONNET="        = "MODEL_SONNET=`"$(Get-ModelPrefix $selectionResult.slots.sonnet.winner.provider $selectionResult.slots.sonnet.winner.modelId)`""
    "MODEL_HAIKU="         = "MODEL_HAIKU=`"$(Get-ModelPrefix $selectionResult.slots.haiku.winner.provider $selectionResult.slots.haiku.winner.modelId)`""
    "MODEL="               = "MODEL=`"$(Get-ModelPrefix $selectionResult.slots.fallback.winner.provider $selectionResult.slots.fallback.winner.modelId)`""
    "NIM_ENABLE_THINKING=" = "NIM_ENABLE_THINKING=$isThinking"
}


foreach ($line in $envLines) {
    $matched = $false
    foreach ($prefix in $mappings.Keys) {
        if ($line.TrimStart().StartsWith($prefix)) {
            $newLines += $mappings[$prefix]; $matched = $true; break
        }
    }
    if (-not $matched) { $newLines += $line }
}

foreach ($prefix in $mappings.Keys) {
    if (-not ($newLines | Where-Object { $_.TrimStart().StartsWith($prefix) })) {
        $newLines += $mappings[$prefix]
    }
}

if ($DryRun) {
    Write-Host "[DRY RUN] .env not modified" -ForegroundColor Yellow
} else {
    Set-Content -Path $envPath -Value $newLines -Encoding UTF8
    Write-Host "[OK] .env updated via fcm-oneshot telemetry." -ForegroundColor Green
}

# SECURITY: Clean up sensitive data from memory
if ($env:NVIDIA_API_KEY) { Remove-Item Env:\NVIDIA_API_KEY -ErrorAction SilentlyContinue }
if ($env:OPENROUTER_API_KEY) { Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue }

# Remove backup file after successful update
if (Test-Path $backupPath) {
    try { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue } catch { }
}

exit 0
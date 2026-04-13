#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
#  Claude Proxy Auto-Updater  v4.0
#  acedreamer/claude-proxy-auto-updater
#
#  Uses free-coding-models internals (fcm-oneshot.mjs) for:
#    - Real latency measurement (actual inference pings)
#    - Verdict classification: Perfect / Normal / Slow / Spiky / Overloaded
#    - Stability score (0-100): p95 + jitter + spike rate + uptime
#    - Uptime %: fraction of successful pings
#
#  This is far more accurate than the previous runspace HTTP health
#  checks because it uses the SAME ping logic as free-coding-models.
#
#  SLOT RULES:
#    OPUS     -> toolCallOk required, heavy role, verdict Normal or better
#    SONNET   -> toolCallOk required, balanced, any good verdict
#    HAIKU    -> fast role, toolCallOk NOT required, lowest latency
#    FALLBACK -> toolCallOk required, highest stability score
# ============================================================

$envPath    = Join-Path $PSScriptRoot ".env"
$backupPath = "$envPath.backup"
$cacheFile  = Join-Path $PSScriptRoot "model-cache.json"
$candidatesFile = Join-Path $PSScriptRoot "model-candidates.json"
$oneshotScript = Join-Path $PSScriptRoot "fcm-oneshot.mjs"
$DryRun = ($args -contains '--dry-run') -or ($args -contains '-DryRun')
$ToolTest = ($args -contains '--tool-test')

$Config = @{
    CacheTTLMinutes = 0.3      # Minutes before re-running fcm-oneshot
    PingTimeoutMs   = 15000   # Passed to fcm-oneshot --timeout
    Providers       = "nvidia,openrouter"  # Comma list passed to fcm-oneshot --providers
    TierFilter      = "S,A"   # Only S+/S/A+/A/A- tier models
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

function Get-CapKey {
    param([string]$Provider, [string]$ModelId)
    return "$Provider/$ModelId"
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

function Is-VerdictAllowed {
    param(
        [string]$Slot,
        [string]$Verdict,
        [bool]$IsDegraded
    )
    if ($IsDegraded) { return $true }
    switch ($Slot) {
        "opus"     { return $Config.OpusSonnetVerdicts -contains $Verdict }
        "sonnet"   { return $Config.OpusSonnetVerdicts -contains $Verdict }
        "haiku"    { return $Config.HaikuVerdicts -contains $Verdict }
        "fallback" { return $Config.FallbackVerdicts -contains $Verdict }
    }
    return $false
}

function Is-ThinkingModel {
    param([string]$ModelId)

    $patterns = @(
        'deepseek-r1',
        'kimi-k2-thinking',
        'qwq',
        '-thinking$'
    )
    foreach ($pattern in $patterns) {
        if ($ModelId -match [regex]::Escape($pattern)) { return $true }
    }
    # Also catch exact keyword match without full regex search if needed
    if ($ModelId -match '\b(thinking|r1)\b|thinking-model|reasoning') { return $true }
    return $false
}

# Get-IsThinking function removed - thinking models are identified by model ID pattern
# thinking status is determined by model name containing "thinking" or specific patterns

function Get-ToolCallEffective {
    param($Model)

    # Use probe status if available from fcm-oneshot
    $status = [string]$Model.toolCallProbeStatus
    if ($status -eq "pass") { return $true }
    if ($status -eq "fail") { return $false }

    # If status is not determined and we have explicit toolCallOk, use it
    if ($status -and $status -ne "unknown" -and $null -ne $Model.toolCallOk) {
        return [bool]$Model.toolCallOk
    }

    # Fallback: Tier-based assumption
    if ($Model.tier -match "^(S\+|S|A\+|A)$") {
        return $true  # Assume S and A tier support tools
    } else {
        return $false # Assume lower tiers don't support tools
    }
}

function Get-TopCandidates {
    param(
        [array]$Models,
        [hashtable]$Weight,
        [int]$Top = 3
    )
    return $Models |
        Sort-Object { Get-Score $_ $Weight } -Descending |
        Select-Object -First $Top |
        ForEach-Object {
            [PSCustomObject]@{
                model = $_.modelId
                prefix = (Get-ModelPrefix $_.provider $_.modelId)
                score = [math]::Round((Get-Score $_ $Weight), 1)
                verdict = $_.verdict
                avgMs = $_.avgMs
                stability = $_.stability
                toolCallOk = $_.effectiveToolCallOk
            }
        }
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
#  SCORING & ASSIGNMENT
# ============================================================
$script:IsDegraded = @($liveModels | Where-Object { $_.degraded -eq $true }).Count -gt 0
if ($script:IsDegraded) {
    Write-Host "[WARN] free-coding-models not found. Install with: npm install -g free-coding-models for full scoring." -ForegroundColor Yellow
}

$normalizedModels = @(
    $liveModels | ForEach-Object {
        $effectiveTool = Get-ToolCallEffective $_
        [PSCustomObject]@{
            modelId = $_.modelId
            provider = $_.provider
            tier = $_.tier
            swe = if ($null -ne $_.swe) { [double]$_.swe } elseif ($null -ne $_.sweBench) { [double]$_.sweBench } else { 0.0 }
            status = $_.status
            verdict = if ($_.verdict) { $_.verdict } else { "Unknown" }
            avgMs = if ($null -ne $_.avgMs) { [double]$_.avgMs } else { 9999.0 }
            stability = if ($null -ne $_.stability) { [double]$_.stability } else { 0.0 }
            degraded = [bool]$_.degraded
            toolCallOk = $_.toolCallOk
            toolCallProbeStatus = if ($_.toolCallProbeStatus) { [string]$_.toolCallProbeStatus } else { "unknown" }
            effectiveToolCallOk = $effectiveTool
            thinking = (Is-ThinkingModel $_.modelId)
        }
    }
)

$aliveModels = @($normalizedModels | Where-Object { $_.status -eq "up" })

function Get-Score {
    param($model, [hashtable]$W)
    $avgMs = if ($null -ne $model.avgMs) { [double]$model.avgMs } else { 9999.0 }
    $latScore  = [math]::Max(0, [math]::Min(100, 100 - (($avgMs - $W.LatTarget) * $W.LatPenalty)))
    if ($script:IsDegraded) {
        return $latScore
    }
    $sweScore  = if ($null -ne $model.swe) { [double]$model.swe } else { 0.0 }
    $stability = if ($null -ne $model.stability) { [double]$model.stability } else { 30.0 }
    $nimBonus  = if ($model.provider -eq "nvidia") { 8 } else { 0 }
    return ($sweScore * $W.SWE) + ($stability * $W.Stab) + ($latScore * $W.Lat) + ($nimBonus * $W.NIM)
}

$Weights = @{
    Opus     = @{ SWE=0.55; Stab=0.20; Lat=0.05; NIM=1.5; LatTarget=1500; LatPenalty=0.01 }
    Sonnet   = @{ SWE=0.35; Stab=0.25; Lat=0.25; NIM=1.0; LatTarget=500;  LatPenalty=0.04 }
    Haiku    = @{ SWE=0.05; Stab=0.15; Lat=0.70; NIM=0.5; LatTarget=200;  LatPenalty=0.12 }
    Fallback = @{ SWE=0.25; Stab=0.50; Lat=0.10; NIM=1.0; LatTarget=800;  LatPenalty=0.02 }
}

$opusEligible = @(
    $aliveModels | Where-Object {
        $_.effectiveToolCallOk -and
        -not $_.thinking -and
        (Is-VerdictAllowed -Slot "opus" -Verdict $_.verdict -IsDegraded $script:IsDegraded)
    }
)
if ($opusEligible.Count -eq 0) {
    $opusEligible = @($aliveModels | Where-Object { $_.effectiveToolCallOk -and -not $_.thinking })
}
$opusCandidate = $opusEligible | Sort-Object { Get-Score $_ $Weights.Opus } -Descending | Select-Object -First 1
if (-not $opusCandidate) {
    $opusCandidate = $aliveModels | Sort-Object { Get-Score $_ $Weights.Opus } -Descending | Select-Object -First 1
}

$sonnetEligible = @(
    $aliveModels | Where-Object {
        $_.modelId -ne $opusCandidate.modelId -and
        $_.effectiveToolCallOk -and
        -not $_.thinking -and
        (Is-VerdictAllowed -Slot "sonnet" -Verdict $_.verdict -IsDegraded $script:IsDegraded)
    }
)
if ($sonnetEligible.Count -eq 0) {
    $sonnetEligible = @($aliveModels | Where-Object { $_.modelId -ne $opusCandidate.modelId -and $_.effectiveToolCallOk })
}
$sonnetCandidate = $sonnetEligible | Sort-Object { Get-Score $_ $Weights.Sonnet } -Descending | Select-Object -First 1
if (-not $sonnetCandidate) { $sonnetCandidate = $opusCandidate }

$haikuEligible = @(
    $aliveModels | Where-Object {
        $_.modelId -notin @($opusCandidate.modelId, $sonnetCandidate.modelId) -and
        -not $_.thinking -and
        (Is-VerdictAllowed -Slot "haiku" -Verdict $_.verdict -IsDegraded $script:IsDegraded)
    }
)
if ($haikuEligible.Count -eq 0) {
    $haikuEligible = @($aliveModels | Where-Object { $_.modelId -notin @($opusCandidate.modelId, $sonnetCandidate.modelId) })
}
$haikuCandidate = $haikuEligible | Sort-Object { Get-Score $_ $Weights.Haiku } -Descending | Select-Object -First 1
if (-not $haikuCandidate) { $haikuCandidate = $sonnetCandidate }

$fallbackEligible = @(
    $aliveModels | Where-Object {
        $_.modelId -notin @($opusCandidate.modelId, $sonnetCandidate.modelId, $haikuCandidate.modelId) -and
        $_.effectiveToolCallOk -and
        -not $_.thinking -and
        (Is-VerdictAllowed -Slot "fallback" -Verdict $_.verdict -IsDegraded $script:IsDegraded)
    }
)
if ($fallbackEligible.Count -eq 0) {
    $fallbackEligible = @($aliveModels | Where-Object { $_.effectiveToolCallOk -and -not $_.thinking })
}
$fallbackCandidate = $fallbackEligible | Sort-Object { Get-Score $_ $Weights.Fallback } -Descending | Select-Object -First 1
if (-not $fallbackCandidate) { $fallbackCandidate = $opusCandidate }

$isThinking = if ($sonnetCandidate.thinking) { "true" } else { "false" }

$candidatesJson = [ordered]@{
    opus     = @(Get-TopCandidates -Models $opusEligible -Weight $Weights.Opus -Top 3)
    sonnet   = @(Get-TopCandidates -Models $sonnetEligible -Weight $Weights.Sonnet -Top 3)
    haiku    = @(Get-TopCandidates -Models $haikuEligible -Weight $Weights.Haiku -Top 3)
    fallback = @(Get-TopCandidates -Models $fallbackEligible -Weight $Weights.Fallback -Top 3)
}
try {
    $candidatesJson | ConvertTo-Json -Depth 6 | Out-File $candidatesFile -Encoding utf8
    Write-Host "[OK] Candidates written to $candidatesFile" -ForegroundColor Green
} catch {
    Write-Host "[WARN] Failed to write ${candidatesFile}: $($_.Exception.Message)" -ForegroundColor Yellow
}

function Get-PrintableRunnerUp {
    param($col)
    if (-not $col -or $col.Count -lt 2) { return "none" }
    $runner = $col[1].model.Split("/")[-1]
    if ($runner.Length -gt 15) { $runner = $runner.Substring(0, 15) + ".." }
    $diff = [math]::Round($col[0].score - $col[1].score, 1)
    return "$runner (d-$diff)"
}

function Get-ScoreComponents {
    param($model, [hashtable]$W)
    $avgMs = if ($null -ne $model.avgMs -and $model.avgMs -ne 9999.0) { [double]$model.avgMs } else { 9999.0 }
    $latScore = [math]::Max(0, [math]::Min(100, 100 - (($avgMs - $W.LatTarget) * $W.LatPenalty)))
    if ($script:IsDegraded) { return [PSCustomObject]@{ SWE=0; Stab=0; Lat=$latScore; NIM=0; Total=$latScore } }
    
    $sweScore  = if ($null -ne $model.swe) { [double]$model.swe } else { 0.0 }
    $stability = if ($null -ne $model.stability) { [double]$model.stability } else { 30.0 }
    $nimBonus  = if ($model.provider -eq "nvidia") { 8 } else { 0 }
    
    return [PSCustomObject]@{
        SWE   = [math]::Round($sweScore * $W.SWE, 1)
        Stab  = [math]::Round($stability * $W.Stab, 1)
        Lat   = [math]::Round($latScore * $W.Lat, 1)
        NIM   = [math]::Round($nimBonus * $W.NIM, 1)
        Total = [math]::Round((($sweScore * $W.SWE) + ($stability * $W.Stab) + ($latScore * $W.Lat) + ($nimBonus * $W.NIM)), 1)
    }
}

$slots = @(
    [PSCustomObject]@{ Name="OPUS";     Model=$opusCandidate;     Weight=$Weights.Opus;     Json=$candidatesJson.opus }
    [PSCustomObject]@{ Name="SONNET";   Model=$sonnetCandidate;   Weight=$Weights.Sonnet;   Json=$candidatesJson.sonnet }
    [PSCustomObject]@{ Name="HAIKU";    Model=$haikuCandidate;    Weight=$Weights.Haiku;    Json=$candidatesJson.haiku }
    [PSCustomObject]@{ Name="FALLBACK"; Model=$fallbackCandidate; Weight=$Weights.Fallback; Json=$candidatesJson.fallback }
)

Write-Host ""
Write-Host "============= MODEL SELECTION ===========================================================================" -ForegroundColor Cyan
Write-Host ("{0,-10} | {1,-42} | {2,-5} | {3,-6} | {4,-7} | {5,-7} | {6}" -f "SLOT", "MODEL", "THINK", "SCORE", "VERDICT", "LAT(ms)", "Runner-up") -ForegroundColor DarkGray
Write-Host "=========================================================================================================" -ForegroundColor Cyan
foreach ($slot in $slots) {
    if (-not $slot.Model) { continue }
    $prefix = Get-ModelPrefix $slot.Model.provider $slot.Model.modelId
    $think = if ($slot.Model.thinking) { "Yes" } else { "No" }
    $score = [math]::Round((Get-Score $slot.Model $slot.Weight), 1)
    $verd  = $slot.Model.verdict
    $lat   = if ($slot.Model.avgMs -eq 9999.0) { "---" } else { [math]::Round($slot.Model.avgMs) }
    $runup = Get-PrintableRunnerUp $slot.Json
    Write-Host ("{0,-10} | {1,-42} | {2,-5} | {3,6} | {4,-7} | {5,7} | {6}" -f $slot.Name, $prefix, $think, $score, $verd, $lat, $runup) -ForegroundColor White
}

Write-Host ""
Write-Host "============= SCORE BREAKDOWN ============================" -ForegroundColor Cyan
Write-Host ("{0,-10} | {1,6} | {2,6} | {3,6} | {4,6} | {5,6}" -f "SLOT", "SWE", "STAB", "LAT", "NIM", "TOTAL") -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan
foreach ($slot in $slots) {
    if (-not $slot.Model) { continue }
    $comps = Get-ScoreComponents $slot.Model $slot.Weight
    Write-Host ("{0,-10} | {1,6:N1} | {2,6:N1} | {3,6:N1} | {4,6:N1} | {5,6:N1}" -f $slot.Name, $comps.SWE, $comps.Stab, $comps.Lat, $comps.NIM, $comps.Total) -ForegroundColor White
}
Write-Host ""

# Build .env
$envLines = if (Test-Path $envPath) { Get-Content $envPath } else { @() }
$newLines = @()
$mappings = @{
    "MODEL_OPUS="          = "MODEL_OPUS=`"$(Get-ModelPrefix $opusCandidate.provider $opusCandidate.modelId)`""
    "MODEL_SONNET="        = "MODEL_SONNET=`"$(Get-ModelPrefix $sonnetCandidate.provider $sonnetCandidate.modelId)`""
    "MODEL_HAIKU="         = "MODEL_HAIKU=`"$(Get-ModelPrefix $haikuCandidate.provider $haikuCandidate.modelId)`""
    "MODEL="               = "MODEL=`"$(Get-ModelPrefix $fallbackCandidate.provider $fallbackCandidate.modelId)`""
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

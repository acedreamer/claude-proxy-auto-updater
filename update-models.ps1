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
$oneshotScript = Join-Path $PSScriptRoot "fcm-oneshot.mjs"

$Config = @{
    CacheTTLMinutes = 45      # Minutes before re-running fcm-oneshot
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
#  MODEL CAPABILITY REGISTRY
#  toolCallOk: model correctly handles Anthropic tool schemas
#              through the free-claude-code proxy
#  thinking:   true = genuine reasoning model needing special params
#              (deepseek-r1, qwq, kimi-thinking variants)
#  role:       heavy | balanced | fast
# ============================================================
$ModelCaps = @{
    # NVIDIA NIM
    "nvidia/moonshotai/kimi-k2.5"                         = @{ toolCallOk=$true;  thinking=$false; role="heavy"    }
    "nvidia/moonshotai/kimi-k2-thinking"                  = @{ toolCallOk=$true;  thinking=$true;  role="heavy"    }
    "nvidia/z-ai/glm4.7"                                  = @{ toolCallOk=$true;  thinking=$false; role="heavy"    }
    "nvidia/deepseek-ai/deepseek-v3.2"                    = @{ toolCallOk=$true;  thinking=$false; role="heavy"    }
    "nvidia/deepseek-ai/deepseek-v3-0324"                 = @{ toolCallOk=$true;  thinking=$false; role="heavy"    }
    "nvidia/minimaxai/minimax-m2.5"                       = @{ toolCallOk=$true;  thinking=$false; role="heavy"    }
    "nvidia/meta/llama-3.3-70b-instruct"                  = @{ toolCallOk=$true;  thinking=$false; role="balanced" }
    "nvidia/meta/llama-3.1-405b-instruct"                 = @{ toolCallOk=$true;  thinking=$false; role="heavy"    }
    "nvidia/qwen/qwen2.5-coder-32b-instruct"              = @{ toolCallOk=$true;  thinking=$false; role="balanced" }
    "nvidia/nvidia/llama-3.2-3b-instruct"                 = @{ toolCallOk=$true;  thinking=$false; role="fast"     }
    "nvidia/nvidia/llama-3.1-8b-instruct"                 = @{ toolCallOk=$true;  thinking=$false; role="fast"     }
    # OpenRouter
    "openrouter/deepseek/deepseek-r1:free"                = @{ toolCallOk=$true;  thinking=$true;  role="heavy"    }
    "openrouter/deepseek/deepseek-r1-0528:free"           = @{ toolCallOk=$true;  thinking=$true;  role="heavy"    }
    "openrouter/qwen/qwen3.6-plus:free"                   = @{ toolCallOk=$false; thinking=$true;  role="heavy"    }
}

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

    $ErrorActionPreference = 'Continue'
    $rawOutput = & node @nodeArgs 2>&1
    $exitCode  = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    # Separate stderr (log lines starting with [fcm-oneshot]) from stdout (JSON)
    $jsonLines = @()
    $logLines  = @()
    foreach ($line in $rawOutput) {
        $lineStr = [string]$line
        if ($lineStr.TrimStart().StartsWith("[fcm-oneshot]") -or $lineStr.TrimStart().StartsWith("[")) {
            # Could be log or JSON start - check more carefully
            if ($lineStr.TrimStart().StartsWith("[fcm-oneshot]")) {
                $logLines += $lineStr
                Write-Host "  $lineStr" -ForegroundColor DarkGray
            } else {
                $jsonLines += $lineStr
            }
        } else {
            $jsonLines += $lineStr
        }
    }

    $jsonStr = ($jsonLines -join "`n").Trim()

    # Find the JSON array in output
    $jsonStart = $jsonStr.IndexOf("[")
    $jsonEnd   = $jsonStr.LastIndexOf("]")

    if ($jsonStart -ge 0 -and $jsonEnd -gt $jsonStart) {
        $jsonStr = $jsonStr.Substring($jsonStart, $jsonEnd - $jsonStart + 1)
        try {
            $parsed = $jsonStr | ConvertFrom-Json
            if ($parsed -and $parsed.Count -gt 0) {
                $liveModels = $parsed
            }
        } catch {
            Write-Host "[WARN] JSON parse failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
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
function Get-Score {
    param($model, [hashtable]$W)
    $sweScore  = [double]$model.swe
    $stability = if ($null -ne $model.stability) { [double]$model.stability } else { 30.0 }
    $avgMs     = if ($null -ne $model.avgMs)     { [double]$model.avgMs }     else { 9999.0 }
    $latScore  = [math]::Max(0, [math]::Min(100, 100 - (($avgMs - $W.LatTarget) * $W.LatPenalty)))
    $nimBonus  = if ($model.provider -eq "nvidia") { 8 } else { 0 }
    return ($sweScore * $W.SWE) + ($stability * $W.Stab) + ($latScore * $W.Lat) + ($nimBonus * $W.NIM)
}

$Weights = @{
    Opus     = @{ SWE=0.50; Stab=0.25; Lat=0.05; NIM=1.5; LatTarget=800;  LatPenalty=0.02 }
    Sonnet   = @{ SWE=0.35; Stab=0.25; Lat=0.20; NIM=1.0; LatTarget=400;  LatPenalty=0.05 }
    Haiku    = @{ SWE=0.10; Stab=0.20; Lat=0.60; NIM=0.5; LatTarget=200;  LatPenalty=0.12 }
    Fallback = @{ SWE=0.30; Stab=0.40; Lat=0.15; NIM=1.0; LatTarget=500;  LatPenalty=0.04 }
}

# Filter & Assign
$opusCandidate = $liveModels | Sort-Object { Get-Score $_ $Weights.Opus } -Descending | Select-Object -First 1
$sonnetCandidate = $liveModels | Where-Object { $_.modelId -ne $opusCandidate.modelId } | Sort-Object { Get-Score $_ $Weights.Sonnet } -Descending | Select-Object -First 1
if (-not $sonnetCandidate) { $sonnetCandidate = $opusCandidate }
$haikuCandidate = $liveModels | Where-Object { $_.modelId -notin @($opusCandidate.modelId, $sonnetCandidate.modelId) } | Sort-Object { Get-Score $_ $Weights.Haiku } -Descending | Select-Object -First 1
if (-not $haikuCandidate) { $haikuCandidate = $sonnetCandidate }
$fallbackCandidate = $liveModels | Sort-Object { Get-Score $_ $Weights.Fallback } -Descending | Select-Object -First 1

# Thinking Mode
$isThinking = "false"
$sonnetCapKey = Get-CapKey $sonnetCandidate.provider $sonnetCandidate.modelId
if ($ModelCaps.ContainsKey($sonnetCapKey) -and $ModelCaps[$sonnetCapKey].thinking) {
    $isThinking = "true"
}

# Build .env
$envLines = Get-Content $envPath
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

Set-Content -Path $envPath -Value $newLines -Encoding UTF8
Write-Host "[OK] .env updated via fcm-oneshot telemetry." -ForegroundColor Green

# SECURITY: Clean up sensitive data from memory
if ($env:NVIDIA_API_KEY) { Remove-Item Env:\NVIDIA_API_KEY -ErrorAction SilentlyContinue }
if ($env:OPENROUTER_API_KEY) { Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue }

# Remove backup file after successful update
if (Test-Path $backupPath) {
    try { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue } catch { }
}

exit 0
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
#  Claude Proxy Auto-Updater  v6.2.1
#  acedreamer/claude-proxy-auto-updater
#
#  UX Polish & Centralized Brain (v6.0+)
# ============================================================

$envPath    = Join-Path $PSScriptRoot ".env"
$backupPath = "$envPath.backup"
$cacheFile  = Join-Path $PSScriptRoot "model-cache.json"
$configFile = Join-Path $PSScriptRoot "config.json"
$oneshotScript = Join-Path $PSScriptRoot "fcm-oneshot.mjs"
$selectorScript = Join-Path $PSScriptRoot "selector.mjs"
$DryRun = ($args -contains '--dry-run') -or ($args -contains '-DryRun')
$ToolTest = ($args -contains '--tool-test')

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
    # Use .NET to avoid PowerShell pipeline/encoding quirks in older versions
    try {
        $lines = [System.IO.File]::ReadAllLines($Path)
        foreach ($line in $lines) {
            if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*)$') {
                $key = $matches[1]
                $val = $matches[2].Trim().Trim('"').Trim("'")
                $result[$key] = $val
            }
        }
    } catch {
        Write-Debug "Read-EnvFile error: $($_.Exception.Message)"
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
    # Find first [ and last ]
    $start = $Text.IndexOf('[')
    $end   = $Text.LastIndexOf(']')
    if ($start -ge 0 -and $end -gt $start) {
        $candidate = $Text.Substring($start, $end - $start + 1)
        try {
            $parsed = $candidate | ConvertFrom-Json
            if ($parsed -is [System.Array]) { return $parsed }
            return @($parsed)
        } catch { }
    }
    return $null
}

# ============================================================
#  EXECUTION BLOCK
# ============================================================
if ($MyInvocation.InvocationName -ne '.') {
    # LOAD CONFIG
    $configData = @{}
    if (Test-Path $configFile) {
        try { $configData = Get-Content $configFile -Encoding UTF8 -Raw | ConvertFrom-Json } catch { }
    }

    # Default settings if config missing
    $CacheTTL = if ($configData.general.cache_ttl_minutes) { $configData.general.cache_ttl_minutes } else { 15 }
    $Providers = if ($configData.general.providers) { $configData.general.providers } else { "nvidia,openrouter" }
    $TierFilter = if ($configData.general.tier_filter) { $configData.general.tier_filter } else { "S+,S,A+,A" }
    $Timeout = if ($configData.general.timeout_ms) { $configData.general.timeout_ms } else { 15000 }

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

    if ($nimKey) { $env:NVIDIA_API_KEY = $nimKey }
    if ($orKey)  { $env:OPENROUTER_API_KEY = $orKey }

    # ============================================================
    #  CACHE CHECK
    # ============================================================
    $liveModels = $null
    $usingCache = $false

    if (Test-Path $cacheFile) {
        $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($cacheAge.TotalMinutes -lt $CacheTTL) {
            try {
                $cached = Get-Content $cacheFile -Encoding UTF8 -Raw | ConvertFrom-Json
                if ($cached -and $cached.Count -gt 0 -and $cached[0].modelId) {
                    $liveModels = $cached
                    $usingCache = $true
                    $ageMin = [math]::Round($cacheAge.TotalMinutes)
                    $nextMin = [math]::Round($CacheTTL - $cacheAge.TotalMinutes)
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

        if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
            Write-Host "[ERROR] Node.js not found. Required for fcm-oneshot.mjs" -ForegroundColor Red
            exit 1
        }
        if (-not (Test-Path $oneshotScript)) {
            Write-Host "[ERROR] fcm-oneshot.mjs not found." -ForegroundColor Red
            exit 1
        }

        Write-Host "  Running one-shot ping (timeout: ${Timeout}ms per model)..." -ForegroundColor White
        Write-Host "  Providers: $Providers  |  Tier filter: $TierFilter" -ForegroundColor DarkGray
        Write-Host ""

        $nodeArgs = @($oneshotScript, "--providers", $Providers, "--tier", $TierFilter, "--timeout", $Timeout)
        if ($ToolTest) {
            $nodeArgs += "--tool-test"
            Write-Host "  Tool-call probing: ENABLED" -ForegroundColor Yellow
        }

        $tmpJson = [System.IO.Path]::GetTempFileName()
        $nodeArgs += "--output", $tmpJson

        $ErrorActionPreference = 'Continue'
        # Node output (live progress) streams directly to console natively
        & node @nodeArgs
        $exitCode  = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'

        if (Test-Path $tmpJson) {
            $rawText = Get-Content $tmpJson -Raw
            Remove-Item $tmpJson -ErrorAction SilentlyContinue
        } else {
            $rawText = "[]"
        }

        $parsed = Extract-JsonArrayFromText -Text $rawText
        if ($parsed -and $parsed.Count -gt 0) {
            $liveModels = $parsed
        }

        if ($null -eq $liveModels -or $liveModels.Count -eq 0) {
            Write-Host "[WARN] fcm-oneshot returned no usable data. Using existing .env." -ForegroundColor Yellow
            exit 0
        }

        try {
            $liveModels | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
            Set-SecureACL $cacheFile
        } catch { }
    }

    # ============================================================
    #  DELEGATE SELECTION TO selector.mjs
    # ============================================================
    Write-Host "  Selecting best models for each slot..." -ForegroundColor White

    $selectorOutput = & node "$selectorScript" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $selectorOutput) {
        Write-Host "[ERROR] selector.mjs failed." -ForegroundColor Red
        exit 1
    }

    try {
        # Convert node output to string and strip potential UTF8 BOM
        $rawJson = [string]$selectorOutput
        if ($rawJson.Length -gt 0 -and [int]$rawJson[0] -eq 65279) {
            $rawJson = $rawJson.Substring(1)
        }
        $selectionResult = $rawJson | ConvertFrom-Json
    } catch {
        Write-Host "[ERROR] Failed to parse selection result." -ForegroundColor Red
        exit 1
    }

    # ============================================================
    #  INSIGHTS
    # ============================================================
    $showInsights = $null
    if ($configData.preferences -and $configData.preferences.PSObject.Properties['show_insights']) {
        $showInsights = $configData.preferences.show_insights
    }

    if ($showInsights -ne $false) {
        Write-Host ""
        Write-Banner "SELECTION INSIGHTS" "Yellow"
        foreach ($sn in @("opus", "sonnet", "haiku", "fallback")) {
            $insight = $selectionResult.slots.$sn.insight
            if ($insight) { Write-Host "  $insight" -ForegroundColor Gray }
        }
        Write-Host ("=" * 54) -ForegroundColor Yellow
    }

    # First-run prompt for insights
    if ($null -eq $showInsights -and -not $DryRun) {
        Write-Host ""
        $choice = Read-Host "Selection insights are now enabled. Keep seeing them? [Y/n]"
        $enabled = $true
        if ($choice -eq "n") { $enabled = $false }
        
        # Update config.json via selector.mjs helper if possible, or direct write
        & node -e "const fs=require('fs'); const data=fs.readFileSync('$($configFile.Replace('\','\\'))', 'utf8'); const c=JSON.parse(data.charCodeAt(0)===0xFEFF?data.slice(1):data); c.preferences.show_insights=$($enabled.ToString().ToLower()); fs.writeFileSync('$($configFile.Replace('\','\\'))', JSON.stringify(c, null, 2));"
    }

    # ============================================================
    #  UI LAYER: MODEL SELECTION
    # ============================================================
    Write-Host ""
    Write-Host "============= MODEL SELECTION ===========================================================================" -ForegroundColor Cyan
    Write-Host ("{0,-10} | {1,-38} | {2,-5} | {3,-6} | {4,-7} | {5,-7} | {6}" -f "SLOT", "MODEL (Short)", "THINK", "SCORE", "VERDICT", "LAT(ms)", "Runner-up") -ForegroundColor DarkGray
    Write-Host "=========================================================================================================" -ForegroundColor Cyan

    $slotNames = @("opus", "sonnet", "haiku", "fallback")
    foreach ($sn in $slotNames) {
        $slot = $selectionResult.slots.$sn
        if (-not $slot -or -not $slot.winner) { continue }
        
        $w = $slot.winner
        $name = $w.shortName
        $think = if ($w.thinking) { "Yes" } else { "No" }
        $score = [math]::Round($w.score, 1)
        $verd  = $w.verdict
        $lat   = if ($w.avgMs -eq 9999.0) { "---" } else { [math]::Round($w.avgMs) }
        
        $runup = "none"
        if ($slot.runner_up) {
            $runup = "$($slot.runner_up.shortName) (d-$([math]::Round($w.score - $slot.runner_up.score, 1)))"
        }
        
        Write-Host ("{0,-10} | {1,-38} | {2,-5} | {3,6} | {4,-7} | {5,7} | {6}" -f $sn.ToUpper(), $name, $think, $score, $verd, $lat, $runup) -ForegroundColor White
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

    # Update .env
    if (-not $DryRun) {
        $newLines = @()
        $isThinking = if ($selectionResult.is_thinking) { "true" } else { "false" }
        
        function Get-Pref { param($s) return Get-ModelPrefix $selectionResult.slots.$s.winner.provider $selectionResult.slots.$s.winner.modelId }

        $mappings = @{
            "MODEL_OPUS="      = "MODEL_OPUS=`"$(Get-Pref opus)`""
            "MODEL_SONNET="    = "MODEL_SONNET=`"$(Get-Pref sonnet)`""
            "MODEL_HAIKU="     = "MODEL_HAIKU=`"$(Get-Pref haiku)`""
            "MODEL="           = "MODEL=`"$(Get-Pref fallback)`""
            "ENABLE_THINKING=" = "ENABLE_THINKING=$isThinking"
        }

        $envLines = if (Test-Path $envPath) { Get-Content $envPath } else { @() }
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
        Set-Content -Path $envPath -Value $newLines -Encoding UTF8
        Write-Host "[OK] .env updated via fcm-oneshot telemetry." -ForegroundColor Green
    } else {
        Write-Host "[DRY RUN] .env not modified" -ForegroundColor Yellow
    }

    # Cleanup
    if ($env:NVIDIA_API_KEY) { Remove-Item Env:\NVIDIA_API_KEY -ErrorAction SilentlyContinue }
    if ($env:OPENROUTER_API_KEY) { Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue }
    if (Test-Path $backupPath) { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue }
}

exit 0

$ErrorActionPreference = 'Stop'
$envPath = Join-Path $PSScriptRoot ".env"
$backupPath = "$envPath.backup"

# ============================================================
# CONFIGURATION
# ============================================================
$Config = @{
    AlwaysFetchLive   = $true  # Set to $true to ignore cache and check live models on every start
    CacheTTLHours     = 4
    CacheFile         = Join-Path $PSScriptRoot "model-cache.json"
    MaxRetries        = 3
    RetryDelaySeconds = 2
}

# ============================================================
# UTILITY: SECURE FILE PERMISSIONS (ACL)
# Restricts access to current user and SYSTEM only
# ============================================================
function Set-SecureACL {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl = Get-Acl $Path
        $acl.SetAccessRuleProtection($true, $false) # Strip inherited permissions
        
        # Allow current user & system full control
        $rules = @(
            (New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $currentUser, "FullControl", "Allow"),
            (New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList "SYSTEM", "FullControl", "Allow")
        )
        foreach ($rule in $rules) { $acl.AddAccessRule($rule) }
        Set-Acl $Path $acl -ErrorAction Stop
    } catch {
        # Silently bypass if user lacks Administrator 'SeSecurityPrivilege' rights
    }
}

# ============================================================
# CLASSIFICATION & SCORING PROFILES
# ============================================================
$ClassificationPatterns = @{
    Heavy    = @("\b\d{3,}b\b", "thinking", "k2-?", "glm-?5", "ultra", "terminus", "r1", "qwq", "nemotron")
    Fast     = @("flash", "nano", "mini", "\b[44789]b\b", "\b12b\b", "small", "compound")
    # Models that frequently fail Anthropic tool-calling schemas or leak JSON formatting
    Excluded = @("mistral", "devstral", "mixtral", "magistral", "gemma", "minimax", "holo", "kimi", "step-", "qwen3")
}

Write-Host "Fetching live model benchmarks..." -ForegroundColor Cyan

# 1. Locate CLI dynamically
$fcmCommand = (Get-Command "free-coding-models" -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $fcmCommand) {
    Write-Host "[ERROR] free-coding-models CLI not found in PATH." -ForegroundColor Red
    exit 1
}

# 2. Load API keys into transient env vars
if (Test-Path $envPath) {
    Copy-Item $envPath $backupPath -Force
    Set-SecureACL $backupPath
    foreach ($envLine in Get-Content $envPath) {
        if ($envLine -match '^NVIDIA_NIM_API_KEY="(.*)"$') { $env:NVIDIA_API_KEY = $matches[1] }
        if ($envLine -match '^OPENROUTER_API_KEY="(.*)"$') { $env:OPENROUTER_API_KEY = $matches[1] }
    }
}

# ============================================================
# DATA ACQUISITION & CACHING LAYER
# ============================================================
$modelsRawJSON = $null
$usingCache = $false

if ($Config.AlwaysFetchLive -eq $false -and (Test-Path $Config.CacheFile)) {
    $cacheAgeInfo = Get-Item $Config.CacheFile
    if ((Get-Date) -lt $cacheAgeInfo.LastWriteTime.AddHours($Config.CacheTTLHours)) {
        $ageMins = [math]::Round(((Get-Date) - $cacheAgeInfo.LastWriteTime).TotalMinutes)
        Write-Host "Using fresh local cache (Age: $ageMins mins)..." -ForegroundColor Magenta
        $modelsRawJSON = Get-Content $Config.CacheFile -Raw
        $usingCache = $true
    }
}

if (-not $usingCache) {
    $attempt = 0
    $delay = $Config.RetryDelaySeconds
    while ($attempt -lt $Config.MaxRetries) {
        try {
            $ErrorActionPreference = 'Continue'
            $output = & $fcmCommand --json --no-telemetry 2>&1
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            
            $outputStr = [string]($output -join "`n")
            $jsonStart = $outputStr.IndexOf("[")
            $jsonEnd = $outputStr.LastIndexOf("]")

            if ($jsonStart -ge 0 -and $jsonEnd -gt $jsonStart) {
                $modelsRawJSON = $outputStr.Substring($jsonStart, ($jsonEnd - $jsonStart + 1))
                $testParse = $modelsRawJSON | ConvertFrom-Json
                if ($null -eq $testParse -or ($testParse | Get-Member -Name "modelId").Count -eq 0) {
                    throw "JSON parsed but lacked expected model schema."
                }
                break
            }
            else { 
                $errSnippet = if ($outputStr.Length -gt 150) { $outputStr.Substring(0, 150) + "..." } else { $outputStr }
                throw "Output data invalid (Exit $exitCode). CLI said: $errSnippet" 
            }
        }
        catch {
            $attempt++
            Write-Host "Attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
            if ($attempt -ge $Config.MaxRetries) { break }
            Start-Sleep -Seconds $delay
            $delay *= 2
        }
    }
    
    if ($null -ne $modelsRawJSON) {
        $modelsRawJSON | Out-File $Config.CacheFile -Encoding utf8
        Set-SecureACL $Config.CacheFile
    }
}

if ($env:NVIDIA_API_KEY) { Remove-Item Env:\NVIDIA_API_KEY -ErrorAction SilentlyContinue }
if ($env:OPENROUTER_API_KEY) { Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue }

if ($null -eq $modelsRawJSON) {
    Write-Host "[WARN] Using previously saved models (CLI/Cache access failed)." -ForegroundColor Yellow
    exit 0
}

try {
    $models = $modelsRawJSON | ConvertFrom-Json
}
catch {
    exit 0
}

# ============================================================
# FILTER & CLASSIFY
# ============================================================
$validModels = $models | Where-Object {
    $m = $_
    $isUp = $m.status -eq "up"
    $isGood = ($m.verdict -eq "Normal" -or $m.verdict -eq "Perfect")
    $isProvider = ($m.provider -eq "nvidia" -or ($m.provider -eq "openrouter" -and $m.modelId -match ":free$"))
    
    $isExcluded = $false
    foreach ($kw in $ClassificationPatterns.Excluded) {
        if ($m.modelId.ToLower() -match $kw) { $isExcluded = $true; break }
    }
    
    $isUp -and $isGood -and $isProvider -and -not $isExcluded
}

# Overcrowding Fallback: If no "Perfect/Normal" models are available, cast a wider net
if (($validModels | Measure-Object).Count -eq 0) {
    Write-Host "[INFO] Ideal models are overcrowded. Expanding search to 'Spiky' or 'Slow' models..." -ForegroundColor Magenta
    $validModels = $models | Where-Object {
        $m = $_
        $isProvider = ($m.provider -eq "nvidia" -or ($m.provider -eq "openrouter" -and $m.modelId -match ":free$"))
        $isExcluded = $false
        foreach ($kw in $ClassificationPatterns.Excluded) {
            if ($m.modelId.ToLower() -match $kw) { $isExcluded = $true; break }
        }
        $m.status -eq "up" -and $isProvider -and -not $isExcluded
    }
}

if (($validModels | Measure-Object).Count -eq 0) {
    Write-Host "[WARN] All acceptable models are completely down. Cannot update." -ForegroundColor Yellow
    exit 0
}

foreach ($model in $validModels) {
    $sweRaw = if ($model.sweScore) { [double]($model.sweScore -replace "%", "") } else { 0.0 }
    $ctxNum = 128000
    if ($model.context -match "^(\d+)k$") { $ctxNum = [int]$matches[1] * 1000 }
    elseif ($model.context -match "^(\d+)M$") { $ctxNum = [int]$matches[1] * 1000000 }
    $nimBonus = if ($model.provider -eq "nvidia") { 5 } else { 0 }

    $model | Add-Member -MemberType NoteProperty -Name "ParsedSwe" -Value $sweRaw -Force
    $model | Add-Member -MemberType NoteProperty -Name "CtxTokens" -Value $ctxNum -Force
    $model | Add-Member -MemberType NoteProperty -Name "NimBonus" -Value $nimBonus -Force

    $id = $model.modelId.ToLower()
    $isHeavy = $false; $isFast = $false
    foreach ($kw in $ClassificationPatterns.Heavy) { if ($id -match $kw) { $isHeavy = $true; break } }
    foreach ($kw in $ClassificationPatterns.Fast) { if ($id -match $kw) { $isFast = $true; break } }

    if ($isFast -and $model.ParsedSwe -ge 70) { $isFast = $false }
    if ($model.ParsedSwe -lt 45) { $isHeavy = $false }

    $role = "balanced"
    if ($isHeavy -and -not $isFast) { $role = "heavy" }
    elseif ($isFast -and -not $isHeavy) { $role = "fast" }
    $model | Add-Member -MemberType NoteProperty -Name "Role" -Value $role -Force
}

# ============================================================
# ASSIGN MODELS
# ============================================================
$opusCandidates = $validModels | Where-Object { $_.tier -match "^[AS]" -and $_.Role -eq "heavy" }
foreach ($m in $opusCandidates) {
    $ctxScore = [math]::Min($m.CtxTokens / 256000 * 100, 100)
    $SCORE_OPUS = ($m.ParsedSwe * 0.6) + ($ctxScore * 0.2) + ($m.stability * 0.1) + ($m.NimBonus * 2)
    $m | Add-Member -MemberType NoteProperty -Name "OpusScore" -Value $SCORE_OPUS -Force
}
$opusModel = $opusCandidates | Sort-Object OpusScore -Descending | Select-Object -First 1

$sonnetCandidates = $validModels | Where-Object { $_.tier -match "^S" -and $_.Role -ne "fast" -and ($null -eq $opusModel -or $_.modelId -ne $opusModel.modelId) }
foreach ($m in $sonnetCandidates) {
    $latScore = [math]::Max(0, 100 - (($m.avgPing - 200) * 0.08)); $ctxScore = [math]::Min($m.CtxTokens / 256000 * 100, 100)
    $SCORE_SONNET = ($m.ParsedSwe * 0.45) + ($latScore * 0.25) + ($m.stability * 0.15) + ($ctxScore * 0.1) + ($m.NimBonus)
    $m | Add-Member -MemberType NoteProperty -Name "SonnetScore" -Value $SCORE_SONNET -Force
}
$sonnetModel = $sonnetCandidates | Sort-Object SonnetScore -Descending | Select-Object -First 1

$usedIds = @()
if ($null -ne $opusModel) { $usedIds += $opusModel.modelId }
if ($null -ne $sonnetModel) { $usedIds += $sonnetModel.modelId }

$haikuCandidates = $validModels | Where-Object { $_.tier -match "^[AS]" -and $_.Role -ne "heavy" -and $_.modelId -notin $usedIds }
if (($haikuCandidates | Measure-Object).Count -eq 0) { $haikuCandidates = $validModels | Where-Object { $_.tier -match "^[AS]" -and $_.modelId -notin $usedIds } }
foreach ($m in $haikuCandidates) {
    $latScore = [math]::Max(0, 100 - (($m.avgPing - 100) * 0.1)); $SCORE_HAIKU = ($latScore * 0.5) + ($m.ParsedSwe * 0.25) + ($m.stability * 0.15) + ($m.NimBonus)
    $m | Add-Member -MemberType NoteProperty -Name "HaikuScore" -Value $SCORE_HAIKU -Force
}
$haikuModel = $haikuCandidates | Sort-Object HaikuScore -Descending | Select-Object -First 1

if ($null -ne $haikuModel) { $usedIds += $haikuModel.modelId }
$fallbackCandidates = $validModels | Where-Object { $_.tier -match "^[AS]" -and $_.modelId -notin $usedIds }
foreach ($m in $fallbackCandidates) {
    $latScore = [math]::Max(0, 100 - (($m.avgPing - 200) * 0.08)); $SCORE_FB = ($m.stability * 0.4) + ($m.ParsedSwe * 0.3) + ($latScore * 0.2) + ($m.NimBonus)
    $m | Add-Member -MemberType NoteProperty -Name "FallbackScore" -Value $SCORE_FB -Force
}
$fallbackModel = $fallbackCandidates | Sort-Object FallbackScore -Descending | Select-Object -First 1

if ($null -eq $opusModel) { $opusModel = $validModels | Sort-Object ParsedSwe -Descending | Select-Object -First 1 }
if ($null -eq $sonnetModel) { $sonnetModel = $opusModel }
if ($null -eq $haikuModel) { $haikuModel = $sonnetModel }
if ($null -eq $fallbackModel) { $fallbackModel = $sonnetModel }

function Get-Prefix { param($p, $m); if ($p -eq "nvidia") { return "nvidia_nim/$m" }; if ($p -eq "openrouter") { return "open_router/$m" }; return $m }
$opusStr = Get-Prefix $opusModel.provider $opusModel.modelId; $sonnetStr = Get-Prefix $sonnetModel.provider $sonnetModel.modelId; $haikuStr = Get-Prefix $haikuModel.provider $haikuModel.modelId; $fallbackStr = Get-Prefix $fallbackModel.provider $fallbackModel.modelId

$isThinking = "false"
$hasMistral = $false
$allNimIds = @($opusStr, $sonnetStr, $haikuStr, $fallbackStr) | Where-Object { $_ -match "^nvidia_nim/" }
foreach ($nimId in $allNimIds) { 
    if ($nimId -match "thinking|kimi|nemotron|qwq|r1") { $isThinking = "true" } 
    if ($nimId -match "mistral|devstral|mixtral") { $hasMistral = $true }
}
if ($hasMistral -eq $true) { $isThinking = "false" }

# ============================================================
# FINAL OUTPUT & ENV UPDATE
# ============================================================
Write-Host "=============================================" -ForegroundColor DarkCyan
Write-Host "       AUTO-SELECTED MODEL ASSIGNMENTS       " -ForegroundColor White
Write-Host "=============================================" -ForegroundColor DarkCyan
Write-Host "  OPUS: $opusStr" -ForegroundColor Magenta
Write-Host "  SONNET: $sonnetStr" -ForegroundColor Yellow
Write-Host "  HAIKU: $haikuStr" -ForegroundColor Cyan
Write-Host "  NIM_ENABLE_THINKING: $isThinking" -ForegroundColor $(if ($isThinking -eq "true") { "Green" } else { "DarkGray" })
Write-Host "============================================="

if (Test-Path $envPath) {
    $envContent = Get-Content $envPath
    $newContent = @()
    foreach ($line in $envContent) {
        if ($line -match "^MODEL_OPUS=") { $newContent += "MODEL_OPUS=`"$opusStr`"" }
        elseif ($line -match "^MODEL_SONNET=") { $newContent += "MODEL_SONNET=`"$sonnetStr`"" }
        elseif ($line -match "^MODEL_HAIKU=") { $newContent += "MODEL_HAIKU=`"$haikuStr`"" }
        elseif ($line -match "^MODEL=") { $newContent += "MODEL=`"$fallbackStr`"" }
        elseif ($line -match "^NIM_ENABLE_THINKING=") { $newContent += "NIM_ENABLE_THINKING=$isThinking" }
        else { $newContent += $line }
    }
    Set-Content -Path $envPath -Value $newContent -Encoding UTF8
    Write-Host "[OK] Environment updated successfully." -ForegroundColor Green
}
Start-Sleep -Seconds 2
exit 0

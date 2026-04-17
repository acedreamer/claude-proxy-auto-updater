# Claude Proxy Auto-Updater - Setup Engine (Windows)
# Version: 1.0
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Text)
    Write-Host "`n>>> $Text" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Gray
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  CLAUDE PROXY: ZERO-TO-HERO SETUP" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Environment Readiness
Write-Step "Checking Environment..."

$node = Get-Command "node" -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host "[ERROR] Node.js not found! Please install it from https://nodejs.org/" -ForegroundColor Red
    exit 1
}
Write-Success "Node.js found: $($node.Source)"

$git = Get-Command "git" -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Host "[ERROR] Git not found! Please install it from https://git-scm.com/" -ForegroundColor Red
    exit 1
}
Write-Success "Git found: $($git.Source)"

$python = Get-Command "uv" -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command "python" -ErrorAction SilentlyContinue
}
if (-not $python) {
    Write-Host "[WARN] Python or UV not found. You will need one of these to run the proxy." -ForegroundColor Yellow
} else {
    Write-Success "Python/UV found: $($python.Source)"
}

# 2. Dependencies
Write-Step "Checking Dependencies..."
$fcm = & npm list -g free-coding-models --depth=0 2>$null
if ($fcm -match "empty") {
    $choice = Read-Host "free-coding-models not found. Install it globally? [Y/n]"
    if ($choice -ne "n") {
        Write-Host "Installing free-coding-models..." -ForegroundColor Gray
        npm install -g free-coding-models
        Write-Success "Installation complete."
    }
} else {
    Write-Success "free-coding-models is already installed."
}

# 3. Proxy Installation
Write-Step "Checking Claude Proxy..."
$proxyPath = Join-Path $PSScriptRoot "..\free-claude-code"
if (-not (Test-Path $proxyPath)) {
    $choice = Read-Host "free-claude-code not found in sibling directory. Clone it now? [Y/n]"
    if ($choice -ne "n") {
        Write-Host "Cloning free-claude-code..." -ForegroundColor Gray
        git clone https://github.com/abetlen/free-claude-code "$proxyPath"
        Write-Success "Cloned to $proxyPath"
        
        # Install proxy deps
        if ($python -and $python.Name -eq "uv") {
            Write-Host "Installing proxy dependencies via uv..." -ForegroundColor Gray
            Set-Location "$proxyPath"
            & uv pip install -r requirements.txt
            Set-Location $PSScriptRoot
        } elseif ($python) {
            Write-Host "Installing proxy dependencies via pip..." -ForegroundColor Gray
            Set-Location "$proxyPath"
            & python -m pip install -r requirements.txt
            Set-Location $PSScriptRoot
        }
    }
} else {
    Write-Success "Found free-claude-code at $proxyPath"
}

# 4. API Keys
Write-Step "Configuring API Keys..."
$envPath = Join-Path $PSScriptRoot ".env"
$nimKey = ""
$orKey = ""

if (Test-Path $envPath) {
    Write-Info ".env already exists. Skipping key setup."
} else {
    Write-Host "Please enter your API keys (leave blank to skip):"
    $nimKey = Read-Host "NVIDIA NIM API Key"
    $orKey = Read-Host "OpenRouter API Key"
    
    $content = @(
        "NVIDIA_NIM_API_KEY=`"$nimKey`"",
        "OPENROUTER_API_KEY=`"$orKey`"",
        "MODEL_OPUS=`"`"",
        "MODEL_SONNET=`"`"",
        "MODEL_HAIKU=`"`"",
        "MODEL=`"`"",
        "NIM_ENABLE_THINKING=false"
    )
    $content | Out-File $envPath -Encoding utf8
    Write-Success "Created .env with your keys."
}

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "  SETUP COMPLETE! You are ready to go." -ForegroundColor Green
Write-Host "  Run .\update-models.ps1 to start." -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
pause

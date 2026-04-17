@echo off
setlocal enabledelayedexpansion

:: 1. Check for .env file first
if not exist "%~dp0.env" (
    echo [WARN] No .env file found. Creating a template...
    echo NVIDIA_NIM_API_KEY="" > "%~dp0.env"
    echo OPENROUTER_API_KEY="" >> "%~dp0.env"
    echo [INFO] Please edit .env and add your API keys, then run this again.
    pause
    exit /b
)

echo ==========================================
echo  CLAUDE PROXY: AUTO-MODEL UPDATE
echo ==========================================
:: 2. Run update with a bypass check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-models.ps1" --tool-test
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Model update failed. Starting server with existing config...
)

echo.
echo ==========================================
echo  STARTING CLAUDE PROXY SERVER
echo ==========================================
:: 3. Check for 'uv' before running
where uv >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    uv run uvicorn server:app --host 0.0.0.0 --port 8082
) else (
    echo [INFO] 'uv' not found. Falling back to standard python/uvicorn...
    python -m uvicorn server:app --host 0.0.0.0 --port 8082
)

pause

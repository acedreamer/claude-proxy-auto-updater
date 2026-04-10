# Claude Proxy Auto-Updater

This script automatically updates the models used by Claude Proxy based on availability and latency.

## Setup
1. Obtain API keys:
   - OpenRouter: Visit [OpenRouter](https://openrouter.ai/) and get your API key
   - NVIDIA NIM: Visit [NVIDIA NIM](https://build.nvidia.com/) to get API key
2. Set environment variables:
   - `OPENROUTER_API_KEY` and `NVIDIA_API_KEY` (for NVIDIA support)

## Usage
Run the script with:
```powershell
.\update-models.ps1
```
This will:
- Fetch available free models from OpenRouter and NVIDIA (if API key provided)
- Update model metadata cache
- Select the fastest available model and save to `config\model-config.json`

Example output in `config\model-config.json`:
{
  "best_model": "claude-3-5-sonnet-latest"
}

## Troubleshooting
- **API key missing**: Ensure `OPENROUTER_API_KEY` and/or `NVIDIA_API_KEY` are set in environment variables
- **No models found**: Check API key validity and internet connection
- **Error when running**: Ensure PowerShell runs with proper execution policy (run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`)

## Scheduling
To run updates daily, execute:
```powershell
.\update-models.ps1 --schedule
```
This sets up a daily scheduled task at 3 AM.
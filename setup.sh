#!/usr/bin/env bash
# Claude Proxy Auto-Updater - Setup Engine (Linux/macOS)
# Version: 1.1

set -euo pipefail

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

write_step() { echo -e "\n${CYAN}>>> $1${NC}"; }
write_success() { echo -e "${GREEN}[OK] $1${NC}"; }
write_info() { echo -e "${GRAY}[INFO] $1${NC}"; }

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  CLAUDE PROXY: ZERO-TO-HERO SETUP${NC}"
echo -e "${CYAN}==========================================${NC}"

# 1. Environment Readiness
write_step "Checking Environment..."

if ! command -v node >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Node.js not found! Please install it via your package manager or nvm.${NC}"
    exit 1
fi
write_success "Node.js found: $(command -v node)"

if ! command -v git >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Git not found! Please install it.${NC}"
    exit 1
fi
write_success "Git found: $(command -v git)"

PYTHON="python3"
if command -v uv >/dev/null 2>&1; then
    PYTHON="uv"
elif ! command -v python3 >/dev/null 2>&1; then
    PYTHON=""
    echo -e "${YELLOW}[WARN] Python or UV not found. You will need one of these to run the proxy.${NC}"
fi

if [[ -n "$PYTHON" ]]; then
    write_success "Python/UV found: $(command -v $PYTHON)"
fi

# 2. Dependencies
write_step "Checking Dependencies..."
if ! npm list -g free-coding-models --depth=0 >/dev/null 2>&1; then
    read -p "free-coding-models not found. Install it globally? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        write_info "Installing free-coding-models..."
        npm install -g free-coding-models || {
            echo -e "${YELLOW}[WARN] Global install failed. Trying with sudo...${NC}"
            sudo npm install -g free-coding-models
        }
        write_success "Installation complete."
    fi
else
    write_success "free-coding-models is already installed."
fi

# 3. Proxy Installation
write_step "Checking Claude Proxy..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_PATH="${SCRIPT_DIR}/../free-claude-code"

if [[ ! -d "$PROXY_PATH" ]]; then
    read -p "free-claude-code not found in sibling directory. Clone it now? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        write_info "Cloning free-claude-code..."
        git clone https://github.com/abetlen/free-claude-code "$PROXY_PATH"
        write_success "Cloned to $PROXY_PATH"
        
        # Install proxy deps
        if [[ "$PYTHON" == "uv" ]]; then
            write_info "Installing proxy dependencies via uv..."
            (cd "$PROXY_PATH" && uv pip install -r requirements.txt)
        elif [[ -n "$PYTHON" ]]; then
            write_info "Installing proxy dependencies via pip..."
            (cd "$PROXY_PATH" && python3 -m pip install -r requirements.txt)
        fi
    fi
else
    write_success "Found free-claude-code at $PROXY_PATH"
fi

# 4. API Keys
write_step "Configuring API Keys..."
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "$ENV_FILE" ]]; then
    write_info ".env already exists. Skipping key setup."
else
    echo "Please enter your API keys (leave blank to skip):"
    read -p "NVIDIA NIM API Key: " NIM_KEY
    read -p "OpenRouter API Key: " OR_KEY
    
    cat <<EOF > "$ENV_FILE"
NVIDIA_NIM_API_KEY="$NIM_KEY"
OPENROUTER_API_KEY="$OR_KEY"
MODEL_OPUS=""
MODEL_SONNET=""
MODEL_HAIKU=""
MODEL=""
ENABLE_THINKING=false
EOF
    write_success "Created .env with your keys."
fi

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}  SETUP COMPLETE! You are ready to go.${NC}"
echo -e "${GREEN}  Run ./update-models.sh to start.${NC}"
echo -e "${GREEN}==========================================${NC}"

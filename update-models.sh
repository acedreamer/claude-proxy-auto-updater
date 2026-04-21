#!/usr/bin/env bash
#
# Claude Proxy Auto-Updater v6.2.1 - Bash Edition
# acedreamer/claude-proxy-auto-updater
#
# UX Polish & Centralized Brain (v6.1+)

set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================
[[ -z "${SCRIPT_DIR:-}" ]] && SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${ENV_PATH:-}" ]] && ENV_PATH="${SCRIPT_DIR}/.env"
[[ -z "${CACHE_FILE:-}" ]] && CACHE_FILE="${SCRIPT_DIR}/model-cache.json"
[[ -z "${CONFIG_FILE:-}" ]] && CONFIG_FILE="${SCRIPT_DIR}/config.json"
[[ -z "${ONESHOT_SCRIPT:-}" ]] && ONESHOT_SCRIPT="${SCRIPT_DIR}/fcm-oneshot.mjs"
[[ -z "${SELECTOR_SCRIPT:-}" ]] && SELECTOR_SCRIPT="${SCRIPT_DIR}/selector.mjs"

# Config values (mirrored from selector.mjs defaults or override via config.json)
CACHE_TTL_MINUTES=15
PING_TIMEOUT_MS=15000
PROVIDERS="nvidia,openrouter"
TIER_FILTER="S+,S,A+,A"

# ============================================================
# UTILITIES
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DARKGRAY='\033[1;30m'
NC='\033[0m'

log_banner() {
    local text="$1"
    local color="${2:-$CYAN}"
    local pad_len=$(( (54 - ${#text}) / 2 ))
    local pad=""
    [[ $pad_len -lt 0 ]] && pad_len=0
    for ((i=0; i<pad_len; i++)); do pad="${pad}="; done
    echo -e "${color}${pad} ${text} ${pad}${NC}"
}

log_info() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_cache() { echo -e "${MAGENTA}[CACHE]${NC} $1"; }

# POSIX env file reader - outputs KEY=value lines
read_env_file() {
    local path="$1"
    [[ ! -f "$path" ]] && return
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            value="${value%$'\r'}"
            # Strip quotes if present
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi
            echo "${key}=${value}"
        fi
    done < "$path"
}

get_model_prefix() {
    local provider="$1" model_id="$2"
    case "$provider" in
        nvidia) echo "nvidia_nim/$model_id" ;;
        openrouter) echo "open_router/$model_id" ;;
        *) echo "$provider/$model_id" ;;
    esac
}

# ============================================================
# CACHE & TELEMETRY
# ============================================================
check_cache() {
    [[ ! -f "$CACHE_FILE" ]] && return 1

    local cache_mtime current_time age_minutes
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        cache_mtime=$(stat -c %Y "$CACHE_FILE")
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        cache_mtime=$(stat -f %m "$CACHE_FILE")
    else
        return 1
    fi
    
    current_time=$(date +%s)
    age_minutes=$(((current_time - cache_mtime) / 60))
    
    if [[ $age_minutes -lt $CACHE_TTL_MINUTES ]]; then
        local remaining=$((CACHE_TTL_MINUTES - age_minutes))
        log_cache "Using ${age_minutes}m old data. Refresh in ${remaining}m."
        return 0
    fi
    return 1
}

# ============================================================
# MAIN
# ============================================================
main() {
    local dry_run=false
    local tool_test=false
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && dry_run=true
        [[ "$arg" == "--tool-test" ]] && tool_test=true
    done

    # 1. LOAD CONFIG
    if [[ -f "$CONFIG_FILE" ]]; then
        # Simple extraction for bash settings
        CACHE_TTL_MINUTES=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$CONFIG_FILE', 'utf8')).general.cache_ttl_minutes || 15)")
        PROVIDERS=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$CONFIG_FILE', 'utf8')).general.providers || 'nvidia,openrouter')")
        TIER_FILTER=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$CONFIG_FILE', 'utf8')).general.tier_filter || 'S+,S,A+,A')")
        PING_TIMEOUT_MS=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$CONFIG_FILE', 'utf8')).general.timeout_ms || 15000)")
    fi

    # 2. LOAD KEYS
    local nim_key="" or_key=""
    while IFS='=' read -r key value; do
        if [[ "$key" == "NVIDIA_NIM_API_KEY" ]]; then nim_key="$value"; fi
        if [[ "$key" == "OPENROUTER_API_KEY" ]]; then or_key="$value"; fi
    done < <(read_env_file "$ENV_PATH")

    if [[ -z "$nim_key" && -z "$or_key" ]]; then
        log_error "No API keys in .env (NVIDIA_NIM_API_KEY / OPENROUTER_API_KEY)"
        exit 1
    fi

    [[ -n "$nim_key" ]] && export NVIDIA_API_KEY="$nim_key"
    [[ -n "$or_key" ]] && export OPENROUTER_API_KEY="$or_key"

    # 3. RUN PINGS IF NEEDED
    if ! check_cache; then
        log_banner "PINGING MODELS VIA FREE-CODING-MODELS" "$CYAN"

        if ! command -v node >/dev/null 2>&1; then
            log_error "Node.js not found. Required for fcm-oneshot.mjs"
            exit 1
        fi

        echo -e "  Running one-shot ping (timeout: ${PING_TIMEOUT_MS}ms per model)..."
        echo -e "  Providers: $PROVIDERS  |  Tier filter: $TIER_FILTER"
        [[ "$tool_test" == "true" ]] && echo -e "  Tool-call probing: ${YELLOW}ENABLED${NC}"
        echo ""

        local node_args=("$ONESHOT_SCRIPT" "--providers" "$PROVIDERS" "--tier" "$TIER_FILTER" "--timeout" "$PING_TIMEOUT_MS")
        [[ "$tool_test" == "true" ]] && node_args+=("--tool-test")

        local tmp_json
        tmp_json=$(mktemp)
        node_args+=("--output" "$tmp_json")

        # R-601: Stream progress live to console natively
        node "${node_args[@]}" || {
            log_warn "fcm-oneshot exited with error. Attempting to parse partial output."
        }

        # Extract JSON array from the output file
        local json_output
        if [[ -f "$tmp_json" ]]; then
            json_output=$(cat "$tmp_json")
            rm -f "$tmp_json"
        else
            json_output="[]"
        fi

        # Simple extraction in case of surrounding text
        json_output=$(echo "$json_output" | node -e '
            const fs = require("fs");
            const s = fs.readFileSync(0, "utf8");
            for (let i = 0; i < s.length; i++) {
                if (s[i] !== "[") continue;
                for (let j = s.length - 1; j > i; j--) {
                    if (s[j] !== "]") continue;
                    const candidate = s.slice(i, j + 1);
                    try {
                        const parsed = JSON.parse(candidate);
                        if (Array.isArray(parsed)) {
                            process.stdout.write(JSON.stringify(parsed));
                            process.exit(0);
                        }
                    } catch {}
                }
            }
            process.exit(1);
        ' 2>/dev/null) || {
            log_error "Failed to extract JSON from fcm-oneshot output."
            exit 1
        }

        if [[ "$json_output" == "[]" || -z "$json_output" ]]; then
            log_warn "fcm-oneshot returned no usable data. Using existing .env."
            exit 0
        fi

        echo "$json_output" > "$CACHE_FILE"
        echo ""
    fi

    # 4. DELEGATE TO selector.mjs
    echo -e "  Selecting best models for each slot..."
    local selection_result
    selection_result=$(node "$SELECTOR_SCRIPT") || {
        log_error "selector.mjs failed or returned invalid output."
        exit 1
    }

    # 5. INSIGHTS
    local show_insights
    show_insights=$(node -e "
        const fs=require('fs');
        if(!fs.existsSync('$CONFIG_FILE')){ console.log('null'); process.exit(0); }
        const c=JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
        console.log(c.preferences && c.preferences.show_insights !== undefined ? c.preferences.show_insights : 'null');
    ")

    if [[ "$show_insights" != "false" ]]; then
        echo ""
        log_banner "SELECTION INSIGHTS" "$YELLOW"
        echo "$selection_result" | node -e "
            const res = JSON.parse(require('fs').readFileSync(0, 'utf8'));
            ['opus','sonnet','haiku','fallback'].forEach(s => {
                if(res.slots[s] && res.slots[s].insight) console.log('  ' + res.slots[s].insight);
            });
        "
        echo -e "${YELLOW}$(printf '=%.0s' {1..54})${NC}"
    fi

    # First-run prompt for insights
    if [[ "$show_insights" == "null" && "$dry_run" == "false" ]]; then
        echo ""
        read -p "Selection insights are now enabled. Keep seeing them? [Y/n] " -n 1 -r
        echo ""
        local choice="true"
        [[ $REPLY =~ ^[Nn]$ ]] && choice="false"
        node -e "const fs=require('fs'); const c=JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8')); c.preferences.show_insights=$choice; fs.writeFileSync('$CONFIG_FILE', JSON.stringify(c, null, 2));"
    fi

    # 6. UI LAYER: MODEL SELECTION
    echo ""
    echo -e "${CYAN}============= MODEL SELECTION ===========================================================================${NC}"
    printf "${DARKGRAY}%-10s | %-38s | %-5s | %-6s | %-7s | %-7s | %s${NC}\n" "SLOT" "MODEL (Short)" "THINK" "SCORE" "VERDICT" "LAT(ms)" "Runner-up"
    echo -e "${CYAN}=========================================================================================================${NC}"

    echo "$selection_result" | node -e '
        const res = JSON.parse(require("fs").readFileSync(0, "utf8"));
        const slots = ["opus", "sonnet", "haiku", "fallback"];
        slots.forEach(sn => {
            const s = res.slots[sn];
            if (!s || !s.winner) return;
            const w = s.winner;
            const name = w.shortName;
            const think = w.thinking ? "Yes" : "No";
            const score = w.score.toFixed(1);
            const lat = w.avgMs === 9999 ? "---" : Math.round(w.avgMs);
            let runup = "none";
            if (s.runner_up) {
                const diff = (w.score - s.runner_up.score).toFixed(1);
                runup = `${s.runner_up.shortName} (d-${diff})`;
            }
            process.stdout.write(`${sn.toUpperCase().padEnd(10)} | ${name.padEnd(38)} | ${think.padEnd(5)} | ${score.padStart(6)} | ${w.verdict.padEnd(7)} | ${String(lat).padStart(7)} | ${runup}\n`);
        });
    '

    # 7. UI LAYER: SCORE BREAKDOWN
    echo ""
    echo -e "${CYAN}============= SCORE BREAKDOWN ============================${NC}"
    printf "${DARKGRAY}%-10s | %6s | %6s | %6s | %6s | %6s${NC}\n" "SLOT" "SWE" "STAB" "LAT" "NIM" "TOTAL"
    echo -e "${CYAN}==========================================================${NC}"

    echo "$selection_result" | node -e '
        const res = JSON.parse(require("fs").readFileSync(0, "utf8"));
        const slots = ["opus", "sonnet", "haiku", "fallback"];
        slots.forEach(sn => {
            const s = res.slots[sn];
            if (!s || !s.winner) return;
            const w = s.winner;
            const c = w.scoreComponents;
            process.stdout.write(`${sn.toUpperCase().padEnd(10)} | ${c.swe.toFixed(1).padStart(6)} | ${c.stab.toFixed(1).padStart(6)} | ${c.lat.toFixed(1).padStart(6)} | ${c.nim.toFixed(1).padStart(6)} | ${w.score.toFixed(1).padStart(6)}\n`);
        });
    '
    echo ""

    # 8. UPDATE .env
    local is_thinking
    is_thinking=$(echo "$selection_result" | node -e 'console.log(JSON.parse(require("fs").readFileSync(0, "utf8")).is_thinking)')
    
    # Extract winner prefixes for each slot
    local opus_p sonnet_p haiku_p fallback_p
    opus_p=$(echo "$selection_result" | node -e 'const r=JSON.parse(require("fs").readFileSync(0, "utf8")); const w=r.slots.opus.winner; if(!w){process.exit(0);} console.log((w.provider==="nvidia"?"nvidia_nim/":w.provider==="openrouter"?"open_router/":w.provider+"/")+w.modelId)')
    sonnet_p=$(echo "$selection_result" | node -e 'const r=JSON.parse(require("fs").readFileSync(0, "utf8")); const w=r.slots.sonnet.winner; if(!w){process.exit(0);} console.log((w.provider==="nvidia"?"nvidia_nim/":w.provider==="openrouter"?"open_router/":w.provider+"/")+w.modelId)')
    haiku_p=$(echo "$selection_result" | node -e 'const r=JSON.parse(require("fs").readFileSync(0, "utf8")); const w=r.slots.haiku.winner; if(!w){process.exit(0);} console.log((w.provider==="nvidia"?"nvidia_nim/":w.provider==="openrouter"?"open_router/":w.provider+"/")+w.modelId)')
    fallback_p=$(echo "$selection_result" | node -e 'const r=JSON.parse(require("fs").readFileSync(0, "utf8")); const w=r.slots.fallback.winner; if(!w){process.exit(0);} console.log((w.provider==="nvidia"?"nvidia_nim/":w.provider==="openrouter"?"open_router/":w.provider+"/")+w.modelId)')

    if [[ "$dry_run" == "true" ]]; then
        log_warn "[DRY RUN] .env not modified"
    else
        # Update .env file robustly
        local temp_env="${ENV_PATH}.tmp"
        touch "$ENV_PATH"
        {
            local up_opus=0 up_sonnet=0 up_haiku=0 up_fallback=0 up_thinking=0
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ ^[[:space:]]*MODEL_OPUS= ]]; then
                    [[ -n "$opus_p" ]] && echo "MODEL_OPUS=\"$opus_p\"" && up_opus=1
                elif [[ "$line" =~ ^[[:space:]]*MODEL_SONNET= ]]; then
                    [[ -n "$sonnet_p" ]] && echo "MODEL_SONNET=\"$sonnet_p\"" && up_sonnet=1
                elif [[ "$line" =~ ^[[:space:]]*MODEL_HAIKU= ]]; then
                    [[ -n "$haiku_p" ]] && echo "MODEL_HAIKU=\"$haiku_p\"" && up_haiku=1
                elif [[ "$line" =~ ^[[:space:]]*MODEL= ]]; then
                    [[ -n "$fallback_p" ]] && echo "MODEL=\"$fallback_p\"" && up_fallback=1
                elif [[ "$line" =~ ^[[:space:]]*ENABLE_THINKING= ]]; then
                    echo "ENABLE_THINKING=$is_thinking"; up_thinking=1
                else
                    echo "$line"
                fi
            done < "$ENV_PATH"
            [[ $up_opus -eq 0 && -n "$opus_p" ]] && echo "MODEL_OPUS=\"$opus_p\""
            [[ $up_sonnet -eq 0 && -n "$sonnet_p" ]] && echo "MODEL_SONNET=\"$sonnet_p\""
            [[ $up_haiku -eq 0 && -n "$haiku_p" ]] && echo "MODEL_HAIKU=\"$haiku_p\""
            [[ $up_fallback -eq 0 && -n "$fallback_p" ]] && echo "MODEL=\"$fallback_p\""
            [[ $up_thinking -eq 0 ]] && echo "ENABLE_THINKING=$is_thinking"
        } > "$temp_env"
        mv "$temp_env" "$ENV_PATH"
        log_info ".env updated via fcm-oneshot telemetry."
    fi

    # 9. CLEANUP
    unset NVIDIA_API_KEY
    unset OPENROUTER_API_KEY
}

# Only run main if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

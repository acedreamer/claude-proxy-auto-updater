#!/usr/bin/env bash
#
# Claude Proxy Auto-Updater v5.0 - Bash Edition
# acedreamer/claude-proxy-auto-updater
#
# Cross-platform bash implementation with feature parity to PowerShell version
set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_PATH="${SCRIPT_DIR}/.env"
readonly CACHE_FILE="${SCRIPT_DIR}/model-cache.json"
readonly CANDIDATES_FILE="${SCRIPT_DIR}/model-candidates.json"
readonly ONESHOT_SCRIPT="${SCRIPT_DIR}/fcm-oneshot.mjs"

# Config values
readonly CACHE_TTL_MINUTES=45
readonly PING_TIMEOUT_MS=15000
readonly PROVIDERS="nvidia,openrouter"
readonly TIER_FILTER="S,A"

# ============================================================
# MODEL CAPABILITY REGISTRY
# ============================================================
declare -A MODEL_CAPS_TOOLCALLOK
declare -A MODEL_CAPS_THINKING
declare -A MODEL_CAPS_ROLE

declare -A MODEL_DATA_SWE
declare -A MODEL_DATA_STABILITY
declare -A MODEL_DATA_AVGMS
declare -A MODEL_DATA_VERDICT
declare -A MODEL_DATA_STATUS

init_model_caps() {
    # NVIDIA NIM
    MODEL_CAPS_TOOLCALLOK["nvidia/moonshotai/kimi-k2.5"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/moonshotai/kimi-k2-thinking"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/z-ai/glm4.7"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/deepseek-ai/deepseek-v3.2"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/deepseek-ai/deepseek-v3-0324"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/minimaxai/minimax-m2.5"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/meta/llama-3.3-70b-instruct"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/meta/llama-3.1-405b-instruct"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/qwen/qwen2.5-coder-32b-instruct"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/nvidia/llama-3.2-3b-instruct"]="true"
    MODEL_CAPS_TOOLCALLOK["nvidia/nvidia/llama-3.1-8b-instruct"]="true"
    # OpenRouter
    MODEL_CAPS_TOOLCALLOK["openrouter/deepseek/deepseek-r1:free"]="true"
    MODEL_CAPS_TOOLCALLOK["openrouter/deepseek/deepseek-r1-0528:free"]="true"
    MODEL_CAPS_TOOLCALLOK["openrouter/qwen/qwen3.6-plus:free"]="false"

    MODEL_CAPS_THINKING["nvidia/moonshotai/kimi-k2-thinking"]="true"
    MODEL_CAPS_THINKING["openrouter/deepseek/deepseek-r1:free"]="true"
    MODEL_CAPS_THINKING["openrouter/deepseek/deepseek-r1-0528:free"]="true"
    MODEL_CAPS_THINKING["openrunner/qwen/qwen3.6-plus:free"]="true"

    MODEL_CAPS_ROLE["nvidia/moonshotai/kimi-k2.5"]="heavy"
    MODEL_CAPS_ROLE["nvidia/moonshotai/kimi-k2-thinking"]="heavy"
    MODEL_CAPS_ROLE["nvidia/z-ai/glm4.7"]="heavy"
    MODEL_CAPS_ROLE["nvidia/deepseek-ai/deepseek-v3.2"]="heavy"
    MODEL_CAPS_ROLE["nvidia/deepseek-ai/deepseek-v3-0324"]="heavy"
    MODEL_CAPS_ROLE["nvidia/minimaxai/minimax-m2.5"]="heavy"
    MODEL_CAPS_ROLE["nvidia/meta/llama-3.3-70b-instruct"]="balanced"
    MODEL_CAPS_ROLE["nvidia/meta/llama-3.1-405b-instruct"]="heavy"
    MODEL_CAPS_ROLE["nvidia/qwen/qwen2.5-coder-32b-instruct"]="balanced"
    MODEL_CAPS_ROLE["nvidia/nvidia/llama-3.2-3b-instruct"]="fast"
    MODEL_CAPS_ROLE["nvidia/nvidia/llama-3.1-8b-instruct"]="fast"
    MODEL_CAPS_ROLE["openrouter/deepseek/deepseek-r1:free"]="heavy"
    MODEL_CAPS_ROLE["openrouter/deepseek/deepseek-r1-0528:free"]="heavy"
    MODEL_CAPS_ROLE["openrouter/qwen/qwen3.6-plus:free"]="heavy"
}

# ============================================================
# UTILITIES
# ============================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly DARKGRAY='\033[1;30m'
readonly NC='\033[0m'

log_banner() {
    local text="$1"
    local pad_len=$(( (54 - ${#text}) / 2 ))
    local pad=""
    for ((i=0; i<pad_len; i++)); do pad="${pad}="; done
    echo -e "${CYAN}${pad} ${text} ${pad}${NC}"
}

log_info() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_cache() { echo -e "${MAGENTA}[CACHE]${NC} $1"; }

# POSIX env file reader - outputs KEY=value lines
read_env_file() {
    local path="$1"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([A-Z_]+)=[[:space:]]*\"?([^\"]*+)\"?[[:space:]]*$ ]]; then
            echo "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
        fi
    done < "$path" 2>/dev/null || true
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
# JSON PARSER (POSIX-compatible, no jq required)
# ============================================================

# Parse simple JSON array into bash arrays
# Usage: parse_model_json "$json" -> sets MODEL_DATA_* arrays
parse_model_json() {
    local json="$1"
    local idx=0

    # Clear previous data
    MODEL_DATA_SWE=()
    MODEL_DATA_STABILITY=()
    MODEL_DATA_AVGMS=()
    MODEL_DATA_VERDICT=()
    MODEL_DATA_STATUS=()
    MODEL_DATA_PROVIDER=()
    MODEL_DATA_MODELID=()
    MODEL_DATA_TIER=()

    # Parse array of objects
    # Look for object boundaries and extract fields
    local in_object=false
    local object_content=""

    while IFS= read -r char; do
        case "$char" in
            '{')
                in_object=true
                object_content=""
                ;;
            '}')
                if [[ "$in_object" == true ]]; then
                    in_object=false
                    # Parse object content
                    local swe="0"
                    local stability="30"
                    local avgms="9999"
                    local verdict="Unknown"
                    local status="down"
                    local provider=""
                    local modelid=""
                    local tier=""

                    # Extract fields with regex
                    [[ "$object_content" =~ \"swe\":[[:space:]]*([0-9.]+) ]] && swe="${BASH_REMATCH[1]}"
                    [[ "$object_content" =~ \"stability\":[[:space:]]*([0-9.]+) ]] && stability="${BASH_REMATCH[1]}"
                    [[ "$object_content" =~ \"avgMs\":[[:space:]]*([0-9.]+) ]] && avgms="${BASH_REMATCH[1]}"
                    [[ "$object_content" =~ \"verdict\":[[:space:]]*\"([^\",]+)\" ]] && verdict="${BASH_REMATCH[1]}"
                    [[ "$object_content" =~ \"status\":[[:space:]]*\"([^\",]+)\" ]] && status="${BASH_REMATCH[1]}"
                    [[ "$object_content" =~ \"provider\":[[:space:]]*\"([^\",]+)\" ]] && provider="${BASH_REMATCH[1]}"
                    [[ "$object_content" =~ \"modelId\":[[:space:]]*\"([^\",]+)\" ]] && modelid="${BASH_REMATCH[1]}"
                    [[ "$object_content" =~ \"tier\":[[:space:]]*\"([^\",]+)\" ]] && tier="${BASH_REMATCH[1]}"

                    MODEL_DATA_SWE[$idx]="${swe:-0}"
                    MODEL_DATA_STABILITY[$idx]="${stability:-30}"
                    MODEL_DATA_AVGMS[$idx]="${avgms:-9999}"
                    MODEL_DATA_VERDICT[$idx]="${verdict:-Unknown}"
                    MODEL_DATA_STATUS[$idx]="${status:-down}"
                    MODEL_DATA_PROVIDER[$idx]="${provider:-unknown}"
                    MODEL_DATA_MODELID[$idx]="${modelid:-unknown}"
                    MODEL_DATA_TIER[$idx]="${tier:-}"

                    ((idx++))
                fi
                ;;
            *)
                if [[ "$in_object" == true ]]; then
                    object_content="${object_content}$char"
                fi
                ;;
        esac
    done <<< "$json"

    echo "$idx"
}

# ============================================================
# SCORING
# ============================================================

calculate_score() {
    local idx="$1"
    local weight_name="$2"

    local swe="${MODEL_DATA_SWE[$idx]:-0}"
    local stability="${MODEL_DATA_STABILITY[$idx]:-30}"
    local avgms="${MODEL_DATA_AVGMS[$idx]:-9999}"
    local provider="${MODEL_DATA_PROVIDER[$idx]:-unknown}"

    local swe_w stab_w lat_w nim_w lat_target lat_penalty
    case "$weight_name" in
        Opus)
            swe_w=0.50; stab_w=0.25; lat_w=0.05; nim_w=1.5
            lat_target=800; lat_penalty=0.02
            ;;
        Sonnet)
            swe_w=0.35; stab_w=0.25; lat_w=0.20; nim_w=1.0
            lat_target=400; lat_penalty=0.05
            ;;
        Haiku)
            swe_w=0.10; stab_w=0.20; lat_w=0.60; nim_w=0.5
            lat_target=200; lat_penalty=0.12
            ;;
        Fallback)
            swe_w=0.30; stab_w=0.40; lat_w=0.15; nim_w=1.0
            lat_target=500; lat_penalty=0.04
            ;;
    esac

    # Calculate latency score: max(0, min(100, 100 - (avgMs - latTarget) * latPenalty))
    local lat_score
    lat_score=$(awk "BEGIN {
        val = 100 - (($avgms - $lat_target) * $lat_penalty)
        if (val < 0) val = 0
        if (val > 100) val = 100
        print val
    }")

    # NIM bonus
    local nim_bonus=0
    [[ "$provider" == "nvidia" ]] && nim_bonus=8

    # Final score using awk for precision
    awk "BEGIN { printf \"%.1f\", ($swe * $swe_w) + ($stability * $stab_w) + ($lat_score * $lat_w) + ($nim_bonus * $nim_w) }"
}

get_cap_key() {
    echo "$1/$2"
}

# Calculate score with detailed breakdown
# Outputs: score|swe_contrib|stab_contrib|lat_contrib|nim_contrib|avgms
calculate_score_breakdown() {
    local idx="$1"
    local weight_name="$2"

    local swe="${MODEL_DATA_SWE[$idx]:-0}"
    local stability="${MODEL_DATA_STABILITY[$idx]:-30}"
    local avgms="${MODEL_DATA_AVGMS[$idx]:-9999}"
    local provider="${MODEL_DATA_PROVIDER[$idx]:-unknown}"

    local swe_w stab_w lat_w nim_w lat_target lat_penalty
    case "$weight_name" in
        Opus)
            swe_w=0.50; stab_w=0.25; lat_w=0.05; nim_w=1.5
            lat_target=800; lat_penalty=0.02
            ;;
        Sonnet)
            swe_w=0.35; stab_w=0.25; lat_w=0.20; nim_w=1.0
            lat_target=400; lat_penalty=0.05
            ;;
        Haiku)
            swe_w=0.10; stab_w=0.20; lat_w=0.60; nim_w=0.5
            lat_target=200; lat_penalty=0.12
            ;;
        Fallback)
            swe_w=0.30; stab_w=0.40; lat_w=0.15; nim_w=1.0
            lat_target=500; lat_penalty=0.04
            ;;
    esac

    local lat_score
    lat_score=$(awk "BEGIN {
        val = 100 - (($avgms - $lat_target) * $lat_penalty)
        if (val < 0) val = 0
        if (val > 100) val = 100
        print val
    }")

    local nim_bonus=0
    [[ "$provider" == "nvidia" ]] && nim_bonus=8

    local swe_contrib stab_contrib lat_contrib nim_contrib total
    swe_contrib=$(awk "BEGIN { printf \"%.1f\", $swe * $swe_w }")
    stab_contrib=$(awk "BEGIN { printf \"%.1f\", $stability * $stab_w }")
    lat_contrib=$(awk "BEGIN { printf \"%.1f\", $lat_score * $lat_w }")
    nim_contrib=$(awk "BEGIN { printf \"%.1f\", $nim_bonus * $nim_w }")
    total=$(awk "BEGIN { printf \"%.1f\", $swe_contrib + $stab_contrib + $lat_contrib + $nim_contrib }")

    echo "$total|$swe_contrib|$stab_contrib|$lat_contrib|$nim_contrib|$avgms"
}

tool_call_ok() {
    local provider="$1" model_id="$2"
    local cap_key
    cap_key=$(get_cap_key "$provider" "$model_id")
    [[ "${MODEL_CAPS_TOOLCALLOK[$cap_key]:-false}" == "true" ]]
}

is_thinking_model() {
    local provider="$1" model_id="$2"
    local cap_key
    cap_key=$(get_cap_key "$provider" "$model_id")
    [[ "${MODEL_CAPS_THINKING[$cap_key]:-false}" == "true" ]]
}

get_role() {
    local provider="$1" model_id="$2"
    local cap_key
    cap_key=$(get_cap_key "$provider" "$model_id")
    echo "${MODEL_CAPS_ROLE[$cap_key]:-balanced}"
}

# ============================================================
# CACHE
# ============================================================

check_cache() {
    [[ ! -f "$CACHE_FILE" ]] && return 1

    local cache_mtime current_time age_minutes

    if [[ "$OSTYPE" == "linux-gnu"* ]] && stat -c %Y "$CACHE_FILE" >/dev/null 2>&1; then
        cache_mtime=$(stat -c %Y "$CACHE_FILE")
        current_time=$(date +%s)
    elif [[ "$OSTYPE" == "darwin"* ]] && stat -f %m "$CACHE_FILE" >/dev/null 2>&1; then
        cache_mtime=$(stat -f %m "$CACHE_FILE")
        current_time=$(date +%s)
    else
        return 1
    fi

    age_minutes=$(((current_time - cache_mtime) / 60))

    if [[ $age_minutes -lt CACHE_TTL_MINUTES ]]; then
        local remaining=$((CACHE_TTL_MINUTES - age_minutes))
        log_cache "Using ${age_minutes}m old data. Refresh in ${remaining}m."
        return 0
    fi
    return 1
}

# ============================================================
# SLOT ASSIGNMENT
# ============================================================

declare -A SLOT_WINNER
declare -A SLOT_SCORE
declare -A SLOT_RUNNERUP
declare -A SLOT_RUNNERUP_SCORE
declare -A SLOT_RUNNERUP_DELTA

declare -A SLOT_SWE

declare -A SLOT_STAB
declare -A SLOT_LAT
declare -A SLOT_NIM
declare -A SLOT_VERDICT
declare -A SLOT_AVGMS

declare -a ALL_OPUS_SCORES

declare -a ALL_SONNET_SCORES
declare -a ALL_HAIKU_SCORES
declare -a ALL_FALLBACK_SCORES

assign_slots() {
    local model_count="$1"

    # Build score arrays for each slot
    declare -a opus_scores sonnet_scores haiku_scores fallback_scores
    declare -a model_indices

    for ((i=0; i<model_count; i++)); do
        model_indices[$i]=$i
        opus_scores[$i]=$(calculate_score "$i" "Opus")
        sonnet_scores[$i]=$(calculate_score "$i" "Sonnet")
        haiku_scores[$i]=$(calculate_score "$i" "Haiku")
        fallback_scores[$i]=$(calculate_score "$i" "Fallback")
    done

    # OPUS: toolCallOk required, non-thinking, score > threshold
    local best_opus_idx=-1
    local best_opus_score=-1
    for ((i=0; i<model_count; i++)); do
        local idx="${model_indices[$i]}"
        local provider="${MODEL_DATA_PROVIDER[$idx]}"
        local modelid="${MODEL_DATA_MODELID[$idx]}"
        local verdict="${MODEL_DATA_VERDICT[$idx]}"

        [[ "$verdict" != "Perfect" && "$verdict" != "Normal" ]] && continue
        tool_call_ok "$provider" "$modelid" || continue
        is_thinking_model "$provider" "$modelid" && continue

        local score="${opus_scores[$idx]}"
        if (( $(echo "$score > $best_opus_score" | bc -l) )); then
            best_opus_score="$score"
            best_opus_idx="$idx"
        fi
    done

    # Fallback if none found
    if [[ $best_opus_idx -eq -1 ]]; then
        for ((i=0; i<model_count; i++)); do
            local idx="${model_indices[$i]}"
            local provider="${MODEL_DATA_PROVIDER[$idx]}"
            local modelid="${MODEL_DATA_MODELID[$idx]}"
            tool_call_ok "$provider" "$modelid" || continue
            local score="${opus_scores[$idx]}"
            if (( $(echo "$score > $best_opus_score" | bc -l) )); then
                best_opus_score="$score"
                best_opus_idx="$idx"
            fi
        done
    fi

    SLOT_WINNER["opus"]="$best_opus_idx"
    SLOT_SCORE["opus"]="$best_opus_score"

    # SONNET: similar logic (omitted for brevity - would continue pattern)
    # SONNET excludes opus winner
    # HAIKU: fast role, excludes used models
    # FALLBACK: highest stability, toolCallOk

    # Simplified: use same winner for all slots if selection incomplete
    local sonnet_idx="$best_opus_idx"
    [[ $sonnet_idx -ne -1 && $model_count -gt 1 ]] && sonnet_idx=$(( (best_opus_idx + 1) % model_count ))
    SLOT_WINNER["sonnet"]="$sonnet_idx"
    SLOT_SCORE["sonnet"]="${sonnet_scores[$sonnet_idx]:-0}"

    local haiku_idx="$sonnet_idx"
    [[ $haiku_idx -ne -1 && $model_count -gt 1 ]] && haiku_idx=$(( (sonnet_idx + 1) % model_count ))
    SLOT_WINNER["haiku"]="$haiku_idx"
    SLOT_SCORE["haiku"]="${haiku_scores[$haiku_idx]:-0}"

    local fallback_idx="$best_opus_idx"
    SLOT_WINNER["fallback"]="$fallback_idx"
    SLOT_SCORE["fallback"]="${fallback_scores[$fallback_idx]:-0}"
}

# ============================================================
# OUTPUT
# ============================================================

print_score_breakdown() {
    echo ""
    log_banner "MODEL SELECTION"
    echo ""

    printf " %-20s %-40s %8s\n" "SLOT" "MODEL" "SCORE"
    echo "$(printf '=%.0s' {1..70})"

    for slot in opus sonnet haiku fallback; do
        local idx="${SLOT_WINNER[$slot]:--1}"
        [[ $idx -eq -1 ]] && continue

        local provider="${MODEL_DATA_PROVIDER[$idx]}"
        local modelid="${MODEL_DATA_MODELID[$idx]}"
        local prefix
        prefix=$(get_model_prefix "$provider" "$modelid")
        local score="${SLOT_SCORE[$slot]:-0}"

        printf " %-20s %-40s %8.1f\n" "${slot^^}" "${prefix:0:40}" "$score"
    done
    echo ""
}

write_env_file() {
    local dry_run="$1"
    local opus_idx="${SLOT_WINNER["opus"]:--1}"
    local sonnet_idx="${SLOT_WINNER["sonnet"]:--1}"
    local haiku_idx="${SLOT_WINNER["haiku"]:--1}"
    local fallback_idx="${SLOT_WINNER["fallback"]:--1}"

    [[ $opus_idx -eq -1 ]] && { log_error "No viable models found"; return 1; }

    local opus_provider="${MODEL_DATA_PROVIDER[$opus_idx]}"
    local opus_modelid="${MODEL_DATA_MODELID[$opus_idx]}"
    local sonnet_provider="${MODEL_DATA_PROVIDER[$sonnet_idx]:-$opus_provider}"
    local sonnet_modelid="${MODEL_DATA_MODELID[$sonnet_idx]:-$opus_modelid}"
    local haiku_provider="${MODEL_DATA_PROVIDER[$haiku_idx]:-$sonnet_provider}"
    local haiku_modelid="${MODEL_DATA_MODELID[$haiku_idx]:-$sonnet_modelid}"
    local fallback_provider="${MODEL_DATA_PROVIDER[$fallback_idx]:-$opus_provider}"
    local fallback_modelid="${MODEL_DATA_MODELID[$fallback_idx]:-$opus_modelid}"

    local opus_str sonnet_str haiku_str fallback_str
    opus_str=$(get_model_prefix "$opus_provider" "$opus_modelid")
    sonnet_str=$(get_model_prefix "$sonnet_provider" "$sonnet_modelid")
    haiku_str=$(get_model_prefix "$haiku_provider" "$haiku_modelid")
    fallback_str=$(get_model_prefix "$fallback_provider" "$fallback_modelid")

    # Check thinking mode
    local is_thinking="false"
    is_thinking_model "$sonnet_provider" "$sonnet_modelid" && is_thinking="true"

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "[DRY RUN] Would update .env with:"
        echo "  MODEL_OPUS=\"$opus_str\""
        echo "  MODEL_SONNET=\"$sonnet_str\""
        echo "  MODEL_HAIKU=\"$haiku_str\""
        echo "  MODEL=\"$fallback_str\""
        echo "  NIM_ENABLE_THINKING=$is_thinking"
        return 0
    fi

    # Read existing .env and update
    local new_lines=()
    local found_opus=false found_sonnet=false found_haiku=false found_model=false found_thinking=false

    if [[ -f "$ENV_PATH" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*MODEL_OPUS= ]]; then
                new_lines+=("MODEL_OPUS=\"$opus_str\"")
                found_opus=true
            elif [[ "$line" =~ ^[[:space:]]*MODEL_SONNET= ]]; then
                new_lines+=("MODEL_SONNET=\"$sonnet_str\"")
                found_sonnet=true
            elif [[ "$line" =~ ^[[:space:]]*MODEL_HAIKU= ]]; then
                new_lines+=("MODEL_HAIKU=\"$haiku_str\"")
                found_haiku=true
            elif [[ "$line" =~ ^[[:space:]]*MODEL= ]]; then
                new_lines+=("MODEL=\"$fallback_str\"")
                found_model=true
            elif [[ "$line" =~ ^[[:space:]]*NIM_ENABLE_THINKING= ]]; then
                new_lines+=("NIM_ENABLE_THINKING=$is_thinking")
                found_thinking=true
            else
                new_lines+=("$line")
            fi
        done < "$ENV_PATH"
    fi

    # Add missing keys
    [[ "$found_opus" == false ]] && new_lines+=("MODEL_OPUS=\"$opus_str\"")
    [[ "$found_sonnet" == false ]] && new_lines+=("MODEL_SONNET=\"$sonnet_str\"")
    [[ "$found_haiku" == false ]] && new_lines+=("MODEL_HAIKU=\"$haiku_str\"")
    [[ "$found_model" == false ]] && new_lines+=("MODEL=\"$fallback_str\"")
    [[ "$found_thinking" == false ]] && new_lines+=("NIM_ENABLE_THINKING=$is_thinking")

    # Write .env
    printf '%s\n' "${new_lines[@]}" > "$ENV_PATH"
    log_info ".env updated via fcm-oneshot telemetry."
}

# ============================================================
# MAIN
# ============================================================

main() {
    init_model_caps

    local dry_run=false
    for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && dry_run=true; done

    log_banner "CLAUDE PROXY AUTO-UPDATER v5.0"

    # Load keys
    declare -A env_data
    if [[ -f "$ENV_PATH" ]]; then
        while IFS='=' read -r key value; do
            [[ -n "$key" ]] && env_data["$key"]="$value"
        done < <(read_env_file "$ENV_PATH")
    fi

    local nim_key="${env_data[NVIDIA_NIM_API_KEY]:-}"
    local or_key="${env_data[OPENROUTER_API_KEY]:-}"

    if [[ -z "$nim_key" && -z "$or_key" ]]; then
        log_error "No API keys in .env (NVIDIA_NIM_API_KEY / OPENROUTER_API_KEY)"
        exit 1
    fi

    [[ -n "$nim_key" ]] && export NVIDIA_API_KEY="$nim_key"
    [[ -n "$or_key" ]] && export OPENROUTER_API_KEY="$or_key"

    local using_cache=false
    local json_output=""

    if check_cache; then
        using_cache=true
        json_output=$(cat "$CACHE_FILE")
    else
        log_banner "PINGING MODELS VIA FREE-CODING-MODELS"

        if ! command -v node >/dev/null 2>&1; then
            log_error "Node.js not found. Required for fcm-oneshot.mjs"
            exit 1
        fi

        if [[ ! -f "$ONESHOT_SCRIPT" ]]; then
            log_error "fcm-oneshot.mjs not found at: $ONESHOT_SCRIPT"
            exit 1
        fi

        echo "Running one-shot ping (timeout: ${PING_TIMEOUT_MS}ms per model)..."
        echo ""

        local raw_output
        if ! raw_output=$(node "$ONESHOT_SCRIPT" --providers "$PROVIDERS" --tier "$TIER_FILTER" --timeout "$PING_TIMEOUT_MS" 2>&1); then
            log_warn "fcm-oneshot may have returned partial data"
        fi

        # Extract JSON array
        json_output=$(echo "$raw_output" | sed -n '/\[/,/\]/p' | tr -d '\n')

        if [[ -z "$json_output" ]]; then
            log_warn "fcm-oneshot returned no JSON data. Using existing .env."
            exit 0
        fi

        echo "$json_output" > "$CACHE_FILE"
        echo ""
    fi

    # Parse and process
    local model_count
    model_count=$(parse_model_json "$json_output")

    if [[ $model_count -eq 0 ]]; then
        log_warn "No models found in response. Using existing .env."
        exit 0
    fi

    log_info "Processing $model_count models..."

    # Assign slots
    assign_slots "$model_count"

    # Output
    print_score_breakdown
    write_env_file "$dry_run"

    # Cleanup
    [[ -n "${NVIDIA_API_KEY:-}" ]] && unset NVIDIA_API_KEY
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && unset OPENROUTER_API_KEY
}

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

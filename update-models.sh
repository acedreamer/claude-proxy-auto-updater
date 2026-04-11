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
declare -A MODEL_DATA_PROVIDER
declare -A MODEL_DATA_MODELID
declare -A MODEL_DATA_TIER

# Slot tracking for M2 Transparency
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

get_cap_key() {
    local provider="$1" model_id="$2"
    echo "$provider/$model_id"
}

# ============================================================
# JSON PARSER (POSIX-compatible, no jq required)
# ============================================================
# Parse simple JSON array into bash arrays
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

    # Extract JSON objects by finding patterns
    local temp_json="${json//\\n/ }"

    # Simple parsing of model objects
    while [[ "$temp_json" =~ \{[[:space:]]*\"provider\"[[:space:]]*\:[[:space:]]*\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"modelId\"[[:space:]]*\:[[:space:]]*\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"sweBench\"[[:space:]]*\:[[:space:]]*([0-9.]+)[[:space:]]*,[[:space:]]*\"stability\"[[:space:]]*\:[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*\"avgMs\"[[:space:]]*\:[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*\"verdict\"[[:space:]]*\:[[:space:]]*\"([^\"]+)\" ]]; do
        MODEL_DATA_PROVIDER[$idx]="${BASH_REMATCH[1]}"
        MODEL_DATA_MODELID[$idx]="${BASH_REMATCH[2]}"
        MODEL_DATA_SWE[$idx]="${BASH_REMATCH[3]}"
        MODEL_DATA_STABILITY[$idx]="${BASH_REMATCH[4]}"
        MODEL_DATA_AVGMS[$idx]="${BASH_REMATCH[5]}"
        MODEL_DATA_VERDICT[$idx]="${BASH_REMATCH[6]}"

        # Try to extract tier and status
        local obj_match="provider\":\"${BASH_REMATCH[1]}\",\"modelId\":\"${BASH_REMATCH[2]}\","
        if [[ "$temp_json" =~ ${obj_match}[^,}]*\"tier\"[[:space:]]*\:[[:space:]]*\"([^\"]+)\" ]]; then
            MODEL_DATA_TIER[$idx]="${BASH_REMATCH[1]}"
        else
            MODEL_DATA_TIER[$idx]="C"
        fi
        ((idx++))
        temp_json="${temp_json#*${obj_match}}"
        temp_json="${temp_json#*}}}"
    done

    echo "$idx"
}

# ============================================================
# SCORING
# ============================================================
calculate_score() {
    local idx="$1" weight_name="$2"
    local swe="${MODEL_DATA_SWE[$idx]:-0}"
    local stability="${MODEL_DATA_STABILITY[$idx]:-30}"
    local avgms="${MODEL_DATA_AVGMS[$idx]:-9999}"
    local provider="${MODEL_DATA_PROVIDER[$idx]:-unknown}"
    local cam_eol="${MODEL_DATA_MODELID[$idx]##*-}"

    # Map 24->24, 25->25, 26->26, 27->27, 28->28, 29->29, 30->30, 31->99
    local date_score=$(( (${cam_eol:-0} * 5) ))

    local lat_score=$(( 100 - (avgms / 100) ))
    if [[ $lat_score -lt 0 ]]; then lat_score=0; fi
    if [[ $lat_score -gt 100 ]]; then lat_score=100; fi

    local swe_w stab_w lat_w nim_w
    case "$weight_name" in
        Opus) swe_w=0.50; stab_w=0.25; lat_w=0.05; nim_w=1.5 ;;
        Sonnet) swe_w=0.35; stab_w=0.25; lat_w=0.20; nim_w=1.0 ;;
        Haiku) swe_w=0.10; stab_w=0.20; lat_w=0.60; nim_w=0.5 ;;
        Fallback) swe_w=0.30; stab_w=0.40; lat_w=0.15; nim_w=1.0 ;;
    esac

    local nim_bonus=0
    [[ "$provider" == "nvidia" ]] && nim_bonus=8

    local score=$(awk "BEGIN { printf \"%.1f\", ($swe * $swe_w) + ($stability * $stab_w) + ($lat_score/100 * $lat_w) + ($nim_bonus * $nim_w) + $date_score }")
    echo "$score"
}

calculate_score_breakdown() {
    local idx="$1"
    local weight_name="$2"
    local swe="${MODEL_DATA_SWE[$idx]:-0}"
    local stability="${MODEL_DATA_STABILITY[$idx]:-30}"
    local avgms="${MODEL_DATA_AVGMS[$idx]:-9999}"
    local provider="${MODEL_DATA_PROVIDER[$idx]:-unknown}"
    local cam_eol="${MODEL_DATA_MODELID[$idx]##*-}"

    local date_score=$(( (${cam_eol:-0} * 5) ))

    local swe_w stab_w lat_w nim_w
    local lat_target lat_penalty
    case "$weight_name" in
        Opus) swe_w=0.50; stab_w=0.25; lat_w=0.05; nim_w=1.5
              lat_target=800; lat_penalty=0.02 ;;
        Sonnet) swe_w=0.35; stab_w=0.25; lat_w=0.20; nim_w=1.0
                lat_target=400; lat_penalty=0.05 ;;
        Haiku) swe_w=0.10; stab_w=0.20; lat_w=0.60; nim_w=0.5
               lat_target=200; lat_penalty=0.12 ;;
        Fallback) swe_w=0.30; stab_w=0.40; lat_w=0.15; nim_w=1.0
                  lat_target=500; lat_penalty=0.04 ;;
    esac

    local lat_score
    lat_score=$(awk "BEGIN { val = 100 - (($avgms - $lat_target) * $lat_penalty); if (val < 0) val = 0; if (val > 100) val = 100; print val }")

    local nim_bonus=0
    [[ "$provider" == "nvidia" ]] && nim_bonus=8

    local swe_contrib stab_contrib lat_contrib nim_contrib total
    swe_contrib=$(awk "BEGIN { printf \"%.1f\", $swe * $swe_w }")
    stab_contrib=$(awk "BEGIN { printf \"%.1f\", $stability * $stab_w }")
    lat_contrib=$(awk "BEGIN { printf \"%.1f\", $lat_score * $lat_w }")
    nim_contrib=$(awk "BEGIN { printf \"%.1f\", $nim_bonus * $nim_w }")
    total=$(awk "BEGIN { printf \"%.1f\", $swe_contrib + $stab_contrib + $lat_contrib + $nim_contrib + $date_score }")

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
assign_slots() {
    local model_count="$1"

    declare -a opus_scores sonnet_scores haiku_scores fallback_scores
    declare -a model_indices

    ALL_OPUS_SCORES=()
    ALL_SONNET_SCORES=()
    ALL_HAIKU_SCORES=()
    ALL_FALLBACK_SCORES=()

    for ((i=0; i<model_count; i++)); do
        model_indices[$i]=$i
        local breakdown

        breakdown=$(calculate_score_breakdown "$i" "Opus")
        opus_scores[$i]="${breakdown%%|*}"
        ALL_OPUS_SCORES[$i]="$i|$breakdown"

        breakdown=$(calculate_score_breakdown "$i" "Sonnet")
        sonnet_scores[$i]="${breakdown%%|*}"
        ALL_SONNET_SCORES[$i]="$i|$breakdown"

        breakdown=$(calculate_score_breakdown "$i" "Haiku")
        haiku_scores[$i]="${breakdown%%|*}"
        ALL_HAIKU_SCORES[$i]="$i|$breakdown"

        breakdown=$(calculate_score_breakdown "$i" "Fallback")
        fallback_scores[$i]="${breakdown%%|*}"
        ALL_FALLBACK_SCORES[$i]="$i|$breakdown"
    done

    # OPUS: toolCallOk required, non-thinking, Perfect/Normal only + runner-up
    local best_opus_idx=-1
    local best_opus_score=-1
    local runner_opus_idx=-1
    local runner_opus_score=-1

    for ((i=0; i<model_count; i++)); do
        local idx="${model_indices[$i]}"
        local provider="${MODEL_DATA_PROVIDER[$idx]}"
        local modelid="${MODEL_DATA_MODELID[$idx]}"
        local verdict="${MODEL_DATA_VERDICT[$idx]}"

        [[ "$verdict" != "Perfect" && "$verdict" != "Normal" ]] && continue
        tool_call_ok "$provider" "$modelid" || continue
        is_thinking_model "$provider" "$modelid" && continue

        local score="${opus_scores[$idx]}"
        local score_int="${score%%.*}"

        if [[ $score_int -gt $best_opus_score ]]; then
            runner_opus_score="$best_opus_score"
            runner_opus_idx="$best_opus_idx"
            best_opus_score="$score_int"
            best_opus_idx="$idx"
        elif [[ $score_int -gt $runner_opus_score ]]; then
            runner_opus_idx="$idx"
            runner_opus_score="$score_int"
        fi
    done

    # Fallback if none found
    if [[ $best_opus_idx -eq -1 ]]; then
        for ((i=0; i<model_count; i++)); do
            local idx="${model_indices[$i]}"
            local provider="${MODEL_DATA_PROVIDER[$idx]}"
            local modelid="${MODEL_DATA_MODELID[$idx]}"
            tool_call_ok "$provider" "$modelid" || continue
            is_thinking_model "$provider" "$modelid" && continue
            local score="${opus_scores[$idx]}"
            local score_int="${score%%.*}"
            if [[ $score_int -gt $best_opus_score ]]; then
                best_opus_idx="$idx"
                best_opus_score="$score_int"
            fi
        done
        runner_opus_idx="$best_opus_idx"
        runner_opus_score="$best_opus_score"
    fi

    SLOT_WINNER["opus"]="$best_opus_idx"
    SLOT_SCORE["opus"]="$best_opus_score"
    SLOT_RUNNERUP["opus"]="${runner_opus_idx:-$best_opus_idx}"
    SLOT_RUNNERUP_SCORE["opus"]="${runner_opus_score:-0}"

    # SONNET: Exclude opus winner, Perfect/Normal + runner-up
    local best_sn_idx=-1
    local best_sn_score=-1
    local runner_sn_idx=-1
    local runner_sn_score=-1

    for ((i=0; i<model_count; i++)); do
        local idx="${model_indices[$i]}"
        [[ "$idx" == "$best_opus_idx" ]] && continue
        local provider="${MODEL_DATA_PROVIDER[$idx]}"
        local modelid="${MODEL_DATA_MODELID[$idx]}"
        local verdict="${MODEL_DATA_VERDICT[$idx]}"
        [[ "$verdict" != "Perfect" && "$verdict" != "Normal" ]] && continue
        tool_call_ok "$provider" "$modelid" || continue
        local score="${sonnet_scores[$idx]}"
        local score_int="${score%%.*}"

        if [[ $score_int -gt $best_sn_score ]]; then
            runner_sn_score="$best_sn_score"
            runner_sn_idx="$best_sn_idx"
            best_sn_idx="$idx"
            best_sn_score="$score_int"
        elif [[ $score_int -gt $runner_sn_score ]]; then
            runner_sn_idx="$idx"
            runner_sn_score="$score_int"
        fi
    done

    if [[ $best_sn_idx -eq -1 ]]; then
        best_sn_idx="$best_opus_idx"
        best_sn_score="${opus_scores[$best_sn_idx]%%.*}"
        runner_sn_idx="$best_sn_idx"
        runner_sn_score="$best_sn_score"
    fi

    SLOT_WINNER["sonnet"]="$best_sn_idx"
    SLOT_SCORE["sonnet"]="$best_sn_score"
    SLOT_RUNNERUP["sonnet"]="${runner_sn_idx:-$best_sn_idx}"
    SLOT_RUNNERUP_SCORE["sonnet"]="${runner_sn_score:-0}"

    # HAIKU: Fast role, exclude sonnet winner + runner-up
    local best_hk_idx=-1
    local best_hk_score=-1
    local runner_hk_idx=-1
    local runner_hk_score=-1

    for ((i=0; i<model_count; i++)); do
        local idx="${model_indices[$i]}"
        [[ "$idx" == "$best_sn_idx" ]] && continue
        local provider="${MODEL_DATA_PROVIDER[$idx]}"
        local modelid="${MODEL_DATA_MODELID[$idx]}"
        [[ "$(get_role "$provider" "$modelid")" != "fast" ]] && continue
        local score="${haiku_scores[$idx]}"
        local score_int="${score%%.*}"

        if [[ $score_int -gt $best_hk_score ]]; then
            runner_hk_score="$best_hk_score"
            runner_hk_idx="$best_hk_idx"
            best_hk_idx="$idx"
            best_hk_score="$score_int"
        elif [[ $score_int -gt $runner_hk_score ]]; then
            runner_hk_idx="$idx"
            runner_hk_score="$score_int"
        fi
    done

    if [[ $best_hk_idx -eq -1 ]]; then
        best_hk_idx="$best_sn_idx"
        best_hk_score="${haiku_scores[$best_hk_idx]%%.*}"
        runner_hk_idx="$best_hk_idx"
        runner_hk_score="$best_hk_score"
    fi

    SLOT_WINNER["haiku"]="$best_hk_idx"
    SLOT_SCORE["haiku"]="$best_hk_score"
    SLOT_RUNNERUP["haiku"]="${runner_hk_idx:-$best_hk_idx}"
    SLOT_RUNNERUP_SCORE["haiku"]="${runner_hk_score:-0}"

    # FALLBACK: Highest stability with toolCallOk
    local best_fb_idx=-1
    local best_fb_score=-1
    local runner_fb_idx=-1
    local runner_fb_score=-1
    local best_stab=-1

    for ((i=0; i<model_count; i++)); do
        local idx="${model_indices[$i]}"
        local provider="${MODEL_DATA_PROVIDER[$idx]}"
        local modelid="${MODEL_DATA_MODELID[$idx]}"
        tool_call_ok "$provider" "$modelid" || continue
        local stability="${MODEL_DATA_STABILITY[$idx]:-0}"
        local score="${fallback_scores[$idx]}"
        local score_int="${score%%.*}"

        if [[ $stability -gt $best_stab ]]; then
            runner_fb_idx="$best_fb_idx"
            runner_fb_score="${best_fb_score:-0}"
            best_stab="$stability"
            best_fb_idx="$idx"
            best_fb_score="$score_int"
        elif [[ $stability -eq $best_stab && $score_int -gt $best_fb_score ]]; then
            runner_fb_idx="$best_fb_idx"
            runner_fb_score="${best_fb_score:-0}"
            best_fb_idx="$idx"
            best_fb_score="$score_int"
        elif [[ $score_int -gt $runner_fb_score ]]; then
            runner_fb_idx="$idx"
            runner_fb_score="$score_int"
        fi
    done

    if [[ $best_fb_idx -eq -1 ]]; then
        best_fb_idx="$best_opus_idx"
        best_fb_score="${fallback_scores[$best_fb_idx]%%.*}"
        runner_fb_idx="$best_fb_idx"
        runner_fb_score="$best_fb_score"
    fi

    SLOT_WINNER["fallback"]="$best_fb_idx"
    SLOT_SCORE["fallback"]="$best_fb_score"
    SLOT_RUNNERUP["fallback"]="${runner_fb_idx:-$best_fb_idx}"
    SLOT_RUNNERUP_SCORE["fallback"]="${runner_fb_score:-0}"

    # Store detailed breakdown for each slot winner and runner-up delta
    for slot in opus sonnet haiku fallback; do
        local winner_idx="${SLOT_WINNER[$slot]:--1}"
        [[ $winner_idx -eq -1 ]] && continue

        local breakdown
        breakdown=$(calculate_score_breakdown "$winner_idx" "${slot^}")

        # Parse breakdown: total|swe|stab|lat|nim|avgms
        local total swe_contrib stab_contrib lat_contrib nim_contrib avgms
        total="${breakdown%%|*}"; breakdown="${breakdown#*|}"
        swe_contrib="${breakdown%%|*}"; breakdown="${breakdown#*|}"
        stab_contrib="${breakdown%%|*}"; breakdown="${breakdown#*|}"
        lat_contrib="${breakdown%%|*}"; breakdown="${breakdown#*|}"
        nim_contrib="${breakdown%%|*}"
        avgms="${breakdown##*|}"

        SLOT_SWE[$slot]="$swe_contrib"
        SLOT_STAB[$slot]="$stab_contrib"
        SLOT_LAT[$slot]="$lat_contrib"
        SLOT_NIM[$slot]="$nim_contrib"
        SLOT_AVGMS[$slot]="$avgms"
        SLOT_VERDICT[$slot]="${MODEL_DATA_VERDICT[$winner_idx]:-Unknown}"

        # Calculate runner-up delta
        local winner_total="$total"
        local runner_score="${SLOT_RUNNERUP_SCORE[$slot]:-0}"

        if [[ "$winner_total" == *.* ]]; then
            winner_total="${winner_total%%.*}"
        fi
        if [[ "$runner_score" == *.* ]]; then
            runner_score="${runner_score%%.*}"
        fi

        local delta=$(( winner_total - runner_score ))
        SLOT_RUNNERUP_DELTA[$slot]="$delta"
    done
}

# ============================================================
# OUTPUT
# ============================================================
print_score_breakdown() {
    echo ""
    log_banner "MODEL SELECTION"
    echo ""

    # Detailed header with verdict, latency, and runner-up
    printf " %-10s | %-38s | %6s | %-7s | %6s | %-20s\n" "SLOT" "MODEL" "SCORE" "VERDICT" "LAT(ms)" "Runner-up"
    echo "$(printf '=%.0s' {1..95})"

    for slot in opus sonnet haiku fallback; do
        local idx="${SLOT_WINNER[$slot]:--1}"
        [[ $idx -eq -1 ]] && continue

        local provider="${MODEL_DATA_PROVIDER[$idx]}"
        local modelid="${MODEL_DATA_MODELID[$idx]}"
        local prefix
        prefix=$(get_model_prefix "$provider" "$modelid")
        local score="${SLOT_SCORE[$slot]:-0}"
        local verdict="${SLOT_VERDICT[$slot]:-Unknown}"
        local avgms="${SLOT_AVGMS[$slot]:-0}"

        # Build runner-up info
        local runner_idx="${SLOT_RUNNERUP[$slot]:--1}"
        local runner_info="none"
        if [[ "$runner_idx" != "$idx" && -n "${MODEL_DATA_MODELID[$runner_idx]:-}" ]]; then
            local runner_model="${MODEL_DATA_MODELID[$runner_idx]}"
            local delta="${SLOT_RUNNERUP_DELTA[$slot]:-0}"
            runner_info="${runner_model} (Δ-${delta})"
        fi

        printf " %-10s | %-38s | %6.1f | %-7s | %6.0f | %-20s\n" "${slot^^}" "${prefix:0:38}" "$score" "$verdict" "${avgms%%.*}" "$runner_info"
    done

    echo ""
    log_banner "SCORE BREAKDOWN"
    echo ""
    printf " %-10s | %6s | %6s | %6s | %6s | %6s\n" "SLOT" "SWE" "STAB" "LAT" "NIM" "TOTAL"
    echo "$(printf '=%.0s' {1..56})"

    for slot in opus sonnet haiku fallback; do
        local idx="${SLOT_WINNER[$slot]:--1}"
        [[ $idx -eq -1 ]] && continue

        local swe="${SLOT_SWE[$slot]:-0}"
        local stab="${SLOT_STAB[$slot]:-0}"
        local lat="${SLOT_LAT[$slot]:-0}"
        local nim="${SLOT_NIM[$slot]:-0}"
        local total="${SLOT_SCORE[$slot]:-0}"

        printf " %-10s | %6.1f | %6.1f | %6.1f | %6.1f | %6.1f\n" "${slot^^}" "$swe" "$stab" "$lat" "$nim" "$total"
    done
    echo ""
}

# Write model-candidates.json with top-3 per slot
write_candidates_json() {
    local model_count="$1"
    shift

    local json="{"
    local first_slot=true

    for slot in opus sonnet haiku fallback; do
        [[ "$first_slot" == "false" ]] && json="${json},"
        first_slot=false

        local scores_array
        case "$slot" in
            opus) scores_array=(${ALL_OPUS_SCORES[@]}) ;;
            sonnet) scores_array=(${ALL_SONNET_SCORES[@]}) ;;
            haiku) scores_array=(${ALL_HAIKU_SCORES[@]}) ;;
            fallback) scores_array=(${ALL_FALLBACK_SCORES[@]}) ;;
        esac

        # Sort by score (descending) using temp file
        local temp_sort="/tmp/candidates_${slot}_$$.txt"
        : > "$temp_sort" 2>/dev/null || temp_sort=""

        for item in "${scores_array[@]}"; do
            local score="${item#*|}"
            score="${score%%|*}"
            echo "$score|$item"
        done | sort -t'|' -k1 -nr > "$temp_sort"

        local json_array="["
        local first_item=true
        local count=0

        while IFS='|' read -r _ idx total swe stab lat nim avgms; do
            [[ $count -ge 3 ]] && break
            [[ -z "$idx" ]] && continue

            [[ "$first_item" == "false" ]] && json_array="${json_array},"
            first_item=false

            local provider="${MODEL_DATA_PROVIDER[$idx]}"
            local modelid="${MODEL_DATA_MODELID[$idx]}"
            local verdict="${MODEL_DATA_VERDICT[$idx]:-Unknown}"
            local prefix
            prefix=$(get_model_prefix "$provider" "$modelid")

            json_array="${json_array}{\"idx\":$idx,\"model\":\"$modelid\",\"prefix\":\"$prefix\",\"score\":$total,\"verdict\":\"$verdict\",\"avgms\":${avgms:-0},\"swe\":$swe,\"stability\":$(awk "BEGIN{print int($stab/0.3)}")}"

            count=$((count + 1))
        done < "$temp_sort"

        [[ -n "$temp_sort" ]] && [[ -f "$temp_sort" ]] && rm -f "$temp_sort"

        json_array="${json_array}]"
        json="${json}\"${slot}\":${json_array}"
    done

    json="${json}}"

    # Write to file
    echo "$json" > "$CANDIDATES_FILE"
    log_info "Candidates written to $CANDIDATES_FILE"
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
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && dry_run=true;
    done

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
    write_candidates_json "$model_count" || true  # Non-fatal
    write_env_file "$dry_run"

    # Cleanup
    [[ -n "${NVIDIA_API_KEY:-}" ]] && unset NVIDIA_API_KEY
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && unset OPENROUTER_API_KEY
}

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
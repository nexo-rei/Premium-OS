#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: core/utils.sh
# Logging, color output, prompts, JSON helpers, misc utilities.
#==============================================================================

[[ -n "${_POS_CORE_UTILS_LOADED:-}" ]] && return 0
_POS_CORE_UTILS_LOADED=1

#----------------------------------------
# Colors — giardati from ui/colors.sh when sourced; fall-back definitions
#----------------------------------------
[[ -z "${POS_RESET:-}" ]] && {
    POS_RESET='\033[0m'
    POS_BOLD='\033[1m'
    POS_DIM='\033[2m'
    POS_ITALIC='\033[3m'
    POS_UNDERLINE='\033[4m'
    POS_CYAN='\033[38;5;51m'
    POS_GREEN='\033[38;5;46m'
    POS_YELLOW='\033[38;5;226m'
    POS_PINK='\033[38;5;198m'
    POS_RED='\033[38;5;196m'
    POS_GRAY='\033[38;5;245m'
    POS_WHITE='\033[38;5;255m'
    POS_PURPLE='\033[38;5;141m'
}

#----------------------------------------
# Logging
#----------------------------------------
pos_log()   { printf '%b\n' "${POS_CYAN}[POS]${POS_RESET} $*"; }
pos_ok()    { printf '%b\n' "${POS_GREEN}✔${POS_RESET} $*"; }
pos_warn()  { printf '%b\n' "${POS_YELLOW}⚠${POS_RESET} $*" >&2; }
pos_error() { printf '%b\n' "${POS_PINK}✖${POS_RESET} $*" >&2; }
pos_debug() { [[ "${POS_DEBUG:-0}" == "1" ]] && printf '%b\n' "${POS_GRAY}[debug]${POS_RESET} $*"; }

#----------------------------------------
# Prompts
# pos_prompt <label> [default]
#----------------------------------------
pos_prompt() {
    local label="$1" default="${2:-}" input
    if [[ -n "$default" ]]; then
        printf '%b' "${POS_YELLOW}$label${POS_RESET} ${POS_GRAY}[$default]${POS_RESET} "
    else
        printf '%b' "${POS_YELLOW}$label${POS_RESET} "
    fi
    read -r input
    echo "${input:-$default}"
}

# pos_confirm <question> → 0 yes / 1 no
pos_confirm() {
    local reply
    printf '%b' "${POS_YELLOW}$1${POS_RESET} ${POS_GRAY}(y/N)${POS_RESET} "
    read -rn 1 reply; printf '\n'
    [[ "${reply,,}" == "y" ]]
}

#----------------------------------------
# Input validation — prevent command injection in file/name inputs
#----------------------------------------
pos_is_safe_name() {
    local name="$1"
    [[ -n "$name" ]] && [[ ${#name} -le 64 ]] && [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

pos_is_hex_color() {
    [[ "$1" =~ ^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$ ]]
}

#----------------------------------------
# HEX ↔ RGB conversion
#----------------------------------------
pos_hex_to_rgb() {
    local hex="${1#\#}"
    [[ ${#hex} -eq 3 ]] && hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"
    printf '%d %d %d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

pos_rgb_to_hex() {
    printf '#%02X%02X%02X' "$1" "$2" "$3"
}

#----------------------------------------
# JSON helpers — jq when available, minimal pure-bash fallback
#----------------------------------------
pos_has_jq() { command -v jq >/dev/null 2>&1; }

# pos_json_get <file> <key.path> → prints value (empty on miss)
pos_json_get() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 1
    if pos_has_jq; then
        jq -r ".$key // empty" "$file" 2>/dev/null
    else
        # Fallback: extract top-level scalar "key": "value" pairs
        local leaf="${key##*.}"
        grep -o "\"$leaf\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" | head -1 \
            | sed -e 's/^[^:]*:[[:space:]]*"//' -e 's/"$//'
    fi
}

# pos_json_set <file> <key.path> <value> [number|bool]
pos_json_set() {
    local file="$1" key="$2" value="$3" type="${4:-string}"
    [[ -f "$file" ]] || return 1
    if pos_has_jq; then
        local tmp="${file}.pos_tmp"
        case "$type" in
            number) jq --arg v "$value" ".$key = (\$v|tonumber)" "$file" >"$tmp" ;;
            bool)   jq --arg v "$value" ".$key = (\$v==\"true\")"  "$file" >"$tmp" ;;
            *)      jq --arg v "$value" ".$key = \$v"              "$file" >"$tmp" ;;
        esac && mv "$tmp" "$file"
    else
        pos_warn "jq not available — cannot set $key in ${file##*/}"
        return 1
    fi
}

#----------------------------------------
# Misc
#----------------------------------------
pos_press_enter() {
    printf '%b' "${POS_GRAY}Press Enter to continue…${POS_RESET}"
    read -rn 1 _; printf '\n'
}

pos_timestamp() { date +%Y-%m-%d-%H-%M-%S; }

pos_elapsed_ms() { # $1=start_epoch_ns → ms
    local now
    now=$(date +%s%N 2>/dev/null) || { echo "0"; return; }
    echo $(( (now - $1) / 1000000 ))
}

pos_human_size() { # bytes → human readable
    local b="${1:-0}"
    if   (( b >= 1048576 )); then awk -v b="$b" 'BEGIN{printf "%.1fMB", b/1048576}'
    elif (( b >= 1024 ));    then awk -v b="$b" 'BEGIN{printf "%.1fKB", b/1024}'
    else                          echo "${b}B"; fi
}

pos_dir_size_bytes() {
    local d="$1"
    [[ -d "$d" ]] || { echo 0; return; }
    if command -v du >/dev/null 2>&1; then
        du -sb "$d" 2>/dev/null | awk '{print $1+0}' || echo 0
    else
        echo 0
    fi
}

pos_sha256() {
    local f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" | awk '{print $1}'
    else
        echo "unavailable"
    fi
}

# Debug-safe clear that keeps buffer when TERM lacks it
pos_clear() { command clear 2>/dev/null || printf '\033[2J\033[H'; }

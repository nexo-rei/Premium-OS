#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: ui/animations.sh
# Terminal animations: fades, slides, spinners, progress bars, glow pulses.
# All functions degrade gracefully when animations are disabled or stdout
# is not a TTY.
#==============================================================================

[[ -n "${_POS_UI_ANIM_LOADED:-}" ]] && return 0
_POS_UI_ANIM_LOADED=1

#----------------------------------------
# Gate: animations enabled?
#----------------------------------------
pos_anim_enabled() {
    [[ "${POS_ANIM_DISABLE:-0}" == "1" ]] && return 1
    [[ -t 1 ]] || return 1
    local a="true"
    if declare -f pos_config_get >/dev/null 2>&1; then
        a=$(pos_config_get ui.animations "true")
    fi
    [[ "$a" == "true" ]]
}

_pos_sleep_frac() { # fractional-sleep with fallbacks
    local sec="$1"
    sleep "$sec" 2>/dev/null || sleep 1
}

#----------------------------------------
# Spinner — runs while a command executes
# pos_spinner <pid> <label>
#----------------------------------------
pos_spinner() {
    local pid="$1" label="${2:-Working}"
    pos_anim_enabled || { wait "$pid"; return $?; }
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0
    # ASCII fallback for terminals without braille glyphs
    [[ "${POS_ASCII_SPINNER:-0}" == "1" ]] && frames=('-' '\' '|' '/')
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%b%s%b %s' "$POS_CYAN" "${frames[$((i % ${#frames[@]}))]}" "$POS_RESET" "$label"
        i=$((i+1)); _pos_sleep_frac 0.08
    done
    printf '\r\033[K'
    tput cnorm 2>/dev/null
    wait "$pid"
    return $?
}

#----------------------------------------
# Progress bar
# pos_progress <pct> <label> [width]
#----------------------------------------
pos_progress() {
    local pct="$1" label="${2:-}" width="${3:-30}"
    (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
    local fill=$(( pct * width / 100 )) empty=$(( width - fill ))
    local bar="" pad=""
    while (( fill-- > 0 ));  do bar+="█"; done
    while (( empty-- > 0 )); do pad+="░"; done
    # Color: gradient green @100, yellow @50, red <30
    local color="$POS_GREEN"
    (( pct < 50 )) && color="$POS_YELLOW"
    (( pct < 30 )) && color="$POS_PINK"
    printf '\r%b%s%s%b %3d%% %s' "$color" "$bar" "$pad" "$POS_RESET" "$pct" "$label"
    (( pct >= 100 )) && printf '\n'
}

# Animated 0→100 demo progress with real callback timing
# pos_progress_run <label> <command...>
pos_progress_run() {
    local label="$1"; shift
    ( "$@" ) & local pid=$!
    local pct=0
    while kill -0 "$pid" 2>/dev/null; do
        (( pct < 95 )) && pct=$((pct + 3 + RANDOM % 5))
        pos_progress "$pct" "$label"
        _pos_sleep_frac 0.05
    done
    wait "$pid"; local rc=$?
    (( rc == 0 )) && pos_progress 100 "$label"
    return $rc
}

#----------------------------------------
# Typewriter fade-in for a line of text
#----------------------------------------
pos_typewrite() { # $1=text [delay]
    local text="$1" delay="${2:-0.015}" i
    if ! pos_anim_enabled; then printf '%s\n' "$text"; return; fi
    for (( i=0; i<${#text}; i++ )); do
        printf '%b%s%b' "$POS_CYAN" "${text:i:1}" "$POS_RESET"
        _pos_sleep_frac "$delay"
    done
    printf '\n'
}

#----------------------------------------
# Fade-in block: lines appear with rising intensity
#----------------------------------------
pos_fade_in() { # reads stdin, fades each line in
    pos_anim_enabled || { cat; return; }
    local line shades=('\033[38;5;236m' '\033[38;5;241m' '\033[38;5;246m' '\033[38;5;251m' '\033[38;5;255m')
    local lcount=0
    while IFS= read -r line; do
        local shade="${shades[$(( lcount < 4 ? lcount : 4 ))]}"
        printf '%b%s%b\n' "$shade" "$line" "$POS_RESET"
        lcount=$((lcount+1))
        _pos_sleep_frac 0.03
    done
}

#----------------------------------------
# Slide-in text from the left
#----------------------------------------
pos_slide_in() { # $1=text [max_indent]
    local text="$1" max="${2:-20}" i
    if ! pos_anim_enabled; then printf '%s\n' "$text"; return; fi
    for (( i=max; i>=0; i-=2 )); do
        printf '\r\033[K%*s%s' "$i" "" "$text"
        _pos_sleep_frac 0.02
    done
    printf '\n'
}

#----------------------------------------
# Glow pulse — for hero banners
#----------------------------------------
pos_glow_pulse() { # $1=text [cycles]
    local text="$1" cycles="${2:-3}" i
    if ! pos_anim_enabled; then printf '%s\n' "$text"; return; fi
    for (( i=0; i<cycles; i++ )); do
        printf '\r%b%b%s%b' "$POS_CYAN" "$POS_BOLD" "$text" "$POS_RESET"
        _pos_sleep_frac 0.20
        printf '\r%b%s%b' "$POS_DIM" "$text" "$POS_RESET"
        _pos_sleep_frac 0.20
    done
    printf '\r%b%b%s%b\n' "$POS_CYAN" "$POS_BOLD" "$text" "$POS_RESET"
}

#----------------------------------------
# Section transition between menu screens
#----------------------------------------
pos_transition() {
    pos_anim_enabled || return 0
    printf '▓'; _pos_sleep_frac 0.01
    printf '▒°'; _pos_sleep_frac 0.01
    printf ' ·'
    printf '\r\033[K'
}

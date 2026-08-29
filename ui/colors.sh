#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: ui/colors.sh
# ANSI color & style definitions matching the PRD design system.
#==============================================================================

[[ -n "${_POS_UI_COLORS_LOADED:-}" ]] && return 0
_POS_UI_COLORS_LOADED=1

#----------------------------------------
# Style attributes
#----------------------------------------
POS_RESET='\033[0m'
POS_BOLD='\033[1m'
POS_DIM='\033[2m'
POS_ITALIC='\033[3m'
POS_UNDERLINE='\033[4m'
POS_BLINK='\033[5m'
POS_REVERSE='\033[7m'
POS_HIDDEN='\033[8m'

#----------------------------------------
# PRD color palette (true-color escapes with 256 fallback)
#   Accent  #00D9FF  → cyan
#   Success #00FF41  → green
#   Warning #FFD700  → gold
#   Danger  #FF006E  → hot pink
#----------------------------------------
pos_supports_truecolor() {
    case "${COLORTERM:-}" in truecolor|24bit) return 0;; esac
    [[ "${TERM:-}" == *direct* ]] && return 0
    return 1
}

if pos_supports_truecolor; then
    POS_CYAN='\033[38;2;0;217;255m'
    POS_GREEN='\033[38;2;0;255;65m'
    POS_YELLOW='\033[38;2;255;215;0m'
    POS_PINK='\033[38;2;255;0;110m'
    POS_WHITE='\033[38;2;255;255;255m'
    POS_BLACK='\033[38;2;26;26;26m'
    POS_GRAY='\033[38;2;140;140;150m'
    POS_PURPLE='\033[38;2;160;120;255m'
    POS_BLUE='\033[38;2;80;140;255m'
    POS_ORANGE='\033[38;2;255;160;60m'
    POS_BG='\033[48;2;10;14;39m'
else
    POS_CYAN='\033[38;5;51m'
    POS_GREEN='\033[38;5;46m'
    POS_YELLOW='\033[38;5;226m'
    POS_PINK='\033[38;5;198m'
    POS_WHITE='\033[38;5;255m'
    POS_BLACK='\033[38;5;235m'
    POS_GRAY='\033[38;5;245m'
    POS_PURPLE='\033[38;5;141m'
    POS_BLUE='\033[38;5;69m'
    POS_ORANGE='\033[38;5;214m'
    POS_BG='\033[48;5;235m'
fi

POS_RED='\033[38;5;196m'
POS_MAGENTA='\033[38;5;201m'

#----------------------------------------
# Style combinators
#----------------------------------------
pos_title()  { printf '%b%b%b' "$POS_CYAN" "$POS_BOLD" "$*"; printf '%b\n' "$POS_RESET"; }
pos_key()    { printf '%b%b' "$POS_YELLOW" "$POS_BOLD"; }
pos_dim_text(){ printf '%b%b%b' "$POS_GRAY" "$*" "$POS_RESET"; }

# Gradient banner across RGB stops (approximation of PRD neon gradient)
pos_gradient_text() { # $1=text — cycles cyan→pink→green palette
    local text="$1" i ch colors=(
        '\033[38;2;0;217;255m'   # cyan
        '\033[38;2;90;140;255m'  # blue
        '\033[38;2;178;75;243m'  # violet
        '\033[38;2;255;0;110m'   # pink
        '\033[38;2;255;120;110m' # coral
        '\033[38;2;0;255;65m'    # green
    )
    local n=${#colors[@]} idx=0
    for (( i=0; i<${#text}; i++ )); do
        ch="${text:i:1}"
        if [[ "$ch" == " " ]]; then printf ' '; else
            idx=$(( (i * n) / ${#text} ))
            printf '%b%s' "${colors[$idx]}" "$ch"
        fi
    done
    printf '%b\n' "$POS_RESET"
}

#----------------------------------------
# Swatch helper used by previews
#----------------------------------------
pos_color_block() { # $1=hex
    local rgb r g b
    rgb=$(pos_hex_to_rgb "$1" 2>/dev/null) || return 1
    read -r r g b <<<"$rgb"
    printf '\033[48;2;%d;%d;%dm    \033[0m' "$r" "$g" "$b"
}

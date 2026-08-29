#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: ui/responsive.sh
# Adaptive UI based on terminal size.
# Breakpoints: mobile <60 cols, tablet 60-100, desktop >100.
#==============================================================================

[[ -n "${_POS_UI_RESP_LOADED:-}" ]] && return 0
_POS_UI_RESP_LOADED=1

#----------------------------------------
# Size detection
#----------------------------------------
detect_terminal_size() { # echoes "WIDTH HEIGHT"
    local w h
    w=$(tput cols 2>/dev/null); h=$(tput lines 2>/dev/null)
    echo "${w:-80} ${h:-24}"
}

terminal_width()  { detect_terminal_size | awk '{print $1}'; }
terminal_height() { detect_terminal_size | awk '{print $2}'; }

get_responsive_layout() { # echoes mobile|tablet|desktop
    local w; w=$(terminal_width)
    if   (( w < 60 ));  then echo "mobile"
    elif (( w <= 100 )); then echo "tablet"
    else echo "desktop"; fi
}

detect_orientation() {
    local w h; read -r w h <<<"$(detect_terminal_size)"
    (( w > h )) && echo "landscape" || echo "portrait"
}

# Window resize trap support — call handle_window_resize to relayout
_POS_RESIZE_CALLBACK=""
handle_window_resize() {
    if [[ -n "$_POS_RESIZE_CALLBACK" ]]; then "$_POS_RESIZE_CALLBACK"; fi
}
trap 'handle_window_resize' WINCH 2>/dev/null || true

pos_on_resize() { _POS_RESIZE_CALLBACK="$1"; }

#----------------------------------------
# Responsive primitives
#----------------------------------------
render_button() { # $1=label [hotkey]
    local label="$1" key="${2:-}" layout; layout=$(get_responsive_layout)
    local w; w=$(terminal_width)
    local bw=$(( w < 44 ? w - 4 : (layout == "desktop" ? 40 : w - 8) ))
    local pad=$(( (bw - ${#label} - ${#key} - 4) > 0 ? (bw - ${#label} - ${#key} - 4) : 1 ))
    if [[ -n "$key" ]]; then
        printf '  %b[%s]%b %s%*s\n' "$POS_YELLOW" "$key" "$POS_RESET" "$label" "$pad" ""
    else
        printf '  %b▸%b %s%*s\n' "$POS_CYAN" "$POS_RESET" "$label" "$pad" ""
    fi
}

responsive_hr() {
    local w; w=$(terminal_width)
    (( w > 100 )) && w=100
    printf '%b' "$POS_GRAY"
    printf '%.0s─' $(seq 1 $(( w - 2 ))) 2>/dev/null
    printf '%b\n' "$POS_RESET"
}

# render_list <item...> — one per line (mobile) or columns (desktop)
render_list() {
    local layout; layout=$(get_responsive_layout)
    local w; w=$(terminal_width)
    local items=("$@")
    if [[ "$layout" == "mobile" ]] || (( ${#items[@]} <= 2 )); then
        local it n=0
        for it in "${items[@]}"; do
            printf '  %b%s%b %s\n' "$POS_CYAN" "$((++n))." "$POS_RESET" "$it"
        done
    else
        # Two-column compact list
        local i half=$(( (${#items[@]} + 1) / 2 )) colw=$(( w / 2 - 4 ))
        for (( i=0; i<half; i++ )); do
            local left="${items[$i]}" right="${items[$((i+half))]:-}"
            printf '  %b%s%b %-*s' "$POS_CYAN" "$((i+1))." "$POS_RESET" "$colw" "$left"
            [[ -n "$right" ]] && printf '  %b%s%b %s' "$POS_CYAN" "$((i+half+1))." "$POS_RESET" "$right"
            printf '\n'
        done
    fi
}

# render_grid <cols_ideal> <item...>
render_grid() {
    local ideal="$1"; shift
    local items=("$@")
    local w; w=$(terminal_width)
    local cols=$ideal
    local layout; layout=$(get_responsive_layout)
    [[ "$layout" == "mobile" ]] && cols=1
    [[ "$layout" == "tablet" && $cols -gt 2 ]] && cols=2
    local per=$cols n=${#items[@]} i j colw=$(( w / cols - 4 ))
    (( colw < 10 )) && colw=10
    for (( i=0; i<n; i+=per )); do
        local line=""
        for (( j=0; j<per && i+j<n; j++ )); do
            printf -v cell '%-*s' "$colw" "${items[$((i+j))]}"
            line+="  $cell"
        done
        printf '%s\n' "$line"
    done
}

#----------------------------------------
# Alert / confirm / input dialogs
#----------------------------------------
responsive_alert() { # $1=title $2=body
    local title="$1" body="$2"
    echo -e "  ${POS_YELLOW}${POS_BOLD}! ${title}${POS_RESET}"
    [[ -n "$body" ]] && echo -e "    ${POS_GRAY}${body}${POS_RESET}"
}

responsive_input() { # $1=label $2=varname [default]
    local label="$1" var="$2" def="${3:-}" val
    val=$(pos_prompt "$label" "$def" 2>/dev/null) || val=$(read -r v && echo "$v")
    printf -v "$var" '%s' "$val"
}

# Key reading with graceful fallback (tap simulation)
pos_read_key() { # echoes the single key pressed
    local k
    IFS= read -rsn 1 k
    echo "$k"
}

# Numeric keypad / number menu selection helper
pos_select() { # $1=prompt → echoes selection string (prompt goes to tty)
    local sel
    printf '%b' "${POS_YELLOW}$1${POS_RESET} " > /dev/tty 2>/dev/null || printf '%b' "${POS_YELLOW}$1${POS_RESET} " >&2
    read -r sel
    echo "$sel"
}

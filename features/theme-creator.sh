#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/theme-creator.sh
# Visual theme creator — interactive color picker, font selection,
# live preview, color-harmony suggestions, JSON export.
#==============================================================================

[[ -n "${_POS_FEAT_THEMECREATOR_LOADED:-}" ]] && return 0
_POS_FEAT_THEMECREATOR_LOADED=1

# Draft working theme (session state)
declare -A TC_DRAFT=(
    [primary]="#00D9FF" [secondary]="#FF006E" [accent]="#00FF41"
    [background]="#0A0E27" [foreground]="#FFFFFF"
    [warning]="#FFD700" [danger]="#FF006E"
    [font]="Fira Code" [font_size]="14" [gradient]="linear"
)

TC_FONTS=("Fira Code" "JetBrains Mono" "FiraCode Nerd" "Hack" "Ubuntu Mono"
          "Source Code Pro" "Cascadia Code" "DejaVu Sans Mono" "Inconsolata"
          "Roboto Mono" "Victor Mono" "IBM Plex Mono" "Space Mono"
          "Anonymous Pro" "Courier Prime")

#----------------------------------------
# get_color_input <label> — HEX or "R,G,B"; echoes normalized HEX
#----------------------------------------
get_color_input() {
    local label="$1" input
    input=$(pos_prompt "$label (HEX #RRGGBB or R,G,B)")
    if pos_is_hex_color "$input"; then
        echo "$input"; return 0
    fi
    if [[ "$input" =~ ^[0-9]{1,3},[0-9]{1,3},[0-9]{1,3}$ ]]; then
        local r g b; IFS=',' read -r r g b <<<"$input"
        (( r<=255 && g<=255 && b<=255 )) && { pos_rgb_to_hex "$r" "$g" "$b"; return 0; }
    fi
    return 1
}

#----------------------------------------
# display_color_picker <key> — palette grid + custom entry
#----------------------------------------
display_color_picker() {
    local key="$1"
    echo -e "\n  ${POS_BOLD}Pick ${key}${POS_RESET} ${POS_GRAY}(current ${TC_DRAFT[$key]})${POS_RESET}"
    local presets=("#00D9FF" "#FF006E" "#00FF41" "#FFD700" "#6272A4" "#BD93F9"
                   "#50FA7B" "#FF79C6" "#8BE9FD" "#F1FA8C" "#FF5555" "#0A0E27"
                   "#1A1A2E" "#16213E" "#282A36" "#44475A" "#FFFFFF" "#F8F8F2")
    local i c
    for i in "${!presets[@]}"; do
        printf '  %b%2d%b ' "$POS_CYAN" "$((i+1))" "$POS_RESET"
        pos_color_block "${presets[$i]}" 2>/dev/null || printf '    '
        printf ' %s' "${presets[$i]}"
        (( (i+1) % 3 == 0 )) && printf '\n'
    done
    printf '\n'
    local choice; choice=$(pos_prompt "Number or custom value")
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#presets[@]} )); then
        TC_DRAFT[$key]="${presets[$((choice-1))]}"
    elif [[ -n "$choice" ]]; then
        local v
        if pos_is_hex_color "$choice"; then TC_DRAFT[$key]="$choice"
        elif v=$(get_color_input "$key" 2>/dev/null); then TC_DRAFT[$key]="$v"
        else pos_warn "Invalid color — keeping ${TC_DRAFT[$key]}"; fi
    fi
    suggest_color_harmony "$key"
}

#----------------------------------------
# suggest_color_harmony <key> — rotating hue ≈ complementary/analogous.
# Approximates via channel rotation in RGB space.
#----------------------------------------
suggest_color_harmony() {
    local key="$1" hex r g b
    hex="${TC_DRAFT[$key]}"
    read -r r g b <<<"$(pos_hex_to_rgb "$hex" 2>/dev/null)" || return 0
    local comp; comp=$(pos_rgb_to_hex $((255-r)) $((255-b)) $((255-g)))
    local an1;  an1=$(pos_rgb_to_hex "$g" "$b" "$r")   # rotate channels
    local an2;  an2=$(pos_rgb_to_hex "$b" "$r" "$g")
    echo -e "  ${POS_GRAY}harmony → complementary:${POS_RESET} $comp  ${POS_GRAY}analogous:${POS_RESET} $an1, $an2"
    echo -n "  swap: "; pos_color_block "$comp" 2>/dev/null; echo -n " "
    pos_color_block "$an1" 2>/dev/null; echo -n " "; pos_color_block "$an2" 2>/dev/null; echo
}

#----------------------------------------
# theme_preview — renders the draft as a living terminal mock
#----------------------------------------
tc_preview() {
    echo
    local p s a bg fg
    p="${TC_DRAFT[primary]}"; s="${TC_DRAFT[secondary]}"; a="${TC_DRAFT[accent]}"
    bg="${TC_DRAFT[background]}"; fg="${TC_DRAFT[foreground]}"
    local pr pg pb sr sg sb ar ag ab br bgc bb fr fgc fb
    read -r pr pg pb <<<"$(pos_hex_to_rgb "$p")"; read -r sr sg sb <<<"$(pos_hex_to_rgb "$s")"
    read -r ar ag ab <<<"$(pos_hex_to_rgb "$a")"; read -r br bgc bb <<<"$(pos_hex_to_rgb "$bg")"
    read -r fr fgc fb <<<"$(pos_hex_to_rgb "$fg")"
    local P=$'\033'"[38;2;${pr};${pg};${pb}m" S=$'\033'"[38;2;${sr};${sg};${sb}m"
    local A=$'\033'"[38;2;${ar};${ag};${ab}m" F=$'\033'"[38;2;${fr};${fgc};${fb}m"
    local B=$'\033'"[48;2;${br};${bgc};${bb}m" R=$'\033'"[0m"
    cat <<PREVIEW
  ${B}${P}┌──────────────────────────────────────┐${R}
  ${B}${P}│${A}  ◢◤ Premium-OS ${F}· theme preview     ${P}│${R}
  ${B}${P}├──────────────────────────────────────┤${R}
  ${B}${F}  user@termux ${P}❯${F} ls -la               ${P}│${R}
  ${B}${S}  drwxr-x--  Documents   ${A}✔ clean    ${P}│${R}
  ${B}${S}  drwxr-x--  Downloads   ${P}⋯ 2.1 GB   ${P}│${R}
  ${B}${F}  user@termux ${P}❯${F} git status           ${P}│${R}
  ${B}${A}  ✔ branch: main ${F}· ${S}3 files staged  ${P}│${R}
  ${B}${P}└──────────────────────────────────────┘${R}
  ${F}font: ${A}${TC_DRAFT[font]} ${TC_DRAFT[font_size]}px${F} · gradient: ${A}${TC_DRAFT[gradient]}${R}
PREVIEW
}

#----------------------------------------
# _tc_choose_font
#----------------------------------------
_tc_choose_font() {
    echo -e "\n  ${POS_BOLD}Fonts${POS_RESET}"
    local i
    for i in "${!TC_FONTS[@]}"; do
        printf '  %b%2d%b %-20s' "$POS_CYAN" "$((i+1))" "$POS_RESET" "${TC_FONTS[$i]}"
        (( (i+1) % 3 == 0 )) && printf '\n'
    done
    printf '\n'
    local c; c=$(pos_prompt "Font number" "1")
    if [[ "$c" =~ ^[0-9]+$ ]] && (( c>=1 && c<=${#TC_FONTS[@]} )); then
        TC_DRAFT[font]="${TC_FONTS[$((c-1))]}"
        pos_ok "Font → ${TC_DRAFT[font]}"
    fi
    local sz; sz=$(pos_prompt "Font size (8-28)" "14")
    [[ "$sz" =~ ^[0-9]+$ ]] && (( sz>=8 && sz<=28 )) && TC_DRAFT[font_size]="$sz"
}

#----------------------------------------
# save_custom_theme <name>
#----------------------------------------
save_custom_theme() {
    local name="$1"
    pos_is_safe_name "$name" || { pos_error "Invalid name."; return 1; }
    mkdir -p "$POS_USER_THEMES_DIR" 2>/dev/null
    local f="$POS_USER_THEMES_DIR/$name.json"
    cat > "$f" <<JSON
{
  "name": "$name",
  "author": "${USER:-premium}",
  "colors": {
    "primary": "${TC_DRAFT[primary]}",
    "secondary": "${TC_DRAFT[secondary]}",
    "accent": "${TC_DRAFT[accent]}",
    "background": "${TC_DRAFT[background]}",
    "foreground": "${TC_DRAFT[foreground]}",
    "warning": "${TC_DRAFT[warning]}",
    "danger": "${TC_DRAFT[danger]}"
  },
  "font": {"family": "${TC_DRAFT[font]}", "size": ${TC_DRAFT[font_size]}},
  "gradient": "${TC_DRAFT[gradient]}",
  "border": {"width": 1, "style": "solid", "radius": 8, "glow": true},
  "blur": {"enabled": true, "amount": 10},
  "emoji": true
}
JSON
    chmod 600 "$f"
    pos_ok "Saved '$name' → $f"
}

#----------------------------------------
# export_theme_code — copy-ready snippet
#----------------------------------------
export_theme_code() {
    cat <<CODE

  # ${POS_DRAFT_NAME:-custom} theme for Premium-OS
  POS_PRIMARY="${TC_DRAFT[primary]}"
  POS_SECONDARY="${TC_DRAFT[secondary]}"
  POS_ACCENT="${TC_DRAFT[accent]}"
  POS_BG="${TC_DRAFT[background]}"
  POS_FG="${TC_DRAFT[foreground]}"

CODE
    pos_ok "Code generated above — copy it to share."
}

#----------------------------------------
# theme_creator_ui — main interactive loop
#----------------------------------------
theme_creator_ui() {
    local c
    while true; do
        _menu_header "🎨 Visual Theme Creator" ""
        tc_preview
        printf ' %b1%b Primary      %b2%b Secondary    %b3%b Accent\n' "$POS_CYAN" "$POS_RESET" "$POS_CYAN" "$POS_RESET" "$POS_CYAN" "$POS_RESET"
        printf ' %b4%b Background   %b5%b Foreground   %b6%b Fonts\n' "$POS_CYAN" "$POS_RESET" "$POS_CYAN" "$POS_RESET" "$POS_CYAN" "$POS_RESET"
        printf ' %b7%b Gradient     %b8%b Save theme   %b9%b Export code\n' "$POS_CYAN" "$POS_RESET" "$POS_CYAN" "$POS_RESET" "$POS_CYAN" "$POS_RESET"
        printf ' %ba%b Apply now    %b0%b Back\n' "$POS_CYAN" "$POS_RESET" "$POS_CYAN" "$POS_RESET"
        c=$(pos_read_key)
        case "$c" in
            1) display_color_picker primary ;;
            2) display_color_picker secondary ;;
            3) display_color_picker accent ;;
            4) display_color_picker background ;;
            5) display_color_picker foreground ;;
            6) _tc_choose_font ;;
            7) local g; g=$(pos_prompt "Gradient: linear / radial / neon" "${TC_DRAFT[gradient]}")
               [[ -n "$g" ]] && TC_DRAFT[gradient]="$g" ;;
            8) local n; n=$(pos_prompt "Save as"); [[ -n "$n" ]] && save_custom_theme "$n" ;;
            9) export_theme_code ;;
            a) local n; n=$(pos_prompt "Save & apply as" "my-theme")
               if save_custom_theme "$n"; then apply_theme "$n"; fi ;;
            0|q) return ;;
        esac
        [[ "$c" =~ ^[19a]$ || "$c" == "8" ]] && pos_press_enter
    done
}

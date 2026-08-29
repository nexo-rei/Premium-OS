#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: ui/menu.sh
# Interactive menu system — responsive, animated, touch-friendly.
# Depends on: core modules, ui/colors.sh, ui/animations.sh, ui/responsive.sh
#==============================================================================

[[ -n "${_POS_UI_MENU_LOADED:-}" ]] && return 0
_POS_UI_MENU_LOADED=1

POS_MENU_HISTORY=()

#----------------------------------------
# Header rendered above every panel
#----------------------------------------
_menu_header() { # $1=title $2=icon
    pos_clear
    local w; w=$(terminal_width)
    local layout; layout=$(get_responsive_layout)
    echo -e " ${POS_CYAN}${POS_BOLD}${2:-◆} ${1:-Menu}${POS_RESET} ${POS_GRAY}· $(date +%H:%M) · ${layout}${POS_RESET}"
    responsive_hr
}

_menu_footer() {
    responsive_hr
    local active; active=$(get_active_profile 2>/dev/null)
    echo -e " ${POS_GRAY}q${POS_RESET}=quit ${POS_GRAY}0${POS_RESET}=back ${POS_GRAY}profile:${POS_CYAN}${active}${POS_RESET}"
}

#----------------------------------------
# Generic selector: prints numbered options, echoes chosen index
# _menu_select <prompt> <opt...> → echoes selection number (1..n) or ""
#----------------------------------------
_menu_select() {
    local prompt="$1"; shift
    local opts=("$@") i
    if [[ "$(get_responsive_layout)" == "mobile" ]]; then
        for i in "${!opts[@]}"; do
            printf ' %b %d %b %s\n' "$POS_PURPLE" "$((i+1))" "$POS_RESET" "${opts[$i]}"
        done
    else
        render_grid 2 "${opts[@]}"
    fi
    printf '%b' "${POS_YELLOW} › ${prompt}:${POS_RESET} "
    read -r sel
    echo "$sel"
}

#----------------------------------------
# Main menu
#----------------------------------------
pos_main_menu() {
    local choice
    while true; do
        _menu_header "Premium-OS" "◢◤"
        cat <<BANNER
 ${POS_CYAN}1${POS_RESET} 🎨 Themes            ${POS_CYAN}7${POS_RESET} 📚 Snippets
 ${POS_CYAN}2${POS_RESET} 🗂  Profiles          ${POS_CYAN}8${POS_RESET} ⌨  Hotkeys
 ${POS_CYAN}3${POS_RESET} ⚡ Performance       ${POS_CYAN}9${POS_RESET} 🚀 Optimizer
 ${POS_CYAN}4${POS_RESET} 💾 Backup & Sync     ${POS_CYAN}10${POS_RESET} 🤖 Smart Suggestions
 ${POS_CYAN}5${POS_RESET} 🧹 Cleanup           ${POS_CYAN}11${POS_RESET} 🧩 Plugins
 ${POS_CYAN}6${POS_RESET} 🌈 Visual FX         ${POS_CYAN}12${POS_RESET} 🌐 Web Dashboard

 ${POS_CYAN}13${POS_RESET} ⚙  Settings          ${POS_CYAN}14${POS_RESET} 🔐 Cyber Lock    ${POS_CYAN}0${POS_RESET} Exit
BANNER
        _menu_footer
        choice=$(pos_read_key)
        case "$choice" in
            1) pos_menu_themes ;;
            2) pos_menu_profiles ;;
            3) pos_menu_performance ;;
            4) pos_menu_backup ;;
            5) pos_menu_cleanup ;;
            6) pos_menu_visualfx ;;
            7) pos_menu_snippets ;;
            8) pos_menu_hotkeys ;;
            9) pos_menu_optimizer ;;
            q|0) echo; pos_ok "Bye."; return 0 ;;
            *)
                # two-digit options (10-14) require a second key
                read -rsn1 -t 0.35 rest 2>/dev/null || rest=""
                case "${choice}${rest}" in
                    10) pos_menu_smart ;;
                    11) pos_menu_plugins ;;
                    12) pos_menu_dashboard ;;
                    13) pos_config_interactive_edit ;;
                    14) pos_menu_cyberlock ;;
                esac ;;
        esac
        pos_transition
    done
}

#----------------------------------------
# 1. Themes
#----------------------------------------
pos_menu_themes() {
    while true; do
        _menu_header "🎨 Themes" ""
        echo -e " ${POS_GRAY}current:${POS_RESET} ${POS_PINK}$(get_current_theme)${POS_RESET}\n"
        theme_preview "$(get_current_theme)" 2>/dev/null
        echo
        local c; c=$(_menu_select "choose" \
            "Apply theme" "Create custom theme" "Visual theme creator" \
            "List all themes" "Export theme" "Back")
        case "$c" in
            1)
                echo -e "\n ${POS_GRAY}Available:${POS_RESET}"
                list_themes | while read -r t; do echo "   • $t"; done
                local t; t=$(pos_prompt "Theme name")
                [[ -n "$t" ]] && apply_theme "$t" && pos_press_enter ;;
            2) create_custom_theme; pos_press_enter ;;
            3) pos_load_feature theme-creator && theme_creator_ui; pos_press_enter ;;
            4) list_themes | while read -r t; do echo "   • $t"; done; pos_press_enter ;;
            5) local t; t=$(pos_prompt "Theme to export"); export_theme "$t"; pos_press_enter ;;
            6|""|q) return ;;
        esac
    done
}

#----------------------------------------
# 2. Profiles
#----------------------------------------
pos_menu_profiles() {
    while true; do
        _menu_header "🗂 Profiles" ""
        local active; active=$(get_active_profile)
        echo -e " ${POS_GRAY}active:${POS_RESET} ${POS_GREEN}●${POS_RESET} ${active}\n"
        list_profiles | while read -r p; do
            [[ "$p" == "$active" ]] \
                && echo -e "   ${POS_GREEN}● $p${POS_RESET}" \
                || echo     "   ○ $p"
        done
        echo
        local c; c=$(_menu_select "choose" "New" "Switch" "Duplicate" "Rename" "Preview" "Export" "Import" "Merge into active" "Delete" "Back")
        case "$c" in
            1) local n; n=$(pos_prompt "New profile name"); [[ -n "$n" ]] && create_profile "$n"; pos_press_enter ;;
            2) local n; n=$(pos_prompt "Switch to"); [[ -n "$n" ]] && switch_profile "$n"; pos_press_enter ;;
            3) local s d; s=$(pos_prompt "Source"); d=$(pos_prompt "New name"); [[ -n "$s" && -n "$d" ]] && duplicate_profile "$s" "$d"; pos_press_enter ;;
            4) local o n; o=$(pos_prompt "Old name"); n=$(pos_prompt "New name"); [[ -n "$o" && -n "$n" ]] && rename_profile "$o" "$n"; pos_press_enter ;;
            5) local n; n=$(pos_prompt "Profile"); [[ -n "$n" ]] && profile_preview "$n"; pos_press_enter ;;
            6) local n; n=$(pos_prompt "Profile"); [[ -n "$n" ]] && export_profile "$n"; pos_press_enter ;;
            7) local f; f=$(pos_prompt "Path to .profile.json"); [[ -n "$f" ]] && import_profile "$f"; pos_press_enter ;;
            8) local n; n=$(pos_prompt "Merge from profile"); [[ -n "$n" ]] && merge_profile "$n"; pos_press_enter ;;
            9) local n; n=$(pos_prompt "Delete profile"); [[ -n "$n" ]] && pos_confirm "Delete '$n'?" && delete_profile "$n"; pos_press_enter ;;
            10|""|q) return ;;
        esac
    done
}

#----------------------------------------
# 3. Performance
#----------------------------------------
pos_menu_performance() {
    _menu_header "⚡ Performance" ""
    pos_load_feature performance-monitor || { pos_press_enter; return; }
    display_dashboard
    pos_press_enter
}

#----------------------------------------
# 4. Backup & Sync
#----------------------------------------
pos_menu_backup() {
    _menu_header "💾 Backup & Sync" ""
    pos_load_feature backup-restore || { pos_press_enter; return; }
    backup_restore_menu
}

#----------------------------------------
# 5. Cleanup
#----------------------------------------
pos_menu_cleanup() {
    _menu_header "🧹 Cleanup" ""
    pos_load_feature cleanup || { pos_press_enter; return; }
    display_cleanup_menu
}

#----------------------------------------
# 6. Visual FX
#----------------------------------------
pos_menu_visualfx() {
    while true; do
        _menu_header "🌈 Visual FX" ""
        local c; c=$(_menu_select "choose" "Icon themes" "Gradient playground" "Border styles" "Emoji banner" "Back")
        case "$c" in
            1) _fx_icon_themes ;;
            2) _fx_gradients ;;
            3) _fx_borders ;;
            4) _fx_emoji ;;
            5|""|q) return ;;
        esac
    done
}

_fx_icon_themes() {
    _menu_header "🎭 Icon Themes" ""
    local themes=(Neon Glassmorphism Minimalist Retro Gradient)
    local previews=("✦ ◆ ◉ ⬢" "◍ ○ ▢ ▧" "+ o # x" "▟▙ ▛▜ ▞▚" "◢◣ ◤◥")
    local i
    for i in "${!themes[@]}"; do
        echo -e "  ${POS_CYAN}$((i+1))${POS_RESET} ${themes[$i]}  ${POS_GRAY}${previews[$i]}${POS_RESET}"
    done
    local c; c=$(pos_prompt "Pick (1-${#themes[@]})")
    if [[ "$c" =~ ^[1-5]$ ]]; then
        pos_config_set ui.icon_theme "${themes[$((c-1))]}"
        pos_ok "Icon theme → ${themes[$((c-1))]}"
    fi
    pos_press_enter
}

_fx_gradients() {
    _menu_header "🌈 Gradient Playground" ""
    echo
    for stops in "0;217;255:255;0;110" "255;215;0:255;0;110" "0;255;65:0;217;255" "160;120;255:26;26;46"; do
        local c1="${stops%%:*}" c2="${stops##*:}"
        local r1 g1 b1 r2 g2 b2
        IFS=';' read -r r1 g1 b1 <<<"$c1"; IFS=';' read -r r2 g2 b2 <<<"$c2"
        local i steps=32 line=""
        for (( i=0; i<=steps; i++ )); do
            local r=$(( r1 + (r2-r1)*i/steps )) g=$(( g1 + (g2-g1)*i/steps )) b=$(( b1 + (b2-b1)*i/steps ))
            line+="\033[38;2;${r};${g};${b}m▓"
        done
        printf '  %s\033[0m\n' "$line"
    done
    echo
    pos_press_enter
}

_fx_borders() {
    _menu_header "▣ Border Styles" ""
    cat <<BOX
  ${POS_CYAN}┌─────────────┐${POS_RESET}  clean modern
  ${POS_CYAN}│  Premium-OS │${POS_RESET}  width 1, radius 8
  ${POS_CYAN}└─────────────┘${POS_RESET}

  ${POS_PINK}╔═════════════╗${POS_RESET}  bold highlight
  ${POS_PINK}║  Premium-OS ║${POS_RESET}  double border
  ${POS_PINK}╚═════════════╝${POS_RESET}

  ${POS_YELLOW}┌─·─·─·─·─·─·─┐${POS_RESET}  retro dotted
  ${POS_YELLOW}·  Premium-OS ·${POS_RESET}  dotted style
  ${POS_YELLOW}└─·─·─·─·─·─·─┘${POS_RESET}
BOX
    pos_press_enter
}

_fx_emoji() {
    _menu_header "😀 Emoji Banner" ""
    echo
    local picker=(🚀 🔥 ⚡ 💎 🎨 🌈 🧠 🛡️ 🎯 🏆 🤖 👾 🦄 🌙 ☀️ ⭐)
    render_grid 4 "${picker[@]}"
    echo
    local e; e=$(pos_prompt "Emoji for banner" "🚀")
    local t; t=$(pos_prompt "Banner text" "PREMIUM-OS")
    echo
    echo "  $e  $t  $e"
    echo
    pos_ok "Banner preview rendered (save via profiles menu)."
    pos_press_enter
}

#----------------------------------------
# 7. Snippets
#----------------------------------------
pos_menu_snippets() {
    _menu_header "📚 Snippets" ""
    pos_load_feature snippets || { pos_press_enter; return; }
    snippets_menu
}

#----------------------------------------
# 8. Hotkeys
#----------------------------------------
pos_menu_hotkeys() {
    _menu_header "⌨ Hotkeys" ""
    pos_load_feature hotkeys || { pos_press_enter; return; }
    hotkeys_menu
}

#----------------------------------------
# 9. Optimizer
#----------------------------------------
pos_menu_optimizer() {
    _menu_header "🚀 Optimizer" ""
    pos_load_feature optimization || { pos_press_enter; return; }
    optimization_menu
}

#----------------------------------------
# 10. Smart Suggestions
#----------------------------------------
pos_menu_smart() {
    _menu_header "🤖 Smart Suggestions" ""
    pos_load_feature smart-suggestions || { pos_press_enter; return; }
    suggest_theme
    pos_press_enter
}

#----------------------------------------
# 11. Plugins
#----------------------------------------
pos_menu_plugins() {
    _menu_header "🧩 Plugins" ""
    pos_load_feature plugin-manager || { pos_press_enter; return; }
    plugin_menu
}

#----------------------------------------
# 12. Web Dashboard
#----------------------------------------
pos_menu_dashboard() {
    _menu_header "🌐 Web Dashboard" ""
    if command -v node >/dev/null 2>&1; then
        echo -e " ${POS_GRAY}Starting on ${POS_CYAN}http://localhost:8080${POS_RESET} (Ctrl+C to stop)…"
        ( cd "$POS_ROOT/web" 2>/dev/null && exec node server.js ) || pos_error "web/ not found"
    else
        pos_warn "Node.js not installed."
        echo -e " ${POS_GRAY}In Termux: ${POS_CYAN}pkg install nodejs${POS_RESET}"
        echo -e " ${POS_GRAY}Everything else works without it.${POS_RESET}"
        pos_press_enter
    fi
}

#----------------------------------------
# 14. Cyber Lock
#----------------------------------------
pos_menu_cyberlock() {
    _menu_header "🔐 Cyber Lock" ""
    if cyber_lock_is_enabled; then
        echo -e " ${POS_GREEN}● enabled${POS_RESET}\n"
        local c; c=$(_menu_select "choose" "Disable lock" "Change password" "Back")
        case "$c" in
            1) cyber_lock_verify && cyber_lock_disable ;;
            2) cyber_lock_verify && cyber_lock_setup ;;
        esac
    else
        echo -e " ${POS_GRAY}○ disabled${POS_RESET}\n"
        pos_confirm "Enable Cyber Lock?" && cyber_lock_setup
    fi
    pos_press_enter
}

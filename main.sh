#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: main.sh — main entry point
# Usage:
#   bash main.sh            → interactive menu (with Cyber Lock if enabled)
#   bash main.sh <cmd> ...  → CLI subcommand (scriptable API)
#   pos                     → same, once INSTALL.sh has linked the alias
#==============================================================================
set -o pipefail

#----------------------------------------
# Resolve repository root
#----------------------------------------
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    POS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    POS_ROOT="$(pwd)"
fi
export POS_ROOT
export POS_HOME="${POS_HOME:-$HOME/.premium-os}"

#----------------------------------------
# Bootstrap core modules
#----------------------------------------
# shellcheck disable=SC1090
. "$POS_ROOT/core/init.sh"
. "$POS_ROOT/ui/colors.sh"
. "$POS_ROOT/core/utils.sh"
. "$POS_ROOT/core/config.sh"
. "$POS_ROOT/core/theme.sh"
. "$POS_ROOT/core/profile.sh"
. "$POS_ROOT/core/security.sh"
. "$POS_ROOT/ui/animations.sh"
. "$POS_ROOT/ui/responsive.sh"

# Feature modules are loaded lazily by the menu / subcommands.
pos_load_feature() { # $1=name
    local f="$POS_ROOT/features/$1.sh"
    if [[ -f "$f" ]]; then
        # shellcheck disable=SC1090
        . "$f"
        return 0
    fi
    pos_error "Feature module not found: $1"
    return 1
}

#----------------------------------------
# Initialization (settings, profiles, snippets)
#----------------------------------------
pos_init
_first_run_rc=$?
if [[ $_first_run_rc -ne 0 && $_first_run_rc -ne 10 ]]; then
    pos_error "Initialization failed. Check permissions on $POS_HOME."
    exit 1
fi

# Auto-backup trigger (once per day when enabled)
_maybe_auto_backup() {
    [[ "$(pos_config_get backup.auto_backup false)" != "true" ]] && return 0
    local stamp_file="$POS_HOME/cache/.last_auto_backup"
    local today; today=$(date +%F)
    [[ "$(cat "$stamp_file" 2>/dev/null)" == "$today" ]] && return 0
    if [[ -f "$POS_ROOT/features/backup-restore.sh" ]]; then
        pos_load_feature "backup-restore"
        create_backup >/dev/null 2>&1 && echo "$today" > "$stamp_file"
    fi
}

#----------------------------------------
# Banner
#----------------------------------------
pos_banner() {
    [[ "$(pos_config_get ui.banner true)" != "true" ]] && return 0
    local cols; cols=$(tput cols 2>/dev/null || echo 80)
    if (( cols >= 70 )); then
        pos_gradient_text "██████╗ ██████╗ ███████╗███╗   ███╗██╗██╗   ██╗███╗   ███╗" 2>/dev/null \
            || echo " ===== P R E M I U M - O S ====="
        pos_gradient_text "██╔══██╗██╔══██╗██╔════╝████╗ ████║██║██║   ██║████╗ ████║" 2>/dev/null
        pos_gradient_text "██████╔╝██████╔╝█████╗  ██╔████╔██║██║██║   ██║██╔████╔██║" 2>/dev/null
        pos_gradient_text "██╔═══╝ ██╔══██╗██╔══╝  ██║╚██╔╝██║██║██║   ██║██║╚██╔╝██║" 2>/dev/null
        pos_gradient_text "██║     ██║  ██║███████╗██║ ╚═╝ ██║██║╚██████╔╝██║ ╚═╝ ██║" 2>/dev/null
        echo -e "${POS_GRAY}        v${POS_VERSION} — premium terminal for Termux${POS_RESET}"
    else
        pos_gradient_text "◢◤ PREMIUM-OS ◢◤" 2>/dev/null || echo "== PREMIUM-OS =="
        echo -e "${POS_GRAY}v${POS_VERSION}${POS_RESET}"
    fi
    local active; active=$(get_active_profile 2>/dev/null)
    echo -e "  ${POS_GRAY}profile:${POS_RESET} ${POS_CYAN}${active}${POS_RESET}  ${POS_GRAY}theme:${POS_RESET} ${POS_PINK}$(get_current_theme 2>/dev/null)${POS_RESET}"
}

#----------------------------------------
# Quick-Setup wizard (first run)
#----------------------------------------
pos_quick_setup_wizard() {
    pos_clear
    pos_typewrite "👋 Welcome to Premium-OS quick setup!"
    echo
    local shell_ theme_ banner_
    shell_=$(pos_prompt "Shell (bash/zsh/fish)" "bash")
    theme_=$(pos_prompt "Theme style (dark/light/neon/minimal/dracula)" "dark")
    banner_=$(pos_prompt "Custom banner text" "Welcome to Premium-OS")

    [[ -f "$(theme_file_for "$theme_")" ]] || theme_="dark"
    local prof; prof=$(pos_prompt "Name for your first profile" "default")
    pos_is_safe_name "$prof" || prof="default"

    if [[ "$prof" != "default" ]]; then
        create_profile "$prof"
        switch_profile "$prof" >/dev/null
    fi

    if pos_has_jq; then
        local pf tmp
        pf="$POS_HOME/profiles/${prof}.json"
        tmp="$pf.pos_tmp"
        jq --arg s "$shell_" --arg b "$banner_" \
           '.shell=$s | .banner=$b' "$pf" >"$tmp" && mv "$tmp" "$pf"
    fi
    apply_theme "$theme_"

    if pos_confirm "Enable Cyber Lock (password protect Premium-OS)?"; then
        cyber_lock_setup
    fi
    pos_ok "Setup complete! Launch again to enter the menu."
    pos_press_enter
}

#----------------------------------------
# CLI subcommands (scriptable API)
#----------------------------------------
pos_cli() {
    local cmd="$1"; shift || true
    case "$cmd" in
        profile|profiles)
            pos_load_feature "profile" 2>/dev/null  # core/profile.sh already loaded
            case "${1:-list}" in
                list)   list_profiles ;;
                active) get_active_profile ;;
                create) create_profile "$2" ;;
                switch) switch_profile "$2" ;;
                delete) delete_profile "$2" ;;
                dup|duplicate) duplicate_profile "$2" "$3" ;;
                rename) rename_profile "$2" "$3" ;;
                import) import_profile "$2" ;;
                export) export_profile "$2" "$3" ;;
                preview) profile_preview "$2" ;;
                *) pos_error "profile: unknown action '${1:-}'"; exit 2 ;;
            esac ;;
        theme|themes)
            case "${1:-list}" in
                list)    list_themes ;;
                current) get_current_theme ;;
                apply)   apply_theme "$2" ;;
                preview) theme_preview "$2" ;;
                create)  shift; create_custom_theme "$@" ;;
                export)  export_theme "$2" "$3" ;;
                *) pos_error "theme: unknown action '${1:-}'"; exit 2 ;;
            esac ;;
        perf|performance)
            pos_load_feature "performance-monitor" || exit 2
            case "${1:-stats}" in
                stats)    get_performance_stats ;;
                dashboard) display_dashboard ;;
                benchmark) benchmark_terminal ;;
                csv)      export_report ;;
                *) pos_error "perf: unknown action"; exit 2 ;;
            esac ;;
        backup)
            pos_load_feature "backup-restore" || exit 2
            case "${1:-create}" in
                create) create_backup ;;
                restore) restore_backup "$2" ;;
                list)   list_backups ;;
                delete) delete_backup "$2" ;;
                preview) preview_backup "$2" ;;
                verify) backup_verification "$2" ;;
                portable) export_portable "$2" ;;
                *) pos_error "backup: unknown action"; exit 2 ;;
            esac ;;
        snippet|snippets)
            pos_load_feature "snippets" || exit 2
            case "${1:-list}" in
                list)   list_snippets ;;
                search) search_snippet "$2" ;;
                add)    add_snippet "$2" "$3" "$4" ;;
                remove) remove_snippet "$2" ;;
                run|exec) execute_snippet "$2" ;;
                *) pos_error "snippet: unknown action"; exit 2 ;;
            esac ;;
        hotkey|hotkeys)
            pos_load_feature "hotkeys" || exit 2
            case "${1:-list}" in
                list)   list_hotkeys ;;
                add|register) register_hotkey "$2" "$3" ;;
                remove) remove_hotkey "$2" ;;
                test)   test_hotkey "$2" ;;
                *) pos_error "hotkey: unknown action"; exit 2 ;;
            esac ;;
        cleanup)
            pos_load_feature "cleanup" || exit 2
            if [[ "${1:-}" == "auto" ]]; then cleanup_all_auto; else display_cleanup_menu; fi ;;
        optimize)
            pos_load_feature "optimization" || exit 2
            case "${1:-scan}" in
                scan)   optimize_startup_scan ;;
                apply)  optimize_apply ;;
                before) benchmark_startup ;;
                *) pos_error "optimize: unknown action"; exit 2 ;;
            esac ;;
        suggest|suggestions)
            pos_load_feature "smart-suggestions" || exit 2
            suggest_theme ;;
        plugin|plugins)
            pos_load_feature "plugin-manager" || exit 2
            case "${1:-list}" in
                list)    list_plugins ;;
                install) install_plugin "$2" ;;
                uninstall|remove) uninstall_plugin "$2" ;;
                enable)  enable_plugin "$2" ;;
                disable) disable_plugin "$2" ;;
                info)    get_plugin_info "$2" ;;
                market)  plugin_marketplace ;;
                *) pos_error "plugin: unknown action"; exit 2 ;;
            esac ;;
        dashboard|web|serve)
            local dir="$POS_ROOT/web"
            if [[ -f "$dir/server.js" ]] && command -v node >/dev/null 2>&1; then
                pos_log "Starting web dashboard on http://localhost:8080"
                ( cd "$dir" && exec node server.js )
            else
                pos_error "Web dashboard requires Node.js. Install it or skip."
                exit 1
            fi ;;
        update)
            bash "$POS_ROOT/scripts/update.sh" ;;
        lock)
            cyber_lock_verify ;;
        setup|wizard)
            pos_quick_setup_wizard ;;
        version|--version|-v)
            echo "Premium-OS v${POS_VERSION}" ;;
        help|--help|-h)
            cat <<'HELP'
Premium-OS — usage:
  bash main.sh                    interactive menu
  bash main.sh profile <action>   list|active|create|switch|delete|duplicate|rename|import|export|preview
  bash main.sh theme <action>     list|current|apply|preview|create|export
  bash main.sh perf <action>      stats|dashboard|benchmark|csv
  bash main.sh backup <action>    create|restore|list|delete|preview|verify|portable
  bash main.sh snippet <action>   list|search|add|remove|run
  bash main.sh hotkey <action>    list|add|remove|test
  bash main.sh cleanup [auto]
  bash main.sh optimize <scan|apply|before>
  bash main.sh suggest
  bash main.sh plugin <action>    list|install|uninstall|enable|disable|info|market
  bash main.sh dashboard          start web dashboard (node required)
  bash main.sh setup              quick-setup wizard
  bash main.sh version
HELP
            ;;
        *)
            pos_error "Unknown command: $cmd (try: help)"
            exit 2 ;;
    esac
}

#----------------------------------------
# Dispatch
#----------------------------------------
if [[ $# -gt 0 ]]; then
    pos_cli "$@"
    exit $?
fi

# Interactive path
if [[ $_first_run_rc -eq 10 ]]; then
    pos_quick_setup_wizard
fi

cyber_lock_verify || { pos_error "Access denied."; exit 1; }

pos_banner
_maybe_auto_backup &

# Launch responsive menu
if declare -f pos_main_menu >/dev/null 2>&1; then
    pos_main_menu
else
    # Menu module missing → graceful degradation to banner + hint
    echo -e "${POS_GRAY}Menu module unavailable. Use CLI: bash main.sh help${POS_RESET}"
fi

exit 0

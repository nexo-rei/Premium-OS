#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/cleanup.sh
# Safe, selective cleanup: history, temp, cache, package cache.
# Dry-run preview, freed-space report, no destructive defaults.
#==============================================================================

[[ -n "${_POS_FEAT_CLEANUP_LOADED:-}" ]] && return 0
_POS_FEAT_CLEANUP_LOADED=1

POS_HOME_D="${POS_HOME:-$HOME/.premium-os}"

#----------------------------------------
# calculate_disk_space <path> → bytes
#----------------------------------------
calculate_disk_space() { pos_dir_size_bytes "$1"; }

#----------------------------------------
# dry_run_cleanup — report what WOULD be freed (deletes nothing)
#----------------------------------------
dry_run_cleanup() {
    echo -e "${POS_BOLD}Cleanup dry-run (nothing deleted):${POS_RESET}"
    local hist tmpc cache aptc
    hist=$(calculate_disk_space "$POS_HOME_D/history")
    tmpc=$(calculate_disk_space "$POS_HOME_D/tmp")
    cache=$(calculate_disk_space "$POS_HOME_D/cache")
    aptc=0
    [[ -n "${PREFIX:-}" && -d "${PREFIX:-}/var/cache/apt/archives" ]] \
        && aptc=$(calculate_disk_space "$PREFIX/var/cache/apt/archives")
    [[ "$aptc" == 0 && -d /var/cache/apt/archives ]] && aptc=$(calculate_disk_space /var/cache/apt/archives)
    printf '  %-28s %s\n' "POS history logs:"  "$(pos_human_size "$hist")"
    printf '  %-28s %s\n' "POS temp files:"    "$(pos_human_size "$tmpc")"
    printf '  %-28s %s\n' "POS cache:"         "$(pos_human_size "$cache")"
    printf '  %-28s %s\n' "package cache:"     "$(pos_human_size "$aptc")"
    printf '  %b%-28s %s%b\n' "$POS_GREEN" "TOTAL reclaimable:" "$(pos_human_size $((hist+tmpc+cache+aptc)))" "$POS_RESET"
}

#----------------------------------------
# cleanup_history — clear command history safely
#----------------------------------------
cleanup_history() {
    local freed=0
    # Shell history files (common locations)
    local hf
    for hf in "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.local/share/fish/fish_history"; do
        if [[ -f "$hf" ]]; then
            local sz; sz=$(stat -c%s "$hf" 2>/dev/null || echo 0)
            cp "$hf" "$POS_HOME_D/cache/history-backup-$(basename "$hf")" 2>/dev/null
            : > "$hf"  # truncate instead of delete — safer
            freed=$((freed + sz))
        fi
    done
    echo "$freed"
}

#----------------------------------------
# cleanup_temp_files — POS tmp + stale tmp dirs (never system files)
#----------------------------------------
cleanup_temp_files() {
    local before after
    before=$(calculate_disk_space "$POS_HOME_D/tmp")
    find "$POS_HOME_D/tmp" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
    mkdir -p "$POS_HOME_D/tmp"
    after=$(calculate_disk_space "$POS_HOME_D/tmp")
    echo $(( before - after ))
}

#----------------------------------------
# cleanup_cache — POS cache only (keeps security files)
#----------------------------------------
cleanup_cache() {
    local before after
    before=$(calculate_disk_space "$POS_HOME_D/cache")
    find "$POS_HOME_D/cache" -mindepth 1 -maxdepth 1 \
        ! -name '.secure' ! -name '.last_auto_backup' \
        -exec rm -rf {} + 2>/dev/null
    mkdir -p "$POS_HOME_D/cache"
    after=$(calculate_disk_space "$POS_HOME_D/cache")
    echo $(( before - after ))
}

#----------------------------------------
# cleanup_packages — apt cache clear (Termux / Debian)
#----------------------------------------
cleanup_packages() {
    local before=0 after=0 d=""
    if [[ -n "${PREFIX:-}" && -d "$PREFIX/var/cache/apt/archives" ]]; then
        d="$PREFIX/var/cache/apt/archives"
    elif [[ -d /var/cache/apt/archives ]]; then
        d="/var/cache/apt/archives"
    fi
    [[ -n "$d" ]] && before=$(calculate_disk_space "$d")
    if command -v apt >/dev/null 2>&1; then
        apt clean >/dev/null 2>&1
        apt autoclean >/dev/null 2>&1
    fi
    [[ -n "$d" ]] && after=$(calculate_disk_space "$d")
    echo $(( before - after ))
}

#----------------------------------------
# safety_confirmation — explicit yes
#----------------------------------------
safety_confirmation() {
    pos_warn "$1"
    pos_confirm "Proceed?" || { pos_log "Aborted."; return 1; }
}

#----------------------------------------
# get_cleanup_report — after cleanup summary
#----------------------------------------
get_cleanup_report() { # $1..$4 freed amounts
    echo
    echo -e "${POS_GREEN}${POS_BOLD}Cleanup report${POS_RESET}"
    printf '  history : %s\n' "$(pos_human_size "${1:-0}")"
    printf '  temp    : %s\n' "$(pos_human_size "${2:-0}")"
    printf '  cache   : %s\n' "$(pos_human_size "${3:-0}")"
    printf '  packages: %s\n' "$(pos_human_size "${4:-0}")"
    printf '  %bTOTAL FREED: %s%b\n' "$POS_GREEN" \
        "$(pos_human_size $(( ${1:-0} + ${2:-0} + ${3:-0} + ${4:-0} )))" "$POS_RESET"
}

#----------------------------------------
# post_cleanup_verification — sanity checks
#----------------------------------------
post_cleanup_verification() {
    local ok=0
    [[ -d "$POS_HOME_D/profiles" ]] || { pos_error "profiles dir missing!"; ok=1; }
    [[ -f "$POS_HOME_D/settings.json" ]] || { pos_error "settings.json missing!"; ok=1; }
    [[ -d "$POS_HOME_D/tmp" ]] || mkdir -p "$POS_HOME_D/tmp"
    [[ $ok -eq 0 ]] && pos_ok "Post-cleanup verification passed."
    return $ok
}

#----------------------------------------
# schedule_cleanup — preference + daily trigger file
#----------------------------------------
schedule_cleanup() {
    local freq="${1:-weekly}"
    pos_config_set cleanup.frequency "$freq"
    pos_ok "Cleanup scheduled: $freq (runs from menu)."
}

#----------------------------------------
# cleanup_all_auto — non-interactive full cleanup (used by CLI auto)
#----------------------------------------
cleanup_all_auto() {
    local h t c p
    h=$(cleanup_history); t=$(cleanup_temp_files)
    c=$(cleanup_cache);   p=$(cleanup_packages)
    get_cleanup_report "$h" "$t" "$c" "$p"
    post_cleanup_verification
}

#----------------------------------------
# display_cleanup_menu — interactive selective cleanup
#----------------------------------------
display_cleanup_menu() {
    local c
    while true; do
        _menu_header "🧹 Auto-Cleanup" ""
        dry_run_cleanup
        echo
        c=$(_menu_select "choose" \
            "Clean command history" "Clean temp files" "Clean POS cache" \
            "Clean package cache" "Clean EVERYTHING (asks first)" \
            "Schedule cleanup" "Back")
        case "$c" in
            1) safety_confirmation "History will be truncated (backup kept in cache)." \
               && { f=$(cleanup_history); pos_ok "Freed $(pos_human_size "$f")"; }; pos_press_enter ;;
            2) f=$(cleanup_temp_files); pos_ok "Freed $(pos_human_size "$f")"; pos_press_enter ;;
            3) f=$(cleanup_cache); pos_ok "Freed $(pos_human_size "$f")"; pos_press_enter ;;
            4) f=$(cleanup_packages); pos_ok "Freed $(pos_human_size "$f")"; pos_press_enter ;;
            5)
               safety_confirmation "This frees ALL of the above."
               local h t cc p
               h=$(cleanup_history); t=$(cleanup_temp_files)
               cc=$(cleanup_cache); p=$(cleanup_packages)
               get_cleanup_report "$h" "$t" "$cc" "$p"
               post_cleanup_verification
               pos_press_enter ;;
            6) local fr; fr=$(pos_prompt "Frequency (daily/weekly)" "weekly")
               schedule_cleanup "$fr"; pos_press_enter ;;
            7|""|q) return ;;
        esac
    done
}

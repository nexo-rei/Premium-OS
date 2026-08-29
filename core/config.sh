#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: core/config.sh
# Configuration management: read/write settings.json, defaults merge.
#==============================================================================

[[ -n "${_POS_CORE_CONFIG_LOADED:-}" ]] && return 0
_POS_CORE_CONFIG_LOADED=1

# Requires core/utils.sh (pos_json_get/pos_json_set/pos_has_jq)

POS_SETTINGS_FILE="${POS_HOME:-$HOME/.premium-os}/settings.json"

#----------------------------------------
# pos_config_get <key.path> [default]
#----------------------------------------
pos_config_get() {
    local key="$1" default="${2:-}" value
    value=$(pos_json_get "$POS_SETTINGS_FILE" "$key" 2>/dev/null)
    echo "${value:-$default}"
}

#----------------------------------------
# pos_config_set <key.path> <value> [number|bool]
#----------------------------------------
pos_config_set() {
    local key="$1" value="$2" type="${3:-string}"
    [[ -f "$POS_SETTINGS_FILE" ]] || { pos_default_settings 2>/dev/null || return 1; }
    pos_json_set "$POS_SETTINGS_FILE" "$key" "$value" "$type"
}

#----------------------------------------
# Validate the settings file; repair minimal damage.
#----------------------------------------
pos_config_validate() {
    local f="$POS_SETTINGS_FILE"
    if [[ ! -f "$f" ]]; then
        pos_warn "settings.json missing — restoring defaults"
        pos_default_settings
        return $?
    fi
    if pos_has_jq && ! jq empty "$f" 2>/dev/null; then
        pos_error "settings.json corrupted — backing up and restoring defaults"
        cp "$f" "${f}.corrupt-$(pos_timestamp)" 2>/dev/null
        rm -f "$f"
        pos_default_settings
        return $?
    fi
    return 0
}

#----------------------------------------
# Merge factory defaults into an existing settings file (upgrade path)
#----------------------------------------
pos_config_merge_defaults() {
    pos_config_validate || return 1
    # Idempotent additions for new features on upgrade
    if pos_has_jq; then
        local f="$POS_SETTINGS_FILE" tmp="${POS_SETTINGS_FILE}.pos_tmp"
        jq '
          .ui        = (.ui        // {}) + {theme:(.ui.theme//"dark"), animations:(.ui.animations//true), banner:(.ui.banner//true), layout:(.ui.layout//"auto"), sound_effects:(.ui.sound_effects//false)} |
          .security  = (.security  // {}) + {cyber_lock_enabled:(.security.cyber_lock_enabled//false), lock_hash:(.security.lock_hash//""), auto_lock_minutes:(.security.auto_lock_minutes//0)} |
          .backup    = (.backup    // {}) + {auto_backup:(.backup.auto_backup//false), max_backups:(.backup.max_backups//10), compress:(.backup.compress//true)} |
          .updates   = (.updates   // {}) + {check_on_start:(.updates.check_on_start//true), auto_update:(.updates.auto_update//false)} |
          .smart     = (.smart     // {}) + {suggestions_enabled:(.smart.suggestions_enabled//true), telemetry_opt_in:(.smart.telemetry_opt_in//false)} |
          .version   = (.version   // "1.0.0")
        ' "$f" >"$tmp" && mv "$tmp" "$f"
    fi
}

#----------------------------------------
# Export the full settings (for backup bundle)
#----------------------------------------
pos_config_export_all() {
    cat "$POS_SETTINGS_FILE" 2>/dev/null
}

#----------------------------------------
# Simple key editing for the Settings panel UI
#----------------------------------------
pos_config_interactive_edit() {
    pos_clear
    echo -e "${POS_BOLD}${POS_CYAN}⚙ Settings${POS_RESET}"
    echo -e "${POS_GRAY}────────────────────────────────────────${POS_RESET}"
    echo "  active_profile : $(pos_config_get active_profile)"
    echo "  theme          : $(pos_config_get ui.theme)"
    echo "  animations     : $(pos_config_get ui.animations)"
    echo "  banner enabled : $(pos_config_get ui.banner)"
    echo "  layout         : $(pos_config_get ui.layout)"
    echo "  auto_backup    : $(pos_config_get backup.auto_backup)"
    echo "  max_backups    : $(pos_config_get backup.max_backups)"
    echo "  suggestions    : $(pos_config_get smart.suggestions_enabled)"
    echo "  cyber_lock     : $(pos_config_get security.cyber_lock_enabled)"
    echo
    echo "  1) Toggle animations    2) Toggle banner"
    echo "  3) Toggle suggestions   4) Toggle auto-backup"
    echo "  0) Back"
    local c; read -rn 1 c; echo
    case "$c" in
        1) local v; v=$(pos_config_get ui.animations true)
           pos_config_set ui.animations "$([ "$v" = true ] && echo false || echo true)" bool; pos_ok "Animations toggled." ;;
        2) local v; v=$(pos_config_get ui.banner true)
           pos_config_set ui.banner "$([ "$v" = true ] && echo false || echo true)" bool; pos_ok "Banner toggled." ;;
        3) local v; v=$(pos_config_get smart.suggestions_enabled true)
           pos_config_set smart.suggestions_enabled "$([ "$v" = true ] && echo false || echo true)" bool; pos_ok "Suggestions toggled." ;;
        4) local v; v=$(pos_config_get backup.auto_backup false)
           pos_config_set backup.auto_backup "$([ "$v" = true ] && echo false || echo true)" bool; pos_ok "Auto-backup toggled." ;;
    esac
    pos_press_enter
}

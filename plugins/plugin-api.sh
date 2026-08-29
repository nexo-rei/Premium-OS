#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: plugins/plugin-api.sh
# Plugin API helpers — OPTIONAL file. Third-party plugins may source this
# inside their own sandbox run for convenience helpers.
#==============================================================================

[[ -n "${_POS_PLUGIN_API_LOADED:-}" ]] && return 0
_POS_PLUGIN_API_LOADED=1

#----------------------------------------
# Logging inside the sandbox — writes to the plugin's data dir
#----------------------------------------
plugin_log() {
    local d="${POS_PLUGIN_DATA_DIR:-${POS_PLUGIN_DIR:-.}/data}"
    mkdir -p "$d" 2>/dev/null
    echo "$(date '+%F %T') [$POS_PLUGIN_NAME] $*" >> "$d/plugin.log"
}

#----------------------------------------
# Storage helpers — simple per-plugin key=value store
#----------------------------------------
plugin_data_set() { # $1=key $2=value
    local d="${POS_PLUGIN_DATA_DIR:-${POS_PLUGIN_DIR:-.}/data}"
    mkdir -p "$d"
    local f="$d/store.conf"; touch "$f"
    grep -v "^$1=" "$f" > "$f.tmp" 2>/dev/null
    echo "$1=$2" >> "$f.tmp"
    mv "$f.tmp" "$f"
}

plugin_data_get() { # $1=key [default]
    local d="${POS_PLUGIN_DATA_DIR:-${POS_PLUGIN_DIR:-.}/data}"
    local v
    v=$(grep "^$1=" "$d/store.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
    echo "${v:-${2:-}}"
}

#----------------------------------------
# Hook registry — all hooks Premium-OS emits today
#----------------------------------------
plugin_available_hooks() {
    cat <<'HOOKS'
startup:init        Premium-OS finished initializing
theme:applied       $1=theme name
profile:switched    $1=profile name
backup:created      $1=backup file path
restore:complete    $1=backup file path
cleanup:complete    no args
system:optimized    no args
plugin:installed    $1=plugin dir name
update:available    $1=new version (if detected)
ui:render           dashboard render tick (web)
HOOKS
}

#----------------------------------------
# Permission keywords a manifest may declare
#----------------------------------------
plugin_available_permissions() {
    echo "filesystem network shell config ui"
}

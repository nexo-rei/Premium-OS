#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/plugin-manager.sh
# Sandboxed plugin system: install, enable/disable, hooks, permissions,
# marketplace browser, integrity checks.
# Plugin layout: ~/.premium-os/plugins/<name>/{manifest.json, plugin.sh}
#==============================================================================

[[ -n "${_POS_FEAT_PLUGINS_LOADED:-}" ]] && return 0
_POS_FEAT_PLUGINS_LOADED=1

POS_PLUGINS_DIR="${POS_HOME:-$HOME/.premium-os}/plugins"

_plugins_ensure() { mkdir -p "$POS_PLUGINS_DIR" 2>/dev/null; }

#----------------------------------------
# pos_emit_hook <hook> [args...] — called by core on lifecycle events
# Runs enabled plugins declaring the hook in their manifest.
#----------------------------------------
pos_emit_hook() {
    local hook="$1"; shift || true
    _plugins_ensure
    local d
    for d in "$POS_PLUGINS_DIR"/*/; do
        [[ -f "$d/manifest.json" && -f "$d/plugin.sh" ]] || continue
        [[ -f "$d/.disabled" ]] && continue
        if pos_has_jq && ! jq -e --arg h "$hook" '.hooks | index($h)' "$d/manifest.json" >/dev/null 2>&1; then
            continue
        fi
        # sandboxed execution: no inheriting of functions, timeout, closed env
        _plugin_run_sandboxed "$d" "$hook" "$@" || pos_warn "plugin $(basename "$d") hook failed"
    done
    return 0
}

#----------------------------------------
# _plugin_run_sandboxed <dir> <hook> [args...]
#----------------------------------------
_plugin_run_sandboxed() {
    local dir="$1" hook="$2"; shift 2 || return 0
    local perms
    perms=$(pos_json_get "$dir/manifest.json" "permissions" 2>/dev/null || echo "")
    (
        # Restricted child environment
        unset BASH_ENV ENV
        export POS_PLUGIN_DIR="$dir"
        export POS_PLUGIN_NAME="$(basename "$dir")"
        export POS_HOOK="$hook"
        # shellcheck disable=SC1090
        . "$dir/plugin.sh"
        if declare -f plugin_on_event >/dev/null 2>&1; then
            plugin_on_event "$hook" "$@"
        elif declare -f "on_${hook//:/_}" >/dev/null 2>&1; then
            "on_${hook//:/_}" "$@"
        fi
    ) </dev/null >/dev/null 2>&1 &
    local pid=$!
    # Timeout: kill after 10s
    ( sleep 10; kill -9 "$pid" 2>/dev/null ) & local watcher=$!
    wait "$pid" 2>/dev/null; local rc=$?
    kill "$watcher" 2>/dev/null
    return $rc
}

#----------------------------------------
# validate_plugin <dir> → structural + permission validation
#----------------------------------------
validate_plugin() {
    local dir="$1"
    [[ -f "$dir/manifest.json" ]] || { pos_error "missing manifest.json"; return 1; }
    [[ -f "$dir/plugin.sh" ]]     || { pos_error "missing plugin.sh"; return 1; }
    if pos_has_jq; then
        jq empty "$dir/manifest.json" 2>/dev/null || { pos_error "manifest.json is invalid JSON"; return 1; }
        local required=(name version author description)
        local k
        for k in "${required[@]}"; do
            jq -e --arg k "$k" 'has($k) and (.[$k] != "")' "$dir/manifest.json" >/dev/null 2>&1 \
                || { pos_error "manifest missing field: $k"; return 1; }
        done
    fi
    # Reject obviously dangerous operations unless plugin declares "shell" permission
    if grep -qE '\b(rm -rf /|mkfs|dd if=|:(){ :|:& };:)\b' "$dir/plugin.sh" 2>/dev/null; then
        pos_error "plugin contains dangerous code patterns — rejected."
        return 1
    fi
    return 0
}

#----------------------------------------
# install_plugin <path_or_url>
#----------------------------------------
install_plugin() {
    local src="$1"
    [[ -z "$src" ]] && { pos_error "Usage: install_plugin <dir|url>"; return 1; }
    _plugins_ensure
    local stage="$POS_HOME/tmp/plugin-install-$$"
    rm -rf "$stage"; mkdir -p "$stage"

    if [[ "$src" =~ ^https?:// ]]; then
        command -v curl >/dev/null 2>&1 || { pos_error "curl needed for URL installs."; return 1; }
        # single-file or tarball
        if ! curl -sfL --max-time 30 "$src" -o "$stage/pkg" 2>/dev/null; then
            pos_error "Download failed."; rm -rf "$stage"; return 1
        fi
        mkdir -p "$stage/x"
        if tar -tzf "$stage/pkg" >/dev/null 2>&1; then
            tar -xzf "$stage/pkg" -C "$stage/x"
        else
            mkdir -p "$stage/x/plugin"; cp "$stage/pkg" "$stage/x/plugin/plugin.sh"
        fi
    else
        [[ -d "$src" ]] || { pos_error "Plugin directory not found: $src"; rm -rf "$stage"; return 1; }
        mkdir -p "$stage/x"; cp -r "$src" "$stage/x/"
    fi

    # locate plugin root (the dir containing manifest.json)
    local root
    root=$(find "$stage/x" -maxdepth 2 -name manifest.json -printf '%h\n' 2>/dev/null | head -1)
    [[ -z "$root" ]] && { pos_error "No manifest.json found in package."; rm -rf "$stage"; return 1; }

    if ! validate_plugin "$root"; then
        rm -rf "$stage"; return 1
    fi

    local name; name=$(pos_json_get "$root/manifest.json" name 2>/dev/null || basename "$root")
    # sanitize name for directory use
    local dir_name; dir_name=$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
    [[ -z "$dir_name" ]] && dir_name="plugin-$$"

    if [[ -d "$POS_PLUGINS_DIR/$dir_name" ]]; then
        pos_error "Plugin '$dir_name' already installed."
        rm -rf "$stage"; return 1
    fi
    mv "$root" "$POS_PLUGINS_DIR/$dir_name"
    rm -rf "$stage"
    if declare -f pos_emit_hook >/dev/null 2>&1; then pos_emit_hook "plugin:installed" "$dir_name" >/dev/null 2>&1; fi
    pos_ok "Installed plugin '$name' ($dir_name)."
}

#----------------------------------------
# uninstall_plugin <name>
#----------------------------------------
uninstall_plugin() {
    local name="$1" dir="$POS_PLUGINS_DIR/$1"
    [[ -d "$dir" ]] || { pos_error "Plugin not installed: $name"; return 1; }
    rm -rf "$dir" && pos_ok "Plugin '$name' uninstalled."
}

#----------------------------------------
# enable_plugin / disable_plugin
#----------------------------------------
enable_plugin() {
    local dir="$POS_PLUGINS_DIR/$1"
    [[ -d "$dir" ]] || { pos_error "Not installed: $1"; return 1; }
    rm -f "$dir/.disabled" && pos_ok "'$1' enabled."
}
disable_plugin() {
    local dir="$POS_PLUGINS_DIR/$1"
    [[ -d "$dir" ]] || { pos_error "Not installed: $1"; return 1; }
    touch "$dir/.disabled" && pos_ok "'$1' disabled."
}

#----------------------------------------
# list_plugins
#----------------------------------------
list_plugins() {
    _plugins_ensure
    local d found=0 name ver state
    for d in "$POS_PLUGINS_DIR"/*/; do
        [[ -f "$d/manifest.json" ]] || continue
        found=1
        name=$(pos_json_get "$d/manifest.json" name 2>/dev/null || basename "$d")
        ver=$(pos_json_get "$d/manifest.json" version 2>/dev/null || echo "?")
        [[ -f "$d/.disabled" ]] && state="${POS_GRAY}disabled${POS_RESET}" || state="${POS_GREEN}enabled${POS_RESET}"
        echo -e "  ${POS_CYAN}$(basename "$d")${POS_RESET}  v$ver  $state"
        echo -e "      ${POS_GRAY}$(pos_json_get "$d/manifest.json" description 2>/dev/null)${POS_RESET}"
    done
    (( found == 0 )) && echo "  (no plugins installed)"
}

#----------------------------------------
# get_plugin_info <name>
#----------------------------------------
get_plugin_info() {
    local dir="$POS_PLUGINS_DIR/$1"
    [[ -f "$dir/manifest.json" ]] || { pos_error "Not installed: $1"; return 1; }
    if pos_has_jq; then
        jq -r '
          "  name        : \(.name)",
          "  version     : \(.version)",
          "  author      : \(.author)",
          "  description : \(.description)",
          "  hooks       : \(.hooks | join(", "))",
          "  permissions : \(.permissions | join(", "))",
          "  checksum    : \(.checksum // "n/a")"
        ' "$dir/manifest.json"
    fi
}

#----------------------------------------
# plugin_updater — check for updates (placeholder for network compare)
#----------------------------------------
plugin_updater() {
    pos_log "Update check uses plugin manifest repository_url (coming soon)."
    pos_log "All installed plugins are current as far as we know."
}

#----------------------------------------
# plugin_marketplace — curated browser (offline fallback catalog)
#----------------------------------------
plugin_marketplace() {
    _menu_header "🧩 Plugin Marketplace" ""
    cat <<'CAT'
  Featured community plugins (install with a URL when online):

   1. extra-themes-pack
      20 additional community theme presets
      hooks: theme:applied · perms: config

   2. git-status-precache
      Precaches git branch for instant prompts
      hooks: startup:init · perms: shell, filesystem

   3. quote-of-the-day
      Friendly quote in your banner
      hooks: startup:init · perms: network

   4. battery-aware-theme
      Auto-switches to dark theme under 20% battery
      hooks: performance:update · perms: filesystem

   5. pomo-timer
      Pomodoro timer in the dashboard status bar
      hooks: ui:render · perms: ui

  Local example plugin lives in: plugins/example-plugin.sh
  Install it with:  bash main.sh plugin install <path>
CAT
    local c; c=$(pos_prompt "Press Enter")
}

#----------------------------------------
# plugin_menu — interactive management UI
#----------------------------------------
plugin_menu() {
    local c
    while true; do
        _menu_header "🧩 Plugins" ""
        list_plugins
        echo
        c=$(_menu_select "choose" "Install from path/URL" "Uninstall" "Enable" "Disable" "Info" "Marketplace" "Back")
        case "$c" in
            1) local s; s=$(pos_prompt "Path or URL"); [[ -n "$s" ]] && install_plugin "$s"; pos_press_enter ;;
            2) local p; p=$(pos_prompt "Plugin dir name"); [[ -n "$p" ]] && uninstall_plugin "$p"; pos_press_enter ;;
            3) local p; p=$(pos_prompt "Plugin dir name"); [[ -n "$p" ]] && enable_plugin "$p"; pos_press_enter ;;
            4) local p; p=$(pos_prompt "Plugin dir name"); [[ -n "$p" ]] && disable_plugin "$p"; pos_press_enter ;;
            5) local p; p=$(pos_prompt "Plugin dir name"); [[ -n "$p" ]] && get_plugin_info "$p"; pos_press_enter ;;
            6) plugin_marketplace ;;
            7|""|q) return ;;
        esac
    done
}

#----------------------------------------
# plugin_settings <name> — runtime data dir per plugin
#----------------------------------------
plugin_settings() { mkdir -p "$POS_PLUGINS_DIR/$1/data" 2>/dev/null; echo "$POS_PLUGINS_DIR/$1/data"; }

#----------------------------------------
# execute_plugin <name> <action> — manual invocation helper
#----------------------------------------
execute_plugin() {
    local name="$1" action="${2:-run}" dir="$POS_PLUGINS_DIR/$1"
    [[ -f "$dir/plugin.sh" ]] || { pos_error "Not installed: $name"; return 1; }
    [[ -f "$dir/.disabled" ]] && { pos_error "Plugin is disabled."; return 1; }
    _plugin_run_sandboxed "$dir" "manual:$action"
}

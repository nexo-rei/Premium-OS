#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: core/init.sh
# First-run initialization: directory creation, permissions, default config.
#==============================================================================

[[ -n "${_POS_CORE_INIT_LOADED:-}" ]] && return 0
_POS_CORE_INIT_LOADED=1

POS_VERSION="1.0.0"
POS_HOME="${POS_HOME:-$HOME/.premium-os}"
POS_ROOT="${POS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

#----------------------------------------
# Directory layout (single source of truth)
#----------------------------------------
pos_ensure_dirs() {
    local d
    for d in \
        "$POS_HOME" \
        "$POS_HOME/profiles" \
        "$POS_HOME/backups" \
        "$POS_HOME/plugins" \
        "$POS_HOME/cache" \
        "$POS_HOME/history" \
        "$POS_HOME/tmp"; do
        if [[ ! -d "$d" ]]; then
            mkdir -p "$d" 2>/dev/null || {
                echo "pos: cannot create $d" >&2
                return 1
            }
        fi
    done
    # User-only permissions on the data root
    chmod 700 "$POS_HOME" 2>/dev/null || true
    return 0
}

#----------------------------------------
# Write the default settings file if missing
#----------------------------------------
pos_default_settings() {
    local f="$POS_HOME/settings.json"
    [[ -f "$f" ]] && return 0
    cat > "$f" <<'JSON'
{
  "version": "1.0.0",
  "active_profile": "default",
  "ui": {
    "theme": "dark",
    "animations": true,
    "sound_effects": false,
    "banner": true,
    "layout": "auto"
  },
  "security": {
    "cyber_lock_enabled": false,
    "lock_hash": "",
    "auto_lock_minutes": 0
  },
  "backup": {
    "auto_backup": false,
    "max_backups": 10,
    "compress": true
  },
  "updates": {
    "check_on_start": true,
    "auto_update": false
  },
  "smart": {
    "suggestions_enabled": true,
    "telemetry_opt_in": false
  }
}
JSON
    chmod 600 "$f" 2>/dev/null || true
}

#----------------------------------------
# Create the factory "default" profile if missing
#----------------------------------------
pos_default_profile() {
    local f="$POS_HOME/profiles/default.json"
    [[ -f "$f" ]] && return 0
    cat > "$f" <<'JSON'
{
  "name": "default",
  "created": "",
  "theme": {
    "name": "dark",
    "primary": "#00D9FF",
    "secondary": "#FF006E",
    "accent": "#00FF41",
    "background": "#0A0E27",
    "foreground": "#FFFFFF",
    "gradient": "neon",
    "font": "Fira Code",
    "font_size": 14
  },
  "shell": "bash",
  "aliases": {
    "ll": "ls -la",
    "gs": "git status",
    "cls": "clear"
  },
  "hotkeys": {
    "Ctrl+Alt+T": "theme-selector",
    "Ctrl+Shift+P": "profile-switch"
  },
  "startup_commands": [],
  "banner": "Welcome to Premium-OS"
}
JSON
    chmod 600 "$f" 2>/dev/null || true
}

#----------------------------------------
# Seed the snippets library with productive defaults
#----------------------------------------
pos_default_snippets() {
    local f="$POS_HOME/snippets.json"
    [[ -f "$f" ]] && return 0
    cat > "$f" <<'JSON'
{
  "snippets": [
    {"id": 1, "category": "Git", "name": "Quick commit", "command": "git add . && git commit -m \"update\""},
    {"id": 2, "category": "Git", "name": "Undo last commit", "command": "git reset --soft HEAD~1"},
    {"id": 3, "category": "Git", "name": "Pretty log", "command": "git log --oneline --graph --decorate"},
    {"id": 4, "category": "System", "name": "Disk usage", "command": "df -h"},
    {"id": 5, "category": "System", "name": "Memory usage", "command": "free -h"},
    {"id": 6, "category": "System", "name": "Largest dirs", "command": "du -sh * 2>/dev/null | sort -rh | head"},
    {"id": 7, "category": "Dev", "name": "Serve folder", "command": "python3 -m http.server 8000"},
    {"id": 8, "category": "Dev", "name": "JSON pretty print", "command": "cat file.json | jq ."},
    {"id": 9, "category": "Package", "name": "Update all", "command": "apt update && apt upgrade -y"},
    {"id": 10, "category": "Package", "name": "Clean apt cache", "command": "apt clean && apt autoclean"}
  ]
}
JSON
    chmod 600 "$f" 2>/dev/null || true
}

#----------------------------------------
# Init entry point — idempotent
# Returns: 0 on fresh init or healthy existing install
#----------------------------------------
pos_init() {
    local first_run=0
    [[ ! -f "$POS_HOME/settings.json" ]] && first_run=1

    pos_ensure_dirs      || return 1
    pos_default_settings || return 1
    pos_default_profile  || return 1
    pos_default_snippets || return 1

    # Hotkeys file
    if [[ ! -f "$POS_HOME/hotkeys.conf" ]]; then
        cat > "$POS_HOME/hotkeys.conf" <<'EOF'
# Premium-OS hotkey bindings — format: HOTKEY=COMMAND
Ctrl+Alt+T=theme-selector
Ctrl+Shift+P=profile-switch
Ctrl+Shift+S=screenshot
EOF
        chmod 600 "$POS_HOME/hotkeys.conf" 2>/dev/null || true
    fi

    # Version stamp
    echo "$POS_VERSION" > "$POS_HOME/.version"

    # Return code 10 = first run (wizard should be shown)
    [[ $first_run -eq 1 ]] && return 10
    return 0
}

#----------------------------------------
# System requirement check — used by INSTALL.sh
#----------------------------------------
pos_check_requirements() {
    local ok=0
    local bash_major="${BASH_VERSINFO[0]}"
    if [[ "$bash_major" -lt 4 ]]; then
        echo "ERROR: bash >= 4.0 required (found $BASH_VERSION)" >&2
        ok=1
    fi
    local free_kb
    free_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$free_kb" ]] && [[ "$free_kb" -lt 51200 ]]; then
        echo "WARN: less than 50MB free disk space" >&2
    fi
    return $ok
}

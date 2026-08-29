#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: core/theme.sh
# Theme system: apply, list, create, save, export themes.
#==============================================================================

[[ -n "${_POS_CORE_THEME_LOADED:-}" ]] && return 0
_POS_CORE_THEME_LOADED=1

# Requires core/utils.sh

POS_THEMES_DIR="${POS_ROOT:-.}/config/themes"
POS_USER_THEMES_DIR="${POS_HOME:-$HOME/.premium-os}/themes"

#----------------------------------------
# Ensure user themes dir exists
#----------------------------------------
_theme_ensure_dirs() { mkdir -p "$POS_USER_THEMES_DIR" 2>/dev/null; }

#----------------------------------------
# list_themes — built-in + user themes
#----------------------------------------
list_themes() {
    local f name
    _theme_ensure_dirs
    for f in "$POS_THEMES_DIR"/*.json "$POS_USER_THEMES_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        if pos_has_jq; then
            name=$(jq -r '.name // empty' "$f" 2>/dev/null)
        else
            name=$(pos_json_get "$f" name 2>/dev/null)
        fi
        name="${name:-$(basename "$f" .json)}"
        [[ "$f" == "$POS_USER_THEMES_DIR"/* ]] && echo "$name (custom)" || echo "$name"
    done | sort -u
}

#----------------------------------------
# theme_file_for <name> → path or empty
#----------------------------------------
theme_file_for() {
    local name="$1"
    [[ "$name" == *" (custom)" ]] && name="${name% (custom)}"
    _theme_ensure_dirs
    if [[ -f "$POS_USER_THEMES_DIR/$name.json" ]]; then echo "$POS_USER_THEMES_DIR/$name.json"
    elif [[ -f "$POS_THEMES_DIR/$name.json" ]]; then echo "$POS_THEMES_DIR/$name.json"; fi
}

#----------------------------------------
# get_current_theme — from active profile, else settings default
#----------------------------------------
get_current_theme() {
    local prof="${POS_HOME:-$HOME/.premium-os}/settings.json"
    local active theme=""
    active=$(pos_json_get "$prof" active_profile 2>/dev/null)
    if [[ -n "$active" && -f "${POS_HOME:-$HOME/.premium-os}/profiles/$active.json" ]]; then
        theme=$(pos_json_get "${POS_HOME:-$HOME/.premium-os}/profiles/$active.json" theme.name 2>/dev/null)
    fi
    [[ -z "$theme" ]] && theme=$(pos_json_get "$prof" ui.theme 2>/dev/null)
    echo "${theme:-dark}"
}

#----------------------------------------
# apply_theme <name> — validate, then write into active profile + settings
#----------------------------------------
apply_theme() {
    local name="$1" file pdir ip
    file=$(theme_file_for "$name")
    [[ -z "$file" ]] && { pos_error "Theme '$name' not found."; return 1; }

    # Self-heal a half-installed data dir instead of failing silently.
    if [[ ! -f "${POS_HOME:-$HOME/.premium-os}/settings.json" ]]; then
        pos_ensure_dirs >/dev/null 2>&1
        pos_default_settings >/dev/null 2>&1
    fi

    # Validate JSON themes
    if pos_has_jq && ! jq empty "$file" 2>/dev/null; then
        pos_error "Theme file is corrupted (invalid JSON)."
        return 1
    fi

    # Update active profile theme reference
    ip="${POS_HOME:-$HOME/.premium-os}/settings.json"
    local active; active=$(pos_json_get "$ip" active_profile)
    if [[ -n "$active" ]]; then
        pdir="${POS_HOME:-$HOME/.premium-os}/profiles/$active.json"
        if [[ -f "$pdir" ]] && pos_has_jq; then
            local tmp="$pdir.pos_tmp"
            # Copy the full theme object from the theme file into the profile
            jq --arg n "$name" --slurpfile t "$file" '
                .theme.name = $n |
                .theme.primary    = ($t[0].colors.primary    // .theme.primary) |
                .theme.secondary  = ($t[0].colors.secondary  // .theme.secondary) |
                .theme.accent     = ($t[0].colors.accent     // .theme.accent) |
                .theme.background = ($t[0].colors.background // .theme.background) |
                .theme.foreground = ($t[0].colors.foreground // .theme.foreground) |
                .theme.gradient   = ($t[0].gradient          // .theme.gradient) |
                .theme.font       = ($t[0].font.family       // .theme.font) |
                .theme.font_size  = ($t[0].font.size         // .theme.font_size)
            ' "$pdir" >"$tmp" && mv "$tmp" "$pdir"
        fi
    fi
    if ! pos_json_set "$ip" ui.theme "$name" >/dev/null 2>&1; then
        pos_error "Could not record theme in settings."
        return 1
    fi

    # Trigger plugin hook if plugin manager is loaded
    if declare -f pos_emit_hook >/dev/null 2>&1; then pos_emit_hook "theme:applied" "$name"; fi
    pos_ok "Theme '${name}' applied."
    return 0
}

#----------------------------------------
# theme_preview <name> — ANSI colored swatch preview
#----------------------------------------
theme_preview() {
    local name="$1" file primary secondary accent bg fg
    file=$(theme_file_for "$name")
    [[ -z "$file" ]] && { pos_error "Theme '$name' not found."; return 1; }
    if pos_has_jq; then
        primary=$(jq -r '.colors.primary    // "#00D9FF"' "$file")
        secondary=$(jq -r '.colors.secondary  // "#FF006E"' "$file")
        accent=$(jq -r '.colors.accent     // "#00FF41"' "$file")
        bg=$(jq -r '.colors.background // "#0A0E27"' "$file")
        fg=$(jq -r '.colors.foreground // "#FFFFFF"' "$file")
    else
        primary=$(pos_json_get "$file" colors.primary); primary="${primary:-#00D9FF}"
        secondary=$(pos_json_get "$file" colors.secondary); secondary="${secondary:-#FF006E}"
        accent=$(pos_json_get "$file" colors.accent); accent="${accent:-#00FF41}"
        bg=$(pos_json_get "$file" colors.background); bg="${bg:-#0A0E27}"
        fg=$(pos_json_get "$file" colors.foreground); fg="${fg:-#FFFFFF}"
    fi

    emit_swatch() { # $1=hex $2=label
        local r g b out=""
        if pos_is_hex_color "$1"; then
            out=$(pos_hex_to_rgb "$1")
            read -r r g b <<<"$out"
            printf '\033[38;2;%d;%d;%dm█■%s\033[0m %-8s' "$r" "$g" "$b" "\033[38;2;${r};${g};${b}m" "$2"
        else
            printf '%-8s' "$2"
        fi
    }

    echo -e "  ${POS_BOLD}Theme preview: $name${POS_RESET}"
    echo -n "  "
    emit_swatch "$primary" "primary"
    echo -n "  "
    emit_swatch "$secondary" "secondary"
    echo -n "  "
    emit_swatch "$accent" "accent"
    echo -n "  "
    emit_swatch "$bg" "bg"
    echo -n "  "
    emit_swatch "$fg" "fg"
    echo
    echo "  ──────────────────────────────────────"
}

#----------------------------------------
# create_custom_theme <name> — interactive creation → JSON in user dir
#----------------------------------------
create_custom_theme() {
    local name="${1:-}"
    [[ -z "$name" ]] && name=$(pos_prompt "Theme name")
    pos_is_safe_name "$name" || { pos_error "Invalid theme name (letters/digits/._-)."; return 1; }
    _theme_ensure_dirs

    local primary secondary accent bg fg font grad_style
    primary=$(pos_prompt "Primary color (HEX)" "#00D9FF")
    pos_is_hex_color "$primary" || primary="#00D9FF"
    secondary=$(pos_prompt "Secondary color (HEX)" "#FF006E")
    pos_is_hex_color "$secondary" || secondary="#FF006E"
    accent=$(pos_prompt "Accent color (HEX)" "#00FF41")
    pos_is_hex_color "$accent" || accent="#00FF41"
    bg=$(pos_prompt "Background color (HEX)" "#0A0E27")
    pos_is_hex_color "$bg" || bg="#0A0E27"
    fg=$(pos_prompt "Foreground color (HEX)" "#FFFFFF")
    pos_is_hex_color "$fg" || fg="#FFFFFF"
    font=$(pos_prompt "Font family" "Fira Code")
    grad_style=$(pos_prompt "Gradient (linear/radial)" "linear")

    cat > "$POS_USER_THEMES_DIR/$name.json" <<JSON
{
  "name": "$name",
  "author": "${USER:-premium}",
  "colors": {
    "primary": "$primary",
    "secondary": "$secondary",
    "accent": "$accent",
    "background": "$bg",
    "foreground": "$fg",
    "warning": "#FFD700",
    "danger": "#FF006E"
  },
  "font": {"family": "$font", "size": 14},
  "gradient": "$grad_style",
  "border": {"width": 1, "style": "solid", "radius": 8, "glow": true},
  "blur": {"enabled": true, "amount": 10},
  "emoji": true
}
JSON
    chmod 600 "$POS_USER_THEMES_DIR/$name.json" 2>/dev/null
    pos_ok "Theme '$name' saved."
}

#----------------------------------------
# export_theme <name> <out_path>
#----------------------------------------
export_theme() {
    local name="$1" out file
    out="${2:-${PWD}/${name}.theme.json}"
    file=$(theme_file_for "$name")
    [[ -z "$file" ]] && { pos_error "Theme '$name' not found."; return 1; }
    cp "$file" "$out" || return 1
    pos_ok "Exported: $out"
}

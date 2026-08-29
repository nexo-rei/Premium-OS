#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: core/profile.sh
# Multi-profile CRUD: create, switch, delete, duplicate, import/export, merge.
# Storage: ~/.premium-os/profiles/<name>.json
#==============================================================================

[[ -n "${_POS_CORE_PROFILE_LOADED:-}" ]] && return 0
_POS_CORE_PROFILE_LOADED=1

# Requires core/utils.sh and (optionally) core/theme.sh for hook emission

POS_PROFILES_DIR="${POS_HOME:-$HOME/.premium-os}/profiles"
POS_SETTINGS_FILE_P="${POS_HOME:-$HOME/.premium-os}/settings.json"

_profiles_ensure() { mkdir -p "$POS_PROFILES_DIR" 2>/dev/null; }

profile_exists() { [[ -n "$1" ]] && [[ -f "$POS_PROFILES_DIR/$1.json" ]]; }

get_active_profile() {
    local a; a=$(pos_json_get "$POS_SETTINGS_FILE_P" active_profile 2>/dev/null)
    echo "${a:-default}"
}

get_profile_name() { get_active_profile; }

list_profiles() {
    local f name
    _profiles_ensure
    for f in "$POS_PROFILES_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        if pos_has_jq; then
            name=$(jq -r '.name // empty' "$f" 2>/dev/null)
        else
            name=$(pos_json_get "$f" name 2>/dev/null)
        fi
        echo "${name:-$(basename "$f" .json)}"
    done
}

#----------------------------------------
# create_profile <name> — from template (clone of "default" or factory JSON)
#----------------------------------------
create_profile() {
    local name="$1"
    pos_is_safe_name "$name" || { pos_error "Invalid profile name."; return 1; }
    _profiles_ensure
    profile_exists "$name" && { pos_error "Profile '$name' already exists."; return 1; }

    local src="$POS_PROFILES_DIR/default.json"
    if [[ -f "$src" ]]; then
        cp "$src" "$POS_PROFILES_DIR/$name.json"
    else
        cat > "$POS_PROFILES_DIR/$name.json" <<'JSON'
{"name":"","theme":{"name":"dark","primary":"#00D9FF","secondary":"#FF006E","accent":"#00FF41","background":"#0A0E27","foreground":"#FFFFFF","gradient":"neon","font":"Fira Code","font_size":14},"shell":"bash","aliases":{},"hotkeys":{},"startup_commands":[],"banner":"Welcome to Premium-OS"}
JSON
    fi
    if pos_has_jq; then
        local tmp="$POS_PROFILES_DIR/$name.json.pos_tmp"
        jq --arg n "$name" --arg c "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '.name=$n | .created=$c' "$POS_PROFILES_DIR/$name.json" >"$tmp" \
            && mv "$tmp" "$POS_PROFILES_DIR/$name.json"
    else
        # Fallback: patch the name field textually
        sed -i -e '0,/"name"[[:space:]]*:[[:space:]]*"[^"]*"/s//"name": "'"$name"'"/' \
            "$POS_PROFILES_DIR/$name.json"
    fi
    chmod 600 "$POS_PROFILES_DIR/$name.json" 2>/dev/null
    pos_ok "Profile '$name' created."
}

#----------------------------------------
# switch_profile <name> — sets active_profile + validates theme
#----------------------------------------
switch_profile() {
    local name="$1"
    [[ -z "$name" ]] && { pos_error "Usage: switch_profile <name>"; return 1; }
    profile_exists "$name" || { pos_error "Profile '$name' not found."; return 1; }
    # Validate JSON before adopting
    if pos_has_jq && ! jq empty "$POS_PROFILES_DIR/$name.json" 2>/dev/null; then
        pos_error "Profile '$name' is corrupted — not switching."
        return 1
    fi
    pos_json_set "$POS_SETTINGS_FILE_P" active_profile "$name" >/dev/null
    if declare -f pos_emit_hook >/dev/null 2>&1; then pos_emit_hook "profile:switched" "$name"; fi
    pos_ok "Switched to profile '$name'."
}

#----------------------------------------
# delete_profile <name> — cannot delete "default"
#----------------------------------------
delete_profile() {
    local name="$1"
    [[ "$name" == "default" ]] && { pos_error "The 'default' profile is protected."; return 1; }
    profile_exists "$name" || { pos_error "Profile '$name' not found."; return 1; }
    # If it's the active profile, fall back to default first
    [[ "$(get_active_profile)" == "$name" ]] && switch_profile "default" >/dev/null
    rm -f "$POS_PROFILES_DIR/$name.json"
    pos_ok "Profile '$name' deleted."
}

#----------------------------------------
# duplicate_profile <src> <dest>
#----------------------------------------
duplicate_profile() {
    local src="$1" dest="$2"
    profile_exists "$src" || { pos_error "Source '$src' not found."; return 1; }
    pos_is_safe_name "$dest" || { pos_error "Invalid destination name."; return 1; }
    profile_exists "$dest" && { pos_error "'$dest' already exists."; return 1; }
    cp "$POS_PROFILES_DIR/$src.json" "$POS_PROFILES_DIR/$dest.json"
    if pos_has_jq; then
        local tmp="$POS_PROFILES_DIR/$dest.json.pos_tmp"
        jq --arg n "$dest" '.name=$n' "$POS_PROFILES_DIR/$dest.json" >"$tmp" \
            && mv "$tmp" "$POS_PROFILES_DIR/$dest.json" \
            || mv "$POS_PROFILES_DIR/$dest.json.pos_tmp" "$POS_PROFILES_DIR/$dest.json"
    else
        sed -i -e '0,/"name"[[:space:]]*:[[:space:]]*"[^"]*"/s//"name": "'"$dest"'"/' \
            "$POS_PROFILES_DIR/$dest.json"
    fi
    chmod 600 "$POS_PROFILES_DIR/$dest.json" 2>/dev/null
    pos_ok "Duplicated '$src' → '$dest'."
}

#----------------------------------------
# rename_profile <old> <new>
#----------------------------------------
rename_profile() {
    local old="$1" new="$2"
    [[ "$old" == "default" ]] && { pos_error "The 'default' profile cannot be renamed."; return 1; }
    profile_exists "$old" || { pos_error "'$old' not found."; return 1; }
    pos_is_safe_name "$new" || { pos_error "Invalid new name."; return 1; }
    profile_exists "$new" && { pos_error "'$new' already exists."; return 1; }
    duplicate_profile "$old" "$new" || return 1
    [[ "$(get_active_profile)" == "$old" ]] && switch_profile "$new" >/dev/null
    rm -f "$POS_PROFILES_DIR/$old.json"
    pos_ok "Renamed '$old' → '$new'."
}

#----------------------------------------
# export_profile <name> [dir] → writes <name>.profile.json
#----------------------------------------
export_profile() {
    local name="$1" dest_dir="${2:-$PWD}" out
    profile_exists "$name" || { pos_error "'$name' not found."; return 1; }
    mkdir -p "$dest_dir" 2>/dev/null
    out="$dest_dir/${name}.profile.json"
    cp "$POS_PROFILES_DIR/$name.json" "$out" || return 1
    pos_ok "Exported: $out"
}

#----------------------------------------
# import_profile <path> — validates and installs a .profile.json
#----------------------------------------
import_profile() {
    local src="$1" name
    [[ -f "$src" ]] || { pos_error "File not found: $src"; return 1; }
    if pos_has_jq && ! jq empty "$src" 2>/dev/null; then
        pos_error "Invalid JSON file."; return 1;
    fi
    if pos_has_jq; then name=$(jq -r '.name // empty' "$src")
    else name=$(pos_json_get "$src" name); fi
    pos_is_safe_name "${name:-}" || { pos_error "Profile has no valid name."; return 1; }
    profile_exists "$name" && { pos_error "Profile '$name' already exists."; return 1; }
    _profiles_ensure
    cp "$src" "$POS_PROFILES_DIR/$name.json"
    chmod 600 "$POS_PROFILES_DIR/$name.json" 2>/dev/null
    pos_ok "Imported profile '$name'."
}

#----------------------------------------
# merge_profile <name> — overlays <name>'s theme/aliases onto active profile
#----------------------------------------
merge_profile() {
    local name="$1" active tmp
    profile_exists "$name" || { pos_error "'$name' not found."; return 1; }
    active=$(get_active_profile)
    [[ "$active" == "$name" ]] && { pos_warn "Nothing to merge (same profile)."; return 0; }
    pos_has_jq || { pos_error "jq required for merge."; return 1; }
    tmp="$POS_PROFILES_DIR/$active.json.pos_tmp"
    jq --slurpfile o "$POS_PROFILES_DIR/$name.json" '
        .theme = ($o[0].theme // .theme) |
        .aliases = ((.aliases // {}) + ($o[0].aliases // {})) |
        .hotkeys = ((.hotkeys // {}) + ($o[0].hotkeys // {}))
    ' "$POS_PROFILES_DIR/$active.json" >"$tmp" && mv "$tmp" "$POS_PROFILES_DIR/$active.json"
    pos_ok "Merged '$name' into active profile '$active'."
}

#----------------------------------------
# profile_preview <name>
#----------------------------------------
profile_preview() {
    local name="$1" f
    f="$POS_PROFILES_DIR/$name.json"
    [[ -f "$f" ]] || { pos_error "'$name' not found."; return 1; }
    echo -e "${POS_BOLD}Profile: ${POS_CYAN}$name${POS_RESET}"
    if pos_has_jq; then
        echo "  theme   : $(jq -r '.theme.name // "?"' "$f")"
        echo "  shell   : $(jq -r '.shell // "?"' "$f")"
        echo "  aliases : $(jq -r '(.aliases // {}) | keys | join(", ")' "$f")"
        echo "  hotkeys : $(jq -r '(.hotkeys // {}) | keys | join(", ")' "$f")"
        echo "  banner  : $(jq -r '.banner // ""' "$f")"
    fi
}

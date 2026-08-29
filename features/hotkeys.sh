#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/hotkeys.sh
# Custom hotkey registry with conflict detection.
# Storage: ~/.premium-os/hotkeys.conf  (KEY=COMMAND.lines, # comments)
#==============================================================================

[[ -n "${_POS_FEAT_HOTKEYS_LOADED:-}" ]] && return 0
_POS_FEAT_HOTKEYS_LOADED=1

POS_HOTKEYS_FILE="${POS_HOME:-$HOME/.premium-os}/hotkeys.conf"

_hk_ensure() { mkdir -p "${POS_HOTKEYS_FILE%/*}"; touch "$POS_HOTKEYS_FILE"; }

#----------------------------------------
# _hk_normalize <key> — canonical form: Ctrl+Shift+P (letters uppercase)
#----------------------------------------
_hk_normalize() {
    local key="$1" out="" part
    # split by '+', title-case modifiers, uppercase the final key
    IFS='+' read -ra parts <<<"$key"
    local i n=${#parts[@]}
    for (( i=0; i<n; i++ )); do
        part="${parts[$i]}"
        # trim whitespace
        part="${part#"${part%%[![:space:]]*}"}"; part="${part%"${part##*[![:space:]]}"}"
        [[ -z "$part" ]] && continue
        if (( i == n-1 )); then
            # final key char: single letters uppercase
            if [[ ${#part} -eq 1 ]]; then part="${part^^}"; else part="${part^}"; fi
        else
            part="${part^}"  # modifiers Capitalized: ctrl→Ctrl, shift→Shift, alt→Alt
        fi
        out+="${out:++}$part"
    done
    echo "$out"
}

_hk_reserved() {
    case "$1" in
        Ctrl+C|Ctrl+Z|Ctrl+D|Ctrl+L|Ctrl+Q|Ctrl+S) return 0 ;;
    esac
    return 1
}

#----------------------------------------
# register_hotkey <key> <command> — with conflict detection
#----------------------------------------
register_hotkey() {
    local key cmd
    key=$(_hk_normalize "$1"); cmd="$2"
    [[ -z "$key" || -z "$cmd" ]] && { pos_error "Usage: register_hotkey <key> <command>"; return 1; }
    # Safety: command injection guard on the command payload
    if [[ "$cmd" == *$'\n'* || "$cmd" == *$'\r'* ]]; then
        pos_error "Invalid command."
        return 1
    fi
    if _hk_reserved "$key"; then
        pos_error "$key is reserved by the terminal — pick another."
        return 1
    fi
    _hk_ensure
    if grep -q "^${key}=" "$POS_HOTKEYS_FILE" 2>/dev/null; then
        pos_error "Conflict: $key already bound to '$(grep "^${key}=" "$POS_HOTKEYS_FILE" | cut -d= -f2-)'."
        return 1
    fi
    echo "${key}=${cmd}" >> "$POS_HOTKEYS_FILE"
    pos_ok "Bound $key → $cmd"
}

#----------------------------------------
# remove_hotkey <key>
#----------------------------------------
remove_hotkey() {
    local key; key=$(_hk_normalize "$1")
    _hk_ensure
    grep -q "^${key}=" "$POS_HOTKEYS_FILE" 2>/dev/null || { pos_error "$key not bound."; return 1; }
    local tmp="$POS_HOTKEYS_FILE.tmp"
    grep -v "^${key}=" "$POS_HOTKEYS_FILE" > "$tmp" && mv "$tmp" "$POS_HOTKEYS_FILE"
    pos_ok "Removed $key"
}

#----------------------------------------
# list_hotkeys
#----------------------------------------
list_hotkeys() {
    _hk_ensure
    local n=0
    while IFS='=' read -r k v; do
        [[ -z "$k" || "$k" == \#* ]] && continue
        printf '  %b%-18s%b %s\n' "$POS_YELLOW" "$k" "$POS_RESET" "$v"
        n=$((n+1))
    done < "$POS_HOTKEYS_FILE"
    (( n == 0 )) && echo "  (no hotkeys yet)"
    return 0
}

#----------------------------------------
# test_hotkey <key> — dry-run display of mapping execution
#----------------------------------------
test_hotkey() {
    local key; key=$(_hk_normalize "$1")
    _hk_ensure
    local cmd; cmd=$(grep "^${key}=" "$POS_HOTKEYS_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
    [[ -z "$cmd" ]] && { pos_error "$key not bound."; return 1; }
    echo -e "  $key → ${POS_CYAN}$cmd${POS_RESET} (not executed in test mode)"
    return 0
}

#----------------------------------------
# export_hotkeys <out_file>
#----------------------------------------
export_hotkeys() {
    local out="${1:-$PWD/hotkeys-export.conf}"
    cp "$POS_HOTKEYS_FILE" "$out" && pos_ok "Exported → $out"
}

#----------------------------------------
# hotkeys_menu — interactive UI
#----------------------------------------
hotkeys_menu() {
    local c
    while true; do
        _menu_header "⌨ Hotkeys" ""
        list_hotkeys
        echo
        c=$(_menu_select "choose" "Add hotkey" "Remove hotkey" "Test hotkey" "Export" "Back")
        case "$c" in
            1) echo -e "  ${POS_GRAY}Press the key combo as text, e.g. Ctrl+Shift+P${POS_RESET}"
               local k m; k=$(pos_prompt "Hotkey"); m=$(pos_prompt "Command")
               [[ -n "$k" && -n "$m" ]] && register_hotkey "$k" "$m"; pos_press_enter ;;
            2) local k; k=$(pos_prompt "Hotkey to remove"); [[ -n "$k" ]] && remove_hotkey "$k"; pos_press_enter ;;
            3) local k; k=$(pos_prompt "Hotkey to test"); [[ -n "$k" ]] && test_hotkey "$k"; pos_press_enter ;;
            4) export_hotkeys; pos_press_enter ;;
            5|""|q) return ;;
        esac
    done
}

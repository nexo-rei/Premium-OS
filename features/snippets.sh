#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/snippets.sh
# Command snippet library: categories, search, copy, edit, delete, execute.
# Storage: ~/.premium-os/snippets.json
#==============================================================================

[[ -n "${_POS_FEAT_SNIPPETS_LOADED:-}" ]] && return 0
_POS_FEAT_SNIPPETS_LOADED=1

POS_SNIPPETS_FILE="${POS_HOME:-$HOME/.premium-os}/snippets.json"

_snip_ensure() {
    mkdir -p "${POS_SNIPPETS_FILE%/*}"
    [[ -f "$POS_SNIPPETS_FILE" ]] && return 0
    echo '{"snippets":[]}' > "$POS_SNIPPETS_FILE"
}

_snip_next_id() {
    if pos_has_jq; then
        jq '[.snippets[].id] | max // 0 | . + 1' "$POS_SNIPPETS_FILE" 2>/dev/null
    else
        echo $(( $(wc -l < "$POS_SNIPPETS_FILE") + 1 ))
    fi
}

#----------------------------------------
# add_snippet <category> <name> <command>
#----------------------------------------
add_snippet() {
    local cat="$1" name="$2" cmd="$3"
    [[ -z "$name" || -z "$cmd" ]] && { pos_error "Usage: add_snippet <category> <name> <command>"; return 1; }
    _snip_ensure
    if ! pos_has_jq; then
        pos_error "jq required for snippet storage."
        return 1
    fi
    local id; id=$(_snip_next_id)
    local tmp="$POS_SNIPPETS_FILE.tmp"
    jq --arg id "$id" --arg c "${cat:-General}" --arg n "$name" --arg cmd "$cmd" \
        '.snippets += [{"id":($id|tonumber),"category":$c,"name":$n,"command":$cmd}]' \
        "$POS_SNIPPETS_FILE" > "$tmp" && mv "$tmp" "$POS_SNIPPETS_FILE"
    pos_ok "Snippet #$id added."
}

#----------------------------------------
# remove_snippet <id>
#----------------------------------------
remove_snippet() {
    local id="$1"
    _snip_ensure
    pos_has_jq || { pos_error "jq required."; return 1; }
    local tmp="$POS_SNIPPETS_FILE.tmp"
    jq --arg id "$id" '.snippets |= map(select(.id != ($id|tonumber)))' \
        "$POS_SNIPPETS_FILE" > "$tmp" && mv "$tmp" "$POS_SNIPPETS_FILE"
    pos_ok "Snippet #$id removed."
}

#----------------------------------------
# list_snippets [category]
#----------------------------------------
list_snippets() {
    _snip_ensure
    pos_has_jq || { pos_error "jq required."; return 1; }
    local filter="${1:-}"
    local q='.snippets[]'
    [[ -n "$filter" ]] && q=".snippets[] | select(.category == \"$filter\")"
    jq -r "$q | \"  \(.id)  [\(.category)] \(.name)\n       $ \(.command)\"" "$POS_SNIPPETS_FILE" 2>/dev/null \
        | sed "s/^  /  ${C:-}/" |
        while IFS= read -r line; do echo -e "$line"; done
}

_snip_categories() {
    pos_has_jq && jq -r '.snippets[].category' "$POS_SNIPPETS_FILE" 2>/dev/null | sort -u
}

#----------------------------------------
# search_snippet <term>
#----------------------------------------
search_snippet() {
    local term="$1"
    _snip_ensure
    pos_has_jq || { pos_error "jq required."; return 1; }
    jq -r --arg t "$term" '
      .snippets[] | select((.name|ascii_downcase|contains($t|ascii_downcase))
                           or (.command|ascii_downcase|contains($t|ascii_downcase)))
      | "  \(.id)  [\(.category)] \(.name)\n       $ \(.command)"' "$POS_SNIPPETS_FILE" 2>/dev/null
}

#----------------------------------------
# get_snippet_command <id>
#----------------------------------------
get_snippet_command() {
    local id="$1"
    pos_has_jq || return 1
    jq -r --arg id "$id" '.snippets[] | select(.id == ($id|tonumber)) | .command' \
        "$POS_SNIPPETS_FILE" 2>/dev/null
}

#----------------------------------------
# execute_snippet <id> — explicit confirmation before running
#----------------------------------------
execute_snippet() {
    local id="$1" cmd
    cmd=$(get_snippet_command "$id")
    [[ -z "$cmd" ]] && { pos_error "Snippet #$id not found."; return 1; }
    echo -e "  Run: ${POS_CYAN}$cmd${POS_RESET}"
    if pos_confirm "Execute snippet #$id?"; then
        eval "$cmd"
    fi
}

#----------------------------------------
# _snip_copy <id> — copy-to-clipboard helpers
#----------------------------------------
_snip_copy() {
    local id="$1" cmd; cmd=$(get_snippet_command "$id")
    [[ -z "$cmd" ]] && { pos_error "Snippet #$id not found."; return 1; }
    if command -v termux-clipboard-set >/dev/null 2>&1; then
        printf '%s' "$cmd" | termux-clipboard-set && pos_ok "Copied to clipboard."
    elif command -v xclip >/dev/null 2>&1; then
        printf '%s' "$cmd" | xclip -selection clipboard && pos_ok "Copied."
    else
        echo "$cmd"
        pos_log "(no clipboard tool — command printed above)"
    fi
}

#----------------------------------------
# snippets_menu — interactive UI
#----------------------------------------
snippets_menu() {
    local c
    while true; do
        _menu_header "📚 Snippets" ""
        echo -e " ${POS_GRAY}categories:${POS_RESET} $(_snip_categories | tr '\n' ' ')"
        echo
        c=$(_menu_select "choose" \
            "Browse all" "By category" "Search" "Add snippet" \
            "Copy to clipboard" "Execute snippet" "Delete snippet" "Back")
        case "$c" in
            1) list_snippets; pos_press_enter ;;
            2) local cat; cat=$(pos_prompt "Category"); [[ -n "$cat" ]] && list_snippets "$cat"; pos_press_enter ;;
            3) local t; t=$(pos_prompt "Search"); [[ -n "$t" ]] && search_snippet "$t"; pos_press_enter ;;
            4) local cat n cmd; cat=$(pos_prompt "Category" "General"); n=$(pos_prompt "Name")
               cmd=$(pos_prompt "Command"); [[ -n "$n" && -n "$cmd" ]] && add_snippet "$cat" "$n" "$cmd"
               pos_press_enter ;;
            5) local i; i=$(pos_prompt "Snippet id"); [[ -n "$i" ]] && _snip_copy "$i"; pos_press_enter ;;
            6) local i; i=$(pos_prompt "Snippet id"); [[ -n "$i" ]] && execute_snippet "$i"; pos_press_enter ;;
            7) local i; i=$(pos_prompt "Snippet id"); [[ -n "$i" ]] && remove_snippet "$i"; pos_press_enter ;;
            8|""|q) return ;;
        esac
    done
}

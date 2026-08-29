#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/smart-suggestions.sh
# Context-aware theme suggestions: time of day, task, learned preferences.
# Privacy-first: all learning stays in ~/.premium-os — opt-in telemetry only.
#==============================================================================

[[ -n "${_POS_FEAT_SMART_LOADED:-}" ]] && return 0
_POS_FEAT_SMART_LOADED=1

POS_SMART_FILE="${POS_HOME:-$HOME/.premium-os}/history/smart-prefs.json"

_smart_init() {
    mkdir -p "${POS_SMART_FILE%/*}"
    [[ -f "$POS_SMART_FILE" ]] && return 0
    cat > "$POS_SMART_FILE" <<'JSON'
{"accepted":{},"rejected":{},"shown":{},"last_rotation":""}
JSON
}

#----------------------------------------
# analyze_usage_pattern — derive a light usage signal
# echoes "dev|system|general"
#----------------------------------------
analyze_usage_pattern() {
    local hf="$HOME/.bash_history"
    [[ -f "$HOME/.zsh_history" ]] && hf="$HOME/.zsh_history"
    [[ -f "$hf" ]] || { echo "general"; return 0; }
    local dev sys
    dev=$(tail -n 200 "$hf" 2>/dev/null | grep -cE '\b(git|npm|node|python|pip|gcc|make|vim|nvim|code)\b' || echo 0)
    sys=$(tail -n 200 "$hf" 2>/dev/null | grep -cE '\b(apt|pkg|df|du|ps|top|kill|mount)\b' || echo 0)
    if   (( dev > sys && dev >= 3 )); then echo "dev"
    elif (( sys > dev && sys >= 3 )); then echo "system"
    else echo "general"
    fi
}

#----------------------------------------
# detect_active_task — from pattern (kebap-case alias)
#----------------------------------------
detect_active_task() { analyze_usage_pattern; }

#----------------------------------------
# _smart_candidates <pattern> <hour> → ranked theme list
#----------------------------------------
_smart_candidates() {
    local pattern="$1" hour="$2"
    local day_themes=(light neon) night_themes=(dark dracula)
    local task_hint=""
    case "$pattern" in
        dev)    task_hint="minimal dracula dark" ;;
        system) task_hint="dracula dark neon" ;;
        *)      task_hint="dark light neon dracula minimal" ;;
    esac
    local bucket
    if (( hour >= 7 && hour < 19 )); then bucket="${day_themes[*]}"
    else bucket="${night_themes[*]}"; fi
    # merge: task hint first, then time bucket, dedup
    echo "$task_hint $bucket" | tr ' ' '\n' | awk '!seen[$0]++'
}

#----------------------------------------
# suggest_theme — compute + optionally present a suggestion
#----------------------------------------
suggest_theme() {
    _smart_init
    [[ "$(pos_config_get smart.suggestions_enabled true)" != "true" ]] && {
        pos_log "Smart suggestions are disabled (settings → toggle)."
        return 0
    }
    local hour pattern current candidates chosen score
    hour=$(date +%H); hour=$((10#$hour))
    pattern=$(analyze_usage_pattern)
    current=$(get_current_theme 2>/dev/null || echo dark)
    candidates=$(_smart_candidates "$pattern" "$hour")

    # avoid suggesting the current theme or frequently rejected ones
    chosen=""
    while read -r cand; do
        [[ -z "$cand" || "$cand" == "$current" ]] && continue
        local rej
        rej=$(pos_json_get "$POS_SMART_FILE" "rejected.$cand" 2>/dev/null)
        [[ "$rej" =~ ^[0-9]+$ ]] && (( rej >= 3 )) && continue
        chosen="$cand"; break
    done <<< "$candidates"

    if [[ -z "$chosen" ]]; then
        pos_log "You already have the best theme right now. 👍"
        return 0
    fi

    # confidence: task match +50, time match +30, prior accepts +20 capped 95
    score=45
    [[ " $candidates " == *" $current "* ]] || score=$((score+10))
    local acc; acc=$(pos_json_get "$POS_SMART_FILE" "accepted.$chosen" 2>/dev/null)
    [[ "$acc" =~ ^[0-9]+$ && $acc -gt 0 ]] && score=$((score + 15 < 95 ? score + 15 : 95))
    (( hour >= 7 && hour < 19 && ( chosen == light || chosen == neon ) )) && score=$((score+15))
    (( ( hour < 7 || hour >= 19 ) && ( chosen == dark || chosen == dracula ) )) && score=$((score+15))

    echo
    echo -e "  ${POS_PURPLE}${POS_BOLD}🤖 Suggestion${POS_RESET} ${POS_GRAY}(${score}% match · task: ${pattern})${POS_RESET}"
    echo -e "  Try the ${POS_CYAN}${POS_BOLD}${chosen}${POS_RESET} theme for this time of day?"
    theme_preview "$chosen" 2>/dev/null || true
    _smart_bump "shown" "$chosen"
    if pos_confirm "Apply '$chosen' now?"; then
        apply_theme "$chosen" && _smart_bump "accepted" "$chosen"
    else
        _smart_bump "rejected" "$chosen"
        pos_log "No problem — I'll tune future suggestions."
    fi
}

_smart_bump() { # $1=bucket $2=theme
    pos_has_jq || return 0
    local f="$POS_SMART_FILE" tmp="$f.tmp" cur
    cur=$(jq -r ".$1[\"$2\"] // 0" "$f" 2>/dev/null || echo 0)
    jq ".$1[\"$2\"] = $((cur+1))" "$f" >"$tmp" 2>/dev/null && mv "$tmp" "$f"
}

#----------------------------------------
# get_suggestion_score — recompute for testing
#----------------------------------------
get_suggestion_score() { suggest_theme >/dev/null 2>&1; echo "see interactive"; }

#----------------------------------------
# learn_preference <theme> accept|reject — manual/CPi hook
#----------------------------------------
learn_preference() {
    _smart_init
    local theme="$1" action="$2"
    case "$action" in
        accept|accepted) _smart_bump accepted "$theme" ;;
        reject|rejected) _smart_bump rejected "$theme" ;;
    esac
}

#----------------------------------------
# weekly_rotation — rotate favorite by week number
#----------------------------------------
weekly_rotation() {
    _smart_init
    local week rotation themes
    week=$(date +%V)
    themes=$(list_themes 2>/dev/null | sed 's/ (custom)//' | tr '\n' ' ')
    local count; count=$(echo "$themes" | wc -w)
    (( count == 0 )) && return 1
    local idx=$(( (10#$week) % count + 1 ))
    local chosen; chosen=$(echo "$themes" | awk -v i="$idx" '{print $i}')
    [[ -n "$chosen" ]] && apply_theme "$chosen"
}

#----------------------------------------
# fetch_weather — optional; only used with opt-in
#----------------------------------------
fetch_weather() {
    [[ "$(pos_config_get smart.telemetry_opt_in false)" != "true" ]] && return 1
    command -v curl >/dev/null 2>&1 || return 1
    curl -sf --max-time 2 "https://wttr.in/?format=%C" 2>/dev/null | head -1
}

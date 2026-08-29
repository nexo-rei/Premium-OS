#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/optimization.sh
# Startup speed optimizer: measure boot time, find slow init lines,
# apply safe optimizations, before/after comparison.
#==============================================================================

[[ -n "${_POS_FEAT_OPT_LOADED:-}" ]] && return 0
_POS_FEAT_OPT_LOADED=1

POS_OPT_STATE="${POS_HOME:-$HOME/.premium-os}/cache/opt-state.json"
SHELL_RC="${SHELL_RC:-$HOME/.bashrc}"
[[ -n "${ZSH_NAME:-}" || -f "$HOME/.zshrc" && ! -f "$SHELL_RC" ]] && SHELL_RC="$HOME/.zshrc"

#----------------------------------------
# benchmark_startup — measure shell rc sourcing time (ms)
#----------------------------------------
benchmark_startup() {
    local rc="$SHELL_RC"
    [[ -f "$rc" ]] || { echo "0"; return 0; }
    # Time a subshell that sources the rc (non-interactive-ish)
    local t0 t1
    t0=$(date +%s%N)
    bash -norc -c ". '$rc' >/dev/null 2>&1; true" 2>/dev/null
    t1=$(date +%s%N)
    echo $(( (t1 - t0) / 1000000 ))
}

#----------------------------------------
# optimize_startup_scan — analyze rc file, find heavy patterns
#----------------------------------------
optimize_startup_scan() {
    local rc="$SHELL_RC"
    echo -e "${POS_BOLD}Startup scan of ${rc}${POS_RESET}"
    [[ -f "$rc" ]] || { pos_warn "No rc file found at $rc"; return 1; }

    local boot_ms; boot_ms=$(benchmark_startup)
    echo -e "  measured rc source time: ${POS_CYAN}${boot_ms}ms${POS_RESET}"
    echo

    local findings=0 line_no=0
    while IFS= read -r line; do
        line_no=$((line_no+1))
        case "$line" in
            *\$\(*curl*|*\$\(*wget*|*curl\ http*|*wget\ http*)
                printf '  %bL%-4d%b network call at boot: %s\n' "$POS_YELLOW" "$line_no" "$POS_RESET" "${line:0:60}"
                findings=$((findings+1)) ;;
            *npm\ *|*nvm*|*pyenv*|*conda*)
                printf '  %bL%-4d%b heavy version manager init: %s\n' "$POS_YELLOW" "$line_no" "$POS_RESET" "${line:0:60}"
                findings=$((findings+1)) ;;
            *fortune*|*cowsay*|*figlet*|*neofetch*|*screenfetch*)
                printf '  %bL%-4d%b splash program at boot: %s\n' "$POS_GRAY" "$line_no" "$POS_RESET" "${line:0:60}"
                findings=$((findings+1)) ;;
        esac
        # Warn on repeated expensive subshells
        if [[ "$line" == *'$('*')'*'$('*')'* ]]; then
            printf '  %bL%-4d%b multiple command substitutions: %s\n' "$POS_GRAY" "$line_no" "$POS_RESET" "${line:0:60}"
            findings=$((findings+1))
        fi
    done < "$rc"

    if (( findings == 0 )); then
        pos_ok "No obvious slow patterns detected."
    else
        echo -e "\n  ${POS_YELLOW}$findings optimization opportunity(ies) found.${POS_RESET}"
    fi
    return 0
}

#----------------------------------------
# optimize_recommend — actionable tips
#----------------------------------------
optimize_recommend() {
    cat <<'TIPS'
  Recommendations:
   1. Lazy-load version managers (nvm/pyenv) on first use.
   2. Move network calls out of rc files into explicit aliases.
   3. Cache prompt git status: run async or on-demand.
   4. Replace splash screens with a cached static banner.
   5. Source Premium-OS last so his fast paths win.
TIPS
}

#----------------------------------------
# optimize_apply — safe one-click tweaks (idempotent markers)
#----------------------------------------
optimize_apply() {
    local rc="$SHELL_RC" changed=0
    [[ -f "$rc" ]] || { pos_warn "No rc file."; return 1; }

    # Marker-guard: append a debounced Premium-OS fast-init block once
    if ! grep -q '# >>> pos-optimize >>>' "$rc"; then
        cat >> "$rc" <<'RC'

# >>> pos-optimize >>>
# Premium-OS startup optimizations (safe, idempotent)
export LESS='-R -F -X'          # no pager for short output
export HISTSIZE=5000
export HISTFILESIZE=10000
shopt -s histappend 2>/dev/null # append, don't clobber history
shopt -s checkwinsize 2>/dev/null
# <<< pos-optimize <<<
RC
        changed=1
    fi

    pos_config_set optimization.applied true bool 2>/dev/null
    local after_ms; after_ms=$(benchmark_startup)

    cat > "$POS_OPT_STATE" <<JSON
{
  "applied": true,
  "rc": "$rc",
  "after_ms": $after_ms,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
    (( changed )) && pos_ok "Optimization block appended to ${rc##*/}" \
                  || pos_ok "Already optimized — nothing new to apply."
    echo -e "  rc source time now: ${POS_CYAN}${after_ms}ms${POS_RESET}"
    if declare -f pos_emit_hook >/dev/null 2>&1; then pos_emit_hook "system:optimized"; fi
}

#----------------------------------------
# optimize_compare — before/after with saved state
#----------------------------------------
optimize_compare() {
    local before after
    before=$(pos_json_get "$POS_OPT_STATE" "before_ms" 2>/dev/null)
    after=$(pos_json_get "$POS_OPT_STATE" "after_ms" 2>/dev/null)
    local cur; cur=$(benchmark_startup)
    echo -e "  before : ${before:-unknown}ms"
    echo -e "  now    : ${cur}ms"
    if [[ -n "$before" && "$before" =~ ^[0-9]+$ && "$before" -gt 0 ]]; then
        local pct=$(( (before - cur) * 100 / before ))
        echo -e "  change : ${pct}% faster" 
    fi
}

#----------------------------------------
# Interactive menu
#----------------------------------------
optimization_menu() {
    local c
    while true; do
        _menu_header "🚀 Startup Optimizer" ""
        c=$(_menu_select "choose" \
            "Scan startup" "Apply one-click optimization" \
            "Recommendations" "Measure boot (before/after)" "Back")
        case "$c" in
            1) optimize_startup_scan; pos_press_enter ;;
            2)
                local b; b=$(benchmark_startup)
                [[ -f "$POS_OPT_STATE" ]] || cat > "$POS_OPT_STATE" <<JSON
{"applied": false, "before_ms": $b, "after_ms": 0, "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
                optimize_apply; pos_press_enter ;;
            3) optimize_recommend; pos_press_enter ;;
            4) optimize_compare; pos_press_enter ;;
            5|""|q) return ;;
        esac
    done
}

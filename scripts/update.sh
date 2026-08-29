#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: scripts/update.sh
# Safe updater: checks for a newer version (git or GitHub API), creates an
# auto-backup before applying, supports rollback on failure.
#==============================================================================
set -o pipefail
POS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export POS_ROOT
export POS_HOME="${POS_HOME:-$HOME/.premium-os}"

# shellcheck disable=SC1090
. "$POS_ROOT/core/init.sh"
. "$POS_ROOT/ui/colors.sh"
. "$POS_ROOT/core/utils.sh"
. "$POS_ROOT/core/config.sh"
. "$POS_ROOT/features/backup-restore.sh" 2>/dev/null || true

POS_REPO_SLUG="${POS_REPO_SLUG:-nexo-rei/Premium-OS}"

#---------------- latest version discovery ----------------
get_latest_version() {
    # 1) git tags when this is a git checkout
    if [[ -d "$POS_ROOT/.git" ]] && command -v git >/dev/null 2>&1; then
        git -C "$POS_ROOT" fetch --tags --quiet 2>/dev/null || true
        git -C "$POS_ROOT" tag --sort=-v:refname 2>/dev/null | grep -E '^v?[0-9]' | head -1 \
            | sed 's/^v//'
        return 0
    fi
    # 2) GitHub releases API fallback
    if command -v curl >/dev/null 2>&1; then
        curl -sf --max-time 5 "https://api.github.com/repos/$POS_REPO_SLUG/releases/latest" 2>/dev/null \
            | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//'
    fi
}

version_gt() { # returns 0 if $1 > $2 (semver-ish)
    [[ "$1" == "$2" ]] && return 1
    local IFS=.
    local i a=($1) b=($2)
    for ((i=0; i<3; i++)); do
        local x=${a[i]:-0} y=${b[i]:-0}
        ((10#$x > 10#$y)) && return 0
        ((10#$x < 10#$y)) && return 1
    done
    return 1
}

#---------------- changelog preview ----------------
show_changelog() {
    local f="$POS_ROOT/docs/CHANGELOG.md"
    if [[ -f "$f" ]]; then
        echo -e "${POS_GRAY}── changelog ──────────────────────────────${POS_RESET}"
        sed -n '2,/^## /{/^## /!p}' "$f" | head -20
        echo -e "${POS_GRAY}───────────────────────────────────────────${POS_RESET}"
    fi
}

#---------------- update apply ----------------
do_update() {
    pos_log "Creating safety backup first…"
    if declare -f create_backup >/dev/null 2>&1; then
        create_backup >/dev/null || pos_warn "Backup failed — continuing anyway."
    fi

    if [[ -d "$POS_ROOT/.git" ]] && command -v git >/dev/null 2>&1; then
        pos_log "Pulling latest…"
        local head_before head_after
        head_before=$(git -C "$POS_ROOT" rev-parse HEAD 2>/dev/null)
        if git -C "$POS_ROOT" pull --ff-only 2>/dev/null; then
            head_after=$(git -C "$POS_ROOT" rev-parse HEAD 2>/dev/null)
            if [[ "$head_before" == "$head_after" ]]; then
                pos_ok "Already up to date."
                return 0
            fi
            pos_ok "Updated to $(cat "$POS_HOME/.version" 2>/dev/null || echo '?')"
            echo "$head_before" > "$POS_HOME/.rollback_commit"
            # Re-run installer steps that are idempotent
            chmod +x "$POS_ROOT/main.sh" "$POS_ROOT/scripts/"*.sh 2>/dev/null
            if declare -f pos_emit_hook >/dev/null 2>&1; then pos_emit_hook "update:available" "applied"; fi
            return 0
        fi
        pos_error "Update failed — rolling back."
        [[ -n "$head_before" ]] && git -C "$POS_ROOT" reset --hard "$head_before" >/dev/null 2>&1
        return 1
    fi

    pos_warn "Not a git checkout — manual update required:"
    echo -e "  ${POS_GRAY}curl -L https://github.com/$POS_REPO_SLUG/archive/main.tar.gz | tar xz${POS_RESET}"
    return 1
}

main() {
    echo -e "${POS_CYAN}${POS_BOLD}Premium-OS Update Manager${POS_RESET}"
    echo -e "  current version: ${POS_CYAN}${POS_VERSION}${POS_RESET}"
    local latest; latest=$(get_latest_version)
    if [[ -z "$latest" ]]; then
        pos_log "Could not reach update sources (offline?) — nothing to do."
        exit 0
    fi
    echo -e "  latest version:  ${POS_GREEN}${latest}${POS_RESET}"
    if version_gt "$latest" "$POS_VERSION"; then
        echo -e "  ${POS_YELLOW}A newer version is available!${POS_RESET}"
        show_changelog
        if pos_confirm "Update now (auto-backup first)?"; then
            do_update
        else
            pos_log "Update postponed."
        fi
    else
        pos_ok "Premium-OS is up to date."
    fi
}

main "$@"

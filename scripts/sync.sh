#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: scripts/sync.sh
# Optional cloud sync of ~/.premium-os via a private Git repository
# (GitHub / GitLab / self-hosted). Disabled by default; fully opt-in.
#
# Setup:
#   bash scripts/sync.sh init git@github.com:you/premium-os-config.git
#   bash scripts/sync.sh push
#   bash scripts/sync.sh pull
#==============================================================================
set -o pipefail
POS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export POS_ROOT POS_HOME="${POS_HOME:-$HOME/.premium-os}"

# shellcheck disable=SC1090
. "$POS_ROOT/core/init.sh"
. "$POS_ROOT/ui/colors.sh"
. "$POS_ROOT/core/utils.sh"

SYNC_META="$POS_HOME/.sync_repo"
SYNC_DIR="$POS_HOME/history/cloud-sync"

err_no_remote() {
    pos_error "No sync remote configured."
    echo -e "  Run: ${POS_CYAN}bash scripts/sync.sh init <git-url>${POS_RESET}"
    exit 1
}

cmd_init() {
    local url="$1"
    [[ -z "$url" ]] && { err_no_remote; }
    command -v git >/dev/null 2>&1 || { pos_error "git required for sync."; exit 1; }
    # allowlist of URL shapes (reject anything weird → no command injection)
    local re='^(https://[A-Za-z0-9._~:/?#@!$&'"'"'()*+,;=%-]+|git@[A-Za-z0-9._-]+:[A-Za-z0-9._~/-]+)$'
    if [[ ! "$url" =~ $re ]]; then
        pos_error "Rejected URL (only https:// or git@host:path forms allowed)."
        exit 1
    fi
    rm -rf "$SYNC_DIR"
    git clone --depth 1 "$url" "$SYNC_DIR" 2>&1 | tail -1
    echo "$url" > "$SYNC_META"
    chmod 600 "$SYNC_META"
    pos_ok "Sync initialized against $url"
    cmd_push
}

_sync_stage() {
    # mirror user data INTO the repo dir (excluding secrets + heavy dirs)
    mkdir -p "$SYNC_DIR/data"
    rsync -a --delete \
        --exclude '.salt' --exclude 'cache' --exclude 'tmp' \
        --exclude 'backups' --exclude '.sync_repo' --exclude '.version' \
        "$POS_HOME/profiles" "$POS_HOME/themes" \
        "$POS_HOME/settings.json" "$POS_HOME/snippets.json" "$POS_HOME/hotkeys.conf" \
        "$SYNC_DIR/data/" 2>/dev/null \
    || {
        # rsync fallback → cp
        mkdir -p "$SYNC_DIR/data"
        cp -r "$POS_HOME/profiles" "$SYNC_DIR/data/" 2>/dev/null
        cp -r "$POS_HOME/themes" "$SYNC_DIR/data/" 2>/dev/null
        cp -f "$POS_HOME/settings.json" "$SYNC_DIR/data/" 2>/dev/null
        cp -f "$POS_HOME/snippets.json" "$SYNC_DIR/data/" 2>/dev/null
        cp -f "$POS_HOME/hotkeys.conf" "$SYNC_DIR/data/" 2>/dev/null
    }
}

cmd_push() {
    [[ -f "$SYNC_META" ]] || err_no_remote
    _sync_stage
    ( cd "$SYNC_DIR"
      git add -A
      if git diff --cached --quiet; then
          pos_ok "Nothing to sync — already current."
          exit 0
      fi
      git -c user.name="Premium-OS" -c user.email="pos@local" \
          commit -q -m "pos sync $(date '+%F %T')"
      git push -q origin HEAD 2>&1 | tail -1
    )
    pos_ok "Config pushed to cloud."
}

cmd_pull() {
    [[ -f "$SYNC_META" ]] || err_no_remote
    ( cd "$SYNC_DIR" && git pull -q --ff-only ) || { pos_error "Pull failed."; exit 1; }
    # safety copy before overwriting
    local rb="$POS_HOME/backups/.rollback-sync-$(date +%s).poz"
    mkdir -p "$POS_HOME/backups"
    tar -czf "$rb" -C "$POS_HOME" profiles themes settings.json snippets.json hotkeys.conf 2>/dev/null
    if [[ -d "$SYNC_DIR/data" ]]; then
        cp -r "$SYNC_DIR/data/." "$POS_HOME/" 2>/dev/null
    fi
    pos_ok "Config pulled and applied (rollback: ${rb##*/})."
}

case "${1:-}" in
    init)  cmd_init "$2" ;;
    push)  cmd_push ;;
    pull)  cmd_pull ;;
    status)
        if [[ -f "$SYNC_META" ]]; then
            echo "remote: $(cat "$SYNC_META")"
            ( cd "$SYNC_DIR" 2>/dev/null && git log --oneline -3 ) || true
        else
            echo "sync not configured"
        fi ;;
    *)
        echo "usage: bash scripts/sync.sh {init <git-url>|push|pull|status}"
        exit 2 ;;
esac

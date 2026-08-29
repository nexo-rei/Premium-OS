#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: scripts/uninstall.sh
# Removes shell integration; optionally removes user data.
#==============================================================================
set -o pipefail
POS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export POS_ROOT POS_HOME="${POS_HOME:-$HOME/.premium-os}"

# shellcheck disable=SC1090
. "$POS_ROOT/ui/colors.sh" 2>/dev/null || true

echo "◢◤ Premium-OS uninstaller"

#---------------- remove shell hook ----------------
remove_hook() {
    local f="$1" tmp
    [[ -f "$f" ]] || return 0
    grep -q '# >>> premium-os >>>' "$f" 2>/dev/null || return 0
    tmp=$(mktemp)
    sed '/# >>> premium-os >>>/,/# <<< premium-os <<</d' "$f" > "$tmp" && mv "$tmp" "$f"
    echo "  removed alias from ${f##*/}"
}

remove_hook "$HOME/.bashrc"
remove_hook "$HOME/.zshrc"
remove_hook "$HOME/.profile"

#---------------- optionally wipe user data ----------------
echo
printf 'Remove ALL user data (%s)? profiles/backups will be lost. (y/N) ' "$POS_HOME"
read -r reply
if [[ "${reply,,}" == "y" ]]; then
    rm -rf "$POS_HOME"
    echo ".  ✔ user data removed ($POS_HOME)"
else
    echo "   user data kept at $POS_HOME"
fi

echo
echo "Premium-OS shell integration removed. The repo directory itself was left"
echo "untouched at: $POS_ROOT"
echo "Delete it manually if desired:  rm -rf \"$POS_ROOT\""

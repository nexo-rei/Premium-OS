#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: INSTALL.sh
# Installation flow:
#   1. requirements check  2. optional deps (jq, node)  3. init dirs
#   4. default configs     5. shell integration (alias) 6. first-run wizard
# Target: < 5 minutes, < 50MB total.
#==============================================================================
set -o pipefail

#────────────────────────── bootstrapping ──────────────────────────
POS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export POS_ROOT
export POS_HOME="${POS_HOME:-$HOME/.premium-os}"

# shellcheck disable=SC1090
. "$POS_ROOT/core/init.sh"
. "$POS_ROOT/ui/colors.sh"
. "$POS_ROOT/core/utils.sh"
. "$POS_ROOT/ui/animations.sh" 2>/dev/null || true

pos_banner_install() {
    echo
    pos_gradient_text "  ◢◤ Premium-OS Installer ◢◤" 2>/dev/null || echo "  == Premium-OS Installer =="
    echo -e "  ${POS_GRAY}v${POS_VERSION} · target size < 50MB · Termux-ready${POS_RESET}"
    echo
}

#────────────────────────── steps ──────────────────────────
step_requirements() {
    echo -e "${POS_CYAN}${POS_BOLD}[1/7]${POS_RESET} Checking system requirements…"
    pos_check_requirements || return 1
    echo "    bash $BASH_VERSION ✔"
    echo "    home: $HOME ✔"
    local tools="tar gzip"
    local miss=""
    for t in $tools; do command -v "$t" >/dev/null 2>&1 || miss+=" $t"; done
    if [[ -n "$miss" ]]; then
        pos_error "Missing required tools:$miss"
        echo -e "  ${POS_GRAY}Install with: pkg install$miss${POS_RESET}"
        return 1
    fi
    pos_ok "Requirements met."
}

step_dependencies() {
    echo -e "${POS_CYAN}${POS_BOLD}[2/7]${POS_RESET} Checking optional dependencies…"
    if command -v jq >/dev/null 2>&1; then
        echo "    jq ✔ (full JSON features)"
    else
        pos_warn "jq not found — installing gives best experience"
        if command -v pkg >/dev/null 2>&1; then
            echo -e "  ${POS_GRAY}Trying: pkg install -y jq${POS_RESET}"
            pkg install -y jq >/dev/null 2>&1 && echo "    jq installed ✔" \
                || pos_warn "jq install skipped (Premium-OS works with reduced JSON features)"
        else
            pos_warn "Continuing without jq (reduced JSON features)"
        fi
    fi
    if command -v node >/dev/null 2>&1; then
        echo "    node ✔ (web dashboard available)"
        POS_HAS_NODE=1
    else
        POS_HAS_NODE=0
        echo "    node not found — web dashboard optional, install later: pkg install nodejs"
    fi
}

step_directories() {
    echo -e "${POS_CYAN}${POS_BOLD}[3/7]${POS_RESET} Initializing ~/.premium-os…"
    pos_init
    local rc=$?
    [[ $rc -eq 0 || $rc -eq 10 ]] || { pos_error "Init failed."; return 1; }
    pos_ok "Directories & defaults ready."
}

step_copy_configs() {
    echo -e "${POS_CYAN}${POS_BOLD}[4/7]${POS_RESET} Verifying theme presets…"
    local n=0 f
    for f in "$POS_ROOT/config/themes"/*.json; do [[ -f "$f" ]] && n=$((n+1)); done
    echo "    $n theme presets available"
    [[ $n -ge 1 ]] || { pos_error "No themes found in $POS_ROOT/config/themes"; return 1; }
    # ensure user themes dir
    mkdir -p "$POS_HOME/themes"
    pos_ok "Configs verified."
}

step_permissions() {
    echo -e "${POS_CYAN}${POS_BOLD}[5/7]${POS_RESET} Setting permissions…"
    chmod +x "$POS_ROOT/main.sh" "$POS_ROOT/scripts/"*.sh 2>/dev/null || true
    chmod +x "$POS_ROOT"/core/*.sh "$POS_ROOT"/features/*.sh "$POS_ROOT"/ui/*.sh 2>/dev/null
    chmod 700 "$POS_HOME" 2>/dev/null
    pos_ok "Permissions set."
}

step_shell_integration() {
    echo -e "${POS_CYAN}${POS_BOLD}[6/7]${POS_RESET} Shell integration…"
    local marker="# >>> premium-os >>>"
    local hook='
# >>> premium-os >>>
export POS_ROOT="'"$POS_ROOT"'"
alias pos="bash '"$POS_ROOT"'/main.sh"
alias premium-os="bash '"$POS_ROOT"'/main.sh"
# <<< premium-os <<<'
    local rc_files=("$HOME/.bashrc" "$HOME/.zshrc")
    local touched=0 f
    for f in "${rc_files[@]}"; do
        [[ -f "$f" ]] || { [[ "$f" == *.bashrc && -n "$HOME" ]] && touch "$f" 2>/dev/null; }
        [[ -f "$f" ]] || continue
        if ! grep -q "$marker" "$f" 2>/dev/null; then
            printf '%s\n' "$hook" >> "$f"
            echo "    aliased in ${f##*/} ✔"
            touched=1
        else
            echo "    ${f##*/} already integrated ✔"
        fi
    done
    export POS_ALIAS_DONE=1
    pos_ok "Shell integration done."
}

step_finish() {
    echo -e "${POS_CYAN}${POS_BOLD}[7/7]${POS_RESET} Finalizing…"
    echo "$POS_VERSION" > "$POS_HOME/.version"

    echo
    echo "  ─────────────────────────────────────────────"
    pos_ok "Premium-OS v${POS_VERSION} installed!"
    echo
    echo -e "  ${POS_BOLD}Start now:${POS_RESET}       bash $POS_ROOT/main.sh"
    echo -e "  ${POS_BOLD}New shells:${POS_RESET}      pos  (alias loaded from rc files)"
    if [[ "${POS_HAS_NODE:-0}" == "1" ]]; then
        echo -e "  ${POS_BOLD}Web dashboard:${POS_RESET}   bash main.sh dashboard  → http://localhost:8080"
    else
        echo -e "  ${POS_BOLD}Web dashboard:${POS_RESET}   pkg install nodejs → bash main.sh dashboard"
    fi
    echo
    if pos_confirm "Run the 2-minute quick-setup wizard now?"; then
        bash "$POS_ROOT/main.sh" setup
    fi
}

#────────────────────────── main ──────────────────────────
main() {
    pos_banner_install
    step_requirements      || { pos_error "Requirements failed."; exit 1; }
    step_dependencies
    step_directories       || exit 1
    step_copy_configs      || exit 1
    step_permissions
    step_shell_integration
    step_finish
}

main "$@"

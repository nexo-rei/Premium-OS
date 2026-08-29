#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: scripts/backup.sh
# Standalone backup entry (cron-friendly).
# Usage: scripts/backup.sh [--encrypt]
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
. "$POS_ROOT/features/backup-restore.sh"

pos_init >/dev/null 2>&1 || true
create_backup "$@"

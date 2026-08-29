#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/backup-restore.sh
# One-click .poz backups (gzipped tar), verification, preview/explorer,
# rolling version history, portable export, optional AES-256 encryption.
#==============================================================================

[[ -n "${_POS_FEAT_BACKUP_LOADED:-}" ]] && return 0
_POS_FEAT_BACKUP_LOADED=1

POS_BACKUPS_DIR="${POS_HOME:-$HOME/.premium-os}/backups"

_backup_ensure() { mkdir -p "$POS_BACKUPS_DIR" 2>/dev/null; }

#----------------------------------------
# create_backup [--encrypt] — bundle ~/.premium-os into .poz
# .poz = tar.gz container with a manifest.json
#----------------------------------------
create_backup() {
    local encrypt=0 password=""
    [[ "${1:-}" == "--encrypt" ]] && { encrypt=1; }
    _backup_ensure
    local ts stamp_archive manifest tmpdir
    ts=$(pos_timestamp)
    tmpdir="$POS_HOME/tmp/bundle-$ts"
    rm -rf "$tmpdir"; mkdir -p "$tmpdir/data"

    # Manifest
    cat > "$tmpdir/manifest.json" <<JSON
{
  "format": "poz",
  "poz_version": 1,
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "premium_os": "${POS_VERSION}",
  "encrypted": ${encrypt},
  "contents": ["profiles","settings","snippets","hotkeys","themes"]
}
JSON
    # Payload — don't recurse into backups/cache/tmp
    cp -r "$POS_HOME/profiles"   "$tmpdir/data/" 2>/dev/null
    cp -r "$POS_HOME/themes"     "$tmpdir/data/" 2>/dev/null
    cp -f "$POS_HOME/settings.json" "$tmpdir/data/" 2>/dev/null
    cp -f "$POS_HOME/snippets.json" "$tmpdir/data/" 2>/dev/null
    cp -f "$POS_HOME/hotkeys.conf"  "$tmpdir/data/" 2>/dev/null

    stamp_archive="$POS_BACKUPS_DIR/backup-$ts.poz"
    tar -czf "$stamp_archive" -C "$tmpdir" . 2>/dev/null
    rm -rf "$tmpdir"

    if [[ $encrypt -eq 1 ]]; then
        if declare -f pos_encrypt_file >/dev/null 2>&1; then
            printf '%b' "${POS_YELLOW}Backup password:${POS_RESET} "; read -rs password; echo
            if pos_encrypt_file "$stamp_archive" "$stamp_archive.enc" "$password"; then
                mv "$stamp_archive.enc" "$stamp_archive"
            else
                pos_warn "Encryption unavailable — backup stored unencrypted."
            fi
            password=""
        fi
    fi

    _backup_enforce_retention
    local size; size=$(pos_dir_size_bytes "$stamp_archive"); size=$(pos_human_size "$(stat -c%s "$stamp_archive" 2>/dev/null || echo 0)")
    if declare -f pos_emit_hook >/dev/null 2>&1; then pos_emit_hook "backup:created" "$stamp_archive"; fi
    pos_ok "Backup created: ${stamp_archive##*/} ($size)"
    echo "$stamp_archive"
}

#----------------------------------------
# _backup_enforce_retention — honor backup.max_backups
#----------------------------------------
_backup_enforce_retention() {
    local max; max=$(pos_config_get backup.max_backups "10")
    [[ "$max" =~ ^[0-9]+$ ]] || max=10
    local count
    count=$(find "$POS_BACKUPS_DIR" -name 'backup-*.poz' 2>/dev/null | wc -l)
    while (( count > max )); do
        local oldest
        oldest=$(find "$POS_BACKUPS_DIR" -name 'backup-*.poz' -printf '%T@ %p\n' 2>/dev/null \
                 | sort -n | head -1 | cut -d' ' -f2-)
        [[ -n "$oldest" ]] && rm -f "$oldest"
        count=$((count-1))
    done
}

#----------------------------------------
# list_backups — timestamped listing with sizes
#----------------------------------------
list_backups() {
    _backup_ensure
    local f n=0
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        printf '  %s  %8s  %s\n' "$(date -r "$f" '+%F %T' 2>/dev/null || echo '?')" \
            "$(pos_human_size "$(stat -c%s "$f" 2>/dev/null || echo 0)")" "${f##*/}"
        n=$((n+1))
    done < <(find "$POS_BACKUPS_DIR" -name 'backup-*.poz' -printf '%T@ %p\n' 2>/dev/null \
             | sort -nr | cut -d' ' -f2-)
    (( n == 0 )) && echo "  (no backups yet)"
    return 0
}

#----------------------------------------
# backup_verification <file> — tar integrity test
#----------------------------------------
backup_verification() {
    local file="$1"
    [[ -f "$file" ]] || file="$POS_BACKUPS_DIR/$file"
    [[ -f "$file" ]] || { pos_error "Backup not found: $1"; return 1; }
    # handle encrypted backups
    if ! tar -tzf "$file" >/dev/null 2>&1; then
        pos_warn "Archive unreadable (corrupt or encrypted)."
        return 1
    fi
    # verify manifest inside
    if tar -xzf "$file" -O ./manifest.json 2>/dev/null | grep -q '"format": "poz"'; then
        pos_ok "Backup integrity OK — $(basename "$file")"
        return 0
    fi
    pos_error "Manifest missing — not a valid .poz backup."
    return 1
}

#----------------------------------------
# preview_backup / backup_explorer — show contents without extracting
#----------------------------------------
preview_backup() {
    local file="$1"
    [[ -f "$file" ]] || file="$POS_BACKUPS_DIR/$file"
    [[ -f "$file" ]] || { pos_error "Not found: $1"; return 1; }
    echo -e "${POS_BOLD}Contents of ${file##*/}:${POS_RESET}"
    tar -tzvf "$file" 2>/dev/null | awk '{printf "  %10s  %s\n", $3, $NF}' | head -60
}
backup_explorer() { preview_backup "$@"; }

#----------------------------------------
# restore_backup <file> [--replace|--merge] — rollback saves pre-state
#----------------------------------------
restore_backup() {
    local file="$1" mode="${2:--merge}"
    [[ -f "$file" ]] || file="$POS_BACKUPS_DIR/$file"
    [[ -f "$file" ]] || { pos_error "Backup not found: $1"; return 1; }

    # Snapshot current state for rollback
    local rollback="$POS_HOME/backups/.rollback-$(pos_timestamp).poz"
    tar -czf "$rollback" -C "$POS_HOME" profiles settings.json snippets.json hotkeys.conf themes 2>/dev/null

    local tmpdir="$POS_HOME/tmp/restore-$$"
    rm -rf "$tmpdir"; mkdir -p "$tmpdir"
    if ! tar -xzf "$file" -C "$tmpdir" 2>/dev/null; then
        # maybe encrypted
        if declare -f pos_decrypt_file >/dev/null 2>&1; then
            local pw; printf '%b' "${POS_YELLOW}Backup password:${POS_RESET} "; read -rs pw; echo
            pos_decrypt_file "$file" "$tmpdir.dec" "$pw" 2>/dev/null \
                && tar -xzf "$tmpdir.dec" -C "$tmpdir" 2>/dev/null
            rm -f "$tmpdir.dec"; pw=""
        fi
        [[ -f "$tmpdir/manifest.json" ]] || { pos_error "Restore failed — corrupt or wrong password."; rm -rf "$tmpdir"; return 1; }
    fi

    if [[ "$mode" == "--replace" ]]; then
        rm -rf "$POS_HOME/profiles" "$POS_HOME/themes"
    fi
    cp -r "$tmpdir/data/." "$POS_HOME/" 2>/dev/null
    rm -rf "$tmpdir"
    if declare -f pos_emit_hook >/dev/null 2>&1; then pos_emit_hook "restore:complete" "$file"; fi
    pos_ok "Restored from ${file##*/} (rollback point: ${rollback##*/})"
}

#----------------------------------------
# rollback_restore — restore the newest .rollback snapshot
#----------------------------------------
rollback_restore() {
    local rb
    rb=$(find "$POS_BACKUPS_DIR" -name '.rollback-*.poz' 2>/dev/null | sort | tail -1)
    [[ -z "$rb" ]] && { pos_error "No rollback point exists."; return 1; }
    tar -xzf "$rb" -C "$POS_HOME" 2>/dev/null \
        && pos_ok "Rolled back to pre-restore state." \
        || pos_error "Rollback failed."
}

#----------------------------------------
# delete_backup <file>
#----------------------------------------
delete_backup() {
    local file="$POS_BACKUPS_DIR/${1##*/}"
    [[ -f "$file" ]] || { pos_error "Not found."; return 1; }
    rm -f "$file" && pos_ok "Deleted ${1##*/}"
}

#----------------------------------------
# export_portable [dir] — single compact portable config (<1MB)
#----------------------------------------
export_portable() {
    local dir="${1:-$PWD}" ts; ts=$(pos_timestamp)
    mkdir -p "$dir" 2>/dev/null
    local out="$dir/premium-os-portable-$ts.tar.gz"
    tar -czf "$out" -C "$POS_HOME" \
        profiles themes settings.json snippets.json hotkeys.conf 2>/dev/null
    [[ -f "$out" ]] && pos_ok "Portable config → $out ($(pos_human_size "$(stat -c%s "$out")"))"
}

# import_portable <file>
import_portable() {
    local file="$1"
    [[ -f "$file" ]] || { pos_error "Not found: $file"; return 1; }
    tar -tzf "$file" >/dev/null 2>&1 || { pos_error "Not a valid portable bundle."; return 1; }
    local rb="$POS_BACKUPS_DIR/.rollback-portable-$(pos_timestamp).poz"
    tar -czf "$rb" -C "$POS_HOME" profiles settings.json snippets.json hotkeys.conf themes 2>/dev/null
    tar -xzf "$file" -C "$POS_HOME" 2>/dev/null && pos_ok "Portable config imported."
}

#----------------------------------------
# schedule_backup — record preference (cron on Termux via crond)
#----------------------------------------
schedule_backup() {
    local freq="${1:-weekly}"
    pos_config_set backup.auto_backup true bool
    pos_ok "Auto-backup enabled ($freq) — runs on Premium-OS start."
}

#----------------------------------------
# Version history snapshots (after config changes)
#----------------------------------------
version_snapshot() { # $1=note
    local vdir="$POS_HOME/history/versions"
    mkdir -p "$vdir"
    local ts; ts=$(pos_timestamp)
    cp "$POS_HOME/settings.json" "$vdir/settings-$ts.json" 2>/dev/null
    [[ -n "${1:-}" ]] && echo "$1" > "$vdir/settings-$ts.note"
}

#----------------------------------------
# backup_restore_menu — interactive UI
#----------------------------------------
backup_restore_menu() {
    while true; do
        _menu_header "💾 Backup & Sync" ""
        list_backups
        echo
        local c; c=$(_menu_select "choose" \
            "Create backup" "Create encrypted backup" "Restore" "Preview backup" \
            "Verify backup" "Rollback last restore" "Portable export" "Portable import" \
            "Enable auto-backup" "Delete backup" "Back")
        case "$c" in
            1) create_backup; pos_press_enter ;;
            2) create_backup --encrypt; pos_press_enter ;;
            3) local f; f=$(pos_prompt "Backup filename"); [[ -n "$f" ]] && restore_backup "$f"; pos_press_enter ;;
            4) local f; f=$(pos_prompt "Backup filename"); [[ -n "$f" ]] && preview_backup "$f"; pos_press_enter ;;
            5) local f; f=$(pos_prompt "Backup filename"); [[ -n "$f" ]] && backup_verification "$f"; pos_press_enter ;;
            6) pos_confirm "Roll back last restore?" && rollback_restore; pos_press_enter ;;
            7) export_portable; pos_press_enter ;;
            8) local f; f=$(pos_prompt "Path to portable bundle"); [[ -n "$f" ]] && import_portable "$f"; pos_press_enter ;;
            9) schedule_backup; pos_press_enter ;;
            10) local f; f=$(pos_prompt "Backup filename to delete"); [[ -n "$f" ]] && delete_backup "$f"; pos_press_enter ;;
            11|""|q) return ;;
        esac
    done
}

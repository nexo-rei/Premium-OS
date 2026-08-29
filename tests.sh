#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: tests.sh — comprehensive test suite (pure bash, no deps)
#
#   bash tests.sh             run everything
#   bash tests.sh --verbose   show captured output on failures
#   bash tests.sh <category>  run one category (install|profiles|themes|
#                             backup|performance|security|integration|ui)
#
# Produces a summary with pass/fail counts, duration and per-category stats.
#==============================================================================
set -u

POS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=0
CATEGORIES=()
for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=1 ;;
        *) CATEGORIES+=("$arg") ;;
    esac
done
[[ ${#CATEGORIES[@]} -eq 0 ]] && \
    CATEGORIES=(install profiles themes backup performance security ui integration)

pass=0 fail=0 total=0
declare -A CAT_PASS CAT_FAIL
FAILED_NAMES=()
T_START=$(date +%s%N)

#────────────────────────── harness ──────────────────────────
ok() { # $1=name $2=0-ok
    total=$((total+1))
    local cat="${CUR_CAT:-misc}"
    if [[ ${2:-1} -eq 0 ]]; then
        pass=$((pass+1)); CAT_PASS[$cat]=$(( ${CAT_PASS[$cat]:-0} + 1 ))
        printf '  \033[32m✔\033[0m %s\n' "$1"
    else
        fail=$((fail+1)); CAT_FAIL[$cat]=$(( ${CAT_FAIL[$cat]:-0} + 1 ))
        FAILED_NAMES+=("$cat/$1")
        printf '  \033[31m✖\033[0m %s\n' "$1"
        [[ $VERBOSE -eq 1 && -n "${LAST_LOG:-}" ]] && sed 's/^/    │ /' <<<"$LAST_LOG"
    fi
}

expect_rc0()     { local n="$1"; shift; LAST_LOG=$("$@" 2>&1); ok "$n" $?; }
expect_rc1()     { local n="$1"; shift; LAST_LOG=$("$@" 2>&1); [[ $? -ne 0 ]] && ok "$n" 0 || ok "$n" 1; }
expect_eq()      { # $1=name $2=expected $3=actual
    LAST_LOG="$3"
    [[ "$2" == "$3" ]] && ok "$1" 0 || ok "$1" 1
}
expect_contains(){ LAST_LOG="$3"; [[ "$3" == *"$2"* ]] && ok "$1" 0 || ok "$1" 1; }

category() { CUR_CAT="$1"; echo; printf '\033[36;1m■ %s\033[0m\n' "$1"; }

#────────────────────────── sandbox ──────────────────────────
TEST_HOME=$(mktemp -d)
export POS_HOME="$TEST_HOME/.premium-os"
export POS_ANIM_DISABLE=1
export HOME="$TEST_HOME"   # sandboxed home so nothing touches the real user
mkdir -p "$POS_HOME"

# Load the full stack (init.sh must be first)
# shellcheck disable=SC1090
. "$POS_ROOT/core/init.sh"
. "$POS_ROOT/ui/colors.sh"
. "$POS_ROOT/core/utils.sh"
. "$POS_ROOT/core/config.sh"
. "$POS_ROOT/core/theme.sh"
. "$POS_ROOT/core/profile.sh"
. "$POS_ROOT/core/security.sh"
. "$POS_ROOT/ui/animations.sh"
. "$POS_ROOT/ui/responsive.sh"
. "$POS_ROOT/features/theme-creator.sh"
. "$POS_ROOT/features/performance-monitor.sh"
. "$POS_ROOT/features/backup-restore.sh"
. "$POS_ROOT/features/cleanup.sh"
. "$POS_ROOT/features/hotkeys.sh"
. "$POS_ROOT/features/snippets.sh"
. "$POS_ROOT/features/optimization.sh"
. "$POS_ROOT/features/smart-suggestions.sh"
. "$POS_ROOT/features/plugin-manager.sh"

has_cat() { for c in "${CATEGORIES[@]}"; do [[ "$c" == "$1" ]] && return 0; done; return 1; }

# Always bootstrap the sandbox data dir — standalone-category runs need it.
pos_init >/dev/null 2>&1 || true

#══════════════════════════ 1. INSTALLATION ══════════════════════════
if has_cat install; then
    category "📦 Installation"
    pos_init >/dev/null 2>&1; rc=$?
    [[ $rc -eq 0 || $rc -eq 10 ]] && ok "pos_init succeeds (idempotent)" 0 || ok "pos_init succeeds (idempotent)" 1

    for d in profiles backups plugins cache history tmp; do
        [[ -d "$POS_HOME/$d" ]] && ok "dir exists: $d" 0 || ok "dir exists: $d" 1
    done
    [[ -f "$POS_HOME/settings.json" ]]                && ok "settings.json created" 0 || ok "settings.json created" 1
    jq empty "$POS_HOME/settings.json" 2>/dev/null    && ok "settings.json valid JSON" 0 || ok "settings.json valid JSON" 1
    [[ -f "$POS_HOME/profiles/default.json" ]]        && ok "default profile created" 0 || ok "default profile created" 1
    jq empty "$POS_HOME/snippets.json" 2>/dev/null    && ok "snippets.json valid JSON" 0 || ok "snippets.json valid JSON" 1
    [[ -f "$POS_HOME/hotkeys.conf" ]]                 && ok "hotkeys.conf created" 0 || ok "hotkeys.conf created" 1
    [[ "$(stat -c%a "$POS_HOME" 2>/dev/null)" == "700" ]] && ok "home dir is 700" 0 || ok "home dir is 700" 1
    [[ "$(stat -c%a "$POS_HOME/settings.json" 2>/dev/null)" == "600" ]] && ok "settings is 600" 0 || ok "settings is 600" 1
    expect_rc0 "idempotent re-init" pos_init
    expect_rc0 "requirements check" pos_check_requirements
    s=$(pos_config_get active_profile); expect_eq "default active profile" "default" "$s"
fi

#══════════════════════════ 2. PROFILES ══════════════════════════
if has_cat profiles; then
    category "🗂 Profiles"
    expect_rc0 "create profile" create_profile t_work
    expect_rc1 "duplicate create rejected" create_profile t_work
    expect_rc1 "unsafe name rejected" create_profile 'bad;name'
    expect_rc0 "switch profile" switch_profile t_work
    expect_eq "active = t_work" "t_work" "$(get_active_profile)"
    expect_rc0 "duplicate profile" duplicate_profile t_work t_copy
    expect_rc0 "rename profile" rename_profile t_copy t_renamed
    expect_rc0 "profile_exists yes" profile_exists t_renamed
    expect_rc1 "profile_exists no" profile_exists t_ghost
    expect_rc1 "delete default protected" delete_profile default
    expect_rc0 "export profile" export_profile t_work "$TEST_HOME"
    [[ -f "$TEST_HOME/t_work.profile.json" ]] && ok "export file exists" 0 || ok "export file exists" 1
    jq '.name="t_imported"' "$TEST_HOME/t_work.profile.json" > "$TEST_HOME/t_imported.profile.json"
    expect_rc0 "import profile" import_profile "$TEST_HOME/t_imported.profile.json"
    expect_rc0 "imported profile exists" profile_exists t_imported
    expect_rc1 "re-import duplicate rejected" import_profile "$TEST_HOME/t_imported.profile.json"
    expect_rc0 "merge profile into active" merge_profile t_work
    expect_rc0 "delete profile" delete_profile t_renamed
    expect_rc0 "switch back to default" switch_profile default
    LAST_LOG=$(profile_preview t_work 2>&1)
    [[ "$LAST_LOG" == *"Profile: "* ]] && ok "profile preview renders" 0 || ok "profile preview renders" 1
    # corruption recovery
    echo "{bad json" > "$POS_HOME/profiles/t_corrupt.json"
    expect_rc1 "corrupt profile rejected on switch" switch_profile t_corrupt
    rm -f "$POS_HOME/profiles/t_corrupt.json"
fi

#══════════════════════════ 3. THEMES ══════════════════════════
if has_cat themes; then
    category "🎨 Themes"
    n=$(list_themes | wc -l)
    [[ $n -ge 5 ]] && ok ">=5 presets listed" 0 || ok ">=5 presets listed" 1
    expect_eq "current theme default" "dark" "$(get_current_theme)"
    expect_rc0 "apply theme neon" apply_theme neon
    expect_eq "current = neon" "neon" "$(get_current_theme)"
    expect_rc1 "apply missing theme fails" apply_theme nope-not-a-theme
    expect_rc0 "apply back to dark" apply_theme dark
    f=$(theme_file_for dracula); [[ -n "$f" && -f "$f" ]] && ok "theme_file_for finds dracula" 0 || ok "theme_file_for finds dracula" 1
    LAST_LOG=$(theme_preview dark 2>&1)
    [[ "$LAST_LOG" == *"Theme preview"* ]] && ok "theme preview renders" 0 || ok "theme preview renders" 1
    expect_rc0 "hex validation good" pos_is_hex_color "#00D9FF"
    expect_rc1 "hex validation bad" pos_is_hex_color "zzzzzz"
    expect_eq "hex→rgb" "255 0 110" "$(pos_hex_to_rgb '#FF006E')"
    expect_eq "rgb→hex" "#00D9FF" "$(pos_rgb_to_hex 0 217 255)"
    # custom theme via creator draft
    TC_DRAFT[primary]="#123456"
    expect_rc0 "save_custom_theme" save_custom_theme t_theme1
    jq empty "$POS_HOME/themes/t_theme1.json" 2>/dev/null && ok "custom theme valid JSON" 0 || ok "custom theme valid JSON" 1
    expect_eq "custom theme color saved" "#123456" "$(jq -r .colors.primary "$POS_HOME/themes/t_theme1.json")"
    list_themes | grep -q "t_theme1" && ok "custom theme listed" 0 || ok "custom theme listed" 1
    expect_rc1 "unsafe theme name rejected" save_custom_theme 'x;y'
    expect_eq "gradient from preset" "neon" "$(jq -r .gradient "$POS_ROOT/config/themes/neon.json")"
fi

#══════════════════════════ 4. BACKUP ══════════════════════════
if has_cat backup; then
    category "💾 Backup & Restore"
    b=$("$POS_ROOT/scripts/backup.sh" 2>/dev/null | tail -1)
    [[ -f "$b" && "$b" == *.poz ]] && ok "scripted backup creates .poz" 0 || ok "scripted backup creates .poz" 1
    expect_rc0 "backup verification" backup_verification "$b"
    LAST_LOG=$(preview_backup "$(basename "$b")" 2>&1)
    [[ "$LAST_LOG" == *"manifest.json"* ]] && ok "preview lists manifest" 0 || ok "preview lists manifest" 1
    # mutate, restore, verify
    pos_config_set active_profile t_work >/dev/null
    expect_rc0 "restore backup" restore_backup "$(basename "$b")"
    expect_eq "state restored" "default" "$(pos_config_get active_profile)"
    rb=$(find "$POS_HOME/backups" -name '.rollback-*.poz' | head -1)
    [[ -n "$rb" ]] && ok "rollback snapshot made" 0 || ok "rollback snapshot made" 1
    expect_rc0 "rollback restore works" rollback_restore
    b2=$("$POS_ROOT/scripts/backup.sh" 2>/dev/null | tail -1)
    b3=$("$POS_ROOT/scripts/backup.sh" 2>/dev/null | tail -1)
    sleep 1
    expect_rc0 "list_backups runs" list_backups
    expect_rc0 "delete backup" delete_backup "$(basename "$b3")"
    [[ ! -f "$b3" ]] && ok "deleted file gone" 0 || ok "deleted file gone" 1
    expect_rc0 "portable export" export_portable "$TEST_HOME"
    ls "$TEST_HOME"/premium-os-portable-*.tar.gz >/dev/null 2>&1 && ok "portable file exists" 0 || ok "portable file exists" 1
    pf=$(ls "$TEST_HOME"/premium-os-portable-*.tar.gz | head -1)
    expect_rc0 "portable import" import_portable "$pf"
    # retention enforcement
    pos_config_set backup.max_backups 2 number >/dev/null
    for i in 1 2 3 4; do create_backup >/dev/null 2>&1; sleep 1; done
    c=$(find "$POS_HOME/backups" -name 'backup-*.poz' | wc -l)
    [[ $c -le 2 ]] && ok "retention enforced (<=2)" 0 || ok "retention enforced (<=2)" 1
fi

#══════════════════════════ 5. PERFORMANCE ══════════════════════════
if has_cat performance; then
    category "⚡ Performance"
    cpu=$(get_cpu_usage)
    [[ "$cpu" =~ ^[0-9]+$ ]] && ok "cpu usage numeric ($cpu%)" 0 || ok "cpu usage numeric" 1
    mem=$(get_memory_usage); read -r mu mt mp <<<"$mem"
    [[ "$mt" -gt 0 ]] && ok "mem total detected (${mt}MB)" 0 || ok "mem total detected" 1
    [[ "$mp" -ge 0 && "$mp" -le 100 ]] && ok "mem pct in range" 0 || ok "mem pct in range" 1
    pc=$(get_process_count)
    [[ "$pc" =~ ^[0-9]+$ && "$pc" -gt 0 ]] && ok "process count ($pc)" 0 || ok "process count" 1
    up=$(calculate_uptime)
    [[ "$up" == *"session"* ]] && ok "uptime format" 0 || ok "uptime format" 1
    bm=$(benchmark_terminal 300)
    [[ "$bm" =~ ^[0-9]+$ && "$bm" -gt 0 ]] && ok "benchmark runs ($bm cmds/s)" 0 || ok "benchmark runs" 1
    LAST_LOG=$(get_performance_stats 2>&1)
    [[ "$LAST_LOG" == cpu=* ]] && ok "stats line format" 0 || ok "stats line format" 1
    _perf_record 10 20; _perf_record 30 25
    f="$POS_HOME/history/perf/$(date +%F).csv"
    [[ -s "$f" ]] && ok "history recorded" 0 || ok "history recorded" 1
    h=$(get_performance_history 1h | wc -l)
    [[ $h -ge 2 ]] && ok "history query 1h ($h rows)" 0 || ok "history query 1h" 1
    expect_rc0 "csv export" export_report "$TEST_HOME/report.csv"
    [[ -s "$TEST_HOME/report.csv" ]] && ok "csv has data" 0 || ok "csv has data" 1

    #──── timing budget (PRD targets) ────
    t0=$(date +%s%N); apply_theme dark >/dev/null 2>&1; t1=$(date +%s%N)
    ms=$(( (t1-t0)/1000000 ))
    [[ $ms -lt 1000 ]] && ok "theme apply <1s (${ms}ms)" 0 || ok "theme apply <1s" 1
    t0=$(date +%s%N); switch_profile default >/dev/null 2>&1; t1=$(date +%s%N)
    ms=$(( (t1-t0)/1000000 ))
    [[ $ms -lt 500 ]] && ok "profile switch <500ms (${ms}ms)" 0 || ok "profile switch <500ms" 1
fi

#══════════════════════════ 6. SECURITY ══════════════════════════
if has_cat security; then
    category "🔐 Security"
    h1=$(pos_hash_password "pw123"); h2=$(pos_hash_password "pw-other")
    [[ ${#h1} -eq 64 ]] && ok "sha256 hash 64 chars" 0 || ok "sha256 hash 64 chars" 1
    [[ "$h1" != "$h2" ]] && ok "hashes differ per input" 0 || ok "hashes differ per input" 1
    [[ "$h1" != "pw123"  ]] && ok "no plaintext stored" 0 || ok "no plaintext stored" 1
    # cyber lock via settings
    pos_config_set security.lock_hash "$h1" >/dev/null
    pos_config_set security.cyber_lock_enabled true bool >/dev/null
    printf 'pw123\n' | cyber_lock_verify >/dev/null 2>&1 && ok "lock accepts correct pw" 0 || ok "lock accepts correct pw" 1
    printf 'wrong1\nwrong2\nwrong3\n' | cyber_lock_verify >/dev/null 2>&1 && ok "lock rejects bad pw" 1 || ok "lock rejects bad pw" 0
    cyber_lock_disable >/dev/null
    [[ "$(pos_config_get security.cyber_lock_enabled)" == "false" ]] && ok "lock disabled" 0 || ok "lock disabled" 1
    # sanitize path
    s=$(pos_sanitize_path 'safe/path.txt'); [[ "$s" == "safe/path.txt" ]] && ok "safe path passes" 0 || ok "safe path passes" 1
    s=$(pos_sanitize_path 'evil;rm -rf ~');  [[ -z "$s" ]] && ok "injection blocked (;)" 0 || ok "injection blocked (;)" 1
    s=$(pos_sanitize_path '$(whoami)');       [[ -z "$s" ]] && ok "injection blocked (\$())" 0 || ok "injection blocked (\$())" 1
    s=$(pos_sanitize_path 'a|b&c');           [[ -z "$s" ]] && ok "injection blocked (|&)" 0 || ok "injection blocked (|&)" 1
    # AES encryption roundtrip (openssl optional)
    if pos_aes_available; then
        echo "secret payload" > "$TEST_HOME/plain.txt"
        pos_encrypt_file "$TEST_HOME/plain.txt" "$TEST_HOME/enc.aes" "pw" && ok "AES encrypt" 0 || ok "AES encrypt" 1
        pos_decrypt_file "$TEST_HOME/enc.aes" "$TEST_HOME/dec.txt" "pw" \
            && [[ "$(cat "$TEST_HOME/dec.txt")" == "secret payload" ]] \
            && ok "AES decrypt roundtrip" 0 || ok "AES decrypt roundtrip" 1
    else
        echo "  (openssl unavailable — AES tests skipped)"
    fi
    # secure store
    pos_secure_store k1 v1secret
    [[ "$(pos_secure_read k1)" == "v1secret" ]] && ok "secure store roundtrip" 0 || ok "secure store roundtrip" 1
    # perms recheck
    [[ "$(stat -c%a "$POS_HOME/settings.json")" == "600" ]] && ok "settings still 600" 0 || ok "settings still 600" 1
    # dangerous plugin scan (validate function directly)
    mkdir -p "$TEST_HOME/evilplug"
    cat > "$TEST_HOME/evilplug/manifest.json" <<'JSON'
{"name":"evil","version":"1","author":"x","description":"x"}
JSON
    echo 'rm -rf /' > "$TEST_HOME/evilplug/plugin.sh"
    expect_rc1 "dangerous plugin rejected" validate_plugin "$TEST_HOME/evilplug"
    echo 'echo hi' > "$TEST_HOME/evilplug/plugin.sh"
    expect_rc0 "clean plugin validates" validate_plugin "$TEST_HOME/evilplug"
fi

#══════════════════════════ 7. UI / RESPONSIVE ══════════════════════════
if has_cat ui; then
    category "📱 UI & Responsive"
    expect_rc0 "responsive layout computed" get_responsive_layout
    sz=$(detect_terminal_size)
    [[ "$sz" =~ ^[0-9]+\ [0-9]+$ ]] && ok "terminal size parsed" 0 || ok "terminal size parsed" 1
    o=$(detect_orientation); [[ "$o" == "portrait" || "$o" == "landscape" ]] && ok "orientation detected" 0 || ok "orientation detected" 1
    # hotkeys feature
    expect_rc0 "register hotkey" register_hotkey "ctrl+alt+q" "qq"
    expect_rc1 "hotkey conflict caught" register_hotkey "Ctrl+Alt+Q" "dupe"
    expect_rc1 "reserved key blocked" register_hotkey "Ctrl+C" "no"
    LAST_LOG=$(list_hotkeys)
    [[ "$LAST_LOG" == *"Ctrl+Alt+Q"* ]] && ok "hotkey listed" 0 || ok "hotkey listed" 1
    LAST_LOG=$(test_hotkey "ctrl+alt+q")
    [[ "$LAST_LOG" == *"not executed"* ]] && ok "test mode doesn't run" 0 || ok "test mode doesn't run" 1
    expect_rc0 "remove hotkey" remove_hotkey "ctrl+alt+q"
    # snippets
    expect_rc0 "add snippet" add_snippet Test tc1 "echo tc"
    LAST_LOG=$(search_snippet tc1)
    [[ "$LAST_LOG" == *"echo tc"* ]] && ok "snippet search found" 0 || ok "snippet search found" 1
    LAST_LOG=$(search_snippet zzz-no-hit)
    [[ -z "$LAST_LOG" ]] && ok "search no match → empty" 0 || ok "search no match → empty" 1
    sid=$(jq '[.snippets[].id] | max' "$POS_HOME/snippets.json")
    expect_eq "get command by id" "echo tc" "$(get_snippet_command "$sid")"
    expect_rc0 "remove snippet" remove_snippet "$sid"
    # cleanup (safe in sandbox)
    expect_rc0 "dry run cleanup" dry_run_cleanup
    echo junk > "$POS_HOME/tmp/junkfile"
    freed=$(cleanup_temp_files)
    [[ ! -f "$POS_HOME/tmp/junkfile" ]] && ok "temp cleaned (freed ${freed}B)" 0 || ok "temp cleaned" 1
    expect_rc0 "post cleanup verification" post_cleanup_verification
    # suggestions (no interaction — candidates function)
    LAST_LOG=$(_smart_candidates dev 13)
    [[ -n "$LAST_LOG" ]] && ok "suggestion candidates produced" 0 || ok "suggestion candidates produced" 1
fi

#══════════════════════════ 8. INTEGRATION (end-to-end) ══════════════════════════
if has_cat integration; then
    category "🔄 Integration (E2E)"
    # main.sh CLI surface
    out=$(POS_HOME="$POS_HOME" HOME="$TEST_HOME" bash "$POS_ROOT/main.sh" version 2>&1)
    expect_contains "CLI version" "Premium-OS v1" "$out"
    out=$(POS_HOME="$POS_HOME" HOME="$TEST_HOME" bash "$POS_ROOT/main.sh" profile list 2>&1)
    expect_contains "CLI profile list" "default" "$out"
    out=$(POS_HOME="$POS_HOME" HOME="$TEST_HOME" bash "$POS_ROOT/main.sh" theme current 2>&1)
    [[ "$out" == *"dark"* || "$out" == *"neon"* ]] && ok "CLI theme current" 0 || { LAST_LOG="$out"; ok "CLI theme current" 1; }
    out=$(POS_HOME="$POS_HOME" HOME="$TEST_HOME" bash "$POS_ROOT/main.sh" perf stats 2>&1)
    expect_contains "CLI perf stats" "cpu=" "$out"
    out=$(POS_HOME="$POS_HOME" HOME="$TEST_HOME" bash "$POS_ROOT/main.sh" nope-command 2>&1)
    expect_contains "CLI unknown cmd error" "Unknown command" "$out"
    out=$(POS_HOME="$POS_HOME" HOME="$TEST_HOME" bash "$POS_ROOT/main.sh" help 2>&1)
    expect_contains "CLI help" "usage:" "$out"
    # plugin hook emission through apply_theme
    LAST_LOG=""
    mkdir -p "$POS_HOME/plugins/hooktest/data"
    cat > "$POS_HOME/plugins/hooktest/manifest.json" <<'JSON'
{"name":"Hook Test","version":"1.0.0","author":"tests","description":"t","hooks":["theme:applied"],"permissions":["filesystem"]}
JSON
    cat > "$POS_HOME/plugins/hooktest/plugin.sh" <<'PLUGIN'
plugin_on_event() {
    echo "hook=$1 arg=$2" >> "$POS_PLUGIN_DIR/data/events.log"
}
PLUGIN
    apply_theme neon >/dev/null 2>&1
    sleep 0.6
    if [[ -f "$POS_HOME/plugins/hooktest/data/events.log" ]] && \
       grep -q "theme:applied" "$POS_HOME/plugins/hooktest/data/events.log"; then
        ok "plugin hook fires on theme apply" 0
    else
        ok "plugin hook fires on theme apply" 1
    fi
    # full roundtrip: profile → theme → backup → restore
    create_profile t_e2e >/dev/null 2>&1
    switch_profile t_e2e >/dev/null 2>&1
    apply_theme dracula >/dev/null 2>&1
    bb=$(create_backup 2>/dev/null | tail -1)
    switch_profile default >/dev/null 2>&1
    restore_backup "$(basename "$bb")" >/dev/null 2>&1
    [[ "$(get_active_profile)" == "t_e2e" ]] && ok "E2E backup restores active profile" 0 \
                                            || ok "E2E backup restores active profile" 1
    [[ "$(get_current_theme)" == "dracula" ]] && ok "E2E theme persisted through cycle" 0 \
                                              || ok "E2E theme persisted through cycle" 1
fi

#══════════════════════════ REPORT ══════════════════════════
T_END=$(date +%s%N)
ELAPSED=$(( (T_END - T_START) / 1000000 ))

echo
echo "══════════════════════════════════════════════════"
echo "  TEST REPORT"
echo "══════════════════════════════════════════════════"
for cat in "${CATEGORIES[@]}"; do
    p=${CAT_PASS[$cat]:-0}; f=${CAT_FAIL[$cat]:-0}
    [[ $((p+f)) -eq 0 ]] && continue
    printf '  %-14s %3d passed · %d failed\n' "$cat" "$p" "$f"
done
echo "──────────────────────────────────────────────────"
printf '  TOTALS: \033[32m%d passed\033[0m · \033[31m%d failed\033[0m · %d total · %dms\n' \
    "$pass" "$fail" "$total" "$ELAPSED"
if [[ $fail -gt 0 ]]; then
    printf '  failing: %s\n' "${FAILED_NAMES[*]}"
fi
echo "══════════════════════════════════════════════════"

rm -rf "$TEST_HOME"
[[ $fail -eq 0 ]]

#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: features/performance-monitor.sh
# Real-time terminal performance dashboard: CPU, RAM, uptime, processes,
# benchmark, cache usage, history, CSV export.
#==============================================================================

[[ -n "${_POS_FEAT_PERF_LOADED:-}" ]] && return 0
_POS_FEAT_PERF_LOADED=1

POS_PERF_DATA="${POS_HOME:-$HOME/.premium-os}/history/perf"
POS_SESSION_START="${POS_SESSION_START:-$(date +%s)}"

#----------------------------------------
# get_cpu_usage — two quick samples of /proc/stat
#----------------------------------------
get_cpu_usage() {
    if [[ ! -r /proc/stat ]]; then echo "N/A"; return 0; fi
    _read_stat() { awk '/^cpu /{print $2, $3, $4, $5, $6, $7, $8}' /proc/stat; }
    local prev; prev=$(_read_stat)   # seed with state from ~0.15s ago
    # Use cached state when possible to avoid sleep on repeated calls
    if [[ -n "$POS_CPU_PREV" ]]; then prev="$POS_CPU_PREV"; else sleep 0.1; fi
    local cur; cur=$(_read_stat)
    export POS_CPU_PREV="$cur"
    awk -v p="$prev" -v c="$cur" 'BEGIN{
        split(p,a," "); split(c,b," ");
        idle_d  = (b[4]+b[5]) - (a[4]+a[5]);
        tot=0; for (i=1;i<=7;i++) tot += b[i]-a[i];
        if (tot<=0) {print 0; exit}
        printf "%.0f", (1 - idle_d/tot)*100
    }'
}

#----------------------------------------
# get_memory_usage — prints "USED_MB TOTAL_MB PCT"
#----------------------------------------
get_memory_usage() {
    if [[ ! -r /proc/meminfo ]]; then echo "0 0 0"; return 0; fi
    awk '
        /MemTotal/     {t=$2}
        /MemAvailable/ {a=$2}
        END {
            u=t-a;
            printf "%.0f %.0f %.0f", u/1024, t/1024, (t>0)?u*100/t:0
        }' /proc/meminfo
}
get_ram_usage() { get_memory_usage; }

#----------------------------------------
# calculate_uptime — session + system
#----------------------------------------
calculate_uptime() {
    local now session sys s
    now=$(date +%s)
    session=$(( now - POS_SESSION_START ))
    s=$session
    _fmt() { local s=$1; printf '%dh %02dm %02ds' $((s/3600)) $(( (s%3600)/60 )) $((s%60)); }
    if [[ -r /proc/uptime ]]; then
        sys=$(awk '{printf "%d", $1}' /proc/uptime)
        printf 'session %s · system %s' "$(_fmt $session)" "$(_fmt $sys)"
    else
        printf 'session %s' "$(_fmt $session)"
    fi
}

#----------------------------------------
# get_process_count
#----------------------------------------
get_process_count() {
    if [[ -d /proc ]]; then
        ls -d /proc/[0-9]* 2>/dev/null | wc -l | tr -d ' '
    else
        ps -e 2>/dev/null | wc -l | tr -d ' '
    fi
}

#----------------------------------------
# benchmark_terminal — quick command-dispatch throughput test
# prints commands/sec
#----------------------------------------
benchmark_terminal() {
    local n="${1:-200}" i t0 t1 elapsed
    t0=$(date +%s%N 2>/dev/null || echo 0)
    if (( t0 == 0 )); then echo "N/A"; return 0; fi
    for (( i=0; i<n; i++ )); do :; done
    t1=$(date +%s%N)
    elapsed=$(( (t1 - t0) / 1000000 ))
    (( elapsed <= 0 )) && elapsed=1
    echo $(( n * 1000 / elapsed ))
}

#----------------------------------------
# get_cache_usage — bytes in POS cache + /tmp estimate
#----------------------------------------
get_cache_usage() {
    local c tmp
    c=$(pos_dir_size_bytes "${POS_HOME:-$HOME/.premium-os}/cache")
    tmp=$(pos_dir_size_bytes "${TMPDIR:-/tmp}")
    echo "${c:-0} ${tmp:-0}"
}

#----------------------------------------
# get_performance_stats — compact machine-readable single line
#----------------------------------------
get_performance_stats() {
    local cpu mem used total pct procs cache tmpc bench
    cpu=$(get_cpu_usage)
    mem=$(get_memory_usage); read -r used total pct <<<"$mem"
    procs=$(get_process_count)
    read -r cache tmpc <<<"$(get_cache_usage)"
    printf 'cpu=%s%% ram=%sMB/%sMB(%s%%) procs=%s cache=%s uptime="%s"' \
        "$cpu" "$used" "$total" "$pct" "$procs" "$(pos_human_size "$cache")" "$(calculate_uptime)"
    echo
}

#----------------------------------------
# _gauge <pct> <label> — color coded
#----------------------------------------
_perf_gauge() {
    local pct="${1:-0}" label="$2" width=22
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    local fill=$(( pct * width / 100 )) empty=$(( width - fill ))
    local bar="" pad=""
    while (( fill-- > 0 ));  do bar+="█"; done
    while (( empty-- > 0 )); do pad+="░"; done
    local color="$POS_GREEN"
    (( pct >= 60 )) && color="$POS_YELLOW"
    (( pct >= 85 )) && color="$POS_PINK"
    printf ' %b%-18s%b %s%s %3d%%\n' "$POS_WHITE" "$label" "$POS_RESET" "${color}${bar}" "${POS_GRAY}${pad}${POS_RESET}" "$pct"
}

#----------------------------------------
# _sparkline <values...> — unicode spark chart
#----------------------------------------
_perf_spark() {
    local chars=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
    local v out="" max=1 n=${#chars[@]}
    for v in "$@"; do (( v > max )) && max=$v; done
    for v in "$@"; do
        out+="${chars[$(( v * (n-1) / max ))]}"
    done
    echo "$out"
}

#----------------------------------------
# display_dashboard [seconds] — real-time updating view
#----------------------------------------
display_dashboard() {
    local duration="${1:-10}" i=0
    local -a cpu_hist=() ram_hist=()
    while (( i < duration )); do
        local cpu mem used total pct procs
        cpu=$(get_cpu_usage); [[ "$cpu" =~ ^[0-9]+$ ]] || cpu=0
        mem=$(get_memory_usage); read -r used total pct <<<"$mem"
        procs=$(get_process_count)
        cpu_hist+=("$cpu"); ram_hist+=("$pct")
        (( ${#cpu_hist[@]} > 24 )) && { cpu_hist=("${cpu_hist[@]:1}"); ram_hist=("${ram_hist[@]:1}"); }

        pos_clear
        echo -e " ${POS_CYAN}${POS_BOLD}⚡ Performance Monitor${POS_RESET} ${POS_GRAY}· Ctrl+C exits · ${i}s/${duration}s${POS_RESET}"
        responsive_hr
        _perf_gauge "$cpu" "CPU"
        _perf_gauge "$pct" "RAM (${used}MB/${total}MB)"
        printf ' %b%-18s%b %s\n' "$POS_WHITE" "Processes" "$POS_RESET" "$procs"
        printf ' %b%-18s%b %s\n' "$POS_WHITE" "Uptime" "$POS_RESET" "$(calculate_uptime)"
        printf ' %b%-18s%b %s\n' "$POS_WHITE" "Benchmark" "$POS_RESET" "$(benchmark_terminal 100) cmds/s"
        local cb tb; read -r cb tb <<<"$(get_cache_usage)"
        printf ' %b%-18s%b %s (tmp: %s)\n' "$POS_WHITE" "Cache" "$POS_RESET" "$(pos_human_size "$cb")" "$(pos_human_size "$tb")"
        echo
        echo -e "  ${POS_GRAY}cpu ${POS_CYAN}$(_perf_spark "${cpu_hist[@]}")${POS_RESET}"
        echo -e "  ${POS_GRAY}ram ${POS_GREEN}$(_perf_spark "${ram_hist[@]}")${POS_RESET}"

        _perf_record "$cpu" "$pct"
        # refresh 2s, interruptible
        read -rsn1 -t 2 key 2>/dev/null && return 0
        i=$((i+2))
    done
}

#----------------------------------------
# _perf_record — append rolling history (capped at 43200 ≈ 24h @2s)
#----------------------------------------
_perf_record() {
    mkdir -p "$POS_PERF_DATA" 2>/dev/null
    local f="$POS_PERF_DATA/$(date +%F).csv"
    echo "$(date +%s),$1,$2" >> "$f"
    # Cheap cap: truncate to last 2000 lines when file grows large
    local lines; lines=$(wc -l < "$f" 2>/dev/null || echo 0)
    if (( lines > 43200 )); then
        tail -n 2000 "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
}

#----------------------------------------
# get_performance_history 1h|24h
#----------------------------------------
get_performance_history() {
    local window="${1:-1h}" cutoff file
    case "$window" in
        24h) cutoff=$(( $(date +%s) - 86400 )); file="$POS_PERF_DATA/$(date +%F).csv" ;;
        *)   cutoff=$(( $(date +%s) - 3600 ));  file="$POS_PERF_DATA/$(date +%F).csv" ;;
    esac
    [[ -f "$file" ]] || { echo "No history yet — run the dashboard first."; return 0; }
    awk -F, -v c="$cutoff" '$1>=c {print}' "$file"
}

#----------------------------------------
# export_report [out.csv] — CSV of history for the window
#----------------------------------------
export_report() {
    local out="${1:-$PWD/perf-report-$(date +%F).csv}"
    {
        echo "epoch,cpu_pct,ram_pct"
        get_performance_history 24h
    } > "$out"
    pos_ok "Report → $out"
}

#!/bin/sh
# /etc/qtun/action/logs.sh
# QTUN Adaptive Logger - Dynamic Core Optimization

MAX_LINES=100
TRIM_TO=80
RUN_DIR="/etc/qtun/run"

[ -d "$RUN_DIR" ] || mkdir -p "$RUN_DIR"

trim_file() {
    file="$1"

    [ -f "$file" ] || return 0

    lines=$(wc -l < "$file" 2>/dev/null)

    if [ "${lines:-0}" -gt "$MAX_LINES" ]; then
        tail -n "$TRIM_TO" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    fi
}

log_append() {
    file="$1"
    msg="$2"
    timestamp=$(date '+%H:%M:%S')

    echo "[$timestamp] $msg" >> "$file"

    trim_file "$file"
}

case "$1" in
    process)
        log_append "$RUN_DIR/qtun_live.log" "$2"
        echo "[QTUN] $2"
        ;;
    rotate)
        target_file="$2"
        trim_file "$target_file"
        ;;
    clear)
        # =========================================================
        # OPTIMALISASI DINAMIS: Bersihkan semua berkas log (.log)
        # yang ada di folder runtime tanpa perlu hardcode nama core.
        # =========================================================
        if ls "$RUN_DIR"/*.log >/dev/null 2>&1; then
            for file in "$RUN_DIR"/*.log; do
                if [ -f "$file" ]; then
                    : > "$file"
                fi
            done
            echo "[QTUN] All dynamic core runtime logs successfully cleared"
        else
            echo "[QTUN] No logs found to clear"
        fi
        ;;
    *)
        echo "Usage: $0 {process|rotate|clear}"
        exit 1
        ;;
esac
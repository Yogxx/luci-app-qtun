#!/bin/sh
# /etc/qtun/action/qtun.sh

# Mengambil mode aktif dari UCI
MODE="$(uci -q get qtun.main.mode 2>/dev/null)"
BACKEND="$(uci -q get qtun.main.backend 2>/dev/null)"
ENABLED="$(uci -q get qtun.main.enabled 2>/dev/null)"
ACTION="${1:-start}"

RUN="/etc/qtun/run"

WATCHDOG_SH="/etc/qtun/action/watchdog.sh"
WATCHDOG_PID="$RUN/watchdog.pid"

BACKEND_SH="/etc/qtun/action/backend.sh"

mkdir -p "$RUN"

log() {
    /etc/qtun/action/logs.sh process "$1"
}

start_watchdog() {
    [ -x "$WATCHDOG_SH" ] || {
        log "Watchdog not found or not executable"
        return 1
    }

    if [ -f "$WATCHDOG_PID" ]; then
        PID="$(cat "$WATCHDOG_PID" 2>/dev/null)"
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            log "QTUN watchdog already running"
            return 0
        fi
    fi

    log "Starting QTUN watchdog"
    "$WATCHDOG_SH" >/dev/null 2>&1 &
    echo "$!" > "$WATCHDOG_PID"
}

stop_watchdog() {
    if [ -f "$WATCHDOG_PID" ]; then
        PID="$(cat "$WATCHDOG_PID" 2>/dev/null)"
        [ -n "$PID" ] && kill "$PID" 2>/dev/null
        rm -f "$WATCHDOG_PID"
        log "QTUN watchdog stopped"
    fi
}

need_backend() {
    case "$MODE" in
        ssh|ssh_ws|ssh_ssl|hysteria|v2ray|xray)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

start_backend() {
    need_backend || {
        log "Backend not used for mode ${MODE:-none}"
        return 0
    }

    [ -x "$BACKEND_SH" ] || {
        log "backend.sh not found or not executable"
        return 1
    }

    log "Starting backend: ${BACKEND:-clash}"
    "$BACKEND_SH" start || return 1
}

stop_backend() {
    [ -x "$BACKEND_SH" ] && "$BACKEND_SH" stop
}

status_backend() {
    if [ -x "$BACKEND_SH" ]; then
        "$BACKEND_SH" status
    else
        log "backend.sh not found or not executable"
    fi
}

# =========================================================
# START MODE (MANUAL START)
# =========================================================
start_mode() {
    # LOG FORMAT: Initializing QTUN mode "q-ssh"
    log "Initializing QTUN mode \"${MODE:-none}\""

    case "$MODE" in
        zivpn)
            /etc/qtun/action/zivpn.sh start || exit 1
            ;;
        q-ssh)
            /etc/qtun/action/q-ssh.sh start || exit 1
            ;;
        clash)
            /etc/qtun/action/clash.sh start || exit 1
            ;;
        ssh)
            /etc/qtun/action/ssh.sh start || exit 1
            ;;
        ssh_ws)
            /etc/qtun/action/ssh_ws.sh start || exit 1
            ;;
        ssh_ssl)
            /etc/qtun/action/ssh_ssl.sh start || exit 1
            ;;
        "")
            log "No mode configured (qtun.main.mode)"
            exit 1
            ;;
        *)
            log "Unknown mode: $MODE"
            exit 1
            ;;
    esac

    start_backend || exit 1

    /etc/qtun/action/routing.sh start

    case "$MODE" in
        clash|q-ssh)
            log "Watchdog skipped for clash mode"
            ;;
        *)
            start_watchdog
            ;;
    esac
}

# =========================================================
# BOOT MODE (AUTOSTART ONLY)
# =========================================================
boot_mode() {
    if [ "$ENABLED" != "1" ]; then
        log "QTUN autostart disabled (qtun.main.enabled=0)"
        exit 0
    fi

    log "QTUN autostart enabled"
    start_mode
}

# =========================================================
# STOP ALL
# =========================================================
stop_mode() {
    stop_watchdog

    /etc/qtun/action/routing.sh stop

    stop_backend

    # =========================================================
    # PERBAIKAN UTAMA: HANYA HENTIKAN CORE YANG SEDANG AKTIF
    # =========================================================
    if [ -n "$MODE" ] && [ -x "/etc/qtun/action/$MODE.sh" ]; then
        /etc/qtun/action/"$MODE.sh" stop
    fi
    
    # Cetakan log terpadu skrip utama
    log "QTUN mode \"${MODE:-none}\" stack stopped"
    sleep 2
}

# =========================================================
# STATUS
# =========================================================
status_mode() {
    log "Enabled (autostart): ${ENABLED:-0}"
    log "Mode: ${MODE:-none}"
    log "Backend option: ${BACKEND:-none}"

    if [ -f "$WATCHDOG_PID" ]; then
        PID="$(cat "$WATCHDOG_PID" 2>/dev/null)"

        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            log "Watchdog: RUNNING (PID $PID)"
        else
            log "Watchdog: DEAD"
        fi
    else
        log "Watchdog: STOPPED"
    fi

    case "$MODE" in
        zivpn)
            [ -x /etc/qtun/action/zivpn.sh ] && /etc/qtun/action/zivpn.sh status
            ;;
        q-ssh)
            [ -x /etc/qtun/action/q-ssh.sh ] && /etc/qtun/action/q-ssh.sh status
            ;;
        clash)
            [ -x /etc/qtun/action/clash.sh ] && /etc/qtun/action/clash.sh status
            ;;
        ssh)
            [ -x /etc/qtun/action/ssh.sh ] && /etc/qtun/action/ssh.sh status
            ;;
        ssh_ws)
            [ -x /etc/qtun/action/ssh_ws.sh ] && /etc/qtun/action/ssh_ws.sh status
            ;;
        ssh_ssl)
            [ -x /etc/qtun/action/ssh_ssl.sh ] && /etc/qtun/action/ssh_ssl.sh status
            ;;
    esac

    status_backend

    /etc/qtun/action/routing.sh status
}

# =========================================================
# ACTION ROUTER
# =========================================================
case "$ACTION" in
    start)
        stop_mode
        start_mode
        ;;
    boot)
        stop_mode
        boot_mode
        ;;
    stop)
        stop_mode
        ;;
    restart)
        stop_mode
        sleep 1
        start_mode
        ;;
    status)
        status_mode
        ;;
    *)
        echo "Usage: $0 {start|boot|stop|restart|status}"
        exit 1
        ;;
esac
#!/bin/sh
# /etc/qtun/action/backend.sh

QTUN="/etc/qtun"

MODE="$(uci -q get qtun.main.mode 2>/dev/null)"
BACKEND="$(uci -q get qtun.main.backend 2>/dev/null)"

[ -z "$BACKEND" ] && BACKEND="clash"

BACKEND_CLASH="$QTUN/action/backend.clash"
BACKEND_TUN="$QTUN/action/backend.tun"

log() {
    /etc/qtun/action/logs.sh process "[backend] $1"
}

need_backend() {
    case "$MODE" in
        ssh|ssh_ws|ssh_ssl|hysteria|v2ray|xray|vmess|vless|trojan)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

start_backend() {
    need_backend || {
        log "Backend not needed for mode: ${MODE:-none}"
        return 0
    }

    case "$BACKEND" in
        clash)
            [ -x "$BACKEND_CLASH" ] || {
                log "backend.clash not found or not executable"
                return 1
            }

            log "Starting backend: clash"
            "$BACKEND_CLASH" start
            ;;

        tun)
            [ -x "$BACKEND_TUN" ] || {
                log "backend.tun not found or not executable"
                return 1
            }

            log "Starting backend: tun"
            "$BACKEND_TUN" start
            ;;

        *)
            log "Unknown backend: $BACKEND"
            return 1
            ;;
    esac
}

stop_backend() {
    [ -x "$BACKEND_CLASH" ] && "$BACKEND_CLASH" stop
    [ -x "$BACKEND_TUN" ] && "$BACKEND_TUN" stop
}

status_backend() {
    log "Mode: ${MODE:-none}"
    log "Backend: ${BACKEND:-clash}"

    case "$BACKEND" in
        clash)
            [ -x "$BACKEND_CLASH" ] && "$BACKEND_CLASH" status
            ;;
        tun)
            [ -x "$BACKEND_TUN" ] && "$BACKEND_TUN" status
            ;;
    esac
}

case "$1" in
    start)
        start_backend
        ;;
    stop)
        stop_backend
        ;;
    restart)
        stop_backend
        sleep 1
        start_backend
        ;;
    status)
        status_backend
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
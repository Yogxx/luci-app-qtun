#!/bin/sh
# /etc/qtun/action/watchdog.sh
# QTUN Multi Mode Watchdog
# Flow:
# proxy fail -> restart WAN iface -> wait iface IP -> test proxy -> reconnect active mode if needed

QTUN="/etc/qtun"
LOG_SH="$QTUN/action/logs.sh"

CHECK_URL="http://ifconfig.me"
QLOAD_PROXY="127.0.0.1:7777"

FAIL_LIMIT=3
SLEEP_TIME=20
WAIT_WAN_MAX=60

STATE_DIR="$QTUN/run"
LAST_IFACE="$STATE_DIR/last_wan_iface"

mkdir -p "$STATE_DIR"

log() {
    "$LOG_SH" process "[watchdog] $1"
}

get_qtun_mode() {
    uci -q get qtun.main.mode 2>/dev/null
}

proxy_ok() {
    local current_mode
    current_mode="$(get_qtun_mode)"

    # =========================================================
    # OPTIMALISASI KHUSUS MODE Q-SSH (MURNI VIA NETSTAT)
    # =========================================================
    if [ "$current_mode" = "q-ssh" ]; then
        # 1. Pastikan binarinya masih hidup di background
        if ! pgrep Q-SSH-WORKER >/dev/null 2>&1; then
            log "Q-SSH-WORKER process died"
            return 1
        fi

        # 2. Cek apakah ada port 1080-1089 berstatus LISTEN pada localhost via netstat
        if netstat -an 2>/dev/null | grep -q "127.0.0.1:108[0-9].*LISTEN"; then
            return 0  # Port aktif, tunnel dianggap sehat
        fi

        log "Q-SSH-WORKER is running but ports 108x disappeared (Modem/Internet down)"
        return 1  # Port hilang, watchdog akan memicu recovery
    fi

    # Pengujian internet standar untuk mode selain q-ssh (zivpn, dll)
    curl -I -s --max-time 10 --socks5-hostname "$QLOAD_PROXY" "$CHECK_URL" >/dev/null 2>&1
}

get_default_dev() {
    ip route show default 2>/dev/null | awk '
        /default/ {
            for (i=1; i<=NF; i++) {
                if ($i == "dev") {
                    print $(i+1)
                    exit
                }
            }
        }
    '
}

get_uci_iface_by_dev() {
    local dev="$1"

    [ -n "$dev" ] || return 1

    ubus call network.interface dump 2>/dev/null | jsonfilter -e \
        "@.interface[@.device='$dev'].interface" 2>/dev/null | head -n1
}

detect_wan_iface() {
    local dev iface

    dev="$(get_default_dev)"

    if [ -n "$dev" ]; then
        echo "$dev" > "$LAST_IFACE"

        iface="$(get_uci_iface_by_dev "$dev")"
        [ -n "$iface" ] && {
            echo "$iface"
            return 0
        }
    fi

    if [ -f "$LAST_IFACE" ]; then
        dev="$(cat "$LAST_IFACE" 2>/dev/null)"
        iface="$(get_uci_iface_by_dev "$dev")"
        [ -n "$iface" ] && {
            echo "$iface"
            return 0
        }
    fi

    for iface in wan wwan modem lte usb tethering; do
        ifstatus "$iface" >/dev/null 2>&1 && {
            echo "$iface"
            return 0
        }
    done

    return 1
}

restart_wan_iface() {
    local iface dev

    iface="$(detect_wan_iface)"

    if [ -z "$iface" ]; then
        log "WAN interface not found, skipping interface restart"
        return 1
    fi

    log "Restarting WAN interface: $iface"

    ifdown "$iface" >/dev/null 2>&1
    sleep 4
    ifup "$iface" >/dev/null 2>&1

    sleep 3
    dev="$(get_default_dev)"
    [ -n "$dev" ] && echo "$dev" > "$LAST_IFACE"

    return 0
}

iface_has_ip() {
    local dev="$1"

    [ -n "$dev" ] || return 1

    ip -4 addr show dev "$dev" 2>/dev/null | \
        awk '/inet / {print $2}' | \
        grep -vqE '^(127\.|169\.254\.)'
}

wait_iface_ip() {
    local dev
    local i=0

    log "Waiting WAN interface IP..."

    while [ "$i" -lt "$WAIT_WAN_MAX" ]; do
        dev="$(get_default_dev)"

        [ -z "$dev" ] && [ -f "$LAST_IFACE" ] && dev="$(cat "$LAST_IFACE" 2>/dev/null)"

        if iface_has_ip "$dev"; then
            log "WAN interface has IP on $dev"
            return 0
        fi

        sleep 2
        i=$((i + 2))
    done

    log "WAN interface IP not found"
    return 1
}

reconnect_tunnel_by_mode() {
    local mode

    mode="$(get_qtun_mode)"

    log "Active QTUN mode: ${mode:-unknown}"

    case "$mode" in
        zivpn)
            /etc/qtun/action/zivpn.sh reconnect-zivpn
            ;;
        ssh)
            /etc/qtun/action/ssh.sh reconnect-ssh
            ;;
        hysteria)
            /etc/qtun/action/hysteria.sh reconnect-hysteria
            ;;
        v2ray)
            /etc/qtun/action/v2ray.sh reconnect-v2ray
            ;;
        xray)
            /etc/qtun/action/xray.sh reconnect-xray
            ;;
        *)
            log "Unsupported QTUN mode: ${mode:-empty}"
            return 1
            ;;
    esac
}

recover_qtun() {
    local mode
    mode="$(get_qtun_mode)"
    log "Starting recovery for mode: ${mode:-unknown}"

    # =========================================================
    # PENANGANAN KHUSUS MODE Q-SSH (CONNECT Q-SSH ONLY)
    # =========================================================
    if [ "$mode" = "q-ssh" ]; then
        log "Q-SSH ports are down. Step 1: Refreshing WAN/Modem interface..."
        
        # 1. Restart interface jaringan modem Anda
        restart_wan_iface
        
        # 2. Tunggu jaringan modem mendapatkan IP kembali
        if wait_iface_ip; then
            # PERBAIKAN TIMING: Beri waktu modem stabil 5 detik sebelum pemicu dial
            sleep 5
            log "Step 2: WAN interface is back online"
            
            # =========================================================
            # STRATEGI BARU: LOOP PENGECEKAN NETSTAT 3x PER 20 DETIK
            # =========================================================
            local attempt=1
            local success=1
            
            while [ $attempt -le 3 ]; do
                log "Waiting 20 seconds for Q-SSH-WORKER native handshake (Attempt $attempt/3)..."
                sleep 20
                
                if proxy_ok; then
                    log "Recovery success: Modem refreshed and Q-SSH-WORKER re-established natively on attempt $attempt!"
                    success=0
                    break
                fi
                
                attempt=$((attempt + 1))
            done
            
            if [ $success -eq 0 ]; then
                return 0
            fi
            
            log "Recovery failed: Ports did not return after 60 seconds of native re-dialing."
        else
            log "Recovery failed: WAN interface did not get an IP in time."
        fi
        return 1
    fi

    # =========================================================
    # LOGIKA LAMA UNTUK MODE INJECTOR LAINNYA (ZIVPN, SSH, dll)
    # =========================================================
    restart_wan_iface || log "WAN interface restart failed or skipped"
    wait_iface_ip || return 1
    sleep 5

    if proxy_ok; then
        log "Recovery success after WAN interface restart only"
        return 0
    fi

    log "Proxy still unhealthy, reconnecting active tunnel mode"
    reconnect_tunnel_by_mode || return 1
    sleep 5

    if proxy_ok; then
        log "Recovery success after tunnel reconnect"
        return 0
    fi

    log "Recovery failed, proxy still unhealthy"
    return 1
}

log "QTUN multi mode watchdog started"

FAIL_COUNT=0
RECOVERING=0

while true; do
    if proxy_ok; then
        FAIL_COUNT=0
        RECOVERING=0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "Proxy check failed ($FAIL_COUNT/$FAIL_LIMIT)"

        if [ "$FAIL_COUNT" -ge "$FAIL_LIMIT" ] && [ "$RECOVERING" = "0" ]; then
            RECOVERING=1
            recover_qtun
            FAIL_COUNT=0
            RECOVERING=0
        fi
    fi

    sleep "$SLEEP_TIME"
done
#!/bin/sh
# /etc/qtun/action/routing.sh
# QTUN Routing Engine - Multi-Mode Adaptive Version

set -u

CLASH_PORT="7892"
DNS_PORT="1053"
QLOAD_PORT="7777"

CLASH_ACTIVE_CFG="/etc/qtun/config/clash/active/config.yaml"
BACKEND_CLASH_CFG="/etc/qtun/config/backend/clash/config.yaml"

MODE="$(uci -q get qtun.main.mode 2>/dev/null)"
BACKEND="$(uci -q get qtun.main.backend 2>/dev/null)"
[ -z "$BACKEND" ] && BACKEND="clash"

QTUN_CHAIN="QTUN"
QTUN_DNS_CHAIN="QTUN_DNS"

log() {
    /etc/qtun/action/logs.sh process "[routing] $1"
}

# Fungsi memeriksa apakah Core berjalan dalam Mode TUN via Runtime Config yang aktif
check_tun_mode() {
    # 1. Jika backend adalah 'tun' (Sing-Box), sudah pasti native TUN auto-route
    if [ "$BACKEND" = "tun" ]; then
        return 0
    fi

    # 2. Jika backend adalah 'clash'
    if [ "$BACKEND" = "clash" ]; then
        TARGET_CHECK_CFG=""

        # Tentukan target file berdasarkan isi $MODE
        if [ "$MODE" = "clash" ]; then
            TARGET_CHECK_CFG="$CLASH_ACTIVE_CFG"
        else
            TARGET_CHECK_CFG="$BACKEND_CLASH_CFG"
        fi

        # Eksekusi pengecekan parameter TUN di dalam berkas YAML yang tepat
        if [ -n "$TARGET_CHECK_CFG" ] && [ -f "$TARGET_CHECK_CFG" ]; then
            if grep -A 10 "^tun:" "$TARGET_CHECK_CFG" 2>/dev/null | grep -q "enable: true"; then
                log "Otomatisasi: Deteksi tun: enable: true pada berkas $TARGET_CHECK_CFG"
                return 0
            fi
        fi
    fi

    return 1
}

create_chains() {
    iptables -t nat -N $QTUN_CHAIN 2>/dev/null
    iptables -t nat -N $QTUN_DNS_CHAIN 2>/dev/null
}

flush_chains() {
    iptables -t nat -F $QTUN_CHAIN 2>/dev/null
    iptables -t nat -F $QTUN_DNS_CHAIN 2>/dev/null
}

delete_hooks() {
    iptables -t nat -D OUTPUT -p tcp -j $QTUN_CHAIN 2>/dev/null
    iptables -t nat -D PREROUTING -i br-lan -p tcp -j $QTUN_CHAIN 2>/dev/null

    iptables -t nat -D OUTPUT -p udp --dport 53 -j $QTUN_DNS_CHAIN 2>/dev/null
    iptables -t nat -D OUTPUT -p tcp --dport 53 -j $QTUN_DNS_CHAIN 2>/dev/null

    iptables -t nat -D PREROUTING -i br-lan -p udp --dport 53 -j $QTUN_DNS_CHAIN 2>/dev/null
    iptables -t nat -D PREROUTING -i br-lan -p tcp --dport 53 -j $QTUN_DNS_CHAIN 2>/dev/null
}

destroy_chains() {
    iptables -t nat -X $QTUN_CHAIN 2>/dev/null
    iptables -t nat -X $QTUN_DNS_CHAIN 2>/dev/null
}

apply_bypass_rules() {
    # Bypass Jaringan Lokal (RFC 1918 & Core Local Bypass)
    iptables -t nat -A $QTUN_CHAIN -d 0.0.0.0/8 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -d 169.254.0.0/16 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -d 224.0.0.0/4 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -d 240.0.0.0/4 -j RETURN

    # Dynamic Bypass Server IP berdasarkan mode aktif
    case "$MODE" in
        # =========================================================
        # PERBAIKAN UTAMA: BYPASS IP VPS UNTUK MODE Q-SSH
        # Ekstraksi IP endpoint langsung menggunakan core binary
        # =========================================================
        q-ssh)
            if [ -x "/etc/qtun/core/Q-SSH-WORKER" ] && [ -f "/etc/qtun/config/q-ssh/config.json" ]; then
                # 1. Bypass IP VPS/Endpoint Asli
                SERVER_IP=$(/etc/qtun/core/Q-SSH-WORKER --show-endpoint /etc/qtun/config/q-ssh/config.json 2>/dev/null)
                if [ -n "$SERVER_IP" ]; then
                    log "Menambahkan bypass IP VPS Q-SSH: $SERVER_IP"
                    iptables -t nat -A $QTUN_CHAIN -d "$SERVER_IP" -j RETURN
                fi

                # 2. BACA DAN BYPASS IP PROXY/BUG DARI CONFIG JSON (KUNCI ANTI LOG LINGLUNG)
                PROXY_IP=$(jsonfilter -i "/etc/qtun/config/q-ssh/config.json" -e '@.proxy.host' 2>/dev/null)
                if [ -n "$PROXY_IP" ] && [ "$PROXY_IP" != "127.0.0.1" ]; then
                    log "Menambahkan bypass IP Proxy Bug Q-SSH: $PROXY_IP"
                    iptables -t nat -A $QTUN_CHAIN -d "$PROXY_IP" -j RETURN
                fi
            fi
            ;;
        zivpn)
            SERVER_IP="$(uci -q get qtun.main.z_server | cut -d':' -f1)"
            if [ -n "$SERVER_IP" ]; then
                iptables -t nat -A $QTUN_CHAIN -d "$SERVER_IP" -j RETURN
            fi
            ;;
        ssh|ssh_ws|ssh_ssl)
            SSH_PROFILE="$(uci -q get qtun.ssh.profile 2>/dev/null)"
            if [ -n "$SSH_PROFILE" ]; then
                SERVER_IP="$(uci -q get qtun.ssh.$SSH_PROFILE.host 2>/dev/null)"
                [ -n "$SERVER_IP" ] && iptables -t nat -A $QTUN_CHAIN -d "$SERVER_IP" -j RETURN
            fi
            ;;
        v2ray|xray|vmess|vless|trojan)
            V2RAY_PROFILE="$(uci -q get qtun.v2ray.profile 2>/dev/null)"
            if [ -n "$V2RAY_PROFILE" ]; then
                SERVER_IP="$(uci -q get qtun.v2ray.$V2RAY_PROFILE.address 2>/dev/null)"
                [ -n "$SERVER_IP" ] && iptables -t nat -A $QTUN_CHAIN -d "$SERVER_IP" -j RETURN
            fi
            ;;
        clash)
            CLASH_PROF="$(uci -q get qtun.clash.profile)"
            CLASH_ACTIVE_CFG="/etc/qtun/config/clash/mihomo/$CLASH_PROF"
            
            if [ -n "$CLASH_PROF" ] && [ -f "$CLASH_ACTIVE_CFG" ]; then
                log "Mengekstrak daftar IP Server dari profil Clash aktif: $CLASH_PROF"
                SERVER_LIST=$(grep -E '^[[:space:]]*-?[[:space:]]*server:' "$CLASH_ACTIVE_CFG" | awk '{print $2}' | sed 's/"//g; s/\x27//g')
                
                for s_host in $SERVER_LIST; do
                    s_ip=$(ping -c 1 -W 1 "$s_host" 2>/dev/null | grep -E -o '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]' | head -n1)
                    if [ -n "$s_ip" ]; then
                        log "Menambahkan multi-bypass IP Server Clash: $s_ip"
                        iptables -t nat -A $QTUN_CHAIN -d "$s_ip" -j RETURN
                    fi
                done
            fi
            ;;
    esac

    # Bypass port aplikasi lokal & management dashboard
    iptables -t nat -A $QTUN_CHAIN -p tcp --dport 7890 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -p tcp --dport "$CLASH_PORT" -j RETURN
    iptables -t nat -A $QTUN_CHAIN -p tcp --dport 9090 -j RETURN
    iptables -t nat -A $QTUN_CHAIN -p tcp --dport "$DNS_PORT" -j RETURN
    
    # KUNCI MULTI-WORKER: Bypass gerbang utama q-load aggregator port 7777
    iptables -t nat -A $QTUN_CHAIN -p tcp --dport "$QLOAD_PORT" -j RETURN

    # Bypass seluruh jangkauan port internal workers (1080 - 1087)
    iptables -t nat -A $QTUN_CHAIN -p tcp --dport 1080:1087 -j RETURN
}

apply_redirect_rules() {
    # Lempar seluruh traffic TCP global ke Clash Redir Port
    iptables -t nat -A $QTUN_CHAIN -p tcp -j REDIRECT --to-ports "$CLASH_PORT"

    # Cegat query DNS dan belokkan ke Clash DNS
    iptables -t nat -A $QTUN_DNS_CHAIN -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
    iptables -t nat -A $QTUN_DNS_CHAIN -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
}

apply_hooks() {
    # Tangkap traffic dari router internal
    iptables -t nat -A OUTPUT -p tcp -j $QTUN_CHAIN

    # Tangkap traffic dari client hotspot / LAN (br-lan)
    iptables -t nat -A PREROUTING -i br-lan -p tcp -j $QTUN_CHAIN

    # Tangkap DNS dari router local
    iptables -t nat -A OUTPUT -p udp --dport 53 -j $QTUN_DNS_CHAIN
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j $QTUN_DNS_CHAIN

    # Tangkap DNS dari client hotspot / LAN
    iptables -t nat -A PREROUTING -i br-lan -p udp --dport 53 -j $QTUN_DNS_CHAIN
    iptables -t nat -A PREROUTING -i br-lan -p tcp --dport 53 -j $QTUN_DNS_CHAIN
}

start_routing() {
    log "Initializing routing engine system..."

    # Selalu bersihkan sisa hooks lama untuk mencegah aturan ganda
    stop_routing

    # Jalankan pengecekan otomatis Mode TUN
    if check_tun_mode; then
        log "Otomatisasi: Mode TUN terdeteksi aktif via $BACKEND."
        log "Aturan NAT REDIRECT dilewati. Routing ditangani langsung oleh Core."
        return 0
    fi

    log "Otomatisasi: Mode NAT REDIRECT dideteksi. Menerapkan iptables..."
    
    create_chains
    flush_chains

    apply_bypass_rules
    apply_redirect_rules
    apply_hooks

    log "iptables routing successfully applied"
}

stop_routing() {
    log "Clearing firewall routing rules..."

    delete_hooks
    flush_chains
    destroy_chains

    log "Routing stopped clean"
}

status_routing() {
    log "Current Profile Mode: ${MODE:-none}"
    log "Current Backend Engine: ${BACKEND:-clash}"
    echo ""
    log "QTUN Traffic NAT Table:"
    iptables -t nat -L $QTUN_CHAIN -n --line-numbers 2>/dev/null || log "QTUN chain inactive"
    echo ""
    log "QTUN DNS Redirection Table:"
    iptables -t nat -L $QTUN_DNS_CHAIN -n --line-numbers 2>/dev/null || log "QTUN_DNS chain inactive"
}

case "$1" in
    start)   start_routing ;;
    stop)    stop_routing ;;
    restart) stop_routing && sleep 1 && start_routing ;;
    status)  status_routing ;;
    *)       echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
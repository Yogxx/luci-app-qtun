#!/bin/sh
# /etc/qtun/action/clash.sh
# QTUN Clash/Mihomo Mode
# default/default.yaml = QTUN fixed settings
# mihomo/*.yaml       = user profiles
# active/config.yaml  = generated runtime config
# active profile      = stored in UCI qtun.clash.profile

BASE="/etc/qtun/config/clash"

DEFAULT_CFG="$BASE/default/default.yaml"
PROFILE_DIR="$BASE/mihomo"
ACTIVE_CFG="$BASE/active/config.yaml"

CLASH_BIN="/etc/qtun/core/clash"
CLASH_LOG="/etc/qtun/run/clash.log"
CLASH_PID="/etc/qtun/run/clash.pid"

log() {
    /etc/qtun/action/logs.sh process "[clash] $1"
}

is_running() {
    [ -f "$CLASH_PID" ] && kill -0 "$(cat "$CLASH_PID" 2>/dev/null)" 2>/dev/null
}

prepare_dirs() {
    mkdir -p "$BASE/active" "$BASE/default" "$BASE/mihomo"
    mkdir -p /etc/qtun/run
}

get_active_profile() {
    PROFILE="$(uci -q get qtun.clash.profile 2>/dev/null)"

    if [ -n "$PROFILE" ]; then
        echo "$PROFILE"
        return 0
    fi

    ls "$PROFILE_DIR"/*.yaml 2>/dev/null | head -n1 | xargs -n1 basename
}

save_active_profile_if_empty() {
    PROFILE="$1"

    [ -n "$(uci -q get qtun.clash.profile 2>/dev/null)" ] && return 0
    [ -n "$PROFILE" ] || return 0

    uci set qtun.clash=clash 2>/dev/null
    uci set qtun.clash.profile="$PROFILE"
    uci commit qtun
}

extract_section() {
    section="$1"
    file="$2"

    [ -f "$file" ] || return 0

    awk -v sec="$section" '
        BEGIN { found=0 }

        $0 ~ "^"sec":" {
            found=1
            print
            next
        }

        found && /^[A-Za-z0-9_-]+:/ {
            exit
        }

        found {
            print
        }
    ' "$file"
}

append_section() {
    section="$1"
    file="$2"

    DATA="$(extract_section "$section" "$file")"

    [ -n "$DATA" ] || return 0

    echo "$DATA" >> "$ACTIVE_CFG"
    echo "" >> "$ACTIVE_CFG"
}

generate_config() {
    prepare_dirs

    [ -f "$DEFAULT_CFG" ] || {
        log "Default config not found: $DEFAULT_CFG"
        return 1
    }

    PROFILE="$(get_active_profile)"

    [ -n "$PROFILE" ] || {
        log "No active profile found in $PROFILE_DIR"
        return 1
    }

    USER_CFG="$PROFILE_DIR/$PROFILE"

    [ -f "$USER_CFG" ] || {
        log "User profile not found: $USER_CFG"
        return 1
    }

    save_active_profile_if_empty "$PROFILE"

    awk '
        /^proxy-providers:/ { exit }
        /^proxies:/ { exit }
        /^proxy-groups:/ { exit }
        /^rule-providers:/ { exit }
        /^rules:/ { exit }
        { print }
    ' "$DEFAULT_CFG" > "$ACTIVE_CFG"

    echo "" >> "$ACTIVE_CFG"

    append_section "proxy-providers" "$USER_CFG"
    append_section "proxies" "$USER_CFG"
    append_section "proxy-groups" "$USER_CFG"
    append_section "rule-providers" "$USER_CFG"
    append_section "rules" "$USER_CFG"

    if ! grep -qE '^proxies:|^proxy-providers:' "$ACTIVE_CFG"; then
        log "Generated config missing proxies/proxy-providers"
        return 1
    fi

    if ! grep -q '^proxy-groups:' "$ACTIVE_CFG"; then
        log "Generated config missing proxy-groups"
        return 1
    fi

    if ! grep -q '^rules:' "$ACTIVE_CFG"; then
        log "Generated config missing rules"
        return 1
    fi

    log "Generated active config: $ACTIVE_CFG from UCI profile: $PROFILE"
    return 0
}

start_clash() {
    log "Starting Clash mode"

    prepare_dirs

    [ -x "$CLASH_BIN" ] || {
        log "Clash binary not found: $CLASH_BIN"
        return 1
    }

    generate_config || return 1

    stop_clash >/dev/null 2>&1

    "$CLASH_BIN" -d "$BASE" -f "$ACTIVE_CFG" > "$CLASH_LOG" 2>&1 &
    echo "$!" > "$CLASH_PID"

    sleep 3

    if is_running; then
        log "Clash started PID $(cat "$CLASH_PID")"
        return 0
    fi

    log "Clash failed"
    [ -f "$CLASH_LOG" ] && cat "$CLASH_LOG"
    return 1
}

stop_clash() {
    if is_running; then
        kill "$(cat "$CLASH_PID" 2>/dev/null)" 2>/dev/null
        sleep 1
    fi

    killall clash >/dev/null 2>&1
    killall mihomo >/dev/null 2>&1
    rm -f "$CLASH_PID"

    log "Clash stopped"
}

status_clash() {
    PROFILE="$(uci -q get qtun.clash.profile 2>/dev/null)"

    if is_running; then
        log "Clash: RUNNING PID $(cat "$CLASH_PID")"
    else
        log "Clash: STOPPED"
    fi

    log "Active profile: ${PROFILE:-auto}"
    [ -f "$ACTIVE_CFG" ] && log "Active config: $ACTIVE_CFG"
}

case "$1" in
    start)
        start_clash
        ;;
    stop)
        stop_clash
        ;;
    restart)
        stop_clash
        sleep 1
        start_clash
        ;;
    status)
        status_clash
        ;;
    generate)
        generate_config
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|generate}"
        exit 1
        ;;
esac
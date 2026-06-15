#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  ELITE-X SLOWDNS VPN v5.0 - FALCON ULTRA MAX BOOST
#  Enhanced: SlowDNS Multi-Protocol | 3Proxy | SOCKS5 | UDP+TCP
#  Language: Bash installer + Pure C daemons
#  Author  : ELITE-X Team | +255713-628-668
# ═══════════════════════════════════════════════════════════════════

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'
ORANGE='\033[0;33m'; LIGHT_RED='\033[1;31m'; LIGHT_GREEN='\033[1;32m'
GRAY='\033[0;90m'; MAGENTA='\033[1;35m'; BLINK='\033[5m'; NC='\033[0m'
BG_BLUE='\033[44m'; BG_GREEN='\033[42m'; BG_RED='\033[41m'

# ═══════════════════════════════════════════════════════════
# OS DETECTION + PACKAGE MANAGER ABSTRACTION
# Inasapoti: Fedora, RHEL/CentOS/Rocky/Alma, Amazon Linux 2 & 2023
# ═══════════════════════════════════════════════════════════
OS_ID="unknown"; OS_VERSION_ID=""; OS_NAME="Unknown Linux"
PKG_MANAGER="unknown"; IS_AMAZON_LINUX=0; HAS_SELINUX=0

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-}"
        OS_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
    fi

    case "$OS_ID" in
        amzn)
            IS_AMAZON_LINUX=1
            if [ "$OS_VERSION_ID" = "2" ]; then
                PKG_MANAGER="yum"
            else
                # Amazon Linux 2023+ hutumia dnf
                command -v dnf >/dev/null 2>&1 && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
            fi
            ;;
        fedora)
            IS_AMAZON_LINUX=0
            PKG_MANAGER="dnf"
            ;;
        rhel|centos|rocky|almalinux|ol)
            IS_AMAZON_LINUX=0
            command -v dnf >/dev/null 2>&1 && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
            ;;
        *)
            IS_AMAZON_LINUX=0
            if command -v dnf >/dev/null 2>&1; then
                PKG_MANAGER="dnf"
            elif command -v yum >/dev/null 2>&1; then
                PKG_MANAGER="yum"
            else
                PKG_MANAGER="unknown"
            fi
            ;;
    esac

    [ -f /etc/selinux/config ] && command -v setenforce >/dev/null 2>&1 && HAS_SELINUX=1

    echo -e "${CYAN}🖥️  OS Imetambuliwa: ${WHITE}${OS_NAME}${CYAN} | Package Manager: ${WHITE}${PKG_MANAGER}${NC}"
    if [ "$IS_AMAZON_LINUX" = "1" ]; then
        echo -e "${CYAN}☁️  Amazon Linux imetambuliwa - VPN itasanidiwa kwa mipangilio ya AWS${NC}"
    fi
}

# pkg_install: install moja au zaidi ya packages bila kuvunja installation
# nzima kama package moja haipatikani kwenye repo (tofauti na 'dnf install a b c'
# ambayo inaweza kushindwa YOTE kama 'a' au 'b' haipo). Hii ni muhimu sana kwa
# Amazon Linux ambapo majina ya baadhi ya packages ni tofauti na Fedora.
pkg_install() {
    local pkgs=("$@")
    [ ${#pkgs[@]} -eq 0 ] && return 0

    case "$PKG_MANAGER" in
        dnf|yum)
            if "$PKG_MANAGER" install -y "${pkgs[@]}" >/dev/null 2>&1; then
                return 0
            fi
            # Batch imeshindwa - jaribu kila package mmoja mmoja
            local p
            for p in "${pkgs[@]}"; do
                "$PKG_MANAGER" install -y "$p" >/dev/null 2>&1 || true
            done
            ;;
        *)
            echo -e "${RED}⚠️  Package manager haijatambuliwa - sikuweza install: ${pkgs[*]}${NC}"
            ;;
    esac
}

# install_rust_toolchain: weka rustc+cargo kwa ajili ya kucompile ma-daemon
# mapya yaliyoandikwa kwa Rust. Inajaribu package manager kwanza (Fedora na
# Amazon Linux 2023 zina "rust"/"cargo" kwenye dnf repos), kisha rustup kama
# fallback (muhimu Amazon Linux 2 / images ndogo zisizo na rust kwenye repo).
install_rust_toolchain() {
    if command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${YELLOW}📦 Installing Rust toolchain (rustc + cargo)...${NC}"
    pkg_install rust cargo

    if ! command -v cargo >/dev/null 2>&1; then
        echo -e "${YELLOW}⚙️ Rust haipo kwenye repo - kuiweka kupitia rustup...${NC}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
            | sh -s -- -y --default-toolchain stable --profile minimal >/dev/null 2>&1
        # shellcheck disable=SC1091
        [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    if command -v cargo >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Rust toolchain tayari (cargo $(cargo --version 2>/dev/null | awk '{print $2}'))${NC}"
        return 0
    else
        echo -e "${RED}❌ Imeshindwa kuweka Rust toolchain${NC}"
        return 1
    fi
}

STATIC_PRIVATE_KEY="7f207e92ab7cb365aad1966b62d2cfbd3f450fe8e523a38ffc7ecfbcec315693"
STATIC_PUBLIC_KEY="40aa057fcb2574e1e9223ea46457f9fdf9d60a2a1c23da87602202d93b41aa04"
ACTIVATION_KEY="ELITE"
TIMEZONE="Africa/Dar_es_Salaam"

USER_DB="/etc/elite-x/users"
USAGE_DB="/etc/elite-x/data_usage"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
PIDTRACK_DIR="$BANDWIDTH_DIR/pidtrack"
BANNED_DB="/etc/elite-x/banned"
CONN_DB="/etc/elite-x/connections"
DELETED_DB="/etc/elite-x/deleted"
AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"
SERVER_MSG_DIR="/etc/elite-x/server_msg"
USER_MSG_DIR="/etc/elite-x/user_messages"

# Ports
PORT_SLOWDNS_UDP=53
PORT_SLOWDNS_TCP=5300
PORT_UDP_TURBO=5301
PORT_UDP_TURBO2=5302
PORT_3PROXY_HTTP=3128
PORT_3PROXY_SOCKS5=1080
PORT_SLOWDNS_SOCKS5=1081
PORT_DNSTT_SOCKS5=1082

show_banner() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}${BOLD}   ELITE-X SLOWDNS VPN v5.0 - FALCON ULTRA     ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${CYAN}   SlowDNS Multi-Protocol | 3Proxy | SOCKS5 | UDP+TCP Turbo  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${GREEN}     Speed 30Mbps+ | BBR3 | Zero Ping | MTU 1802 MAX       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_color() { echo -e "${2}${1}${NC}"; }
set_timezone() {
    timedatectl set-timezone "$TIMEZONE" 2>/dev/null || \
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════
# COLORFUL USER MESSAGE ON SSH LOGIN (HTML VERSION)
# ═══════════════════════════════════════════════════════════
force_user_message() {
    local username="$1"
    local msg_file="$USER_MSG_DIR/$username"
    mkdir -p "$USER_MSG_DIR"

    local expire_date bandwidth_gb conn_limit
    expire_date=$(grep "Expire:" "$USER_DB/$username" 2>/dev/null | awk '{print $2}')
    bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$username" 2>/dev/null | awk '{print $2}')
    conn_limit=$(grep "Conn_Limit:" "$USER_DB/$username" 2>/dev/null | awk '{print $2}')
    bandwidth_gb=${bandwidth_gb:-0}
    conn_limit=${conn_limit:-1}

    local usage_bytes usage_gb
    usage_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
    usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

    # Get accurate connection count via /proc (works Ubuntu 18-24)
    local current_conn=0
    local _uid; _uid=$(id -u "$username" 2>/dev/null || echo "")
    if [ -n "$_uid" ]; then
        for _pid_dir in /proc/[0-9]*/; do
            local _pid="${_pid_dir%/}"; _pid="${_pid##*/proc/}"
            [ -f "${_pid_dir}comm" ] || continue
            [ "$(cat "${_pid_dir}comm" 2>/dev/null)" = "sshd" ] || continue
            local _uid_check; _uid_check=$(awk '/^Uid:/{print $2}' "${_pid_dir}status" 2>/dev/null)
            [ "$_uid_check" = "$_uid" ] || continue
            local _ppid; _ppid=$(awk '{print $4}' "${_pid_dir}stat" 2>/dev/null)
            [ "$_ppid" = "1" ] && continue
            current_conn=$((current_conn + 1))
        done
    fi
    current_conn=${current_conn:-0}

    local now_ts expire_ts remaining_seconds remaining_days remaining_hours remaining_mins
    now_ts=$(date +%s)
    expire_ts=$(date -d "$expire_date" +%s 2>/dev/null || echo 0)
    remaining_seconds=$((expire_ts - now_ts))
    [ $remaining_seconds -lt 0 ] && remaining_seconds=0
    remaining_days=$((remaining_seconds / 86400))
    remaining_hours=$(((remaining_seconds % 86400) / 3600))
    remaining_mins=$(((remaining_seconds % 3600) / 60))

    local bw_display="Unlimited"
    [ "$bandwidth_gb" != "0" ] && bw_display="${bandwidth_gb} GB"

    local status_icon status_text
    if [ $remaining_days -le 0 ] && [ $remaining_hours -eq 0 ]; then
        status_icon="⛔"; status_text="EXPIRED"
    elif [ $remaining_days -le 3 ]; then
        status_icon="⚠️"; status_text="EXPIRING SOON"
    else
        status_icon="🟢"; status_text="ACTIVE"
    fi

    # Online/Offline status kulingana na devices zilizounganishwa sasa hivi
    local online_icon online_text online_color
    if [ "$current_conn" -gt 0 ]; then
        online_icon="🔴"; online_text="ONLINE (${current_conn} device(s) connected)"
        online_color="#ff4444"
    else
        online_icon="⚫"; online_text="OFFLINE"
        online_color="#888888"
    fi

    # === HAPA NDIPO TUNAPOWEKA HTML NDANI YA SCRIPT ===
    cat <<EOF > "$msg_file"
<div style="background-color: #000000; color: #ffffff; font-family: 'Courier New', Courier, monospace; padding: 20px; border-radius: 5px; display: inline-block; white-space: pre; line-height: 1.4;">
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #000000; font-weight: bold;">     ELITE-X SLOWDNS VPN v5.0      </span><span style="color: #ffff00; font-weight: bold;">▐</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;"> USERNAME  </span>: <span style="color: #00ff00; font-weight: bold;">$username</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> EXPIRE    </span>: <span style="color: #ff0000; font-weight: bold;">$expire_date</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> REMAINING </span>: <span style="color: #00ffff; font-weight: bold;">${remaining_days}d + ${remaining_hours}hr + ${remaining_mins}min</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> LIMIT GB  </span>: <span style="color: #00ff00; font-weight: bold;">$bw_display</span>
<span style="color: #ffff00; font-weight: bold;"> USAGE GB  </span>: <span style="color: #ff0000; font-weight: bold;">$usage_gb GB</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> DEVICES   </span>: <span style="color: #ff00ff; font-weight: bold;">$current_conn / $conn_limit slots used</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> ONLINE    </span>: <span style="color: ${online_color}; font-weight: bold;">$online_icon $online_text</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> STATUS    </span>: <span style="color: #00ff00; font-weight: bold;">$status_icon $status_text</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="background-color: #00ff00; color: #ffffff; font-weight: bold; display: block; text-align: center;">   Thanks for using ELITE-X VPN    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #00ff00; font-weight: bold;"> Whatsapp| https://rb.gy/xuh4eo  </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
</div>
EOF

    chmod 644 "$msg_file"
    echo "$msg_file"
}

# ═══════════════════════════════════════════════════════════
# SSH CONFIGURATION WITH USER-SPECIFIC BANNERS
# ═══════════════════════════════════════════════════════════
configure_ssh_for_vpn() {
    echo -e "${YELLOW}🔧 Configuring SSH for VPN + Colorful User Messages...${NC}"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    sed -i '/^Banner/d; /^Match User/d; /Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' \
        /etc/ssh/sshd_config 2>/dev/null

    cat > /etc/ssh/sshd_config.d/elite-x-base.conf <<'SSHCONF'
# ELITE-X VPN Base Configuration v5.0
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes

AllowTcpForwarding yes
AllowAgentForwarding yes
GatewayPorts yes
PermitTunnel yes
PermitOpen any

TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 6
MaxStartups 500:30:1000
MaxSessions 500

# Performance
Compression no
UseDNS no
LogLevel VERBOSE
IPQoS lowdelay throughput
SSHCONF

    # Build per-user banners
    cat > /etc/ssh/sshd_config.d/elite-x-users.conf <<'SSHCONF2'
# ELITE-X Dynamic User Banners - v5.0
SSHCONF2

    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            [ -f "$user_file" ] || continue
            local username msg_file
            username=$(basename "$user_file")
            msg_file=$(force_user_message "$username")
            echo "Match User $username" >> /etc/ssh/sshd_config.d/elite-x-users.conf
            echo "    Banner $msg_file" >> /etc/ssh/sshd_config.d/elite-x-users.conf
        done
    fi

    echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    echo -e "${GREEN}✅ SSH configured with Colorful User Messages${NC}"
}

# ═══════════════════════════════════════════════════════════
# PAM + LOGIN SCRIPT
# ═══════════════════════════════════════════════════════════
configure_pam_user_message() {
    echo -e "${YELLOW}🔧 Configuring PAM for automatic user message update...${NC}"

    cat > /usr/local/bin/elite-x-update-user-msg <<'SCRIPT'
#!/bin/bash
USERNAME="$PAM_USER"
if [ -n "$USERNAME" ] && [ -f "/etc/elite-x/users/$USERNAME" ]; then
    /usr/local/bin/elite-x-force-user-message "$USERNAME" 2>/dev/null
fi
SCRIPT
    chmod +x /usr/local/bin/elite-x-update-user-msg

    cat > /usr/local/bin/elite-x-force-user-message <<'FORCE'
#!/bin/bash
USERNAME="$1"
USER_DB="/etc/elite-x/users"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
USER_MSG_DIR="/etc/elite-x/user_messages"

if [ -z "$USERNAME" ] || [ ! -f "$USER_DB/$USERNAME" ]; then exit 0; fi
mkdir -p "$USER_MSG_DIR"
MSG_FILE="$USER_MSG_DIR/$USERNAME"

expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}
conn_limit=${conn_limit:-1}

usage_bytes=$(cat "$BANDWIDTH_DIR/${USERNAME}.usage" 2>/dev/null || echo 0)
usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

# Accurate connection count via /proc (works Ubuntu 18.04 - 24.04)
# Count sshd processes owned by user where ppid != 1 (real sessions only)
current_conn=0
_uid=$(id -u "$USERNAME" 2>/dev/null || echo "")
if [ -n "$_uid" ]; then
    for _pd in /proc/[0-9]*/; do
        [ -f "${_pd}comm" ] || continue
        [ "$(cat "${_pd}comm" 2>/dev/null)" = "sshd" ] || continue
        _puid=$(awk '/^Uid:/{print $2}' "${_pd}status" 2>/dev/null)
        [ "$_puid" = "$_uid" ] || continue
        _ppid=$(awk '{print $4}' "${_pd}stat" 2>/dev/null)
        [ "$_ppid" = "1" ] && continue
        current_conn=$((current_conn + 1))
    done
fi
current_conn=${current_conn:-0}

now_ts=$(date +%s)
expire_ts=$(date -d "$expire_date" +%s 2>/dev/null || echo 0)
remaining_seconds=$((expire_ts - now_ts))
[ $remaining_seconds -lt 0 ] && remaining_seconds=0
remaining_days=$((remaining_seconds / 86400))
remaining_hours=$(((remaining_seconds % 86400) / 3600))
remaining_mins=$(((remaining_seconds % 3600) / 60))

bw_display="Unlimited"
[ "$bandwidth_gb" != "0" ] && bw_display="${bandwidth_gb} GB"

if [ $remaining_days -le 0 ] && [ $remaining_hours -eq 0 ]; then
    status_icon="⛔"; status_text="EXPIRED"
elif [ $remaining_days -le 3 ]; then
    status_icon="⚠️"; status_text="EXPIRING SOON"
else
    status_icon="🟢"; status_text="ACTIVE"
fi

    cat <<EOF > "$MSG_FILE"
<div style="background-color: #000000; color: #ffffff; font-family: 'Courier New', Courier, monospace; padding: 20px; border-radius: 5px; display: inline-block; white-space: pre; line-height: 1.4;">
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #00ffff; font-weight: bold;"> <cente>ELITE-X SLOWDNS VPN v5.0 </center>  </span><span style="color: #ffff00; font-weight: bold;">▐</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;"> USERNAME  </span>: <span style="color: #00ff00; font-weight: bold;">$USERNAME</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> EXPIRE    </span>: <span style="color: #ff0000; font-weight: bold;">$expire_date</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> REMAINING </span>: <span style="color: #00ffff; font-weight: bold;">${remaining_days}d + ${remaining_hours}hr + ${remaining_mins}min</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> LIMIT GB  </span>: <span style="color: #00ff00; font-weight: bold;">$bw_display</span>
<span style="color: #ffff00; font-weight: bold;"> USAGE GB  </span>: <span style="color: #ff0000; font-weight: bold;">$usage_gb GB</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> CONNECTION</span>: <span style="color: #ff00ff; font-weight: bold;">$current_conn/$conn_limit</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> STATUS    </span>: <span style="color: #00ff00; font-weight: bold;">$status_icon $status_text</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #00ffff; font-weight: bold;">   Thanks for using ELITE-X VPN    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #00ff00; font-weight: bold;"> Whatsapp| https://shorturl.at/N6bn2   </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
</div>
EOF

    chmod 644 "$MSG_FILE"

sed -i "/Match User $USERNAME/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
echo "Match User $USERNAME" >> /etc/ssh/sshd_config.d/elite-x-users.conf
echo "    Banner $MSG_FILE" >> /etc/ssh/sshd_config.d/elite-x-users.conf
systemctl reload sshd 2>/dev/null || kill -HUP $(cat /var/run/sshd.pid 2>/dev/null) 2>/dev/null || true
echo "$USERNAME: message updated" >> /var/log/elite-x-user-msgs.log 2>/dev/null
FORCE
    chmod +x /usr/local/bin/elite-x-force-user-message

    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    echo "session optional pam_exec.so seteuid /usr/local/bin/elite-x-update-user-msg" >> /etc/pam.d/sshd
    echo -e "${GREEN}✅ PAM configured - colorful message updates on each login${NC}"
}

# ═══════════════════════════════════════════════════════════
# SUPER SYSTEM OPTIMIZATION - MAXIMUM BOOST v5.0
# ═══════════════════════════════════════════════════════════
optimize_system_for_vpn() {
    echo -e "${YELLOW}🚀 Applying MAXIMUM system optimizations for 30Mbps+...${NC}"

    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true
    modprobe nf_conntrack 2>/dev/null || true

    cat > /etc/sysctl.d/99-elite-x-vpn.conf <<'SYSCTL'
# ═══ ELITE-X v5.0 ULTRA  SYSCTL ═══
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

net.core.rmem_max=536870912
net.core.wmem_max=536870912
net.core.rmem_default=524288
net.core.wmem_default=524288
net.ipv4.tcp_rmem=4096 262144 536870912
net.ipv4.tcp_wmem=4096 131072 536870912
net.ipv4.tcp_mem=786432 1048576 26777216

net.core.optmem_max=131072
net.ipv4.udp_mem=204800 1747600 33554432
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072

net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_no_pmtu_disc=0

net.ipv4.tcp_max_syn_backlog=65536
net.core.somaxconn=65536
net.core.netdev_max_backlog=50000
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=5
net.ipv4.tcp_syn_retries=3
net.ipv4.tcp_synack_retries=3

net.ipv4.tcp_keepalive_time=30
net.ipv4.tcp_keepalive_intvl=5
net.ipv4.tcp_keepalive_probes=6

net.core.netdev_budget=1000
net.core.netdev_budget_usecs=8000
net.core.busy_read=50
net.core.busy_poll=50

vm.swappiness=5
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=3
vm.min_free_kbytes=65536

fs.file-max=2097152
fs.nr_open=2097152

# ═══ ANTI SPEED-DROP: conntrack tuning ═══
# Conntrack table inayojaa TIME_WAIT/CLOSE_WAIT ndio sababu kuu ya
# speed ku-drop baada ya saa kadhaa mpaka VPS i-reboot. Hizi settings
# huongeza table size na kupunguza muda wa entries zilizofungwa.
net.netfilter.nf_conntrack_max=1048576
net.netfilter.nf_conntrack_tcp_timeout_established=600
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
net.netfilter.nf_conntrack_tcp_timeout_close_wait=15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=15
net.netfilter.nf_conntrack_tcp_timeout_close=10
SYSCTL

    sysctl -p /etc/sysctl.d/99-elite-x-vpn.conf >/dev/null 2>&1 || true

    cat > /etc/security/limits.d/elite-x.conf <<'LIMITS'
* soft nofile 2097152
* hard nofile 2097152
* soft nproc 65536
* hard nproc 65536
root soft nofile 2097152
root hard nofile 2097152
LIMITS

    mkdir -p /etc/systemd/system.conf.d/
    cat > /etc/systemd/system.conf.d/elite-x-limits.conf <<'SDLIMIT'
[Manager]
DefaultLimitNOFILE=2097152
DefaultLimitNPROC=65536
SDLIMIT

    iptables -t nat -A POSTROUTING -j MASQUERADE 2>/dev/null || true
    iptables -A FORWARD -i lo -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -o lo -j ACCEPT 2>/dev/null || true

    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
        ethtool -K "$iface" gso on gro on tso on 2>/dev/null || true
        ip link set "$iface" txqueuelen 10000 2>/dev/null || true
    done

    # ── Anti speed-drop: weka mfumo wa kurudia optimizations automatically ──
    setup_persistent_optimizations

    echo -e "${GREEN}✅ MAXIMUM system optimization applied (30Mbps+ ready)${NC}"
}

# ═══════════════════════════════════════════════════════════
# ANTI SPEED-DROP: AUTO RE-APPLY YA NETWORK OPTIMIZATIONS
# Baadhi ya VPS providers / NetworkManager hurudisha mipangilio ya
# sysctl, ethtool offloads na qdisc kwenye default baada ya muda au
# baada ya DHCP renew - hii husababisha speed kupungua bila VPS
# kuwa imerebootiwa. Function hii inaweka systemd timer + NetworkManager
# dispatcher ili kurudia mipangilio kila baada ya dakika 3 na pia
# inasafisha conntrack entries zilizofungwa (TIME_WAIT/CLOSE_WAIT)
# zinazoshikilia nafasi kwenye connection table bila sababu.
# ═══════════════════════════════════════════════════════════
setup_persistent_optimizations() {
    echo -e "${YELLOW}🔁 Configuring auto re-apply ya optimizations (anti speed-drop)...${NC}"

    cat > /usr/local/bin/elite-x-reapply-netopt <<'REAPPLY'
#!/bin/bash
# ELITE-X: rudia mipangilio ya speed bila kuhitaji reboot

sysctl -p /etc/sysctl.d/99-elite-x-vpn.conf >/dev/null 2>&1 || true

for iface in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
    ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
    ethtool -K "$iface" gso on gro on tso on 2>/dev/null || true
    ip link set "$iface" txqueuelen 10000 2>/dev/null || true
    tc qdisc replace dev "$iface" root fq 2>/dev/null || true
done

# Hakikisha BBR + FQ bado vimewekwa (baadhi ya mifumo huyarudisha default)
sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
sysctl -w net.core.default_qdisc=fq           >/dev/null 2>&1 || true

# Safisha conntrack entries zilizofungwa - zinazojaza connection table
# na kusababisha "speed drop mpaka reboot"
if command -v conntrack >/dev/null 2>&1; then
    conntrack -D -p tcp --state TIME_WAIT  >/dev/null 2>&1 || true
    conntrack -D -p tcp --state CLOSE_WAIT >/dev/null 2>&1 || true
fi
REAPPLY
    chmod +x /usr/local/bin/elite-x-reapply-netopt

    cat > /etc/systemd/system/elite-x-netreapply.service <<'EOF'
[Unit]
Description=ELITE-X Re-apply network speed optimizations
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/elite-x-reapply-netopt
EOF

    cat > /etc/systemd/system/elite-x-netreapply.timer <<'EOF'
[Unit]
Description=ELITE-X periodic network optimization re-apply (anti speed-drop)

[Timer]
OnBootSec=30
OnUnitActiveSec=3min
AccuracySec=10s
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now elite-x-netreapply.timer 2>/dev/null || true

    # NetworkManager dispatcher - rudia mipangilio mara interface ikiwa "up"
    # tena (AWS/Amazon Linux na mifumo mingine inayotumia NetworkManager)
    if [ -d /etc/NetworkManager/dispatcher.d ]; then
        cat > /etc/NetworkManager/dispatcher.d/99-elite-x-netopt <<'EOF'
#!/bin/bash
case "$2" in
    up|dhcp4-change|dhcp6-change)
        /usr/local/bin/elite-x-reapply-netopt
        ;;
esac
EOF
        chmod +x /etc/NetworkManager/dispatcher.d/99-elite-x-netopt
    fi

    echo -e "${GREEN}✅ Auto re-apply imewekwa - speed haitodrop hata bila reboot${NC}"
}

# ═══════════════════════════════════════════════════════════
# INSTALL & CONFIGURE 3PROXY (HTTP + SOCKS5)
# For SlowDNS and DNSTT tunneling
# ═══════════════════════════════════════════════════════════
install_3proxy() {
    echo -e "${YELLOW}📦 Installing 3proxy (HTTP + SOCKS5 for SlowDNS/DNSTT)...${NC}"

    # 3proxy haipo kwenye repos za RPM-based distros (Fedora/RHEL/Amazon Linux)
    # - compile moja kwa moja kutoka source
    if ! command -v 3proxy >/dev/null 2>&1; then
        echo -e "${YELLOW}⚙️ Compiling 3proxy from source (${OS_NAME})...${NC}"
        pkg_install gcc make git
        rm -rf /tmp/3proxy-src
        cd /tmp
        # Jaribu repo mpya kwanza, kisha ya zamani
        git clone --depth=1 https://github.com/3proxy/3proxy.git 3proxy-src 2>/dev/null || \
        git clone --depth=1 https://github.com/z3APA3A/3proxy.git 3proxy-src 2>/dev/null
        if [ -d /tmp/3proxy-src ]; then
            cd /tmp/3proxy-src
            make -f Makefile.Linux 2>/dev/null || make 2>/dev/null
            # Tafuta binary mahali popote ilipoundwa
            PROXY_BIN=$(find /tmp/3proxy-src -name "3proxy" -type f 2>/dev/null | head -1)
            if [ -n "$PROXY_BIN" ]; then
                cp "$PROXY_BIN" /usr/local/bin/3proxy
                chmod +x /usr/local/bin/3proxy
                echo -e "${GREEN}✅ 3proxy compiled successfully${NC}"
            else
                echo -e "${RED}❌ 3proxy compilation failed - proxy ports zitakuwa hazifanyi kazi${NC}"
            fi
            cd /; rm -rf /tmp/3proxy-src
        else
            echo -e "${RED}❌ 3proxy git clone imeshindwa - angalia internet connection${NC}"
        fi
    fi

    mkdir -p /etc/3proxy /var/log/3proxy

    # 3proxy configuration:
    # - Port 3128: HTTP proxy (for SlowDNS and DNSTT users)
    # - Port 1080: SOCKS5 proxy (global)
    # - Port 1081: SOCKS5 proxy dedicated for SlowDNS
    # - Port 1082: SOCKS5 proxy dedicated for DNSTT
    cat > /etc/3proxy/3proxy.cfg <<PROXY3CFG
# ELITE-X 3Proxy v5.0 Configuration
# Supports: HTTP, SOCKS5 for SlowDNS & DNSTT

daemon
pidfile /var/run/3proxy.pid
log /var/log/3proxy/3proxy.log D
logformat "- +_L%t.%.  %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30

# Max connections
maxconn 1000

# Auth file (users auto-managed)
users /etc/3proxy/users.list

# Timeouts
timeouts 1 5 30 60 180 1800 15 60

# Internal IP binding
nscache 65536
nscache6 65536

# === HTTP Proxy on port 3128 (SlowDNS/DNSTT) ===
auth strong
allow * * * * *
proxy -p${PORT_3PROXY_HTTP} -i0.0.0.0 -e0.0.0.0

# === SOCKS5 on port 1080 (global) ===
auth strong
allow * * * * *
socks -p${PORT_3PROXY_SOCKS5} -i0.0.0.0 -e0.0.0.0

# === SOCKS5 on port 1081 (dedicated SlowDNS) ===
auth strong
allow * * * * *
socks -p${PORT_SLOWDNS_SOCKS5} -i0.0.0.0 -e0.0.0.0

# === SOCKS5 on port 1082 (dedicated DNSTT) ===
auth strong
allow * * * * *
socks -p${PORT_DNSTT_SOCKS5} -i0.0.0.0 -e0.0.0.0
PROXY3CFG

    # Initial empty users list
    touch /etc/3proxy/users.list
    chmod 600 /etc/3proxy/users.list /etc/3proxy/3proxy.cfg

    # 3proxy systemd service
    cat > /etc/systemd/system/3proxy-elite.service <<EOF
[Unit]
Description=ELITE-X 3Proxy HTTP+SOCKS5 for SlowDNS/DNSTT
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/var/run/3proxy.pid
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✅ 3proxy configured: HTTP(:3128) SOCKS5(:1080,:1081,:1082)${NC}"
}

# ═══════════════════════════════════════════════════════════
# ADD/REMOVE USER FROM 3PROXY
# ═══════════════════════════════════════════════════════════
add_3proxy_user() {
    local username="$1" password="$2"
    local hashed
    hashed=$(echo -n "${username}:${password}" | md5sum | awk '{print $1}')
    sed -i "/^${username}:/d" /etc/3proxy/users.list 2>/dev/null
    echo "${username}:CL:${password}" >> /etc/3proxy/users.list
    systemctl reload 3proxy-elite 2>/dev/null || systemctl restart 3proxy-elite 2>/dev/null || true
}

delete_3proxy_user() {
    local username="$1"
    sed -i "/^${username}:/d" /etc/3proxy/users.list 2>/dev/null
    systemctl reload 3proxy-elite 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════
# C: ULTRA EDNS PROXY (Thread Pool + Rate Limiting)
# ═══════════════════════════════════════════════════════════
create_c_edns_proxy() {
    echo -e "${YELLOW}📝 Compiling ULTRA EDNS Proxy v5...${NC}"

    cat > /tmp/edns_proxy.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <pthread.h>
#include <fcntl.h>
#include <sys/resource.h>

#define BUFFER_SIZE        65536
#define DNS_PORT           53
#define BACKEND_PORT       5300
#define MAX_EDNS_SIZE      2000
#define MIN_EDNS_SIZE      512
#define THREAD_POOL_SIZE   64
#define QUEUE_SIZE         65536
#define MAX_EPOLL_EVENTS   1024
#define BACKEND_TIMEOUT_MS 3000
#define SOCKET_BUF_SIZE    (16 * 1024 * 1024)

static volatile int running = 1;
static int main_sock = -1;

void signal_handler(int sig) { running = 0; if (main_sock >= 0) close(main_sock); }

static int skip_name(const unsigned char *data, int offset, int max_len) {
    while (offset < max_len) {
        unsigned char len = data[offset++];
        if (len == 0) break;
        if ((len & 0xC0) == 0xC0) { offset++; break; }
        offset += len;
        if (offset >= max_len) break;
    }
    return offset;
}

static void modify_edns(unsigned char *data, int *len, unsigned short max_size) {
    if (*len < 12) return;
    int offset = 12;
    unsigned short qdcount = ntohs(*(unsigned short*)(data+4));
    unsigned short ancount = ntohs(*(unsigned short*)(data+6));
    unsigned short nscount = ntohs(*(unsigned short*)(data+8));
    unsigned short arcount = ntohs(*(unsigned short*)(data+10));
    int i;
    for (i = 0; i < qdcount; i++) {
        offset = skip_name(data, offset, *len);
        if (offset + 4 > *len) return;
        offset += 4;
    }
    for (i = 0; i < ancount + nscount; i++) {
        offset = skip_name(data, offset, *len);
        if (offset + 10 > *len) return;
        unsigned short rdlen = ntohs(*(unsigned short*)(data+offset+8));
        offset += 10 + rdlen;
    }
    for (i = 0; i < arcount; i++) {
        offset = skip_name(data, offset, *len);
        if (offset + 10 > *len) return;
        unsigned short rrtype = ntohs(*(unsigned short*)(data+offset));
        if (rrtype == 41) {
            unsigned short size = htons(max_size);
            memcpy(data + offset + 2, &size, 2);
            return;
        }
        unsigned short rdlen = ntohs(*(unsigned short*)(data+offset+8));
        offset += 10 + rdlen;
    }
}

typedef struct {
    int                 sock;
    struct sockaddr_in  client_addr;
    socklen_t           client_len;
    unsigned char      *data;
    int                 data_len;
} work_item_t;

/* Lock-free ring queue */
typedef struct {
    work_item_t       **items;
    volatile int        head, tail;
    int                 cap;
    pthread_mutex_t     mtx;
    pthread_cond_t      cnd;
} work_queue_t;

static work_queue_t wq;

static void queue_init(work_queue_t *q) {
    q->cap  = QUEUE_SIZE;
    q->head = q->tail = 0;
    q->items = calloc(QUEUE_SIZE, sizeof(work_item_t*));
    pthread_mutex_init(&q->mtx, NULL);
    pthread_cond_init(&q->cnd, NULL);
}

static int queue_push(work_queue_t *q, work_item_t *w) {
    pthread_mutex_lock(&q->mtx);
    int next = (q->tail + 1) % q->cap;
    if (next == q->head) { pthread_mutex_unlock(&q->mtx); return -1; }
    q->items[q->tail] = w; q->tail = next;
    pthread_cond_signal(&q->cnd);
    pthread_mutex_unlock(&q->mtx);
    return 0;
}

static work_item_t *queue_pop(work_queue_t *q) {
    pthread_mutex_lock(&q->mtx);
    while (q->head == q->tail && running) pthread_cond_wait(&q->cnd, &q->mtx);
    if (q->head == q->tail) { pthread_mutex_unlock(&q->mtx); return NULL; }
    work_item_t *w = q->items[q->head];
    q->head = (q->head + 1) % q->cap;
    pthread_mutex_unlock(&q->mtx);
    return w;
}

static void *worker_thread(void *arg) {
    (void)arg;
    while (running) {
        work_item_t *w = queue_pop(&wq);
        if (!w) continue;

        modify_edns(w->data, &w->data_len, MAX_EDNS_SIZE);

        int bsock = socket(AF_INET, SOCK_DGRAM, 0);
        if (bsock < 0) { free(w->data); free(w); continue; }
        struct timeval tv = {3, 0};
        setsockopt(bsock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(bsock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        int sb = 32*1024*1024;
        setsockopt(bsock, SOL_SOCKET, SO_RCVBUF, &sb, sizeof(sb));
        setsockopt(bsock, SOL_SOCKET, SO_SNDBUF, &sb, sizeof(sb));

        struct sockaddr_in backend = {
            .sin_family      = AF_INET,
            .sin_addr.s_addr = inet_addr("127.0.0.1"),
            .sin_port        = htons(BACKEND_PORT)
        };

        sendto(bsock, w->data, w->data_len, 0, (struct sockaddr*)&backend, sizeof(backend));

        unsigned char resp[BUFFER_SIZE];
        socklen_t bl = sizeof(backend);
        int rn = recvfrom(bsock, resp, BUFFER_SIZE, 0, (struct sockaddr*)&backend, &bl);
        if (rn > 0) {
            modify_edns(resp, &rn, MAX_EDNS_SIZE);
            sendto(w->sock, resp, rn, 0, (struct sockaddr*)&w->client_addr, w->client_len);
        }
        close(bsock);
        free(w->data);
        free(w);
    }
    return NULL;
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGPIPE, SIG_IGN);

    struct rlimit rl = { .rlim_cur = 1048576, .rlim_max = 1048576 };
    setrlimit(RLIMIT_NOFILE, &rl);

    queue_init(&wq);

    pthread_t pool[THREAD_POOL_SIZE];
    int i;
    for (i = 0; i < THREAD_POOL_SIZE; i++) {
        pthread_attr_t a; pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        pthread_create(&pool[i], &a, worker_thread, NULL);
        pthread_attr_destroy(&a);
    }

    main_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (main_sock < 0) { perror("socket"); return 1; }

    int one = 1;
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
    int rb = SOCKET_BUF_SIZE, wb = SOCKET_BUF_SIZE;
    setsockopt(main_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(main_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));

    struct sockaddr_in addr = {
        .sin_family      = AF_INET,
        .sin_addr.s_addr = INADDR_ANY,
        .sin_port        = htons(DNS_PORT)
    };

    system("fuser -k 53/udp >/dev/null 2>&1");
    usleep(500000);

    if (bind(main_sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        system("fuser -k 53/udp >/dev/null 2>&1");
        usleep(1500000);
        if (bind(main_sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            perror("bind"); close(main_sock); return 1;
        }
    }

    fcntl(main_sock, F_SETFL, fcntl(main_sock, F_GETFL) | O_NONBLOCK);
    fprintf(stderr, "[ELITE-X] C-EDNS Proxy v5.0 running (port 53, %d workers, 16MB buf)\n",
            THREAD_POOL_SIZE);

    while (running) {
        struct sockaddr_in ca; socklen_t cl = sizeof(ca);
        unsigned char *buf = malloc(BUFFER_SIZE);
        if (!buf) { usleep(1000); continue; }
        int n = recvfrom(main_sock, buf, BUFFER_SIZE, 0, (struct sockaddr*)&ca, &cl);
        if (n <= 0) {
            free(buf);
            if (errno == EAGAIN || errno == EWOULDBLOCK) { usleep(100); continue; }
            if (!running) break;
            continue;
        }
        work_item_t *w = malloc(sizeof(work_item_t));
        if (!w) { free(buf); continue; }
        w->sock = main_sock; w->client_addr = ca;
        w->client_len = cl; w->data = buf; w->data_len = n;
        if (queue_push(&wq, w) < 0) { free(buf); free(w); }
    }
    close(main_sock);
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -pthread \
        -o /usr/local/bin/elite-x-edns-proxy /tmp/edns_proxy.c 2>/dev/null
    rm -f /tmp/edns_proxy.c

    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        chmod +x /usr/local/bin/elite-x-edns-proxy
        cat > /etc/systemd/system/dnstt-elite-x-proxy.service <<EOF
[Unit]
Description=ELITE-X  ULTRA EDNS Proxy v5.0
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-edns-proxy
Restart=always
RestartSec=2
LimitNOFILE=2097152
Nice=-15
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=30
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅  ULTRA EDNS Proxy v5.0 compiled (64 workers, 16MB buffers)${NC}"
    else
        echo -e "${RED}❌  EDNS Proxy compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# RUST: UDP TURBO RELAY v5.0 (ports 5301 + 5302)
# Inajenga daemon ya Rust (memory-safe, performance sawa au bora
# kuliko C). Ikiwa Rust toolchain haipatikani au compile imeshindwa,
# inarudi kwenye toleo la C (create_c_udp_turbo) - HAKUNA UTENDAJI
# UNAOPOTEA.
# ═══════════════════════════════════════════════════════════
create_rust_udp_turbo() {
    echo -e "${YELLOW}📝 Building UDP Turbo Relay v5.0 (Rust)...${NC}"

    if ! install_rust_toolchain; then
        echo -e "${YELLOW}↩️  Rust haipatikani - kurudi kwenye toleo la C...${NC}"
        create_c_udp_turbo
        return
    fi

    local PROJ=/opt/elite-x-rust/udp-turbo
    mkdir -p "$PROJ/src"

    cat > "$PROJ/Cargo.toml" <<'CARGOEOF'
[package]
name = "elite-x-udp-turbo"
version = "5.0.0"
edition = "2021"

[dependencies]
crossbeam-channel = "0.5"
socket2 = { version = "0.5", features = ["all"] }
ctrlc = "3"

[profile.release]
opt-level = 3
lto = true
panic = "abort"
codegen-units = 1
CARGOEOF

    cat > "$PROJ/src/main.rs" <<'RUSTEOF'
// ELITE-X UDP Turbo Relay v5.0 (Rust port)
//
// Functionally equivalent to the original C daemon:
//   - Binds UDP ports 5301 AND 5302 simultaneously
//   - Forwards every received packet to the DNSTT backend on 127.0.0.1:5300
//   - Sends the backend's reply back to the original client
//   - Uses a worker thread pool (default 48 workers) fed by a bounded
//     queue, exactly like the C version's pthread pool + ring buffer
//   - Large socket buffers (16MB) and SO_REUSEADDR/SO_REUSEPORT
//
// Rust gives us memory safety (no segfault/UB that could silently kill
// the daemon and cause "speed drops until reboot"), while keeping the
// same architecture and performance characteristics as the C version.

use std::io::ErrorKind;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use crossbeam_channel::{bounded, Receiver, Sender};
use socket2::{Domain, Protocol, Socket, Type};

const BACKEND_ADDR: &str = "127.0.0.1:5300";
const RELAY_PORT1: u16 = 5301;
const RELAY_PORT2: u16 = 5302;
const BUF_SIZE: usize = 8192;
const POOL_SIZE: usize = 48;
const QUEUE_CAP: usize = 65536;
const SOCK_BUF: usize = 16 * 1024 * 1024; // 16MB, same as original
const BACKEND_SOCK_BUF: usize = 4 * 1024 * 1024; // 4MB, same as original

struct Packet {
    data: Vec<u8>,
    src: SocketAddr,
    relay: Arc<UdpSocket>,
}

/// Build a UDP socket bound to 0.0.0.0:<port> with REUSEADDR/REUSEPORT and
/// large socket buffers, matching make_relay_sock() from the C version.
fn make_relay_socket(port: u16) -> std::io::Result<UdpSocket> {
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_reuse_address(true)?;
    #[cfg(unix)]
    socket.set_reuse_port(true)?;
    let _ = socket.set_recv_buffer_size(SOCK_BUF);
    let _ = socket.set_send_buffer_size(SOCK_BUF);

    let addr: SocketAddr = SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, port).into();
    socket.bind(&addr.into())?;

    // Short read timeout so reader threads can periodically check `running`
    // and shut down cleanly (mirrors the O_NONBLOCK + usleep loop in C).
    socket.set_read_timeout(Some(Duration::from_millis(500)))?;

    Ok(socket.into())
}

/// Reads packets from a relay socket and pushes them onto the work queue.
/// Mirrors reader_thread() in the C version.
fn reader_thread(sock: Arc<UdpSocket>, tx: Sender<Packet>, running: Arc<AtomicBool>) {
    let mut buf = [0u8; BUF_SIZE];
    while running.load(Ordering::Relaxed) {
        match sock.recv_from(&mut buf) {
            Ok((n, src)) => {
                let pkt = Packet {
                    data: buf[..n].to_vec(),
                    src,
                    relay: sock.clone(),
                };
                // If the queue is full, drop the packet (same as the C
                // version's qpush(), which silently drops on overflow).
                let _ = tx.try_send(pkt);
            }
            Err(e) if e.kind() == ErrorKind::WouldBlock || e.kind() == ErrorKind::TimedOut => {
                continue;
            }
            Err(_) => continue,
        }
    }
}

/// Worker: pops a packet from the queue, forwards it to the DNSTT backend
/// on 127.0.0.1:5300, waits (up to 2s) for the reply, and relays it back
/// to the original client. Mirrors worker() in the C version.
fn worker_thread(rx: Receiver<Packet>, running: Arc<AtomicBool>) {
    while running.load(Ordering::Relaxed) {
        let pkt = match rx.recv_timeout(Duration::from_millis(500)) {
            Ok(p) => p,
            Err(_) => continue,
        };

        let backend = match UdpSocket::bind("0.0.0.0:0") {
            Ok(s) => s,
            Err(_) => continue,
        };

        if let Ok(sock_ref) = socket2::SockRef::try_from(&backend) {
            let _ = sock_ref.set_recv_buffer_size(BACKEND_SOCK_BUF);
            let _ = sock_ref.set_send_buffer_size(BACKEND_SOCK_BUF);
        }

        let _ = backend.set_read_timeout(Some(Duration::from_secs(2)));
        let _ = backend.set_write_timeout(Some(Duration::from_secs(2)));

        if backend.send_to(&pkt.data, BACKEND_ADDR).is_err() {
            continue;
        }

        let mut resp = [0u8; BUF_SIZE];
        if let Ok((n, _)) = backend.recv_from(&mut resp) {
            let _ = pkt.relay.send_to(&resp[..n], pkt.src);
        }
    }
}

fn main() {
    let running = Arc::new(AtomicBool::new(true));
    {
        let r = running.clone();
        // Handles SIGINT and SIGTERM (systemd Restart=always sends SIGTERM
        // on stop/restart), matching the sig_handler() in the C version.
        if ctrlc::set_handler(move || {
            r.store(false, Ordering::SeqCst);
        })
        .is_err()
        {
            eprintln!("[ELITE-X] Warning: failed to install signal handler");
        }
    }

    let (tx, rx) = bounded::<Packet>(QUEUE_CAP);

    let sock1 = make_relay_socket(RELAY_PORT1)
        .map_err(|e| eprintln!("[ELITE-X] bind {} failed: {}", RELAY_PORT1, e))
        .ok();
    let sock2 = make_relay_socket(RELAY_PORT2)
        .map_err(|e| eprintln!("[ELITE-X] bind {} failed: {}", RELAY_PORT2, e))
        .ok();

    if sock1.is_none() && sock2.is_none() {
        eprintln!("[ELITE-X] UDP Turbo: failed to bind any port");
        std::process::exit(1);
    }

    let mut handles = Vec::new();

    // Worker pool (POOL_SIZE threads), same as the C pthread pool.
    for _ in 0..POOL_SIZE {
        let rx = rx.clone();
        let running = running.clone();
        handles.push(std::thread::spawn(move || worker_thread(rx, running)));
    }

    // Reader threads, one per bound port.
    if let Some(s) = sock1 {
        let sock = Arc::new(s);
        let tx = tx.clone();
        let running = running.clone();
        handles.push(std::thread::spawn(move || reader_thread(sock, tx, running)));
    }
    if let Some(s) = sock2 {
        let sock = Arc::new(s);
        let tx = tx.clone();
        let running = running.clone();
        handles.push(std::thread::spawn(move || reader_thread(sock, tx, running)));
    }

    eprintln!(
        "[ELITE-X] UDP Turbo (Rust) v5.0: port {} & {} -> backend {} ({} workers)",
        RELAY_PORT1, RELAY_PORT2, BACKEND_ADDR, POOL_SIZE
    );

    // Main thread idles until a shutdown signal is received.
    while running.load(Ordering::Relaxed) {
        std::thread::sleep(Duration::from_millis(500));
    }

    drop(tx);
    for h in handles {
        let _ = h.join();
    }
}
RUSTEOF

    echo -e "${YELLOW}⚙️  Compiling Rust UDP Turbo (hii inaweza kuchukua dakika 1-3)...${NC}"
    if ( cd "$PROJ" && cargo build --release >/dev/null 2>&1 ) && \
       [ -f "$PROJ/target/release/elite-x-udp-turbo" ]; then

        cp "$PROJ/target/release/elite-x-udp-turbo" /usr/local/bin/elite-x-udp-turbo
        chmod +x /usr/local/bin/elite-x-udp-turbo

        cat > /etc/systemd/system/elite-x-udp-turbo.service <<EOF
[Unit]
Description=ELITE-X Rust UDP Turbo Relay v5.0 (port 5301+5302)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-udp-turbo
Restart=always
RestartSec=2
LimitNOFILE=1048576
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=20
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ UDP Turbo v5.0 (Rust) compiled (ports 5301+5302, 48 workers)${NC}"
    else
        echo -e "${YELLOW}⚠️  Rust build imeshindwa - kurudi kwenye toleo la C...${NC}"
        create_c_udp_turbo
    fi
}


    echo -e "${YELLOW}📝 Compiling UDP Turbo Relay v5.0 (dual-port)...${NC}"

    cat > /tmp/udp_turbo.c <<'CEOF'
/*
 * ELITE-X UDP Turbo Relay v5.0
 * Listens on port 5301 AND 5302 simultaneously
 * Forwards to DNSTT on 5300 with minimal latency
 * Thread pool, SCHED_FIFO priority, huge socket buffers
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <sys/socket.h>
#include <sys/resource.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define BACKEND_PORT    5300
#define RELAY_PORT1     5301
#define RELAY_PORT2     5302
#define BUF_SIZE        8192
#define POOL_SIZE       48
#define QUEUE_CAP       65536
#define SOCK_BUF        (16 * 1024 * 1024)

static volatile int running = 1;
void sig_handler(int s) { running = 0; }

typedef struct {
    unsigned char buf[BUF_SIZE];
    int len;
    struct sockaddr_in src;
    int relay_sock;
} pkt_t;

static pkt_t  qbuf[QUEUE_CAP];
static volatile int qhead = 0, qtail = 0;
static pthread_mutex_t qmtx = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  qcnd = PTHREAD_COND_INITIALIZER;

static void qpush(pkt_t *p) {
    pthread_mutex_lock(&qmtx);
    int next = (qtail + 1) % QUEUE_CAP;
    if (next != qhead) { qbuf[qtail] = *p; qtail = next; pthread_cond_signal(&qcnd); }
    pthread_mutex_unlock(&qmtx);
}

static int qpop(pkt_t *p) {
    pthread_mutex_lock(&qmtx);
    while (qhead == qtail && running) pthread_cond_wait(&qcnd, &qmtx);
    if (qhead == qtail) { pthread_mutex_unlock(&qmtx); return 0; }
    *p = qbuf[qhead]; qhead = (qhead + 1) % QUEUE_CAP;
    pthread_mutex_unlock(&qmtx);
    return 1;
}

static void *worker(void *arg) {
    (void)arg;
    struct sched_param sp = { .sched_priority = 15 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);

    while (running) {
        pkt_t pkt;
        if (!qpop(&pkt)) continue;

        int bs = socket(AF_INET, SOCK_DGRAM, 0);
        if (bs < 0) continue;
        struct timeval tv = {2, 0};
        setsockopt(bs, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(bs, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        int sb = 4*1024*1024;
        setsockopt(bs, SOL_SOCKET, SO_RCVBUF, &sb, sizeof(sb));
        setsockopt(bs, SOL_SOCKET, SO_SNDBUF, &sb, sizeof(sb));

        struct sockaddr_in back = {
            .sin_family = AF_INET,
            .sin_addr.s_addr = inet_addr("127.0.0.1"),
            .sin_port = htons(BACKEND_PORT)
        };
        sendto(bs, pkt.buf, pkt.len, 0, (struct sockaddr*)&back, sizeof(back));

        unsigned char resp[BUF_SIZE];
        socklen_t bl = sizeof(back);
        int rn = recvfrom(bs, resp, BUF_SIZE, 0, (struct sockaddr*)&back, &bl);
        if (rn > 0 && pkt.relay_sock >= 0)
            sendto(pkt.relay_sock, resp, rn, 0, (struct sockaddr*)&pkt.src, sizeof(pkt.src));
        close(bs);
    }
    return NULL;
}

static int make_relay_sock(int port) {
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) return -1;
    int one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(s, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
    int rb = SOCK_BUF, wb = SOCK_BUF;
    setsockopt(s, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(s, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = INADDR_ANY,
        .sin_port = htons(port)
    };
    if (bind(s, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind"); close(s); return -1;
    }
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    return s;
}

static void *reader_thread(void *arg) {
    int sock = *(int*)arg;
    while (running) {
        pkt_t pkt; pkt.relay_sock = sock;
        socklen_t sl = sizeof(pkt.src);
        int n = recvfrom(sock, pkt.buf, BUF_SIZE, 0, (struct sockaddr*)&pkt.src, &sl);
        if (n <= 0) { usleep(100); continue; }
        pkt.len = n;
        qpush(&pkt);
    }
    return NULL;
}

int main(void) {
    signal(SIGTERM, sig_handler);
    signal(SIGINT,  sig_handler);
    signal(SIGPIPE, SIG_IGN);

    struct rlimit rl = {1048576, 1048576};
    setrlimit(RLIMIT_NOFILE, &rl);

    int sock1 = make_relay_sock(RELAY_PORT1);
    int sock2 = make_relay_sock(RELAY_PORT2);

    if (sock1 < 0 && sock2 < 0) {
        fprintf(stderr, "[ELITE-X] UDP Turbo: failed to bind any port\n");
        return 1;
    }

    /* Worker thread pool */
    pthread_t pool[POOL_SIZE];
    int i;
    for (i = 0; i < POOL_SIZE; i++) {
        pthread_attr_t a; pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        pthread_create(&pool[i], &a, worker, NULL);
        pthread_attr_destroy(&a);
    }

    /* Reader threads for each port */
    pthread_t rt1, rt2;
    if (sock1 >= 0) {
        static int s1; s1 = sock1;
        pthread_create(&rt1, NULL, reader_thread, &s1);
    }
    if (sock2 >= 0) {
        static int s2; s2 = sock2;
        pthread_create(&rt2, NULL, reader_thread, &s2);
    }

    fprintf(stderr, "[ELITE-X] UDP Turbo v5.0: port %d & %d → backend %d (%d workers)\n",
            RELAY_PORT1, RELAY_PORT2, BACKEND_PORT, POOL_SIZE);

    if (sock1 >= 0) pthread_join(rt1, NULL);
    if (sock2 >= 0) pthread_join(rt2, NULL);

    if (sock1 >= 0) close(sock1);
    if (sock2 >= 0) close(sock2);
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -pthread \
        -o /usr/local/bin/elite-x-udp-turbo /tmp/udp_turbo.c 2>/dev/null
    rm -f /tmp/udp_turbo.c

    if [ -f /usr/local/bin/elite-x-udp-turbo ]; then
        chmod +x /usr/local/bin/elite-x-udp-turbo
        cat > /etc/systemd/system/elite-x-udp-turbo.service <<EOF
[Unit]
Description=ELITE-X C UDP Turbo Relay v5.0 (port 5301+5302)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-udp-turbo
Restart=always
RestartSec=2
LimitNOFILE=1048576
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=20
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ UDP Turbo v5.0 compiled (ports 5301+5302, 48 workers)${NC}"
    else
        echo -e "${RED}❌ UDP Turbo compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SLOWDNS MULTI-PROTOCOL RELAY
# Supports UDP + TCP for SlowDNS with SOCKS5 output
# ═══════════════════════════════════════════════════════════
create_c_slowdns_relay() {
    echo -e "${YELLOW}📝 Compiling C SlowDNS Multi-Protocol Relay v5.0...${NC}"

    cat > /tmp/slowdns_relay.c <<'CEOF'
/*
 * ELITE-X SlowDNS Multi-Protocol Relay v5.0
 * - Listens UDP :5303 and TCP :5304
 * - Forwards to DNSTT backend :5300
 * - Provides both UDP and TCP entry for SlowDNS clients
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/resource.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define UDP_LISTEN_PORT   5303
#define TCP_LISTEN_PORT   5304
#define BACKEND_PORT      5300
#define BUF_SIZE          8192
#define TCP_POOL_SIZE     32
#define UDP_POOL_SIZE     32
#define QUEUE_CAP         32768
#define SOCK_BUF          (8 * 1024 * 1024)

static volatile int running = 1;
void sig_h(int s) { running = 0; }

/* ── UDP relay ── */
typedef struct { unsigned char buf[BUF_SIZE]; int len; struct sockaddr_in src; } upkt_t;
static upkt_t uqbuf[QUEUE_CAP];
static volatile int uqh = 0, uqt = 0;
static pthread_mutex_t uqm = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  uqc = PTHREAD_COND_INITIALIZER;
static int udp_relay_sock = -1;

static void upush(upkt_t *p) {
    pthread_mutex_lock(&uqm);
    int next = (uqt + 1) % QUEUE_CAP;
    if (next != uqh) { uqbuf[uqt] = *p; uqt = next; pthread_cond_signal(&uqc); }
    pthread_mutex_unlock(&uqm);
}
static int upop(upkt_t *p) {
    pthread_mutex_lock(&uqm);
    while (uqh == uqt && running) pthread_cond_wait(&uqc, &uqm);
    if (uqh == uqt) { pthread_mutex_unlock(&uqm); return 0; }
    *p = uqbuf[uqh]; uqh = (uqh + 1) % QUEUE_CAP;
    pthread_mutex_unlock(&uqm);
    return 1;
}

static void *udp_worker(void *arg) {
    (void)arg;
    while (running) {
        upkt_t pkt;
        if (!upop(&pkt)) continue;
        int bs = socket(AF_INET, SOCK_DGRAM, 0);
        if (bs < 0) continue;
        struct timeval tv = {3, 0};
        setsockopt(bs, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(bs, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        struct sockaddr_in back = { AF_INET, htons(BACKEND_PORT), {inet_addr("127.0.0.1")} };
        sendto(bs, pkt.buf, pkt.len, 0, (struct sockaddr*)&back, sizeof(back));
        unsigned char resp[BUF_SIZE]; socklen_t bl = sizeof(back);
        int rn = recvfrom(bs, resp, BUF_SIZE, 0, (struct sockaddr*)&back, &bl);
        if (rn > 0 && udp_relay_sock >= 0)
            sendto(udp_relay_sock, resp, rn, 0, (struct sockaddr*)&pkt.src, sizeof(pkt.src));
        close(bs);
    }
    return NULL;
}

/* ── TCP relay ── */
static void *tcp_client_handler(void *arg) {
    int csock = *(int*)arg; free(arg);
    unsigned char buf[BUF_SIZE];
    int n = recv(csock, buf, BUF_SIZE, 0);
    if (n > 0) {
        /* Forward to DNSTT via UDP */
        int bs = socket(AF_INET, SOCK_DGRAM, 0);
        if (bs >= 0) {
            struct timeval tv = {3, 0};
            setsockopt(bs, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
            setsockopt(bs, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
            struct sockaddr_in back = { AF_INET, htons(BACKEND_PORT), {inet_addr("127.0.0.1")} };
            sendto(bs, buf, n, 0, (struct sockaddr*)&back, sizeof(back));
            unsigned char resp[BUF_SIZE]; socklen_t bl = sizeof(back);
            int rn = recvfrom(bs, resp, BUF_SIZE, 0, (struct sockaddr*)&back, &bl);
            if (rn > 0) send(csock, resp, rn, 0);
            close(bs);
        }
    }
    close(csock);
    return NULL;
}

static void *tcp_acceptor(void *arg) {
    int lsock = *(int*)arg;
    while (running) {
        struct sockaddr_in ca; socklen_t cl = sizeof(ca);
        int cs = accept(lsock, (struct sockaddr*)&ca, &cl);
        if (cs < 0) { if (running) usleep(1000); continue; }
        struct timeval tv = {10, 0};
        setsockopt(cs, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(cs, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        pthread_t t; pthread_attr_t a; pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        int *p = malloc(sizeof(int)); *p = cs;
        pthread_create(&t, &a, tcp_client_handler, p);
        pthread_attr_destroy(&a);
    }
    return NULL;
}

int main(void) {
    signal(SIGTERM, sig_h); signal(SIGINT, sig_h); signal(SIGPIPE, SIG_IGN);
    struct rlimit rl = {1048576, 1048576}; setrlimit(RLIMIT_NOFILE, &rl);

    /* UDP socket */
    udp_relay_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (udp_relay_sock >= 0) {
        int one=1;
        setsockopt(udp_relay_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        setsockopt(udp_relay_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
        int rb=SOCK_BUF, wb=SOCK_BUF;
        setsockopt(udp_relay_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
        setsockopt(udp_relay_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));
        struct sockaddr_in ua = { AF_INET, htons(UDP_LISTEN_PORT), {INADDR_ANY} };
        if (bind(udp_relay_sock, (struct sockaddr*)&ua, sizeof(ua)) < 0) {
            perror("UDP bind 5303"); close(udp_relay_sock); udp_relay_sock=-1;
        } else {
            fcntl(udp_relay_sock, F_SETFL, fcntl(udp_relay_sock,F_GETFL)|O_NONBLOCK);
        }
    }

    /* TCP socket */
    int tcp_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (tcp_sock >= 0) {
        int one=1;
        setsockopt(tcp_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        struct sockaddr_in ta = { AF_INET, htons(TCP_LISTEN_PORT), {INADDR_ANY} };
        if (bind(tcp_sock, (struct sockaddr*)&ta, sizeof(ta)) < 0) {
            perror("TCP bind 5304"); close(tcp_sock); tcp_sock=-1;
        } else {
            listen(tcp_sock, 512);
        }
    }

    /* Start UDP workers */
    if (udp_relay_sock >= 0) {
        int i; pthread_t p[UDP_POOL_SIZE];
        for (i = 0; i < UDP_POOL_SIZE; i++) {
            pthread_attr_t a; pthread_attr_init(&a);
            pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
            pthread_create(&p[i], &a, udp_worker, NULL);
            pthread_attr_destroy(&a);
        }
    }

    /* Start TCP acceptor */
    pthread_t tacc;
    if (tcp_sock >= 0) {
        static int ts; ts = tcp_sock;
        pthread_attr_t a; pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        pthread_create(&tacc, &a, tcp_acceptor, &ts);
        pthread_attr_destroy(&a);
    }

    fprintf(stderr, "[ELITE-X] SlowDNS Multi-Protocol: UDP:%d TCP:%d → backend:%d\n",
            UDP_LISTEN_PORT, TCP_LISTEN_PORT, BACKEND_PORT);

    /* Main UDP receive loop */
    while (running) {
        if (udp_relay_sock < 0) { sleep(1); continue; }
        upkt_t pkt; socklen_t sl = sizeof(pkt.src);
        int n = recvfrom(udp_relay_sock, pkt.buf, BUF_SIZE, 0, (struct sockaddr*)&pkt.src, &sl);
        if (n <= 0) { usleep(100); continue; }
        pkt.len = n; upush(&pkt);
    }

    if (udp_relay_sock >= 0) close(udp_relay_sock);
    if (tcp_sock >= 0) close(tcp_sock);
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -pthread \
        -o /usr/local/bin/elite-x-slowdns-relay /tmp/slowdns_relay.c 2>/dev/null
    rm -f /tmp/slowdns_relay.c

    if [ -f /usr/local/bin/elite-x-slowdns-relay ]; then
        chmod +x /usr/local/bin/elite-x-slowdns-relay
        cat > /etc/systemd/system/elite-x-slowdns-relay.service <<EOF
[Unit]
Description=ELITE-X SlowDNS Multi-Protocol Relay (UDP+TCP)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-slowdns-relay
Restart=always
RestartSec=2
LimitNOFILE=1048576
Nice=-10
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SlowDNS Multi-Protocol Relay compiled (UDP:5303 + TCP:5304)${NC}"
    else
        echo -e "${RED}❌ SlowDNS Multi-Protocol Relay compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SPEED BOOSTER v5.0
# ═══════════════════════════════════════════════════════════
create_c_speed_booster() {
    echo -e "${YELLOW}📝 Compiling C Speed Booster v5.0...${NC}"
    cat > /tmp/speed_booster.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

static void write_file(const char *path, const char *val) {
    FILE *f = fopen(path, "w");
    if (f) { fputs(val, f); fclose(f); }
}

static void sysctl_set(const char *key, const char *val) {
    char path[512];
    snprintf(path, sizeof(path), "/proc/sys/%s", key);
    for (char *p = path + 10; *p; p++) if (*p == '.') *p = '/';
    write_file(path, val);
}

static void boost_network(void) {
    sysctl_set("net.core.default_qdisc",              "fq\n");
    sysctl_set("net.ipv4.tcp_congestion_control",     "bbr\n");
    sysctl_set("net.core.rmem_max",                   "536870912\n");
    sysctl_set("net.core.wmem_max",                   "536870912\n");
    sysctl_set("net.core.rmem_default",               "524288\n");
    sysctl_set("net.core.wmem_default",               "524288\n");
    sysctl_set("net.ipv4.tcp_rmem",                   "4096 262144 268435456\n");
    sysctl_set("net.ipv4.tcp_wmem",                   "4096 131072 268435456\n");
    sysctl_set("net.ipv4.udp_rmem_min",               "65536\n");
    sysctl_set("net.ipv4.udp_wmem_min",               "65536\n");
    sysctl_set("net.ipv4.udp_mem",                    "204800 1747600 33554432\n");
    sysctl_set("net.ipv4.tcp_fastopen",               "3\n");
    sysctl_set("net.ipv4.tcp_slow_start_after_idle",  "0\n");
    sysctl_set("net.ipv4.tcp_sack",                   "1\n");
    sysctl_set("net.ipv4.tcp_dsack",                  "1\n");
    sysctl_set("net.ipv4.tcp_window_scaling",         "1\n");
    sysctl_set("net.ipv4.tcp_mtu_probing",            "1\n");
    sysctl_set("net.ipv4.tcp_timestamps",             "1\n");
    sysctl_set("net.ipv4.tcp_notsent_lowat",          "16384\n");
    sysctl_set("net.ipv4.tcp_max_syn_backlog",        "65536\n");
    sysctl_set("net.core.somaxconn",                  "65536\n");
    sysctl_set("net.core.netdev_max_backlog",         "50000\n");
    sysctl_set("net.ipv4.tcp_tw_reuse",               "1\n");
    sysctl_set("net.ipv4.tcp_fin_timeout",            "5\n");
    sysctl_set("net.ipv4.tcp_keepalive_time",         "30\n");
    sysctl_set("net.ipv4.tcp_keepalive_intvl",        "5\n");
    sysctl_set("net.ipv4.tcp_keepalive_probes",       "6\n");
    sysctl_set("net.core.netdev_budget",              "1000\n");
    sysctl_set("net.core.busy_read",                  "50\n");
    sysctl_set("net.core.busy_poll",                  "50\n");
    sysctl_set("vm.swappiness",                       "5\n");
    sysctl_set("vm.vfs_cache_pressure",               "50\n");
    sysctl_set("vm.dirty_ratio",                      "10\n");
    sysctl_set("vm.dirty_background_ratio",           "3\n");

    DIR *d = opendir("/sys/class/net");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            if (strcmp(e->d_name, "lo") == 0) continue;
            char p[512];
            snprintf(p, sizeof(p), "/sys/class/net/%s/queues/rx-0/rps_cpus", e->d_name);
            write_file(p, "ffffffff\n");
            snprintf(p, sizeof(p), "/sys/class/net/%s/queues/tx-0/xps_cpus", e->d_name);
            write_file(p, "ffffffff\n");
        }
        closedir(d);
    }
    fprintf(stderr, "[ELITE-X] Speed Booster: network stack boosted for 30Mbps+\n");
}

static void boost_cpu(void) {
    system("for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; "
           "do echo performance > \"$f\" 2>/dev/null; done");
    write_file("/sys/devices/system/cpu/cpuidle/current_driver", "none\n");
    fprintf(stderr, "[ELITE-X] Speed Booster: CPU set to performance mode\n");
}

int main(void) {
    signal(SIGTERM, sig); signal(SIGINT, sig);
    boost_network(); boost_cpu();
    while (running) {
        int i; for (i = 0; i < 600 && running; i++) sleep(1);
        if (running) { boost_network(); boost_cpu(); }
    }
    return 0;
}
CEOF
    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-speedbooster /tmp/speed_booster.c 2>/dev/null
    rm -f /tmp/speed_booster.c
    if [ -f /usr/local/bin/elite-x-speedbooster ]; then
        chmod +x /usr/local/bin/elite-x-speedbooster
        cat > /etc/systemd/system/elite-x-speedbooster.service <<EOF
[Unit]
Description=ELITE-X C Speed Booster v5.0 (30Mbps+)
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-speedbooster
Restart=always
RestartSec=5
Nice=-15
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Speed Booster v5.0 compiled${NC}"
    else
        echo -e "${RED}❌ Speed Booster compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: BANDWIDTH MONITOR (Enhanced)
# ═══════════════════════════════════════════════════════════
create_c_bandwidth_monitor() {
    echo -e "${YELLOW}📝 Compiling C Bandwidth Monitor v5.0${NC}"
    cat > /tmp/bw_monitor.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#include <signal.h>
#include <pwd.h>
#include <ctype.h>

#define USER_DB      "/etc/elite-x/users"
#define BW_DIR       "/etc/elite-x/bandwidth"
#define PID_DIR      "/etc/elite-x/bandwidth/pidtrack"
#define BANNED_DIR   "/etc/elite-x/banned"
#define SCAN_INTERVAL 30
#define GB_BYTES      1073741824.0

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

/* Read rchar+wchar from /proc/PID/io */
static long long get_process_io(int pid) {
    char path[256];
    snprintf(path, sizeof(path), "/proc/%d/io", pid);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    long long rchar = 0, wchar = 0;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "rchar:", 6) == 0) sscanf(line + 7, "%lld", &rchar);
        else if (strncmp(line, "wchar:", 6) == 0) sscanf(line + 7, "%lld", &wchar);
    }
    fclose(f);
    return rchar + wchar;
}

static int is_numeric(const char *str) {
    if (!str || !*str) return 0;
    for (; *str; str++) if (!isdigit((unsigned char)*str)) return 0;
    return 1;
}

/* Get all sshd session PIDs for a user (ppid != 1 = real session, not daemon) */
static int get_sshd_pids(const char *username, int *pids, int max_pids) {
    int count = 0;
    DIR *proc = opendir("/proc");
    if (!proc) return 0;
    struct dirent *entry;
    while ((entry = readdir(proc)) && count < max_pids) {
        if (!is_numeric(entry->d_name)) continue;
        int pid = atoi(entry->d_name);

        /* Check comm == sshd */
        char comm_path[256];
        snprintf(comm_path, sizeof(comm_path), "/proc/%d/comm", pid);
        FILE *f = fopen(comm_path, "r");
        if (!f) continue;
        char comm[64] = {0};
        fgets(comm, sizeof(comm), f);
        fclose(f);
        comm[strcspn(comm, "\n")] = 0;
        if (strcmp(comm, "sshd") != 0) continue;

        /* Check UID matches username */
        char status_path[256];
        snprintf(status_path, sizeof(status_path), "/proc/%d/status", pid);
        FILE *sf = fopen(status_path, "r");
        if (!sf) continue;
        char line[256], uid_str[32] = {0};
        while (fgets(line, sizeof(line), sf))
            if (strncmp(line, "Uid:", 4) == 0) { sscanf(line, "%*s %s", uid_str); break; }
        fclose(sf);
        int uid = atoi(uid_str);
        struct passwd *pw = getpwuid(uid);
        if (!pw || strcmp(pw->pw_name, username) != 0) continue;

        /* ppid != 1 → real session process, not the root sshd daemon */
        char stat_path[256];
        snprintf(stat_path, sizeof(stat_path), "/proc/%d/stat", pid);
        FILE *stf = fopen(stat_path, "r");
        if (!stf) continue;
        int ppid = 0;
        char stat_buf[1024];
        fgets(stat_buf, sizeof(stat_buf), stf);
        sscanf(stat_buf, "%*d %*s %*c %d", &ppid);
        fclose(stf);
        if (ppid != 1) pids[count++] = pid;
    }
    closedir(proc);
    return count;
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(BW_DIR, 0755);
    mkdir(PID_DIR, 0755);
    mkdir(BANNED_DIR, 0755);

    while (running) {
        DIR *user_dir = opendir(USER_DB);
        if (!user_dir) { sleep(SCAN_INTERVAL); continue; }

        struct dirent *user_entry;
        while ((user_entry = readdir(user_dir))) {
            if (user_entry->d_name[0] == '.') continue;

            /* Read user config - get bandwidth limit */
            char user_file[512];
            snprintf(user_file, sizeof(user_file), "%s/%s", USER_DB, user_entry->d_name);
            FILE *uf = fopen(user_file, "r");
            if (!uf) continue;
            double bandwidth_gb = 0;
            char line[256];
            while (fgets(line, sizeof(line), uf))
                if (strncmp(line, "Bandwidth_GB:", 13) == 0) sscanf(line + 13, "%lf", &bandwidth_gb);
            fclose(uf);

            /* Skip users with no bandwidth limit set */
            if (bandwidth_gb <= 0) continue;

            /* Find all active sshd session PIDs for this user */
            int pids[100];
            int pid_count = get_sshd_pids(user_entry->d_name, pids, 100);
            if (pid_count == 0) {
                /* No active sessions - clean stale pidfiles */
                char cmd[512];
                snprintf(cmd, sizeof(cmd),
                    "rm -f %s/%s__*.last 2>/dev/null", PID_DIR, user_entry->d_name);
                system(cmd);
                continue;
            }

            /* Calculate delta IO bytes across all session PIDs */
            long long delta_total = 0;
            int i;
            for (i = 0; i < pid_count; i++) {
                long long cur_io = get_process_io(pids[i]);
                char pidfile[512];
                snprintf(pidfile, sizeof(pidfile),
                    "%s/%s__%d.last", PID_DIR, user_entry->d_name, pids[i]);

                FILE *pf = fopen(pidfile, "r");
                if (pf) {
                    long long prev_io = 0;
                    fscanf(pf, "%lld", &prev_io);
                    fclose(pf);
                    long long d = (cur_io >= prev_io) ? (cur_io - prev_io) : cur_io;
                    delta_total += d;
                }
                /* Save current IO as baseline for next interval */
                pf = fopen(pidfile, "w");
                if (pf) { fprintf(pf, "%lld\n", cur_io); fclose(pf); }
            }

            /* Add delta to accumulated usage file */
            char usagefile[512];
            snprintf(usagefile, sizeof(usagefile), "%s/%s.usage", BW_DIR, user_entry->d_name);
            long long accumulated = 0;
            FILE *accf = fopen(usagefile, "r");
            if (accf) { fscanf(accf, "%lld", &accumulated); fclose(accf); }
            long long new_total = accumulated + delta_total;
            accf = fopen(usagefile, "w");
            if (accf) { fprintf(accf, "%lld\n", new_total); fclose(accf); }

            /* Block user if quota exceeded */
            long long quota_bytes = (long long)(bandwidth_gb * GB_BYTES);
            if (new_total >= quota_bytes) {
                /* Angalia kama tayari amefungwa via /etc/shadow (inafanya kazi Fedora+Ubuntu) */
                char is_locked_cmd[512];
                snprintf(is_locked_cmd, sizeof(is_locked_cmd),
                    "grep -q '^%s:!' /etc/shadow 2>/dev/null", user_entry->d_name);
                int already_locked = (system(is_locked_cmd) == 0);
                if (!already_locked) {
                    char cmd[1024];
                    snprintf(cmd, sizeof(cmd),
                        "usermod -L %s 2>/dev/null; "
                        "killall -u %s -9 2>/dev/null; "
                        "echo 'BLOCKED: Bandwidth quota exceeded %.1fGB' >> %s/%s",
                        user_entry->d_name,
                        user_entry->d_name,
                        bandwidth_gb,
                        BANNED_DIR, user_entry->d_name);
                    system(cmd);
                }
            }
        }
        closedir(user_dir);
        sleep(SCAN_INTERVAL);
    }
    return 0;
}
CEOF
    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-bandwidth-c /tmp/bw_monitor.c 2>/dev/null
    rm -f /tmp/bw_monitor.c
    if [ -f /usr/local/bin/elite-x-bandwidth-c ]; then
        chmod +x /usr/local/bin/elite-x-bandwidth-c
        cat > /etc/systemd/system/elite-x-bandwidth.service <<EOF
[Unit]
Description=ELITE-X C Bandwidth Monitor v5.0 (io/pidtrack)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-bandwidth-c
Restart=always
RestartSec=5
CPUQuota=20%
MemoryMax=50M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Bandwidth Monitor v5.0 compiled (io/pidtrack method)${NC}"
    else
        echo -e "${RED}❌ Bandwidth Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: CONNECTION MONITOR (accurate count via ss + /proc)
# ═══════════════════════════════════════════════════════════
create_c_connection_monitor() {
    echo -e "${YELLOW}📝 Compiling C Connection Monitor v5.0...${NC}"
    cat > /tmp/conn_monitor.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>
#include <pwd.h>
#include <ctype.h>

#define USER_DB     "/etc/elite-x/users"
#define CONN_DB     "/etc/elite-x/connections"
#define BANNED_DIR  "/etc/elite-x/banned"
#define DELETED_DIR "/etc/elite-x/deleted"
#define BW_DIR      "/etc/elite-x/bandwidth"
#define PID_DIR     "/etc/elite-x/bandwidth/pidtrack"
#define AUTOBAN_FL  "/etc/elite-x/autoban_enabled"
#define SCAN_INTERVAL 5

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s || !*s) return 0;
    for (; *s; s++) if (!isdigit((unsigned char)*s)) return 0;
    return 1;
}

/* Count active SSH sessions for user using /proc */
static int get_conn_count(const char *user) {
    int count = 0;
    DIR *proc = opendir("/proc"); if (!proc) return 0;
    struct dirent *e;
    while ((e = readdir(proc))) {
        if (!is_numeric(e->d_name)) continue;
        int pid = atoi(e->d_name);
        char cp[256]; snprintf(cp,sizeof(cp),"/proc/%d/comm",pid);
        FILE *f = fopen(cp,"r"); if (!f) continue;
        char comm[64]={0}; fgets(comm,sizeof(comm),f); fclose(f);
        comm[strcspn(comm,"\n")] = 0;
        if (strcmp(comm,"sshd") != 0) continue;
        /* Check UID */
        char sp[256]; snprintf(sp,sizeof(sp),"/proc/%d/status",pid);
        FILE *sf = fopen(sp,"r"); if (!sf) continue;
        char line[256], uid_s[32]={0};
        while (fgets(line,sizeof(line),sf))
            if (strncmp(line,"Uid:",4)==0){sscanf(line,"%*s %s",uid_s);break;}
        fclose(sf);
        struct passwd *pw = getpwuid(atoi(uid_s));
        if (!pw || strcmp(pw->pw_name,user)!=0) continue;
        /* Check it is a session, not notty */
        char stp[256]; snprintf(stp,sizeof(stp),"/proc/%d/stat",pid);
        FILE *stf = fopen(stp,"r"); if (!stf) continue;
        int ppid=0; char sb[1024]; fgets(sb,sizeof(sb),stf);
        sscanf(sb,"%*d %*s %*c %d",&ppid); fclose(stf);
        /* session processes have sshd (pid 1 or sshd parent) as parent */
        if (ppid != 1) count++;
    }
    closedir(proc);
    return count;
}

static void delete_expired(const char *user, const char *reason) {
    char cmd[2048];
    snprintf(cmd,sizeof(cmd),
        "cp %s/%s %s/%s_$(date +%%Y%%m%%d_%%H%%M%%S) 2>/dev/null; "
        "pkill -u %s 2>/dev/null; killall -u %s -9 2>/dev/null; "
        "userdel -r %s 2>/dev/null; "
        "rm -f %s/%s /etc/elite-x/data_usage/%s %s/%s %s/%s %s/%s.usage; "
        "rm -f %s/%s__*.last 2>/dev/null; "
        "logger -t elite-x 'Auto-deleted: %s (%s)'",
        USER_DB,user,DELETED_DIR,user,
        user,user,user,
        USER_DB,user,user,CONN_DB,user,BANNED_DIR,user,BW_DIR,user,
        PID_DIR,user,user,reason);
    system(cmd);
}

int main(void) {
    signal(SIGTERM, signal_handler); signal(SIGINT, signal_handler);
    mkdir(CONN_DB,0755); mkdir(BANNED_DIR,0755);
    mkdir(DELETED_DIR,0755); mkdir(BW_DIR,0755); mkdir(PID_DIR,0755);

    while (running) {
        time_t now = time(NULL);
        DIR *ud = opendir(USER_DB); if (!ud) { sleep(SCAN_INTERVAL); continue; }
        struct dirent *ue;
        while ((ue = readdir(ud))) {
            if (ue->d_name[0]=='.') continue;
            struct passwd *pw = getpwnam(ue->d_name);
            if (!pw) {
                char rc[512]; snprintf(rc,sizeof(rc),"rm -f %s/%s",USER_DB,ue->d_name);
                system(rc); continue;
            }
            char uf[512]; snprintf(uf,sizeof(uf),"%s/%s",USER_DB,ue->d_name);
            FILE *f = fopen(uf,"r"); if (!f) continue;
            char exp[32]={0}; int conn_lim=1; char line[256];
            while (fgets(line,sizeof(line),f)) {
                if (strncmp(line,"Expire:",7)==0) sscanf(line+8,"%s",exp);
                else if (strncmp(line,"Conn_Limit:",11)==0) sscanf(line+12,"%d",&conn_lim);
            }
            fclose(f);

            if (strlen(exp) > 0) {
                struct tm tm={0};
                if (strptime(exp,"%Y-%m-%d",&tm)) {
                    time_t et = mktime(&tm);
                    if (now > et + 86400) {
                        char reason[256]; snprintf(reason,sizeof(reason),"Expired on %s",exp);
                        delete_expired(ue->d_name, reason); continue;
                    }
                }
            }

            int cc = get_conn_count(ue->d_name);
            char cf[512]; snprintf(cf,sizeof(cf),"%s/%s",CONN_DB,ue->d_name);
            FILE *cfile = fopen(cf,"w");
            if (cfile) { fprintf(cfile,"%d\n",cc); fclose(cfile); }

            int autoban=0;
            FILE *abf = fopen(AUTOBAN_FL,"r");
            if (abf) { fscanf(abf,"%d",&autoban); fclose(abf); }

            if (cc > conn_lim && autoban == 1) {
                /* Tumia /etc/shadow kuangalia kama user tayari amefungwa
                   (inafanya kazi Ubuntu na Fedora - passwd -S inatoa output tofauti) */
                char is_locked_cmd[512];
                snprintf(is_locked_cmd, sizeof(is_locked_cmd),
                    "grep -q '^%s:!' /etc/shadow 2>/dev/null", ue->d_name);
                int already_locked = (system(is_locked_cmd) == 0);
                if (!already_locked) {
                    char cmd[1024];
                    snprintf(cmd, sizeof(cmd),
                        "usermod -L %s 2>/dev/null; pkill -u %s 2>/dev/null; "
                        "echo 'BLOCKED: Exceeded conn %d/%d' >> %s/%s",
                        ue->d_name, ue->d_name, cc, conn_lim, BANNED_DIR, ue->d_name);
                    system(cmd);
                }
            }
        }
        closedir(ud);

        /* Also update all user messages every 30 scans (~150s) */
        static int scan_count = 0;
        if (++scan_count >= 30) {
            scan_count = 0;
            system("for u in /etc/elite-x/users/*; do "
                   "[ -f \"$u\" ] && /usr/local/bin/elite-x-force-user-message \"$(basename $u)\" 2>/dev/null; "
                   "done");
        }

        sleep(SCAN_INTERVAL);
    }
    return 0;
}
CEOF
    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-connmon-c /tmp/conn_monitor.c 2>/dev/null
    rm -f /tmp/conn_monitor.c
    if [ -f /usr/local/bin/elite-x-connmon-c ]; then
        chmod +x /usr/local/bin/elite-x-connmon-c
        cat > /etc/systemd/system/elite-x-connmon.service <<EOF
[Unit]
Description=ELITE-X C Connection Monitor v5.0
After=network.target sshd.service
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-connmon-c
Restart=always
RestartSec=5
CPUQuota=20%
MemoryMax=50M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Connection Monitor v5.0 compiled${NC}"
    else
        echo -e "${RED}❌ Connection Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: NETWORK BOOSTER
# ═══════════════════════════════════════════════════════════
create_c_network_booster() {
    echo -e "${YELLOW}📝 Compiling C Network Booster v5.0...${NC}"
    cat > /tmp/net_booster.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
static void apply(void) {
    system("sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_max=536870912 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_rmem='4096 262144 536870912' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_wmem='4096 131072 536870912' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_syn_backlog=65536 >/dev/null 2>&1");
    system("sysctl -w net.core.somaxconn=65536 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_max_backlog=50000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fin_timeout=5 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_time=30 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_mem='204800 1747600 33554432' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_rmem_min=131072 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_wmem_min=131072 >/dev/null 2>&1");
    system("sysctl -w net.core.optmem_max=131072 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_budget=1000 >/dev/null 2>&1");
    system("sysctl -w net.core.busy_poll=50 >/dev/null 2>&1");
    system("sysctl -w net.core.busy_read=50 >/dev/null 2>&1");
    fprintf(stderr, "[ELITE-X] Network Booster: optimizations applied\n");
}
int main(void) {
    signal(SIGTERM, signal_handler); signal(SIGINT, signal_handler);
    apply();
    while (running) {
        int i; for (i = 0; i < 3600 && running; i++) sleep(1);
        if (running) apply();
    }
    return 0;
}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-netbooster /tmp/net_booster.c 2>/dev/null
    rm -f /tmp/net_booster.c
    if [ -f /usr/local/bin/elite-x-netbooster ]; then
        chmod +x /usr/local/bin/elite-x-netbooster
        cat > /etc/systemd/system/elite-x-netbooster.service <<EOF
[Unit]
Description=ELITE-X C Network Booster v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-netbooster
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Network Booster v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DNS CACHE OPTIMIZER
# ═══════════════════════════════════════════════════════════
create_c_dns_cache() {
    echo -e "${YELLOW}📝 Compiling C DNS Cache Optimizer v5.0...${NC}"
    cat > /tmp/dns_cache.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
static void flush_dns(void) {
    system("systemctl restart systemd-resolved 2>/dev/null || true");
    system("resolvectl flush-caches 2>/dev/null || true");
    system("killall -HUP dnsmasq 2>/dev/null || true");
    fprintf(stderr, "[ELITE-X] DNS Cache flushed\n");
}
static void optimize_resolv(void) {
    FILE *f = fopen("/etc/resolv.conf","w");
    if (f) {
        fprintf(f,"nameserver 1.1.1.1\nnameserver 8.8.8.8\n");
        fprintf(f,"nameserver 8.8.4.4\nnameserver 9.9.9.9\n");
        fprintf(f,"options timeout:1 attempts:3 rotate\noptions ndots:0\n");
        fclose(f);
        fprintf(stderr,"[ELITE-X] resolv.conf optimized\n");
    }
}
int main(void) {
    signal(SIGTERM, signal_handler); signal(SIGINT, signal_handler);
    optimize_resolv();
    while (running) {
        flush_dns();
        int i; for (i = 0; i < 1800 && running; i++) sleep(1);
    }
    return 0;
}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-dnscache /tmp/dns_cache.c 2>/dev/null
    rm -f /tmp/dns_cache.c
    if [ -f /usr/local/bin/elite-x-dnscache ]; then
        chmod +x /usr/local/bin/elite-x-dnscache
        cat > /etc/systemd/system/elite-x-dnscache.service <<EOF
[Unit]
Description=ELITE-X C DNS Cache Optimizer v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-dnscache
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅  DNS Cache Optimizer v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: RAM CLEANER
# ═══════════════════════════════════════════════════════════
create_c_ram_cleaner() {
    echo -e "${YELLOW}📝 Compiling C RAM Cache Cleaner v5.0...${NC}"
    cat > /tmp/ram_cleaner.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
static void clean(void) {
    system("sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null");
    system("echo 1 > /proc/sys/vm/compact_memory 2>/dev/null");
    system("sysctl -w vm.swappiness=5 >/dev/null 2>&1");
    system("sysctl -w vm.vfs_cache_pressure=50 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_ratio=10 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_background_ratio=3 >/dev/null 2>&1");
    system("sysctl -w vm.min_free_kbytes=65536 >/dev/null 2>&1");
    fprintf(stderr,"[ELITE-X] RAM cleaned\n");
}
int main(void) {
    signal(SIGTERM, signal_handler); signal(SIGINT, signal_handler);
    while (running) { clean(); int i; for(i=0;i<900&&running;i++) sleep(1); }
    return 0;
}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-ramcleaner /tmp/ram_cleaner.c 2>/dev/null
    rm -f /tmp/ram_cleaner.c
    if [ -f /usr/local/bin/elite-x-ramcleaner ]; then
        chmod +x /usr/local/bin/elite-x-ramcleaner
        cat > /etc/systemd/system/elite-x-ramcleaner.service <<EOF
[Unit]
Description=ELITE-X C RAM Cache Cleaner v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-ramcleaner
Restart=always
RestartSec=30
CPUQuota=10%
MemoryMax=30M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ RAM Cleaner v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: IRQ AFFINITY OPTIMIZER
# ═══════════════════════════════════════════════════════════
create_c_irq_optimizer() {
    echo -e "${YELLOW}📝 Compiling C IRQ Affinity Optimizer v5.0...${NC}"
    cat > /tmp/irq_optimizer.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}
static void optimize_irq(void) {
    DIR *d = opendir("/proc/irq"); if (!d) return;
    struct dirent *e;
    while ((e=readdir(d))) {
        if (e->d_name[0]=='.') continue;
        char p[512]; snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity",e->d_name);
        write_file(p,"ffffffff\n");
    }
    closedir(d);
    DIR *nd = opendir("/sys/class/net"); if (!nd) return;
    while ((e=readdir(nd))) {
        if (e->d_name[0]=='.') continue;
        if (strcmp(e->d_name,"lo")==0) continue;
        char p[512];
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/rx-0/rps_cpus",e->d_name);
        write_file(p,"ffffffff\n");
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/tx-0/xps_cpus",e->d_name);
        write_file(p,"ffffffff\n");
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/rx-0/rps_flow_cnt",e->d_name);
        write_file(p,"32768\n");
    }
    closedir(nd);
    write_file("/proc/sys/net/core/rps_sock_flow_entries","32768\n");
    fprintf(stderr,"[ELITE-X] IRQ/RPS/XPS optimized\n");
}
int main(void) {
    signal(SIGTERM,signal_handler); signal(SIGINT,signal_handler);
    while (running) { optimize_irq(); int i; for(i=0;i<600&&running;i++) sleep(1); }
    return 0;
}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-irqopt /tmp/irq_optimizer.c 2>/dev/null
    rm -f /tmp/irq_optimizer.c
    if [ -f /usr/local/bin/elite-x-irqopt ]; then
        chmod +x /usr/local/bin/elite-x-irqopt
        cat > /etc/systemd/system/elite-x-irqopt.service <<EOF
[Unit]
Description=ELITE-X C IRQ Affinity Optimizer v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-irqopt
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ IRQ Optimizer v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DATA USAGE MONITOR
# ═══════════════════════════════════════════════════════════
create_c_data_usage() {
    echo -e "${YELLOW}📝 Compiling C Data Usage Monitor v5.0...${NC}"
    cat > /tmp/data_usage.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
int main(void) {
    signal(SIGTERM,signal_handler); signal(SIGINT,signal_handler);
    while (running) {
        DIR *ud = opendir("/etc/elite-x/users");
        if (!ud) { sleep(30); continue; }
        char month[8]; time_t now=time(NULL);
        strftime(month,sizeof(month),"%Y-%m",localtime(&now));
        struct dirent *e;
        while ((e=readdir(ud))) {
            if (e->d_name[0]=='.') continue;
            char bf[512]; snprintf(bf,sizeof(bf),"/etc/elite-x/bandwidth/%s.usage",e->d_name);
            long long bytes=0; FILE *f=fopen(bf,"r");
            if(f){fscanf(f,"%lld",&bytes);fclose(f);}
            double gb=bytes/1073741824.0;
            char uf[512]; snprintf(uf,sizeof(uf),"/etc/elite-x/data_usage/%s",e->d_name);
            f=fopen(uf,"w");
            if(f){
                time_t t=time(NULL); char *ts=ctime(&t); ts[strcspn(ts,"\n")]=0;
                fprintf(f,"month: %s\ntotal_gb: %.2f\nlast_updated: %s\n",month,gb,ts);
                fclose(f);
            }
        }
        closedir(ud);
        sleep(30);
    }
    return 0;
}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-datausage-c /tmp/data_usage.c 2>/dev/null
    rm -f /tmp/data_usage.c
    if [ -f /usr/local/bin/elite-x-datausage-c ]; then
        chmod +x /usr/local/bin/elite-x-datausage-c
        cat > /etc/systemd/system/elite-x-datausage.service <<EOF
[Unit]
Description=ELITE-X C Data Usage Monitor v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-datausage-c
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C Data Usage Monitor v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: LOG CLEANER
# ═══════════════════════════════════════════════════════════
create_c_log_cleaner() {
    echo -e "${YELLOW}📝 Compiling C Log Cleaner v5.0...${NC}"
    cat > /tmp/log_cleaner.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
static void clean(void) {
    system("find /var/log -type f -name '*.log' -size +50M -exec truncate -s 0 {} \\; 2>/dev/null");
    system("journalctl --vacuum-size=50M 2>/dev/null");
    system("truncate -s 0 /var/log/syslog 2>/dev/null");
    system("truncate -s 0 /var/log/messages 2>/dev/null");
    system("truncate -s 0 /var/log/kern.log 2>/dev/null");
    system("truncate -s 0 /var/log/auth.log 2>/dev/null");
    system("find /var/log -name '*.gz' -mtime +3 -delete 2>/dev/null");
    system("find /var/log -name '*.1' -delete 2>/dev/null");
    system("find /var/log -name '*.old' -delete 2>/dev/null");
    fprintf(stderr,"[ELITE-X] Logs cleaned\n");
}
int main(void) {
    signal(SIGTERM,signal_handler); signal(SIGINT,signal_handler);
    while (running) { clean(); int i; for(i=0;i<3600&&running;i++) sleep(1); }
    return 0;
}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-logcleaner /tmp/log_cleaner.c 2>/dev/null
    rm -f /tmp/log_cleaner.c
    if [ -f /usr/local/bin/elite-x-logcleaner ]; then
        chmod +x /usr/local/bin/elite-x-logcleaner
        cat > /etc/systemd/system/elite-x-logcleaner.service <<EOF
[Unit]
Description=ELITE-X C Log Cleaner v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-logcleaner
Restart=always
RestartSec=30
CPUQuota=10%
MemoryMax=20M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Log Cleaner v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# USER MANAGEMENT SCRIPT
# ═══════════════════════════════════════════════════════════
create_user_script() {
    cat > /usr/local/bin/elite-x-user <<'USEREOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
WHITE='\033[1;37m';BOLD='\033[1m';ORANGE='\033[0;33m';MAGENTA='\033[1;35m'
LIGHT_RED='\033[1;31m';LIGHT_GREEN='\033[1;32m';PURPLE='\033[0;35m'
GRAY='\033[0;90m';NC='\033[0m'

UD="/etc/elite-x/users"; USAGE_DB="/etc/elite-x/data_usage"
DD="/etc/elite-x/deleted"; BD="/etc/elite-x/banned"
CONN_DB="/etc/elite-x/connections"; BW_DIR="/etc/elite-x/bandwidth"
PID_DIR="$BW_DIR/pidtrack"; AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"
mkdir -p "$UD" "$USAGE_DB" "$DD" "$BD" "$CONN_DB" "$BW_DIR" "$PID_DIR"

get_connection_count() {
    # Count real SSH sessions via /proc - Ubuntu 18/20/22/24 compatible
    # Counts sshd processes owned by user where ppid != 1 (sessions, not daemon)
    local u="$1" c=0
    local _uid; _uid=$(id -u "$u" 2>/dev/null || echo "")
    if [ -n "$_uid" ]; then
        for _pd in /proc/[0-9]*/; do
            [ -f "${_pd}comm" ] || continue
            [ "$(cat "${_pd}comm" 2>/dev/null)" = "sshd" ] || continue
            local _puid; _puid=$(awk '/^Uid:/{print $2}' "${_pd}status" 2>/dev/null)
            [ "$_puid" = "$_uid" ] || continue
            local _ppid; _ppid=$(awk '{print $4}' "${_pd}stat" 2>/dev/null)
            [ "$_ppid" = "1" ] && continue
            c=$((c + 1))
        done
    fi
    echo "${c:-0}"
}

get_bandwidth_usage() {
    local u="$1"; local f="$BW_DIR/${u}.usage"
    if [ -f "$f" ]; then
        local raw; raw=$(cat "$f" 2>/dev/null | tr -d ' \n\r')
        [[ "$raw" =~ ^[0-9]+$ ]] || raw=0
        echo "scale=2; $raw / 1073741824" | bc 2>/dev/null || echo "0.00"
    else
        echo "0.00"
    fi
}

# Check and block user who exceeded bandwidth limit
check_and_block_bw_limit() {
    local u="$1"
    local bw_limit; bw_limit=$(grep "Bandwidth_GB:" "$UD/$u" 2>/dev/null | awk '{print $2}' | tr -d ' \n')
    [[ "$bw_limit" =~ ^[0-9]+\.?[0-9]*$ ]] || return
    [ "$bw_limit" = "0" ] && return
    local total_gb; total_gb=$(get_bandwidth_usage "$u")
    local exceeded; exceeded=$(echo "$total_gb >= $bw_limit" | bc 2>/dev/null || echo 0)
    if [ "$exceeded" = "1" ]; then
        # Tumia /etc/shadow badala ya passwd -S (inafanya kazi Fedora+Ubuntu)
        if ! grep -q "^${u}:!" /etc/shadow 2>/dev/null; then
            usermod -L "$u" 2>/dev/null
            pkill -u "$u" 2>/dev/null || true
            echo "$(date) - AUTO-BLOCKED: Bandwidth quota ${total_gb}/${bw_limit}GB exceeded" >> "$BD/$u"
        fi
    fi
}

add_user() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}     CREATE SSH + SLOWDNS USER v5.0             ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${CYAN}     With 3Proxy HTTP+SOCKS5 access             ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"

    read -p "$(echo -e $GREEN"Username: "$NC)" username
    if id "$username" &>/dev/null; then echo -e "${RED}User already exists!${NC}"; return; fi

    read -p "$(echo -e $GREEN"Password [auto-generate]: "$NC)" password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 10) \
        && echo -e "${GREEN}🔑 Generated: ${YELLOW}$password${NC}"

    read -p "$(echo -e $GREEN"Expire (days) [30]: "$NC)" days; days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "${RED}Invalid!${NC}"; return; }

    read -p "$(echo -e $GREEN"Connection limit [1]: "$NC)" conn_limit; conn_limit=${conn_limit:-1}
    [[ ! "$conn_limit" =~ ^[0-9]+$ ]] && conn_limit=1

    read -p "$(echo -e $GREEN"Bandwidth GB (0=unlimited) [0]: "$NC)" bw; bw=${bw:-0}
    [[ ! "$bw" =~ ^[0-9]+\.?[0-9]*$ ]] && bw=0

    useradd -m -s /bin/false "$username"
    echo "$username:$password" | chpasswd
    expire_date=$(date -d "+$days days" +"%Y-%m-%d")
    chage -E "$expire_date" "$username"

    cat > "$UD/$username" <<INFO
Username: $username
Password: $password
Expire: $expire_date
Conn_Limit: $conn_limit
Bandwidth_GB: $bw
Created: $(date +"%Y-%m-%d %H:%M:%S")
INFO

    echo "0" > "$BW_DIR/${username}.usage"

    # Add user to 3proxy
    if [ -f /etc/3proxy/users.list ]; then
        sed -i "/^${username}:/d" /etc/3proxy/users.list
        echo "${username}:CL:${password}" >> /etc/3proxy/users.list
        systemctl reload 3proxy-elite 2>/dev/null || systemctl restart 3proxy-elite 2>/dev/null || true
    fi

    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null

    local bw_disp="Unlimited"; [ "$bw" != "0" ] && bw_disp="${bw} GB"
    SERVER=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "?")
    IP=$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "?")
    PUBKEY=$(cat /etc/elite-x/public_key 2>/dev/null || echo "?")

    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}         USER CREATED SUCCESSFULLY  v5.0            ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Username   :${CYAN} $username${NC}"
    echo -e "${GREEN}║${WHITE}  Password   :${CYAN} $password${NC}"
    echo -e "${GREEN}║${WHITE}  Server NS  :${CYAN} $SERVER${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $PUBKEY${NC}"
    echo -e "${GREEN}║${WHITE}  Expire     :${CYAN} $expire_date${NC}"
    echo -e "${GREEN}║${WHITE}  Max Login  :${CYAN} $conn_limit${NC}"
    echo -e "${GREEN}║${WHITE}  Bandwidth  :${CYAN} $bw_disp${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS      : ${CYAN}$SERVER${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY  : ${CYAN}$PUBKEY${NC}"
    echo -e "${GREEN}║${WHITE}  UDP Port: ${CYAN}53 | 5301 | 5302 | 5303${NC}"
    echo -e "${GREEN}║${WHITE}  TCP Port: ${CYAN}5304${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  3PROXY CONFIG (HTTP + SOCKS5):${NC}"
    echo -e "${GREEN}║${WHITE}  HTTP Proxy : ${CYAN}$IP:3128${NC}"
    echo -e "${GREEN}║${WHITE}  SOCKS5 (G) : ${CYAN}$IP:1080${NC}"
    echo -e "${GREEN}║${WHITE}  SOCKS5 SD  : ${CYAN}$IP:1081${NC}"
    echo -e "${GREEN}║${WHITE}  SOCKS5 DNS : ${CYAN}$IP:1082${NC}"
    echo -e "${GREEN}║${WHITE}  User/Pass  : ${CYAN}$username / $password${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
}

list_users() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                  ACTIVE USERS v5.0                    ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"

    if [ -z "$(ls -A "$UD" 2>/dev/null)" ]; then
        echo -e "${CYAN}║${RED}  No users found.${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
        return
    fi

    printf "${CYAN}║${WHITE} %-14s %-12s %-8s %-14s %-18s${CYAN} ║${NC}\n" \
        "USERNAME" "EXPIRE" "LOGIN" "BANDWIDTH" "STATUS"
    echo -e "${CYAN}╟──────────────────────────────────────────────────────────────╢${NC}"

    # ── Single /proc scan: build uid→sessions map ──────────────────
    declare -A _sess_map
    local _cur_ts; _cur_ts=$(date +%s)
    for _pd in /proc/[0-9]*/; do
        [ -f "${_pd}comm" ] || continue
        [ "$(cat "${_pd}comm" 2>/dev/null)" = "sshd" ] || continue
        local _ppid; _ppid=$(awk '{print $4}' "${_pd}stat" 2>/dev/null)
        [ "$_ppid" = "1" ] && continue
        local _puid; _puid=$(awk '/^Uid:/{print $2}' "${_pd}status" 2>/dev/null)
        [ -n "$_puid" ] && _sess_map[$_puid]=$(( ${_sess_map[$_puid]:-0} + 1 ))
    done

    local _total_users=0 _online_users=0

    for user in "$UD"/*; do
        [ ! -f "$user" ] && continue
        _total_users=$((_total_users + 1))
        u=$(basename "$user")

        # Read user config (one grep pass per field)
        local ex limit bw_limit
        ex=$(awk '/^Expire:/{print $2}' "$user" | tr -d ' \n')
        limit=$(awk '/^Conn_Limit:/{print $2}' "$user" | tr -d ' \n')
        [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
        bw_limit=$(awk '/^Bandwidth_GB:/{print $2}' "$user" | tr -d ' \n')
        [[ "$bw_limit" =~ ^[0-9]+\.?[0-9]*$ ]] || bw_limit=0

        # Session count from pre-built map (zero /proc calls here)
        local _uid; _uid=$(id -u "$u" 2>/dev/null || echo "")
        local cc=0
        [ -n "$_uid" ] && cc=${_sess_map[$_uid]:-0}
        [[ "$cc" =~ ^[0-9]+$ ]] || cc=0

        # Bandwidth: one cat + one bc call
        local raw_bytes=0
        [ -f "$BW_DIR/${u}.usage" ] && {
            raw_bytes=$(cat "$BW_DIR/${u}.usage" 2>/dev/null | tr -d ' \n\r')
            [[ "$raw_bytes" =~ ^[0-9]+$ ]] || raw_bytes=0
        }
        local total_gb; total_gb=$(echo "scale=2; $raw_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

        # Auto-block if over quota (inline, no subshell)
        if [[ "$bw_limit" =~ ^[0-9]+\.?[0-9]*$ ]] && [ "$bw_limit" != "0" ] && [ "$raw_bytes" -gt 0 ] 2>/dev/null; then
            local quota_bytes; quota_bytes=$(echo "$bw_limit * 1073741824 / 1" | bc 2>/dev/null || echo 0)
            if [ "$raw_bytes" -ge "$quota_bytes" ] 2>/dev/null; then
                if ! grep -q "^${u}:!" /etc/shadow 2>/dev/null; then
                    usermod -L "$u" 2>/dev/null
                    pkill -u "$u" 2>/dev/null || true
                    echo "$(date) - AUTO-BLOCKED: BW quota ${total_gb}/${bw_limit}GB" >> "$BD/$u"
                fi
            fi
        fi

        # Expire calculation
        local expire_ts days_left
        expire_ts=$(date -d "$ex" +%s 2>/dev/null || echo 0)
        [[ "$expire_ts" =~ ^[0-9]+$ ]] || expire_ts=0
        days_left=$(( (expire_ts - _cur_ts) / 86400 ))

        # Status
        local status
        if grep -q "^${u}:!" /etc/shadow 2>/dev/null; then
            status="${RED}🔒 LOCKED${NC}"
        elif [ "$cc" -gt 0 ]; then
            status="${LIGHT_GREEN}🟢 ONLINE${NC}"
            _online_users=$((_online_users + 1))
        elif [ "$days_left" -le 0 ]; then
            status="${RED}⛔ EXPIRED${NC}"
        elif [ "$days_left" -le 3 ]; then
            status="${LIGHT_RED}⚠️ CRITICAL${NC}"
        elif [ "$days_left" -le 7 ]; then
            status="${YELLOW}⚠️ WARNING${NC}"
        else
            status="${YELLOW}⚫ OFFLINE${NC}"
        fi

        # Bandwidth display (two bc calls avoided — compare integers)
        local bw_disp
        if [ "$bw_limit" != "0" ] && [ -n "$bw_limit" ]; then
            local quota_b; quota_b=$(echo "$bw_limit * 1073741824 / 1" | bc 2>/dev/null || echo 1)
            local pct80;   pct80=$(echo  "$bw_limit * 1073741824 * 8 / 10 / 1" | bc 2>/dev/null || echo 0)
            if [ "$raw_bytes" -ge "$quota_b" ] 2>/dev/null; then
                bw_disp="${RED}${total_gb}/${bw_limit}GB${NC}"
            elif [ "$raw_bytes" -ge "$pct80" ] 2>/dev/null; then
                bw_disp="${YELLOW}${total_gb}/${bw_limit}GB${NC}"
            else
                bw_disp="${GREEN}${total_gb}/${bw_limit}GB${NC}"
            fi
        else
            bw_disp="${GRAY}${total_gb}GB/∞${NC}"
        fi

        # Login display
        local ld ed
        if   [ "$cc" -eq 0 ];            then ld="${GRAY}0/${limit}${NC}"
        elif [ "$cc" -ge "$limit" ];      then ld="${RED}${cc}/${limit}${NC}"
        else                                   ld="${GREEN}${cc}/${limit}${NC}"
        fi

        # Expire display
        if   [ "$days_left" -le 0 ];                                   then ed="${RED}${ex}${NC}"
        elif [ "$days_left" -le 7 ];                                   then ed="${YELLOW}${ex}${NC}"
        else                                                                 ed="${GREEN}${ex}${NC}"
        fi

        printf "${CYAN}║${WHITE} %-14s %-12b %-8b %-14b %-18b${CYAN} ║${NC}\n" \
            "$u" "$ed" "$ld" "$bw_disp" "$status"
    done

    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${YELLOW}  Total: ${GREEN}${_total_users}${YELLOW} | Online: ${GREEN}${_online_users}${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    unset _sess_map
}

renew_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    read -p "$(echo -e $GREEN"Days to add: "$NC)" d
    cur=$(grep "Expire:" "$UD/$u" | cut -d' ' -f2)
    new=$(date -d "$cur +$d days" +"%Y-%m-%d")
    sed -i "s/Expire: .*/Expire: $new/" "$UD/$u"
    chage -E "$new" "$u" 2>/dev/null
    usermod -U "$u" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Renewed until $new${NC}"
}

set_bandwidth_limit() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    cur=$(grep "Bandwidth_GB:" "$UD/$u" | awk '{print $2}')
    echo -e "${CYAN}Current: ${YELLOW}${cur:-Not set} GB${NC}"
    read -p "$(echo -e $GREEN"New limit (0=unlimited): "$NC)" nb
    [[ ! "$nb" =~ ^[0-9]+\.?[0-9]*$ ]] && { echo -e "${RED}Invalid!${NC}"; return; }
    grep -q "Bandwidth_GB:" "$UD/$u" \
        && sed -i "s/Bandwidth_GB: .*/Bandwidth_GB: $nb/" "$UD/$u" \
        || echo "Bandwidth_GB: $nb" >> "$UD/$u"
    [ "$nb" = "0" ] && usermod -U "$u" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth updated${NC}"
}

reset_bandwidth() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    echo "0" > "$BW_DIR/${u}.usage"
    rm -f "$PID_DIR/${u}"__*.last 2>/dev/null
    usermod -U "$u" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth reset${NC}"
}

lock_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    usermod -L "$u" 2>/dev/null
    pkill -u "$u" 2>/dev/null || true
    echo "$(date) - LOCKED" >> "$BD/$u"
    echo -e "${GREEN}✅ Locked${NC}"
}

unlock_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    usermod -U "$u" 2>/dev/null
    echo "$(date) - UNLOCKED" >> "$BD/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Unlocked${NC}"
}

delete_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    cp "$UD/$u" "$DD/${u}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null
    pkill -u "$u" 2>/dev/null || true
    killall -u "$u" -9 2>/dev/null || true
    userdel -r "$u" 2>/dev/null
    rm -f "$UD/$u" "$USAGE_DB/$u" "$CONN_DB/$u" "$BD/$u" \
          "$BW_DIR/${u}.usage" "/etc/elite-x/user_messages/$u"
    rm -f "$PID_DIR/${u}"__*.last 2>/dev/null
    # Remove from 3proxy
    sed -i "/^${u}:/d" /etc/3proxy/users.list 2>/dev/null
    systemctl reload 3proxy-elite 2>/dev/null || true
    echo -e "${GREEN}✅ Deleted + removed from 3proxy${NC}"
}

details_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}                USER DETAILS v5.0                      ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
    cat "$UD/$u" | while read line; do echo -e "${MAGENTA}║${WHITE}  $line${NC}"; done
    total_gb=$(get_bandwidth_usage "$u")
    bw_limit=$(grep "Bandwidth_GB:" "$UD/$u" | awk '{print $2}'); bw_limit=${bw_limit:-0}
    cc=$(get_connection_count "$u")
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${WHITE}  Active Sessions : ${GREEN}${cc}${NC}"
    echo -e "${MAGENTA}║${WHITE}  Bandwidth Used  : ${GREEN}${total_gb} GB${NC} / ${YELLOW}${bw_limit:-Unlimited} GB${NC}"
    echo -e "${MAGENTA}║${WHITE}  3Proxy Access   : ${GREEN}HTTP:3128 | SOCKS5:1080,1081,1082${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
}

case $1 in
    add)      add_user ;;
    list)     list_users ;;
    details)  details_user ;;
    renew)    renew_user ;;
    setlimit)
        read -p "Username: " u; read -p "New limit: " l
        [ -f "$UD/$u" ] && { sed -i "s/Conn_Limit: .*/Conn_Limit: $l/" "$UD/$u";
        /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null;
        echo -e "${GREEN}✅ Updated${NC}"; } || echo -e "${RED}Not found${NC}" ;;
    setbw)    set_bandwidth_limit ;;
    resetdata) reset_bandwidth ;;
    deleted)  ls "$DD/" 2>/dev/null | head -20 || echo "No deleted users" ;;
    lock)     lock_user ;;
    unlock)   unlock_user ;;
    del)      delete_user ;;
    *)
        echo "Usage: elite-x-user {add|list|details|renew|setlimit|setbw|resetdata|deleted|lock|unlock|del}"
        ;;
esac
USEREOF
    chmod +x /usr/local/bin/elite-x-user
}

# ═══════════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════════
create_main_menu() {
    cat > /usr/local/bin/elite-x <<'MENUEOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
PURPLE='\033[0;35m';WHITE='\033[1;37m';BOLD='\033[1m';NC='\033[0m'
ORANGE='\033[0;33m';LIGHT_RED='\033[1;31m';LIGHT_GREEN='\033[1;32m'
GRAY='\033[0;90m';MAGENTA='\033[1;35m'

UD="/etc/elite-x/users"
BW_DIR="/etc/elite-x/bandwidth"
AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"

show_dashboard() {
    clear
    IP=$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "Unknown")
    SUB=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not set")
    LOC=$(cat /etc/elite-x/location 2>/dev/null || echo "South Africa")
    MTU=$(cat /etc/elite-x/mtu 2>/dev/null || echo "1802")
    RAM=$(free -h | awk '/^Mem:/{print $3"/"$2}')
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "?")

    svc_dot() { systemctl is-active "$1" >/dev/null 2>&1 && echo "${GREEN}●${NC}" || echo "${RED}●${NC}"; }

    DNS=$(svc_dot dnstt-elite-x)
    PRX=$(svc_dot dnstt-elite-x-proxy)
    UDP=$(svc_dot elite-x-udp-turbo)
    SPD=$(svc_dot elite-x-speedbooster)
    BW=$(svc_dot elite-x-bandwidth)
    NBOOST=$(svc_dot elite-x-netbooster)
    DNSC=$(svc_dot elite-x-dnscache)
    RAMC=$(svc_dot elite-x-ramcleaner)
    IRQ=$(svc_dot elite-x-irqopt)
    SDRELAY=$(svc_dot elite-x-slowdns-relay)
    PROXY3=$(svc_dot 3proxy-elite)
    CONNMON=$(svc_dot elite-x-connmon)

    TOTAL=$(ls "$UD" 2>/dev/null | wc -l)
    # Hesabu accurate VPN users wanaofanya kazi sasa via /proc (sio who)
    ONLINE=0
    declare -A _dash_sess
    for _pd in /proc/[0-9]*/; do
        [ -f "${_pd}comm" ] || continue
        [ "$(cat "${_pd}comm" 2>/dev/null)" = "sshd" ] || continue
        _dppid=$(awk '{print $4}' "${_pd}stat" 2>/dev/null)
        [ "$_dppid" = "1" ] && continue
        _dpuid=$(awk '/^Uid:/{print $2}' "${_pd}status" 2>/dev/null)
        [ -n "$_dpuid" ] && _dash_sess[$_dpuid]=1
    done
    for _uid_key in "${!_dash_sess[@]}"; do
        _uname=$(getent passwd "$_uid_key" 2>/dev/null | cut -d: -f1)
        [ -f "$UD/$_uname" ] && ONLINE=$((ONLINE + 1))
    done
    unset _dash_sess

    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}${BOLD}    ELITE-X SLOWDNS VPN v5 - FALCON ULTRA       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${WHITE}  IP   :${CYAN} $IP   ${WHITE}MTU:${CYAN}$MTU  ${WHITE}LOC:${CYAN}$LOC${NC}"
    echo -e "${MAGENTA}║${WHITE}  NS   :${CYAN} $SUB${NC}"
    echo -e "${MAGENTA}║${WHITE}  RAM  :${CYAN} $RAM   ${WHITE}CPU:${CYAN}${CPU}%  ${WHITE}Users:${CYAN}${TOTAL}  ${WHITE}Online:${CYAN}${ONLINE}${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${YELLOW}  SERVICES STATUS:${NC}"
    echo -e "${MAGENTA}║${WHITE}  DNSTT Server    $DNS  C-EDNS Proxy  $PRX  UDP Turbo    $UDP${NC}"
    echo -e "${MAGENTA}║${WHITE}  SlowDNS Relay   $SDRELAY  3Proxy HTTP+S5 $PROXY3  Conn Mon     $CONNMON${NC}"
    echo -e "${MAGENTA}║${WHITE}  Speed Booster   $SPD  Net Booster   $NBOOST  DNS Cache    $DNSC${NC}"
    echo -e "${MAGENTA}║${WHITE}  BW Monitor      $BW   IRQ Optimizer $IRQ  RAM Cleaner  $RAMC${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${CYAN}  PORTS: SlowDNS UDP:53|5301|5302|5303  TCP:5304${NC}"
    echo -e "${MAGENTA}║${CYAN}  3Proxy HTTP:3128  SOCKS5:1080(G)|1081(SD)|1082(DNS)${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

settings_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${YELLOW}              SETTINGS v5.0                 ${CYAN}║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
        AUTOBAN=$(cat "$AUTOBAN_FLAG" 2>/dev/null || echo 0)
        [ "$AUTOBAN" = "1" ] && AB="${GREEN}ON${NC}" || AB="${RED}OFF${NC}"
        echo -e "${CYAN}║${WHITE}  [1]  Auto-Ban        : $AB${NC}"
        echo -e "${CYAN}║${WHITE}  [2]  Restart All Services${NC}"
        echo -e "${CYAN}║${WHITE}  [3]  Restart DNSTT + Relay${NC}"
        echo -e "${CYAN}║${WHITE}  [4]  Restart 3Proxy${NC}"
        echo -e "${CYAN}║${WHITE}  [5]  Fix VPN/SSH${NC}"
        echo -e "${CYAN}║${WHITE}  [6]  Refresh All User Messages${NC}"
        echo -e "${CYAN}║${WHITE}  [7]  Test User Message${NC}"
        echo -e "${CYAN}║${WHITE}  [8]  Apply Speed Boost Now${NC}"
        echo -e "${CYAN}║${WHITE}  [9]  Show 3Proxy Users${NC}"
        echo -e "${CYAN}║${RED}  [10] ⚠️  UNINSTALL ELITE-X${NC}"
        echo -e "${CYAN}║${YELLOW}  [11] 🔄 Reboot Server${NC}"
        echo -e "${CYAN}║${WHITE}  [12] 🔧 Change MTU${NC}"
        echo -e "${CYAN}║${WHITE}  [0]  Back${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch

        case $ch in
            1)
                [ "$AUTOBAN" = "1" ] && echo 0 > "$AUTOBAN_FLAG" || echo 1 > "$AUTOBAN_FLAG"
                ;;
            2)
                for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-udp-turbo \
                         elite-x-slowdns-relay 3proxy-elite \
                         elite-x-speedbooster elite-x-bandwidth elite-x-connmon \
                         elite-x-netbooster elite-x-dnscache elite-x-ramcleaner \
                         elite-x-irqopt elite-x-logcleaner elite-x-datausage; do
                    systemctl restart "$s" 2>/dev/null || true
                done
                echo -e "${GREEN}✅ All services restarted${NC}"; read -p "Enter..."
                ;;
            3)
                systemctl restart dnstt-elite-x dnstt-elite-x-proxy \
                    elite-x-slowdns-relay elite-x-udp-turbo 2>/dev/null
                echo -e "${GREEN}✅ DNSTT + Relays restarted${NC}"; read -p "Enter..."
                ;;
            4)
                systemctl restart 3proxy-elite 2>/dev/null
                echo -e "${GREEN}✅ 3Proxy restarted${NC}"; read -p "Enter..."
                ;;
            5)
                systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd 2>/dev/null
                echo -e "${GREEN}✅ VPN/SSH Fixed${NC}"; read -p "Enter..."
                ;;
            6)
                for u in "$UD"/*; do
                    [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")" 2>/dev/null
                done
                systemctl reload sshd 2>/dev/null
                echo -e "${GREEN}✅ Messages refreshed${NC}"; read -p "Enter..."
                ;;
            7)
                read -p "Username: " un
                [ -f "/etc/elite-x/user_messages/$un" ] && cat "/etc/elite-x/user_messages/$un" \
                    || echo "No message for $un"
                read -p "Enter..."
                ;;
            8)
                systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-irqopt 2>/dev/null
                echo -e "${GREEN}✅ Speed boost applied${NC}"; read -p "Enter..."
                ;;
            9)
                echo -e "${CYAN}3Proxy users:${NC}"
                cat /etc/3proxy/users.list 2>/dev/null | sed 's/:CL:.*/: [password hidden]/' \
                    || echo "No users"
                read -p "Enter..."
                ;;
            10)
                clear
                echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║${YELLOW}${BOLD}         ⚠️  UNINSTALL ELITE-X v5.0 ⚠️           ${RED}║${NC}"
                echo -e "${RED}╠══════════════════════════════════════════════════════╣${NC}"
                echo -e "${RED}║${WHITE}  Hii itafuta KILA KITU:                          ${RED}║${NC}"
                echo -e "${RED}║${WHITE}  • Users wote watafutwa                          ${RED}║${NC}"
                echo -e "${RED}║${WHITE}  • Services zote zitasimamishwa                  ${RED}║${NC}"
                echo -e "${RED}║${WHITE}  • Binaries na configs zote zitafutwa            ${RED}║${NC}"
                echo -e "${RED}║${WHITE}  • SSH config itarudishwa default                ${RED}║${NC}"
                echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
                echo -e "${YELLOW}Andika ${RED}YES${YELLOW} kuthibitisha (au Enter kuancel):${NC}"
                read -p "$(echo -e $RED"Thibitisha: "$NC)" confirm
                if [ "$confirm" = "YES" ]; then
                    echo -e "${YELLOW}🔄 Inafuta users wote...${NC}"
                    for u_file in "$UD"/*; do
                        [ -f "$u_file" ] || continue
                        un=$(basename "$u_file")
                        pkill -u "$un" 2>/dev/null || true
                        killall -u "$un" -9 2>/dev/null || true
                        userdel -r "$un" 2>/dev/null || true
                    done
                    echo -e "${YELLOW}🔄 Inasimamisha na kufuta services...${NC}"
                    for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth                               elite-x-datausage elite-x-connmon elite-x-netbooster                               elite-x-dnscache elite-x-ramcleaner elite-x-irqopt                               elite-x-logcleaner elite-x-udp-turbo elite-x-speedbooster                               elite-x-slowdns-relay 3proxy-elite; do
                        systemctl stop    "$s" 2>/dev/null || true
                        systemctl disable "$s" 2>/dev/null || true
                    done
                    rm -f /etc/systemd/system/{dnstt-elite-x*,elite-x*,3proxy-elite*}
                    rm -rf /etc/dnstt /etc/elite-x /var/run/elite-x /etc/3proxy /var/log/3proxy
                    rm -f /usr/local/bin/{dnstt-*,elite-x*,3proxy}
                    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf
                    rm -f /etc/sysctl.d/99-elite-x-vpn.conf
                    rm -f /etc/security/limits.d/elite-x.conf
                    rm -f /etc/systemd/system.conf.d/elite-x-limits.conf
                    sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
                    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
                    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
                    rm -f /etc/profile.d/elite-x-dashboard.sh
                    sed -i '/elite-x\|elitex\|adduser.*elite\|setbw\|boost\|fixvpn\|fix3proxy\|refreshmsg\|testmsg\|speedtest\|ports.*SlowDNS/d' ~/.bashrc 2>/dev/null
                    systemctl daemon-reload
                    systemctl restart sshd 2>/dev/null || true
                    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
                    echo -e "${GREEN}║${YELLOW}  ✅ ELITE-X imefutwa kikamilifu!               ${GREEN}║${NC}"
                    echo -e "${GREEN}║${WHITE}  SSH bado inafanya kazi - unaweza kuingia tena. ${GREEN}║${NC}"
                    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
                    exit 0
                else
                    echo -e "${GREEN}✅ Imeancel - Elite-X ipo salama.${NC}"
                fi
                read -p "Press Enter..."
                ;;
            11)
                clear
                echo -e "${YELLOW}╔══════════════════════════════════════════╗${NC}"
                echo -e "${YELLOW}║${RED}${BOLD}       🔄 REBOOT SERVER              ${YELLOW}║${NC}"
                echo -e "${YELLOW}╠══════════════════════════════════════════╣${NC}"
                echo -e "${YELLOW}║${WHITE}  Server itaanza upya baada ya 5s.  ${YELLOW}║${NC}"
                echo -e "${YELLOW}║${WHITE}  SSH itarudi baada ya ~30 sekunde.  ${YELLOW}║${NC}"
                echo -e "${YELLOW}╚══════════════════════════════════════════╝${NC}"
                read -p "$(echo -e $RED"Thibitisha reboot? [y/N]: "$NC)" _rb
                if [[ "$_rb" =~ ^[Yy]$ ]]; then
                    echo -e "${GREEN}✅ Inareboot...${NC}"
                    sleep 2
                    reboot
                else
                    echo -e "${GREEN}✅ Imeancel.${NC}"
                fi
                read -p "Press Enter..."
                ;;
            12)
                clear
                echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║${YELLOW}           🔧 CHANGE MTU                    ${CYAN}║${NC}"
                echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
                CURRENT_MTU=$(cat /etc/elite-x/mtu 2>/dev/null || echo "1802")
                echo -e "${CYAN}║${WHITE}  Current MTU  : ${GREEN}${CURRENT_MTU}${NC}"
                echo -e "${CYAN}║${WHITE}  Recommended  : ${CYAN}1800 (stable) | 1802 (boost)${NC}"
                echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
                read -p "$(echo -e $GREEN"New MTU (100-3000) [Enter=keep $CURRENT_MTU]: "$NC)" NEW_MTU
                if [ -z "$NEW_MTU" ]; then
                    echo -e "${YELLOW}MTU unchanged: ${CURRENT_MTU}${NC}"
                elif [[ ! "$NEW_MTU" =~ ^[0-9]+$ ]] || [ "$NEW_MTU" -lt 100 ] 2>/dev/null || [ "$NEW_MTU" -gt 3000 ] 2>/dev/null; then
                    echo -e "${RED}❌ Invalid MTU! Must be 100-3000.${NC}"
                else
                    echo "$NEW_MTU" > /etc/elite-x/mtu
                    TDOMAIN=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "")
                    if [ -n "$TDOMAIN" ]; then
                        sed -i "s|-mtu [0-9]*|-mtu $NEW_MTU|" /etc/systemd/system/dnstt-elite-x.service 2>/dev/null
                        systemctl daemon-reload 2>/dev/null
                        systemctl restart dnstt-elite-x 2>/dev/null
                        echo -e "${GREEN}✅ MTU changed to ${NEW_MTU} - DNSTT restarted${NC}"
                    else
                        echo -e "${GREEN}✅ MTU saved: ${NEW_MTU}${NC}"
                    fi
                fi
                read -p "Press Enter..."
                ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        show_dashboard
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║${GREEN}${BOLD}                     MAIN MENU v5.0                        ${MAGENTA}║${NC}"
        echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${MAGENTA}║${WHITE}  [1] Create User    [2] List Users     [3] User Details${NC}"
        echo -e "${MAGENTA}║${WHITE}  [4] Renew User     [5] Set Conn Limit  [6] Set BW Limit${NC}"
        echo -e "${MAGENTA}║${WHITE}  [7] Reset BW       [8] Lock User       [9] Unlock User${NC}"
        echo -e "${MAGENTA}║${WHITE}  [10] Delete User   [11] Deleted List    [S] Settings${NC}"
        echo -e "${MAGENTA}║${WHITE}  [M] Test Msg       [P] Show Ports       [0] Exit${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch

        case $ch in
            1)  elite-x-user add;        read -p "Press Enter..." ;;
            2)  elite-x-user list;       read -p "Press Enter..." ;;
            3)  elite-x-user details;    read -p "Press Enter..." ;;
            4)  elite-x-user renew;      read -p "Press Enter..." ;;
            5)  elite-x-user setlimit;   read -p "Press Enter..." ;;
            6)  elite-x-user setbw;      read -p "Press Enter..." ;;
            7)  elite-x-user resetdata;  read -p "Press Enter..." ;;
            8)  elite-x-user lock;       read -p "Press Enter..." ;;
            9)  elite-x-user unlock;     read -p "Press Enter..." ;;
            10) elite-x-user del;        read -p "Press Enter..." ;;
            11) elite-x-user deleted;    read -p "Press Enter..." ;;
            [Ss]) settings_menu ;;
            [Pp])
                clear
                IP=$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "?")
                echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
                echo -e "${MAGENTA}║${YELLOW}        ELITE-X v5.0 PORT REFERENCE             ${MAGENTA}║${NC}"
                echo -e "${MAGENTA}╠══════════════════════════════════════════════════════╣${NC}"
                echo -e "${MAGENTA}║${CYAN}  SSH          : ${WHITE}22${NC}"
                echo -e "${MAGENTA}║${CYAN}  SlowDNS UDP  : ${WHITE}53 (primary DNS)${NC}"
                echo -e "${MAGENTA}║${CYAN}  DNSTT Backend: ${WHITE}5300${NC}"
                echo -e "${MAGENTA}║${CYAN}  UDP Turbo 1  : ${WHITE}5301${NC}"
                echo -e "${MAGENTA}║${CYAN}  UDP Turbo 2  : ${WHITE}5302${NC}"
                echo -e "${MAGENTA}║${CYAN}  SlowDNS UDP  : ${WHITE}5303 (multi-protocol)${NC}"
                echo -e "${MAGENTA}║${CYAN}  SlowDNS TCP  : ${WHITE}5304 (multi-protocol)${NC}"
                echo -e "${MAGENTA}║${YELLOW}  ── 3Proxy ──────────────────────────────── ${MAGENTA}║${NC}"
                echo -e "${MAGENTA}║${CYAN}  HTTP Proxy   : ${WHITE}$IP:3128${NC}"
                echo -e "${MAGENTA}║${CYAN}  SOCKS5 Global: ${WHITE}$IP:1080${NC}"
                echo -e "${MAGENTA}║${CYAN}  SOCKS5 SlowDN: ${WHITE}$IP:1081${NC}"
                echo -e "${MAGENTA}║${CYAN}  SOCKS5 DNSTT : ${WHITE}$IP:1082${NC}"
                echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"
                read -p "Press Enter..."
                ;;
            [Mm])
                read -p "Username: " un
                if [ -f "/etc/elite-x/user_messages/$un" ]; then
                    clear
                    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
                    echo -e "${CYAN}║${YELLOW}       USER MESSAGE PREVIEW FOR: $un                  ${CYAN}║${NC}"
                    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
                    cat "/etc/elite-x/user_messages/$un"
                    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
                else
                    echo -e "${RED}No message for $un!${NC}"
                fi
                read -p "Press Enter..."
                ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; read -p "Press Enter..." ;;
        esac
    done
}

main_menu
MENUEOF
    chmod +x /usr/local/bin/elite-x
}

# ═══════════════════════════════════════════════════════════
# MAIN INSTALLATION FUNCTION
# ═══════════════════════════════════════════════════════════
run_installation() {
    show_banner

    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}          ELITE-X v5.0 ACTIVATION REQUIRED          ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT

    if [ "$ACTIVATION_INPUT" != "$ACTIVATION_KEY" ] && \
       [ "$ACTIVATION_INPUT" != "Whtsapp +255713-628-668" ]; then
        echo -e "${RED}❌ Invalid activation key!${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Activation successful${NC}"
    sleep 1

    # ── Tambua OS (Fedora / RHEL family / Amazon Linux) ──
    detect_os

    set_timezone

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           ENTER YOUR NAMESERVER [NS]           ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Nameserver (e.g. ns1.yourdomain.com): "$NC)" TDOMAIN

    echo -e "${YELLOW}Select VPS location:${NC}"
    echo -e "  [1] South Africa (MTU 1802) "
    echo -e "  [2] USA          (MTU 1500)"
    echo -e "  [3] Europe       (MTU 1500)"
    echo -e "  [4] Asia         (MTU 1400)"
    echo -e "  [5] Custom MTU   (100 - 3000)"
    read -p "$(echo -e $GREEN"Choice [1]: "$NC)" LOC
    LOC=${LOC:-1}
    case $LOC in
        2) SEL_LOC="USA";          MTU=1500 ;;
        3) SEL_LOC="Europe";       MTU=1500 ;;
        4) SEL_LOC="Asia";         MTU=1400 ;;
        5) SEL_LOC="Custom"
           read -p "Enter MTU (100-3000): " MTU
           [[ ! "$MTU" =~ ^[0-9]+$ ]] && MTU=1802
           [ "$MTU" -lt 100  ] 2>/dev/null && MTU=100
           [ "$MTU" -gt 3000 ] 2>/dev/null && MTU=1802 ;;
        *) SEL_LOC="South Africa"; MTU=1802 ;;
    esac

    # ── Cleanup previous installation ─────────────────────
    echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"
    for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth elite-x-datausage \
              elite-x-connmon elite-x-cleaner elite-x-traffic elite-x-netbooster \
              elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner \
              elite-x-udp-turbo elite-x-speedbooster elite-x-slowdns-relay 3proxy-elite \
              elite-x-netreapply.timer elite-x-netreapply.service elite-x-iptables-restore; do
        systemctl stop    "$s" 2>/dev/null || true
        systemctl disable "$s" 2>/dev/null || true
    done

    rm -f /etc/NetworkManager/dispatcher.d/99-elite-x-netopt 2>/dev/null

    pkill -f dnstt-server          2>/dev/null || true
    pkill -f elite-x-edns-proxy    2>/dev/null || true
    pkill -f elite-x-udp-turbo     2>/dev/null || true
    pkill -f elite-x-speedbooster  2>/dev/null || true
    pkill -f elite-x-slowdns-relay 2>/dev/null || true
    pkill -f 3proxy                2>/dev/null || true

    rm -rf /etc/systemd/system/{dnstt-elite-x*,elite-x*,3proxy-elite*} 2>/dev/null
    rm -rf /etc/dnstt /etc/elite-x /var/run/elite-x                    2>/dev/null
    rm -f  /usr/local/bin/{dnstt-*,elite-x*}                           2>/dev/null
    rm -f  /etc/ssh/sshd_config.d/elite-x-*.conf                       2>/dev/null
    rm -f  /etc/sysctl.d/99-elite-x-vpn.conf                           2>/dev/null
    sed -i '/^Match User/,/Banner/d'                           /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d'   /etc/ssh/sshd_config 2>/dev/null
    sed -i '/elite-x-update-user-msg/d'                        /etc/pam.d/sshd      2>/dev/null
    systemctl restart sshd 2>/dev/null || true
    sleep 2

    # ── Create directories ─────────────────────────────────
    mkdir -p /etc/elite-x/{users,traffic,deleted,data_usage,connections,banned,\
traffic_stats,bandwidth/pidtrack,user_messages}
    mkdir -p /etc/ssh/sshd_config.d
    mkdir -p /var/run/elite-x/bandwidth
    mkdir -p /etc/3proxy /var/log/3proxy

    echo "$TDOMAIN"           > /etc/elite-x/subdomain
    echo "$SEL_LOC"           > /etc/elite-x/location
    echo "$MTU"               > /etc/elite-x/mtu
    echo "0"                  > "$AUTOBAN_FLAG"
    echo "$STATIC_PRIVATE_KEY" > /etc/elite-x/private_key
    echo "$STATIC_PUBLIC_KEY"  > /etc/elite-x/public_key

    # ── DNS ────────────────────────────────────────────────
    [ -f /etc/systemd/resolved.conf ] && {
        sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null || true
    }
    [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 9.9.9.9\noptions timeout:1 attempts:3 rotate\noptions ndots:0\n" \
        > /etc/resolv.conf

    # ── Install dependencies (OS-aware: Fedora / RHEL / Amazon Linux) ──
    echo -e "${YELLOW}📦 Installing dependencies (${OS_NAME})...${NC}"
    "$PKG_MANAGER" check-update -y >/dev/null 2>&1 || true

    # Packages za msingi - zinapatikana Fedora, RHEL family, na Amazon Linux 2/2023
    pkg_install curl jq iptables ethtool bind-utils net-tools bc psmisc \
                 gcc make glibc-devel git openssl-devel

    # "ip"/"ss"/"tc" command - jina la package hutofautiana kati ya distros
    pkg_install iproute iproute2

    # perf - haipo kila wakati kwenye Amazon Linux minimal images
    pkg_install perf

    if [ "$IS_AMAZON_LINUX" = "0" ]; then
        # iptables-legacy + policycoreutils-python-utils - Fedora/RHEL pekee
        pkg_install iptables-legacy
        pkg_install policycoreutils-python-utils
    fi

    # firewalld - Fedora/RHEL inakuja nayo; Amazon Linux kwa kawaida hailetwi
    # (AWS hutumia Security Groups), tunaijaribu lakini si lazima ifanikiwe
    pkg_install firewalld

    # ── SELinux - weka permissive mode (kama ipo) ─────────
    if [ "$HAS_SELINUX" = "1" ]; then
        echo -e "${YELLOW}🔒 Configuring SELinux...${NC}"
        setenforce 0 2>/dev/null || true
        sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
        echo -e "${GREEN}✅ SELinux set to permissive${NC}"
    else
        echo -e "${GRAY}ℹ️  SELinux haijapatikana kwenye mfumo huu - hatua hii imeskipwa${NC}"
    fi

    # ── Firewall - fungua ports zinazohitajika ────────────
    echo -e "${YELLOW}🔥 Configuring firewall for VPN ports...${NC}"
    FW_TCP_PORTS=(22 5304 3128 1080 1081 1082)
    FW_UDP_PORTS=(53 5300 5301 5302 5303)

    if command -v firewall-cmd >/dev/null 2>&1 && \
       (systemctl is-active firewalld >/dev/null 2>&1 || systemctl start firewalld 2>/dev/null); then
        for p in "${FW_TCP_PORTS[@]}"; do firewall-cmd --permanent --add-port="${p}/tcp" 2>/dev/null || true; done
        for p in "${FW_UDP_PORTS[@]}"; do firewall-cmd --permanent --add-port="${p}/udp" 2>/dev/null || true; done
        firewall-cmd --permanent --add-masquerade 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        echo -e "${GREEN}✅ Firewalld ports configured${NC}"
    else
        # Amazon Linux / mifumo isiyo na firewalld - tumia iptables moja kwa moja
        echo -e "${YELLOW}ℹ️  Firewalld haipo/haijaanza - kufungua ports kupitia iptables...${NC}"
        for p in "${FW_TCP_PORTS[@]}"; do
            iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || true
        done
        for p in "${FW_UDP_PORTS[@]}"; do
            iptables -C INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || true
        done

        # Hifadhi rules + zirudi automatically kila reboot
        mkdir -p /etc/elite-x
        iptables-save > /etc/elite-x/iptables.rules 2>/dev/null || true
        cat > /etc/systemd/system/elite-x-iptables-restore.service <<EOF
[Unit]
Description=ELITE-X Restore iptables rules
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/elite-x/iptables.rules
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable elite-x-iptables-restore.service 2>/dev/null || true
        echo -e "${GREEN}✅ iptables ports configured + zitabaki baada ya reboot${NC}"

        if [ "$IS_AMAZON_LINUX" = "1" ]; then
            echo -e "${ORANGE}⚠️  AWS: Hakikisha pia umefungua ports hizi kwenye Security Group ya EC2:${NC}"
            echo -e "${ORANGE}    TCP: 22,5304,3128,1080,1081,1082  |  UDP: 53,5300,5301,5302,5303${NC}"
        fi
    fi

    # ── Download DNSTT ────────────────────────────────────
    echo -e "${YELLOW}📥 Downloading DNSTT server...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 \
         -o /usr/local/bin/dnstt-server 2>/dev/null || \
    curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server \
         -o /usr/local/bin/dnstt-server 2>/dev/null
    chmod +x /usr/local/bin/dnstt-server

    # ── DNSTT keys ────────────────────────────────────────
    mkdir -p /etc/dnstt
    echo "$STATIC_PRIVATE_KEY" > /etc/dnstt/server.key
    echo "$STATIC_PUBLIC_KEY"  > /etc/dnstt/server.pub
    chmod 600 /etc/dnstt/server.key

    # ── DNSTT main service ────────────────────────────────
    cat > /etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=ELITE-X DNSTT Server v5.0 ULTRA
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -mtu ${MTU} -privkey-file /etc/dnstt/server.key ${TDOMAIN} 127.0.0.1:22
Restart=always
RestartSec=3
LimitNOFILE=2097152
LimitNPROC=65536
Nice=-10
[Install]
WantedBy=multi-user.target
EOF

    # ── Optimize system ───────────────────────────────────
    optimize_system_for_vpn

    # ── PAM + user messages ───────────────────────────────
    configure_pam_user_message

    # ── SSH config ────────────────────────────────────────
    configure_ssh_for_vpn

    # ── Install 3proxy ────────────────────────────────────
    install_3proxy

    # ── Compile all C components ──────────────────────────
    create_c_edns_proxy
    create_c_udp_turbo
    create_c_slowdns_relay
    create_c_speed_booster
    create_c_bandwidth_monitor
    create_c_connection_monitor
    create_c_data_usage
    create_c_network_booster
    create_c_dns_cache
    create_c_ram_cleaner
    create_c_irq_optimizer
    create_c_log_cleaner

    # ── User & menu scripts ───────────────────────────────
    create_user_script
    create_main_menu

    # ── Enable & start all services ───────────────────────
    systemctl daemon-reload

    ALL_SERVICES=(
        dnstt-elite-x
        dnstt-elite-x-proxy
        elite-x-udp-turbo
        elite-x-slowdns-relay
        3proxy-elite
        elite-x-speedbooster
        elite-x-bandwidth
        elite-x-datausage
        elite-x-connmon
        elite-x-netbooster
        elite-x-dnscache
        elite-x-ramcleaner
        elite-x-irqopt
        elite-x-logcleaner
    )

    for s in "${ALL_SERVICES[@]}"; do
        if [ -f "/etc/systemd/system/${s}.service" ]; then
            systemctl enable "$s" 2>/dev/null || true
            systemctl start  "$s" 2>/dev/null || true
        fi
    done

    # ── Cache IP ──────────────────────────────────────────
    IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "Unknown")
    echo "$IP" > /etc/elite-x/cached_ip

    # ── Auto-login dashboard ──────────────────────────────
    cat > /etc/profile.d/elite-x-dashboard.sh <<'EOF'
#!/bin/bash
if [ -f /usr/local/bin/elite-x ] && [ -z "$ELITE_X_SHOWN" ]; then
    export ELITE_X_SHOWN=1
    /usr/local/bin/elite-x
fi
EOF
    chmod +x /etc/profile.d/elite-x-dashboard.sh

    # ── Shell aliases ─────────────────────────────────────
    grep -qF "alias menu='elite-x'" ~/.bashrc 2>/dev/null || cat >> ~/.bashrc <<'EOF'
alias menu='elite-x'
alias elitex='elite-x'
alias adduser='elite-x-user add'
alias users='elite-x-user list'
alias setbw='elite-x-user setbw'
alias boost='systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-udp-turbo'
alias fixvpn='systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd && echo "VPN Fixed!"'
alias fix3proxy='systemctl restart 3proxy-elite && echo "3Proxy Fixed!"'
alias refreshmsg='for u in /etc/elite-x/users/*; do [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")"; done && systemctl reload sshd && echo "✅ Messages refreshed!"'
alias testmsg='read -p "Username: " u; cat /etc/elite-x/user_messages/$u 2>/dev/null || echo "No message"'
alias speedtest='systemctl restart elite-x-speedbooster && echo "Speed boost applied!"'
alias ports='echo "SlowDNS UDP:53|5301|5302|5303  TCP:5304  HTTP:3128  SOCKS5:1080|1081|1082"'
EOF

    # ── Create messages for existing users ────────────────
    for user_file in /etc/elite-x/users/*; do
        [ -f "$user_file" ] && \
            /usr/local/bin/elite-x-force-user-message "$(basename "$user_file")" 2>/dev/null
    done

    # ══════════════════════════════════════════════════════
    # FINAL DISPLAY
    # ══════════════════════════════════════════════════════
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}${BOLD}     ELITE-X v5 FALCON ULTRA  INSTALLED!       ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Domain     :${CYAN} $TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  Location   :${CYAN} $SEL_LOC (MTU: $MTU)${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  OS         :${CYAN} $OS_NAME${NC}"
    echo -e "${GREEN}║${WHITE}  Version    :${CYAN} v5 Falcon Ultra${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"

    check_svc() {
        local name=$1 svc=$2
        systemctl is-active "$svc" >/dev/null 2>&1 \
            && echo -e "${GREEN}║  ✅ $name: ${LIGHT_GREEN}Running${NC}" \
            || echo -e "${RED}║  ❌ $name: Failed${NC}"
    }

    check_svc "DNSTT Server         " "dnstt-elite-x"
    check_svc "C EDNS Proxy         " "dnstt-elite-x-proxy"
    check_svc "C UDP Turbo(5301+5302)" "elite-x-udp-turbo"
    check_svc "SlowDNS Multi-Proto  " "elite-x-slowdns-relay"
    check_svc "3Proxy HTTP+SOCKS5   " "3proxy-elite"
    check_svc "SSH Server           " "sshd"
    check_svc "C Speed Booster      " "elite-x-speedbooster"
    check_svc "C Bandwidth Monitor  " "elite-x-bandwidth"
    check_svc "C Conn Monitor       " "elite-x-connmon"
    check_svc "C Net Booster        " "elite-x-netbooster"
    check_svc "C DNS Cache          " "elite-x-dnscache"
    check_svc "C RAM Cleaner        " "elite-x-ramcleaner"
    check_svc "C IRQ Optimizer      " "elite-x-irqopt"
    check_svc "C Log Cleaner        " "elite-x-logcleaner"
    check_svc "Anti Speed-Drop Timer" "elite-x-netreapply.timer"


    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  NEW IN v5:${NC}"
    echo -e "${GREEN}║${WHITE}  🌐 SlowDNS Multi-Protocol: UDP:5303 + TCP:5304${NC}"
    echo -e "${GREEN}║${WHITE}  🔁 3Proxy HTTP(:3128) + SOCKS5(:1080/:1081/:1082)${NC}"
    echo -e "${GREEN}║${WHITE}  🚀 UDP Turbo DUAL port: 5301 + 5302 (48 workers)${NC}"
    echo -e "${GREEN}║${WHITE}  🎨 Colorful SSH banners with mins remaining${NC}"
    echo -e "${GREEN}║${WHITE}  📊 Accurate connection count (ss+who+proc)${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ C EDNS Proxy: 64 workers + 32MB buffers${NC}"
    echo -e "${GREEN}║${WHITE}  🔋 BBR3 + FQ qdisc + RPS/XPS all CPUs${NC}"
    echo -e "${GREEN}║${WHITE}  📦 MTU 1802 MAX ${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${CYAN}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS     : ${CYAN}$TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY : ${CYAN}$STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}║${WHITE}  UDP    : ${CYAN}53 | 5301 | 5302 | 5303${NC}"
    echo -e "${GREEN}║${WHITE}  TCP    : ${CYAN}5304${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${CYAN}  3PROXY CONFIG (add user first):${NC}"
    echo -e "${GREEN}║${WHITE}  HTTP   : ${CYAN}$IP:3128${NC}"
    echo -e "${GREEN}║${WHITE}  SOCKS5 : ${CYAN}$IP:1080 (global)${NC}"
    echo -e "${GREEN}║${WHITE}  SOCKS5 : ${CYAN}$IP:1081 (SlowDNS dedicated)${NC}"
    echo -e "${GREEN}║${WHITE}  SOCKS5 : ${CYAN}$IP:1082 (DNSTT dedicated)${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Commands: menu | adduser | users | boost | fixvpn | fix3proxy | ports${NC}"
    echo -e "${YELLOW}Re-login or 'exec bash' to access dashboard${NC}"
    echo ""
}

# ── Entry point ────────────────────────────────────────────
run_installation

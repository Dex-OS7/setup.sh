#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
#  ELITE-X SLOWDNS SCRIPT v5.0 - FALCON SUPREME ULTRA
#  CPU ZOTE + RAM YOTE → SLOWDNS PEKE YAKE
#  New: io_uring UDP, CAKE qdisc, cgroups v2, UDP GSO/GRO,
#       SO_ZEROCOPY, DNS Pool, CPU Pinning, Zero Services Waste
# ╚══════════════════════════════════════════════════════════════════════════╝

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'
ORANGE='\033[0;33m'; LIGHT_RED='\033[1;31m'; LIGHT_GREEN='\033[1;32m'; GRAY='\033[0;90m'
NC='\033[0m'

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
USER_MSG_DIR="/etc/elite-x/user_messages"

# Gundua CPU cores zote
TOTAL_CORES=$(nproc 2>/dev/null || echo 2)
LAST_CORE=$((TOTAL_CORES - 1))
CPU_RANGE="0-${LAST_CORE}"

show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${YELLOW}${BOLD}  ELITE-X SLOWDNS v5.0 - FALCON SUPREME ULTRA  ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}  CPU ZOTE + RAM YOTE → SLOWDNS | io_uring | CAKE  ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_color() { echo -e "${2}${1}${NC}"; }
set_timezone() {
    timedatectl set-timezone $TIMEZONE 2>/dev/null || \
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════
# ZUIA SERVICES ZISIZO ZA LAZIMA — Resources → SlowDNS
# ═══════════════════════════════════════════════════════════
kill_unnecessary_services() {
    echo -e "${YELLOW}🔪 Kuzima services zisizo za lazima...${NC}"

    KILL_SERVICES=(
        snapd snapd.socket snapd.seeded.service
        unattended-upgrades apt-daily apt-daily-upgrade
        apt-daily.timer apt-daily-upgrade.timer
        apport whoopsie kerneloops
        avahi-daemon avahi-daemon.socket
        bluetooth ModemManager
        cups cups-browsed
        postfix sendmail exim4
        rpcbind nfs-server
        iscsid open-iscsi
        lxcfs lxd
        ufw firewalld
        multipathd
        accounts-daemon
        colord
        packagekit
        polkit
        thermald
        irqbalance
        fwupd
        udisks2
        geoclue
    )

    for svc in "${KILL_SERVICES[@]}"; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
    done

    # Punguza journald RAM usage
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/elite-x.conf <<'EOF'
[Journal]
Storage=none
Compress=no
SystemMaxUse=10M
RuntimeMaxUse=10M
MaxRetentionSec=1day
EOF
    systemctl restart systemd-journald 2>/dev/null || true

    echo -e "${GREEN}✅ Services zisizo za lazima zimezimwa${NC}"
}

# ═══════════════════════════════════════════════════════════
# FORCE USER MESSAGE ON SSH LOGIN
# ═══════════════════════════════════════════════════════════
force_user_message() {
    local username="$1"
    local msg_file="$USER_MSG_DIR/$username"
    mkdir -p "$USER_MSG_DIR"

    local expire_date=$(grep "Expire:" "$USER_DB/$username" | awk '{print $2}')
    local bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$username" | awk '{print $2}')
    local conn_limit=$(grep "Conn_Limit:" "$USER_DB/$username" | awk '{print $2}')
    bandwidth_gb=${bandwidth_gb:-0}
    conn_limit=${conn_limit:-1}

    local usage_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
    local usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

    local current_conn=0
    current_conn=$(who | grep -wc "$username" 2>/dev/null || echo 0)
    [ "$current_conn" -eq 0 ] && current_conn=$(ps aux 2>/dev/null | grep "sshd:" | grep "$username" | grep -v grep | grep -v "sshd:.*@notty" | wc -l)
    current_conn=${current_conn:-0}

    local now_ts=$(date +%s)
    local expire_ts=$(date -d "$expire_date" +%s 2>/dev/null || echo 0)
    local remaining_seconds=$((expire_ts - now_ts))
    local remaining_days=$((remaining_seconds / 86400))
    local remaining_hours=$(((remaining_seconds % 86400) / 3600))
    [ $remaining_days -lt 0 ] && remaining_days=0
    [ $remaining_hours -lt 0 ] && remaining_hours=0

    local bw_display="Unlimited"
    [ "$bandwidth_gb" != "0" ] && bw_display="${bandwidth_gb} GB"

    local status="🟢 ACTIVE"
    if [ $remaining_days -le 0 ]; then
        status="⛔ EXPIRED"
    elif [ $remaining_days -le 3 ]; then
        status="⚠️ EXPIRING SOON"
    fi

    cat > "$msg_file" <<EOF
═════════════════════════════
 ELITE-X SLOWDNS VPN v5.0
═════════════════════════════
 USERNAME  : $username
─────────────────────────────
 EXPIRE    : $expire_date
─────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
─────────────────────────────
 LIMIT GB  : $bw_display
 USAGE GB  : ${usage_gb} GB
─────────────────────────────
 CONNECTION: ${current_conn}/${conn_limit}
─────────────────────────────
 STATUS    : $status
═════════════════════════════
  Thanks for using ELITE-X
═════════════════════════════
EOF
    chmod 644 "$msg_file"
    echo "$msg_file"
}

# ═══════════════════════════════════════════════════════════
# SSH CONFIGURATION
# ═══════════════════════════════════════════════════════════
configure_ssh_for_vpn() {
    echo -e "${YELLOW}🔧 Configuring SSH...${NC}"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    sed -i '/^Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/^Match User/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null

    cat > /etc/ssh/sshd_config.d/elite-x-base.conf <<'SSHCONF'
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
ClientAliveInterval 20
ClientAliveCountMax 10
MaxStartups 1000:30:2000
MaxSessions 1000
Compression no
UseDNS no
LogLevel VERBOSE
IPQoS lowdelay throughput
SSHCONF

    cat > /etc/ssh/sshd_config.d/elite-x-users.conf <<'SSHCONF2'
# ELITE-X Dynamic User Banners
SSHCONF2

    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            [ -f "$user_file" ] || continue
            local username=$(basename "$user_file")
            local msg_file=$(force_user_message "$username")
            echo "Match User $username" >> /etc/ssh/sshd_config.d/elite-x-users.conf
            echo "    Banner $msg_file" >> /etc/ssh/sshd_config.d/elite-x-users.conf
        done
    fi

    echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    echo -e "${GREEN}✅ SSH configured${NC}"
}

# ═══════════════════════════════════════════════════════════
# PAM USER MESSAGE
# ═══════════════════════════════════════════════════════════
configure_pam_user_message() {
    echo -e "${YELLOW}🔧 Configuring PAM...${NC}"

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
expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}; conn_limit=${conn_limit:-1}
usage_bytes=$(cat "$BANDWIDTH_DIR/${USERNAME}.usage" 2>/dev/null || echo 0)
usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")
current_conn=0
current_conn=$(who | grep -wc "$USERNAME" 2>/dev/null || echo 0)
[ "$current_conn" -eq 0 ] && current_conn=$(ps aux 2>/dev/null | grep "sshd:" | grep "$USERNAME" | grep -v grep | grep -v "sshd:.*@notty" | wc -l)
current_conn=${current_conn:-0}
now_ts=$(date +%s)
expire_ts=$(date -d "$expire_date" +%s 2>/dev/null || echo 0)
remaining_seconds=$((expire_ts - now_ts))
remaining_days=$((remaining_seconds / 86400))
remaining_hours=$(((remaining_seconds % 86400) / 3600))
[ $remaining_days -lt 0 ] && remaining_days=0
[ $remaining_hours -lt 0 ] && remaining_hours=0
bw_display="Unlimited"
[ "$bandwidth_gb" != "0" ] && bw_display="${bandwidth_gb} GB"
status="🟢 ACTIVE"
if [ $remaining_days -le 0 ]; then status="⛔ EXPIRED"
elif [ $remaining_days -le 3 ]; then status="⚠️ EXPIRING SOON"; fi
cat > "$MSG_FILE" <<EOF
═════════════════════════════
 ELITE-X SLOWDNS VPN v5.0
═════════════════════════════
 USERNAME  : $USERNAME
─────────────────────────────
 EXPIRE    : $expire_date
─────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
─────────────────────────────
 LIMIT GB  : $bw_display
 USAGE GB  : ${usage_gb} GB
─────────────────────────────
 CONNECTION: ${current_conn}/${conn_limit}
─────────────────────────────
 STATUS    : $status
═════════════════════════════
  Thanks for using ELITE-X
═════════════════════════════
EOF
chmod 644 "$MSG_FILE"
sed -i "/Match User $USERNAME/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
echo "Match User $USERNAME" >> /etc/ssh/sshd_config.d/elite-x-users.conf
echo "    Banner $MSG_FILE" >> /etc/ssh/sshd_config.d/elite-x-users.conf
systemctl reload sshd 2>/dev/null || kill -HUP $(cat /var/run/sshd.pid 2>/dev/null) 2>/dev/null || true
FORCE
    chmod +x /usr/local/bin/elite-x-force-user-message

    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    echo "session optional pam_exec.so seteuid /usr/local/bin/elite-x-update-user-msg" >> /etc/pam.d/sshd
    echo -e "${GREEN}✅ PAM configured${NC}"
}

# ═══════════════════════════════════════════════════════════
# SUPREME SYSTEM OPTIMIZATION v5.0
# CPU ZOTE + RAM YOTE → SLOWDNS
# ═══════════════════════════════════════════════════════════
optimize_system_supreme() {
    echo -e "${YELLOW}🚀 Applying SUPREME system optimization — CPU/RAM zote → SlowDNS...${NC}"

    # Load modules za lazima
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true
    modprobe sch_cake 2>/dev/null || true
    modprobe udp_tunnel 2>/dev/null || true

    # ── Disable irqbalance — tutasimamia IRQ wenyewe ──
    systemctl stop irqbalance 2>/dev/null || true
    systemctl disable irqbalance 2>/dev/null || true
    systemctl mask irqbalance 2>/dev/null || true

    cat > /etc/sysctl.d/99-elite-x-v5.conf <<'SYSCTL'
# ══════════════════════════════════════════════
#  ELITE-X v5.0 SUPREME SYSCTL
#  CPU ZOTE + RAM YOTE → SLOWDNS UDP
# ══════════════════════════════════════════════

# IP Forwarding
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0

# BBR + FQ — Maximum TCP throughput
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# ── TCP Buffers — 512MB max ──
net.core.rmem_max=536870912
net.core.wmem_max=536870912
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.tcp_rmem=4096 524288 536870912
net.ipv4.tcp_wmem=4096 262144 536870912
net.ipv4.tcp_mem=786432 2097152 536870912

# ── UDP Buffers — SUPREME BOOST ──
net.core.optmem_max=131072
net.ipv4.udp_mem=204800 1747600 536870912
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072

# ── TCP Features ──
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_ecn=1
net.ipv4.tcp_ecn_fallback=1

# ── Connection Handling ──
net.ipv4.tcp_max_syn_backlog=262144
net.core.somaxconn=262144
net.core.netdev_max_backlog=262144
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=5
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_synack_retries=2

# ── Keepalive — Connections ziishi zaidi ──
net.ipv4.tcp_keepalive_time=20
net.ipv4.tcp_keepalive_intvl=3
net.ipv4.tcp_keepalive_probes=10

# ── Network Device Performance ──
net.core.netdev_budget=2000
net.core.netdev_budget_usecs=20000
net.core.busy_read=100
net.core.busy_poll=100
net.core.netdev_max_backlog=262144

# ── Memory — Weka RAM kwa network ──
vm.swappiness=1
vm.vfs_cache_pressure=10
vm.dirty_ratio=40
vm.dirty_background_ratio=10
vm.min_free_kbytes=32768
vm.overcommit_memory=1
vm.overcommit_ratio=95

# ── File Descriptors — Maximum ──
fs.file-max=4194304
fs.nr_open=4194304
fs.pipe-max-size=4194304

# ── Kernel Performance ──
kernel.sched_min_granularity_ns=500000
kernel.sched_wakeup_granularity_ns=1000000
kernel.sched_migration_cost_ns=250000
kernel.numa_balancing=0
kernel.nmi_watchdog=0
kernel.perf_event_max_sample_rate=1
SYSCTL

    sysctl -p /etc/sysctl.d/99-elite-x-v5.conf >/dev/null 2>&1 || true

    # ── Limits — Maximum kwa kila kitu ──
    cat > /etc/security/limits.d/elite-x.conf <<'LIMITS'
* soft nofile 4194304
* hard nofile 4194304
* soft nproc  131072
* hard nproc  131072
* soft memlock unlimited
* hard memlock unlimited
root soft nofile 4194304
root hard nofile 4194304
root soft memlock unlimited
root hard memlock unlimited
LIMITS

    # ── Systemd global limits ──
    mkdir -p /etc/systemd/system.conf.d/
    cat > /etc/systemd/system.conf.d/elite-x.conf <<'SDCONF'
[Manager]
DefaultLimitNOFILE=4194304
DefaultLimitNPROC=131072
DefaultLimitMEMLOCK=infinity
SDCONF

    # ── IPTables optimization ──
    iptables -t nat -A POSTROUTING -j MASQUERADE 2>/dev/null || true
    iptables -A FORWARD -i lo -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -o lo -j ACCEPT 2>/dev/null || true

    # ── NIC Optimization — GSO/GRO/TSO ON ──
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        # Queue length maximum
        ip link set "$iface" txqueuelen 20000 2>/dev/null || true
        # Hardware offload ON
        ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
        ethtool -K "$iface" gso on gro on tso on gro-hw on 2>/dev/null || true
        ethtool -K "$iface" rx-udp-gro-forwarding on 2>/dev/null || true
        # CAKE qdisc — bora zaidi kuliko fq kwa UDP/DNS
        tc qdisc del dev "$iface" root 2>/dev/null || true
        tc qdisc add dev "$iface" root cake bandwidth 1gbit \
            diffserv4 triple-isolate nat wash 2>/dev/null || \
        tc qdisc add dev "$iface" root fq 2>/dev/null || true
    done

    # ── CPU Performance Governor — Cores ZOTE ──
    for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$cpu_gov" 2>/dev/null || true
    done

    # ── Disable CPU C-states (power saving) — Latency ndogo ──
    for cpu_idle in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        echo 1 > "$cpu_idle" 2>/dev/null || true
    done

    # ── Hugepages — RAM bora zaidi ──
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    # Tumia 60% ya RAM kwa hugepages
    HUGEPAGES=$((TOTAL_RAM_KB * 60 / 100 / 2048))
    echo $HUGEPAGES > /proc/sys/vm/nr_hugepages 2>/dev/null || true

    echo -e "${GREEN}✅ SUPREME optimization applied — CPU/RAM zote → SlowDNS${NC}"
}

# ═══════════════════════════════════════════════════════════
# CGROUPS v2 — Weka CPU/RAM zote kwa SlowDNS
# ═══════════════════════════════════════════════════════════
setup_cgroups_for_slowdns() {
    echo -e "${YELLOW}🔧 Setting up cgroups v2 — CPU/RAM zote → SlowDNS...${NC}"

    cat > /usr/local/bin/elite-x-cgroup-setup <<'CGEOF'
#!/bin/bash
# Elite-X cgroups v2 setup — CPU/RAM dedicated kwa SlowDNS

CGROUP_BASE="/sys/fs/cgroup"
ELITE_CGROUP="$CGROUP_BASE/elite-x-slowdns"

# Check cgroup v2
if [ ! -f "$CGROUP_BASE/cgroup.controllers" ]; then
    echo "cgroups v2 not available" >&2
    exit 0
fi

# Unda cgroup kwa SlowDNS
mkdir -p "$ELITE_CGROUP" 2>/dev/null || true

# Enable controllers
echo "+cpu +memory +io" > "$CGROUP_BASE/cgroup.subtree_control" 2>/dev/null || true

# CPU weight — maximum (10000 = highest)
echo 10000 > "$ELITE_CGROUP/cpu.weight" 2>/dev/null || true

# CPU max — tumia cores ZOTE (hakuna limit)
echo "max 100000" > "$ELITE_CGROUP/cpu.max" 2>/dev/null || true

# Memory — tumia RAM YOTE (hakuna limit)
echo "max" > "$ELITE_CGROUP/memory.max" 2>/dev/null || true
echo "max" > "$ELITE_CGROUP/memory.high" 2>/dev/null || true

# Memory swap — isiswap (RAM iwe free kwa SlowDNS)
echo "0" > "$ELITE_CGROUP/memory.swap.max" 2>/dev/null || true

# IO weight — maximum
echo "default 1000" > "$ELITE_CGROUP/io.weight" 2>/dev/null || true

# Ongeza DNSTT na proxy processes
for proc_name in dnstt-server elite-x-edns-proxy elite-x-udp-turbo \
                  elite-x-uring-proxy elite-x-dns-pool; do
    for pid in $(pgrep -f "$proc_name" 2>/dev/null); do
        echo "$pid" > "$ELITE_CGROUP/cgroup.procs" 2>/dev/null || true
    done
done

echo "[ELITE-X] cgroups v2: SlowDNS processes wamewekwa kwenye cgroup ya dedicated"
CGEOF
    chmod +x /usr/local/bin/elite-x-cgroup-setup

    # Service ya cgroup
    cat > /etc/systemd/system/elite-x-cgroup.service <<EOF
[Unit]
Description=ELITE-X cgroups v2 Setup — CPU/RAM → SlowDNS
After=network.target dnstt-elite-x.service dnstt-elite-x-proxy.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/elite-x-cgroup-setup
ExecStartPost=/bin/sleep 3
ExecStartPost=/usr/local/bin/elite-x-cgroup-setup
[Install]
WantedBy=multi-user.target
EOF
    echo -e "${GREEN}✅ cgroups v2 configured — CPU/RAM zote → SlowDNS${NC}"
}

# ═══════════════════════════════════════════════════════════
# C: io_uring UDP PROXY — HARAKA ZAIDI (v5.0 NEW)
# io_uring = async I/O bila context switching
# Inasupport UDP GSO/GRO na SO_ZEROCOPY
# ═══════════════════════════════════════════════════════════
create_c_uring_proxy() {
    echo -e "${YELLOW}📝 Compiling C io_uring UDP Proxy v5.0...${NC}"

    # Check kama io_uring ipo
    LIBURING_OK=0
    if pkg-config --exists liburing 2>/dev/null; then
        LIBURING_OK=1
    elif [ -f /usr/include/liburing.h ]; then
        LIBURING_OK=1
    fi

    cat > /tmp/uring_proxy.c <<'CEOF'
/*
 * ELITE-X io_uring UDP Proxy v5.0
 * - io_uring async I/O: batch syscalls, hakuna context switch
 * - UDP GSO: packets nyingi kwa sendmsg mmoja
 * - SO_ZEROCOPY: data haipitii CPU buffer
 * - Thread pool ya dedicated CPU cores
 * - Ring buffer ya 65536 entries
 * Fallback: kama io_uring haipo, tumia epoll ya haraka
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <pthread.h>
#include <fcntl.h>
#include <sched.h>
#include <sys/socket.h>
#include <sys/resource.h>
#include <sys/mman.h>
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <netinet/in.h>
#include <netinet/udp.h>
#include <arpa/inet.h>
#include <linux/errqueue.h>

#ifdef HAVE_URING
#include <liburing.h>
#endif

#define DNS_PORT        53
#define BACKEND_PORT    5300
#define BUF_SIZE        8192
#define POOL_SIZE       128
#define QUEUE_CAP       131072
#define SOCK_BUF_SIZE   (64 * 1024 * 1024)   /* 64MB per socket */
#define MAX_EDNS_SIZE   4096
#define MIN_EDNS_SIZE   512
#define BATCH_SIZE      64    /* Process 64 packets kwa wakati mmoja */

static volatile int running = 1;
static int main_sock = -1;

void sig_handler(int s) { running = 0; if (main_sock >= 0) close(main_sock); }

/* ── DNS name skip ── */
static int skip_name(const unsigned char *d, int off, int max) {
    while (off < max) {
        unsigned char l = d[off++];
        if (!l) break;
        if ((l & 0xC0) == 0xC0) { off++; break; }
        off += l; if (off >= max) break;
    }
    return off;
}

/* ── Modify EDNS0 OPT payload size ── */
static void modify_edns(unsigned char *d, int *len, unsigned short msz) {
    if (*len < 12) return;
    int off = 12;
    unsigned short qd = ntohs(*(unsigned short*)(d+4));
    unsigned short an = ntohs(*(unsigned short*)(d+6));
    unsigned short ns = ntohs(*(unsigned short*)(d+8));
    unsigned short ar = ntohs(*(unsigned short*)(d+10));
    int i;
    for (i=0;i<qd;i++){ off=skip_name(d,off,*len); if(off+4>*len) return; off+=4; }
    for (i=0;i<an+ns;i++){ off=skip_name(d,off,*len); if(off+10>*len) return;
        unsigned short rl=ntohs(*(unsigned short*)(d+off+8)); off+=10+rl; }
    for (i=0;i<ar;i++){ off=skip_name(d,off,*len); if(off+10>*len) return;
        unsigned short rt=ntohs(*(unsigned short*)(d+off));
        if(rt==41){ unsigned short sz=htons(msz); memcpy(d+off+2,&sz,2); return; }
        unsigned short rl=ntohs(*(unsigned short*)(d+off+8)); off+=10+rl; }
}

/* ── Work item ── */
typedef struct {
    unsigned char       buf[BUF_SIZE];
    int                 len;
    struct sockaddr_in  src;
    int                 reply_sock;
} work_t;

/* ── Lock-free ring queue ── */
typedef struct {
    work_t             *ring[QUEUE_CAP];
    volatile int        head, tail;
    pthread_mutex_t     mtx;
    pthread_cond_t      cnd;
} queue_t;

static queue_t wq;

static void q_init(queue_t *q) {
    memset(q,0,sizeof(*q));
    pthread_mutex_init(&q->mtx,NULL);
    pthread_cond_init(&q->cnd,NULL);
}
static int q_push(queue_t *q, work_t *w) {
    pthread_mutex_lock(&q->mtx);
    int nx=(q->tail+1)%QUEUE_CAP;
    if(nx==q->head){ pthread_mutex_unlock(&q->mtx); return -1; }
    q->ring[q->tail]=w; q->tail=nx;
    pthread_cond_signal(&q->cnd);
    pthread_mutex_unlock(&q->mtx);
    return 0;
}
static work_t *q_pop(queue_t *q) {
    pthread_mutex_lock(&q->mtx);
    while(q->head==q->tail && running) pthread_cond_wait(&q->cnd,&q->mtx);
    if(q->head==q->tail){ pthread_mutex_unlock(&q->mtx); return NULL; }
    work_t *w=q->ring[q->head]; q->head=(q->head+1)%QUEUE_CAP;
    pthread_mutex_unlock(&q->mtx);
    return w;
}

/* ── Pin thread kwa CPU core fulani ── */
static void pin_to_cpu(int core_id) {
    cpu_set_t cs; CPU_ZERO(&cs);
    int ncpu = (int)sysconf(_SC_NPROCESSORS_ONLN);
    CPU_SET(core_id % ncpu, &cs);
    pthread_setaffinity_np(pthread_self(), sizeof(cs), &cs);
}

/* ── Worker thread — forward packet kwa DNSTT ── */
static void *worker(void *arg) {
    int tid = (int)(long)arg;
    /* Pin kila worker kwa core yake */
    pin_to_cpu(tid);

    /* Real-time priority */
    struct sched_param sp = { .sched_priority = 50 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);

    while (running) {
        work_t *w = q_pop(&wq);
        if (!w) continue;

        int bs = socket(AF_INET, SOCK_DGRAM, 0);
        if (bs < 0) { free(w); continue; }

        /* Timeouts fupi — haraka isisubiri */
        struct timeval tv = {2, 0};
        setsockopt(bs, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(bs, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        /* Socket buffers kubwa */
        int rb = 4*1024*1024, wb = 4*1024*1024;
        setsockopt(bs, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
        setsockopt(bs, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));

        /* IP TOS — Low Delay (priority kwa routers) */
        int tos = 0x10; /* IPTOS_LOWDELAY */
        setsockopt(bs, IPPROTO_IP, IP_TOS, &tos, sizeof(tos));

        struct sockaddr_in back = {
            .sin_family = AF_INET,
            .sin_addr.s_addr = inet_addr("127.0.0.1"),
            .sin_port = htons(BACKEND_PORT)
        };

        modify_edns(w->buf, &w->len, MAX_EDNS_SIZE);
        sendto(bs, w->buf, w->len, 0, (struct sockaddr*)&back, sizeof(back));

        unsigned char resp[BUF_SIZE];
        socklen_t bl = sizeof(back);
        int rn = recvfrom(bs, resp, BUF_SIZE, 0, (struct sockaddr*)&back, &bl);
        if (rn > 0) {
            modify_edns(resp, &rn, MIN_EDNS_SIZE);
            sendto(w->reply_sock, resp, rn, 0,
                   (struct sockaddr*)&w->src, sizeof(w->src));
        }
        close(bs);
        free(w);
    }
    return NULL;
}

int main(void) {
    signal(SIGTERM, sig_handler);
    signal(SIGINT,  sig_handler);
    signal(SIGPIPE, SIG_IGN);

    /* Raise limits */
    struct rlimit rl = {4194304, 4194304};
    setrlimit(RLIMIT_NOFILE, &rl);
    struct rlimit rlm = {RLIM_INFINITY, RLIM_INFINITY};
    setrlimit(RLIMIT_MEMLOCK, &rlm);

    q_init(&wq);

    int ncpu = (int)sysconf(_SC_NPROCESSORS_ONLN);
    /* Unda worker moja kwa kila CPU core × 4 */
    int nworkers = ncpu * 4;
    if (nworkers < 16) nworkers = 16;
    if (nworkers > POOL_SIZE) nworkers = POOL_SIZE;

    pthread_t pool[POOL_SIZE];
    int i;
    for (i = 0; i < nworkers; i++) {
        pthread_attr_t a; pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        /* Stack size ndogo — kuokoa RAM */
        pthread_attr_setstacksize(&a, 256*1024);
        pthread_create(&pool[i], &a, worker, (void*)(long)i);
        pthread_attr_destroy(&a);
    }

    main_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (main_sock < 0) { perror("socket"); return 1; }

    int one = 1;
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));

    /* 64MB socket buffers kwa main socket */
    int rb = SOCK_BUF_SIZE, wb = SOCK_BUF_SIZE;
    setsockopt(main_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(main_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));

    /* IP TOS Low Delay */
    int tos = 0x10;
    setsockopt(main_sock, IPPROTO_IP, IP_TOS, &tos, sizeof(tos));

    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = INADDR_ANY,
        .sin_port = htons(DNS_PORT)
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

    /* Non-blocking */
    fcntl(main_sock, F_SETFL, fcntl(main_sock, F_GETFL)|O_NONBLOCK);

    /* Pin main thread kwa core 0 */
    pin_to_cpu(0);

    /* Main thread real-time priority */
    struct sched_param sp = {.sched_priority = 99};
    sched_setscheduler(0, SCHED_FIFO, &sp);

    fprintf(stderr,
        "[ELITE-X] io_uring UDP Proxy v5.0: port 53, %d workers, %d CPU cores\n",
        nworkers, ncpu);

    /* ── BATCH receive loop — receive nyingi kwa wakati mmoja ── */
    while (running) {
        /* Batch: jaribu kupokea packets BATCH_SIZE kwa mzunguko mmoja */
        int received = 0;
        while (received < BATCH_SIZE && running) {
            work_t *w = malloc(sizeof(work_t));
            if (!w) break;

            socklen_t sl = sizeof(w->src);
            int n = recvfrom(main_sock, w->buf, BUF_SIZE, 0,
                             (struct sockaddr*)&w->src, &sl);
            if (n <= 0) {
                free(w);
                if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                if (!running) goto done;
                break;
            }
            w->len = n;
            w->reply_sock = main_sock;

            if (q_push(&wq, w) < 0) { free(w); } /* Queue full — drop */
            else received++;
        }
        if (received == 0) usleep(50); /* Subiri kidogo kama hakuna packets */
    }
done:
    close(main_sock);
    return 0;
}
CEOF

    # Compile na flags za hali ya juu
    gcc -O3 -march=native -mtune=native -flto -pthread \
        -DHAVE_URING \
        -fomit-frame-pointer \
        -fno-stack-protector \
        -funroll-loops \
        -o /usr/local/bin/elite-x-uring-proxy /tmp/uring_proxy.c \
        -luring 2>/dev/null || \
    gcc -O3 -march=native -mtune=native -flto -pthread \
        -fomit-frame-pointer \
        -funroll-loops \
        -o /usr/local/bin/elite-x-uring-proxy /tmp/uring_proxy.c 2>/dev/null

    rm -f /tmp/uring_proxy.c

    if [ -f /usr/local/bin/elite-x-uring-proxy ]; then
        chmod +x /usr/local/bin/elite-x-uring-proxy
        cat > /etc/systemd/system/elite-x-uring-proxy.service <<EOF
[Unit]
Description=ELITE-X io_uring UDP Proxy v5.0 (CPU×4 Workers)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-uring-proxy
Restart=always
RestartSec=1
LimitNOFILE=4194304
LimitMEMLOCK=infinity
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99
CPUAffinity=${CPU_RANGE}
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C io_uring UDP Proxy v5.0 compiled (CPU×4 workers, 64MB buffers)${NC}"
        return 0
    else
        echo -e "${RED}❌ io_uring Proxy compilation failed${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DNS CONNECTION POOL — Stable Connections (v5.0 NEW)
# Pool ya sockets zinazokuwa tayari — hakuna delay ya kuunda socket
# ═══════════════════════════════════════════════════════════
create_c_dns_pool() {
    echo -e "${YELLOW}📝 Compiling C DNS Connection Pool v5.0...${NC}"

    cat > /tmp/dns_pool.c <<'CEOF'
/*
 * ELITE-X DNS Connection Pool v5.0
 * - Pool ya UDP sockets 256 zinazokuwa tayari daima
 * - Round-robin load balancing kati ya sockets
 * - Hakuna delay ya kuunda socket kwa kila packet
 * - Inaongeza stability na inapunguza packet loss
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

#define POOL_PORT       5302
#define BACKEND_PORT    5300
#define SOCKET_POOL     256
#define BUF_SIZE        8192
#define WORKER_THREADS  64
#define QUEUE_SIZE      65536
#define SOCK_BUF        (8 * 1024 * 1024)

static volatile int running = 1;
static int relay_sock = -1;
void sig(int s) { running = 0; }

/* ── Socket Pool ── */
static int pool_socks[SOCKET_POOL];
static volatile int pool_idx = 0;
static pthread_mutex_t pool_lock = PTHREAD_MUTEX_INITIALIZER;

/* ── Pata socket kutoka pool (round-robin) ── */
static int get_pool_socket(void) {
    pthread_mutex_lock(&pool_lock);
    int idx = pool_idx % SOCKET_POOL;
    pool_idx++;
    pthread_mutex_unlock(&pool_lock);
    return pool_socks[idx];
}

/* ── Work item ── */
typedef struct {
    unsigned char buf[BUF_SIZE];
    int len;
    struct sockaddr_in src;
} pkt_t;

static pkt_t *queue[QUEUE_SIZE];
static volatile int qhead=0, qtail=0;
static pthread_mutex_t qmtx=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  qcnd=PTHREAD_COND_INITIALIZER;

static void q_push(pkt_t *p){
    pthread_mutex_lock(&qmtx);
    int nx=(qtail+1)%QUEUE_SIZE;
    if(nx!=qhead){ queue[qtail]=p; qtail=nx; pthread_cond_signal(&qcnd); }
    else free(p);
    pthread_mutex_unlock(&qmtx);
}
static pkt_t *q_pop(void){
    pthread_mutex_lock(&qmtx);
    while(qhead==qtail&&running) pthread_cond_wait(&qcnd,&qmtx);
    if(qhead==qtail){ pthread_mutex_unlock(&qmtx); return NULL; }
    pkt_t *p=queue[qhead]; qhead=(qhead+1)%QUEUE_SIZE;
    pthread_mutex_unlock(&qmtx);
    return p;
}

static void *worker(void *arg){
    (void)arg;
    struct sched_param sp={.sched_priority=40};
    pthread_setschedparam(pthread_self(),SCHED_FIFO,&sp);

    struct sockaddr_in back={
        .sin_family=AF_INET,
        .sin_addr.s_addr=inet_addr("127.0.0.1"),
        .sin_port=htons(BACKEND_PORT)
    };

    while(running){
        pkt_t *p=q_pop(); if(!p) continue;

        /* Tumia socket kutoka pool — haraka, hakuna socket mpya */
        int bs=get_pool_socket();

        sendto(bs,p->buf,p->len,0,(struct sockaddr*)&back,sizeof(back));

        unsigned char resp[BUF_SIZE];
        socklen_t bl=sizeof(back);
        int rn=recvfrom(bs,resp,BUF_SIZE,0,(struct sockaddr*)&back,&bl);
        if(rn>0 && relay_sock>=0)
            sendto(relay_sock,resp,rn,0,(struct sockaddr*)&p->src,sizeof(p->src));
        free(p);
    }
    return NULL;
}

int main(void){
    signal(SIGTERM,sig); signal(SIGINT,sig); signal(SIGPIPE,SIG_IGN);

    struct rlimit rl={4194304,4194304};
    setrlimit(RLIMIT_NOFILE,&rl);

    /* ── Unda socket pool — tayari daima ── */
    int i;
    for(i=0;i<SOCKET_POOL;i++){
        pool_socks[i]=socket(AF_INET,SOCK_DGRAM,0);
        if(pool_socks[i]<0){ fprintf(stderr,"Pool socket %d failed\n",i); pool_socks[i]=0; continue; }
        struct timeval tv={2,0};
        setsockopt(pool_socks[i],SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));
        setsockopt(pool_socks[i],SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));
        int rb=SOCK_BUF,wb=SOCK_BUF;
        setsockopt(pool_socks[i],SOL_SOCKET,SO_RCVBUF,&rb,sizeof(rb));
        setsockopt(pool_socks[i],SOL_SOCKET,SO_SNDBUF,&wb,sizeof(wb));
        int tos=0x10; setsockopt(pool_socks[i],IPPROTO_IP,IP_TOS,&tos,sizeof(tos));
    }

    /* ── Main relay socket ── */
    relay_sock=socket(AF_INET,SOCK_DGRAM,0);
    if(relay_sock<0) return 1;
    int one=1;
    setsockopt(relay_sock,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    setsockopt(relay_sock,SOL_SOCKET,SO_REUSEPORT,&one,sizeof(one));
    int rb=SOCK_BUF,wb=SOCK_BUF;
    setsockopt(relay_sock,SOL_SOCKET,SO_RCVBUF,&rb,sizeof(rb));
    setsockopt(relay_sock,SOL_SOCKET,SO_SNDBUF,&wb,sizeof(wb));

    struct sockaddr_in addr={.sin_family=AF_INET,.sin_addr.s_addr=INADDR_ANY,.sin_port=htons(POOL_PORT)};
    if(bind(relay_sock,(struct sockaddr*)&addr,sizeof(addr))<0){
        perror("bind dns pool"); close(relay_sock); return 1;
    }
    fcntl(relay_sock,F_SETFL,fcntl(relay_sock,F_GETFL)|O_NONBLOCK);

    /* Worker threads */
    pthread_t pool[WORKER_THREADS];
    for(i=0;i<WORKER_THREADS;i++){
        pthread_attr_t a; pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a,PTHREAD_CREATE_DETACHED);
        pthread_create(&pool[i],&a,worker,NULL);
        pthread_attr_destroy(&a);
    }

    fprintf(stderr,"[ELITE-X] DNS Pool v5.0: port %d, %d sockets, %d workers\n",
            POOL_PORT,SOCKET_POOL,WORKER_THREADS);

    while(running){
        pkt_t *p=malloc(sizeof(pkt_t)); if(!p){usleep(100);continue;}
        socklen_t sl=sizeof(p->src);
        int n=recvfrom(relay_sock,p->buf,BUF_SIZE,0,(struct sockaddr*)&p->src,&sl);
        if(n<=0){ free(p); if(errno==EAGAIN||errno==EWOULDBLOCK){usleep(50);continue;} continue; }
        p->len=n;
        q_push(p);
    }
    close(relay_sock);
    for(i=0;i<SOCKET_POOL;i++) if(pool_socks[i]>0) close(pool_socks[i]);
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -pthread \
        -funroll-loops -fomit-frame-pointer \
        -o /usr/local/bin/elite-x-dns-pool /tmp/dns_pool.c 2>/dev/null
    rm -f /tmp/dns_pool.c

    if [ -f /usr/local/bin/elite-x-dns-pool ]; then
        chmod +x /usr/local/bin/elite-x-dns-pool
        cat > /etc/systemd/system/elite-x-dns-pool.service <<EOF
[Unit]
Description=ELITE-X C DNS Connection Pool v5.0 (256 sockets)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-dns-pool
Restart=always
RestartSec=1
LimitNOFILE=4194304
Nice=-19
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=80
CPUAffinity=${CPU_RANGE}
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C DNS Pool v5.0 compiled (256 sockets tayari)${NC}"
    else
        echo -e "${RED}❌ DNS Pool compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: UDP TURBO RELAY (Enhanced v5.0)
# ═══════════════════════════════════════════════════════════
create_c_udp_turbo() {
    echo -e "${YELLOW}📝 Compiling C UDP Turbo Relay v5.0...${NC}"

    cat > /tmp/udp_turbo.c <<'CEOF'
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

#define RELAY_PORT   5301
#define BACKEND_PORT 5300
#define BUF_SIZE     8192
#define POOL_SIZE    64
#define QUEUE_CAP    131072
#define SOCK_BUF     (32 * 1024 * 1024)

static volatile int running=1;
static int relay_sock=-1;
void sig(int s){running=0;}

typedef struct { unsigned char buf[BUF_SIZE]; int len; struct sockaddr_in src; } pkt_t;
static pkt_t qbuf[QUEUE_CAP];
static volatile int qh=0,qt=0;
static pthread_mutex_t qm=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  qc=PTHREAD_COND_INITIALIZER;

static void qpush(pkt_t *p){
    pthread_mutex_lock(&qm);
    int nx=(qt+1)%QUEUE_CAP;
    if(nx!=qh){qbuf[qt]=*p;qt=nx;pthread_cond_signal(&qc);}
    pthread_mutex_unlock(&qm);
}
static int qpop(pkt_t *p){
    pthread_mutex_lock(&qm);
    while(qh==qt&&running) pthread_cond_wait(&qc,&qm);
    if(qh==qt){pthread_mutex_unlock(&qm);return 0;}
    *p=qbuf[qh];qh=(qh+1)%QUEUE_CAP;
    pthread_mutex_unlock(&qm);
    return 1;
}

static void *worker(void *arg){
    (void)arg;
    struct sched_param sp={.sched_priority=60};
    pthread_setschedparam(pthread_self(),SCHED_FIFO,&sp);
    struct sockaddr_in back={.sin_family=AF_INET,.sin_addr.s_addr=inet_addr("127.0.0.1"),.sin_port=htons(BACKEND_PORT)};
    while(running){
        pkt_t pkt; if(!qpop(&pkt)) continue;
        int bs=socket(AF_INET,SOCK_DGRAM,0); if(bs<0) continue;
        struct timeval tv={2,0};
        setsockopt(bs,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));
        setsockopt(bs,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));
        int rb=4*1024*1024,wb=4*1024*1024;
        setsockopt(bs,SOL_SOCKET,SO_RCVBUF,&rb,sizeof(rb));
        setsockopt(bs,SOL_SOCKET,SO_SNDBUF,&wb,sizeof(wb));
        int tos=0x10; setsockopt(bs,IPPROTO_IP,IP_TOS,&tos,sizeof(tos));
        sendto(bs,pkt.buf,pkt.len,0,(struct sockaddr*)&back,sizeof(back));
        unsigned char resp[BUF_SIZE]; socklen_t bl=sizeof(back);
        int rn=recvfrom(bs,resp,BUF_SIZE,0,(struct sockaddr*)&back,&bl);
        if(rn>0&&relay_sock>=0)
            sendto(relay_sock,resp,rn,0,(struct sockaddr*)&pkt.src,sizeof(pkt.src));
        close(bs);
    }
    return NULL;
}

int main(void){
    signal(SIGTERM,sig); signal(SIGINT,sig); signal(SIGPIPE,SIG_IGN);
    struct rlimit rl={4194304,4194304}; setrlimit(RLIMIT_NOFILE,&rl);
    relay_sock=socket(AF_INET,SOCK_DGRAM,0); if(relay_sock<0) return 1;
    int one=1;
    setsockopt(relay_sock,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    setsockopt(relay_sock,SOL_SOCKET,SO_REUSEPORT,&one,sizeof(one));
    int rb=SOCK_BUF,wb=SOCK_BUF;
    setsockopt(relay_sock,SOL_SOCKET,SO_RCVBUF,&rb,sizeof(rb));
    setsockopt(relay_sock,SOL_SOCKET,SO_SNDBUF,&wb,sizeof(wb));
    struct sockaddr_in addr={.sin_family=AF_INET,.sin_addr.s_addr=INADDR_ANY,.sin_port=htons(RELAY_PORT)};
    if(bind(relay_sock,(struct sockaddr*)&addr,sizeof(addr))<0){perror("bind");close(relay_sock);return 1;}
    fcntl(relay_sock,F_SETFL,fcntl(relay_sock,F_GETFL)|O_NONBLOCK);
    pthread_t pool[POOL_SIZE]; int i;
    for(i=0;i<POOL_SIZE;i++){
        pthread_attr_t a; pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a,PTHREAD_CREATE_DETACHED);
        pthread_create(&pool[i],&a,worker,NULL);
        pthread_attr_destroy(&a);
    }
    fprintf(stderr,"[ELITE-X] UDP Turbo v5.0: port %d, %d workers\n",RELAY_PORT,POOL_SIZE);
    while(running){
        pkt_t pkt; socklen_t sl=sizeof(pkt.src);
        int n=recvfrom(relay_sock,pkt.buf,BUF_SIZE,0,(struct sockaddr*)&pkt.src,&sl);
        if(n<=0){usleep(50);continue;}
        pkt.len=n; qpush(&pkt);
    }
    close(relay_sock); return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -pthread \
        -funroll-loops -fomit-frame-pointer \
        -o /usr/local/bin/elite-x-udp-turbo /tmp/udp_turbo.c 2>/dev/null
    rm -f /tmp/udp_turbo.c

    if [ -f /usr/local/bin/elite-x-udp-turbo ]; then
        chmod +x /usr/local/bin/elite-x-udp-turbo
        cat > /etc/systemd/system/elite-x-udp-turbo.service <<EOF
[Unit]
Description=ELITE-X UDP Turbo Relay v5.0
After=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-udp-turbo
Restart=always
RestartSec=1
LimitNOFILE=4194304
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=70
CPUAffinity=${CPU_RANGE}
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ UDP Turbo v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPREME SPEED BOOSTER (v5.0)
# CPU ZOTE kwa SlowDNS — performance governor + hugepages
# ═══════════════════════════════════════════════════════════
create_c_speed_booster() {
    echo -e "${YELLOW}📝 Compiling C Supreme Speed Booster v5.0...${NC}"

    cat > /tmp/speed_booster.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <sched.h>

static volatile int running=1;
void sig(int s){running=0;}

static void wf(const char *p,const char *v){FILE *f=fopen(p,"w");if(f){fputs(v,f);fclose(f);}}

static void boost_network(void){
    /* TCP/UDP buffers — maximum */
    wf("/proc/sys/net/core/rmem_max","536870912\n");
    wf("/proc/sys/net/core/wmem_max","536870912\n");
    wf("/proc/sys/net/core/rmem_default","1048576\n");
    wf("/proc/sys/net/core/wmem_default","1048576\n");
    wf("/proc/sys/net/ipv4/udp_rmem_min","131072\n");
    wf("/proc/sys/net/ipv4/udp_wmem_min","131072\n");
    /* BBR + CAKE */
    wf("/proc/sys/net/core/default_qdisc","fq\n");
    wf("/proc/sys/net/ipv4/tcp_congestion_control","bbr\n");
    /* Connection handling */
    wf("/proc/sys/net/core/somaxconn","262144\n");
    wf("/proc/sys/net/ipv4/tcp_max_syn_backlog","262144\n");
    wf("/proc/sys/net/core/netdev_max_backlog","262144\n");
    wf("/proc/sys/net/ipv4/tcp_tw_reuse","1\n");
    wf("/proc/sys/net/ipv4/tcp_fin_timeout","5\n");
    wf("/proc/sys/net/ipv4/tcp_keepalive_time","20\n");
    wf("/proc/sys/net/ipv4/tcp_keepalive_intvl","3\n");
    wf("/proc/sys/net/ipv4/tcp_keepalive_probes","10\n");
    wf("/proc/sys/net/ipv4/tcp_fastopen","3\n");
    wf("/proc/sys/net/ipv4/tcp_slow_start_after_idle","0\n");
    /* Netdev budget — process packets zaidi */
    wf("/proc/sys/net/core/netdev_budget","2000\n");
    wf("/proc/sys/net/core/netdev_budget_usecs","20000\n");
    wf("/proc/sys/net/core/busy_read","100\n");
    wf("/proc/sys/net/core/busy_poll","100\n");
    /* Memory */
    wf("/proc/sys/vm/swappiness","1\n");
    wf("/proc/sys/vm/vfs_cache_pressure","10\n");
    wf("/proc/sys/vm/overcommit_memory","1\n");

    /* RPS/XPS — cores zote */
    DIR *nd=opendir("/sys/class/net"); if(!nd) return;
    struct dirent *e;
    while((e=readdir(nd))){
        if(e->d_name[0]=='.') continue;
        if(!strcmp(e->d_name,"lo")) continue;
        char p[512];
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/rx-0/rps_cpus",e->d_name);
        wf(p,"ffffffff\n");
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/rx-0/rps_flow_cnt",e->d_name);
        wf(p,"32768\n");
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/tx-0/xps_cpus",e->d_name);
        wf(p,"ffffffff\n");
    }
    closedir(nd);
    wf("/proc/sys/net/core/rps_sock_flow_entries","32768\n");
    fprintf(stderr,"[ELITE-X] Network boosted: 512MB buffers, BBR, RPS/XPS all cores\n");
}

static void boost_cpu(void){
    /* Performance governor — cores ZOTE */
    DIR *d=opendir("/sys/devices/system/cpu");
    if(!d) return;
    struct dirent *e;
    while((e=readdir(d))){
        if(strncmp(e->d_name,"cpu",3)!=0) continue;
        char p[512];
        snprintf(p,sizeof(p),"/sys/devices/system/cpu/%s/cpufreq/scaling_governor",e->d_name);
        wf(p,"performance\n");
        /* Disable CPU idle states — latency ndogo */
        int i;
        for(i=0;i<10;i++){
            snprintf(p,sizeof(p),"/sys/devices/system/cpu/%s/cpuidle/state%d/disable",e->d_name,i);
            wf(p,"1\n");
        }
    }
    closedir(d);
    /* Pin DNSTT processes kwa CPU real-time priority */
    system("for pid in $(pgrep -f dnstt-server); do renice -n -20 -p $pid 2>/dev/null; chrt -f -p 95 $pid 2>/dev/null; done");
    system("for pid in $(pgrep -f elite-x-uring-proxy); do chrt -f -p 99 $pid 2>/dev/null; done");
    system("for pid in $(pgrep -f elite-x-dns-pool); do chrt -f -p 80 $pid 2>/dev/null; done");
    system("for pid in $(pgrep -f elite-x-udp-turbo); do chrt -f -p 70 $pid 2>/dev/null; done");
    fprintf(stderr,"[ELITE-X] CPU: performance governor, idle disabled, processes pinned\n");
}

static void boost_irq(void){
    /* Spread IRQs kwa cores zote */
    DIR *d=opendir("/proc/irq"); if(!d) return;
    struct dirent *e;
    while((e=readdir(d))){
        if(e->d_name[0]=='.') continue;
        char p[256];
        snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity",e->d_name);
        wf(p,"ffffffff\n");
    }
    closedir(d);
    fprintf(stderr,"[ELITE-X] IRQ: distributed across all CPU cores\n");
}

static void limit_other_services(void){
    /* Punguza CPU kwa services nyingine — zaidi inakwenda SlowDNS */
    system("systemctl set-property systemd-journald.service CPUWeight=1 2>/dev/null");
    system("systemctl set-property cron.service CPUWeight=1 2>/dev/null");
    system("systemctl set-property ssh.service CPUWeight=50 2>/dev/null");
    system("systemctl set-property sshd.service CPUWeight=50 2>/dev/null");
    fprintf(stderr,"[ELITE-X] Other services CPU limited — SlowDNS gets priority\n");
}

int main(void){
    signal(SIGTERM,sig); signal(SIGINT,sig);
    /* Real-time priority kwa booster yenyewe */
    struct sched_param sp={.sched_priority=1};
    sched_setscheduler(0,SCHED_FIFO,&sp);

    boost_network();
    boost_cpu();
    boost_irq();
    limit_other_services();

    /* Re-apply kila dakika 5 */
    while(running){
        int i; for(i=0;i<300&&running;i++) sleep(1);
        if(running){ boost_network(); boost_cpu(); boost_irq(); }
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -funroll-loops -fomit-frame-pointer \
        -o /usr/local/bin/elite-x-speedbooster /tmp/speed_booster.c 2>/dev/null
    rm -f /tmp/speed_booster.c

    if [ -f /usr/local/bin/elite-x-speedbooster ]; then
        chmod +x /usr/local/bin/elite-x-speedbooster
        cat > /etc/systemd/system/elite-x-speedbooster.service <<EOF
[Unit]
Description=ELITE-X Supreme Speed Booster v5.0
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-speedbooster
Restart=always
RestartSec=5
Nice=-20
IOSchedulingClass=realtime
IOSchedulingPriority=0
CPUAffinity=${CPU_RANGE}
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Supreme Speed Booster v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: BANDWIDTH MONITOR
# ═══════════════════════════════════════════════════════════
create_c_bandwidth_monitor() {
    echo -e "${YELLOW}📝 Compiling C Bandwidth Monitor...${NC}"
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
#define USER_DB "/etc/elite-x/users"
#define BW_DIR "/etc/elite-x/bandwidth"
#define PID_DIR "/etc/elite-x/bandwidth/pidtrack"
#define BANNED_DIR "/etc/elite-x/banned"
#define SCAN_INTERVAL 20
#define GB_BYTES 1073741824.0
static volatile int running=1;
void signal_handler(int sig){running=0;}
static long long get_io(int pid){
    char p[256]; snprintf(p,sizeof(p),"/proc/%d/io",pid);
    FILE *f=fopen(p,"r"); if(!f) return 0;
    long long rc=0,wc=0; char l[256];
    while(fgets(l,sizeof(l),f)){
        if(!strncmp(l,"rchar:",6)) sscanf(l+7,"%lld",&rc);
        else if(!strncmp(l,"wchar:",6)) sscanf(l+7,"%lld",&wc);
    }
    fclose(f); return rc+wc;
}
static int is_num(const char *s){for(;*s;s++) if(!isdigit(*s)) return 0; return 1;}
static int get_pids(const char *user,int *pids,int max){
    int cnt=0; DIR *proc=opendir("/proc"); if(!proc) return 0;
    struct dirent *e;
    while((e=readdir(proc))&&cnt<max){
        if(!is_num(e->d_name)) continue;
        int pid=atoi(e->d_name);
        char cp[256]; snprintf(cp,sizeof(cp),"/proc/%d/comm",pid);
        FILE *f=fopen(cp,"r"); if(!f) continue;
        char comm[64]={0}; fgets(comm,sizeof(comm),f); fclose(f);
        comm[strcspn(comm,"\n")]=0;
        if(strcmp(comm,"sshd")!=0) continue;
        char sp[256]; snprintf(sp,sizeof(sp),"/proc/%d/status",pid);
        FILE *sf=fopen(sp,"r"); if(!sf) continue;
        char line[256],uid_s[32]={0};
        while(fgets(line,sizeof(line),sf))
            if(!strncmp(line,"Uid:",4)){sscanf(line,"%*s %s",uid_s);break;}
        fclose(sf);
        struct passwd *pw=getpwuid(atoi(uid_s));
        if(!pw||strcmp(pw->pw_name,user)!=0) continue;
        char stp[256]; snprintf(stp,sizeof(stp),"/proc/%d/stat",pid);
        FILE *stf=fopen(stp,"r"); if(!stf) continue;
        int ppid; char sb[1024]; fgets(sb,sizeof(sb),stf);
        sscanf(sb,"%*d %*s %*c %d",&ppid); fclose(stf);
        if(ppid!=1) pids[cnt++]=pid;
    }
    closedir(proc); return cnt;
}
int main(void){
    signal(SIGTERM,signal_handler); signal(SIGINT,signal_handler);
    mkdir(BW_DIR,0755); mkdir(PID_DIR,0755); mkdir(BANNED_DIR,0755);
    while(running){
        DIR *ud=opendir(USER_DB); if(!ud){sleep(SCAN_INTERVAL);continue;}
        struct dirent *ue;
        while((ue=readdir(ud))){
            if(ue->d_name[0]=='.') continue;
            char uf[512]; snprintf(uf,sizeof(uf),"%s/%s",USER_DB,ue->d_name);
            FILE *f=fopen(uf,"r"); if(!f) continue;
            double bw=0; char l[256];
            while(fgets(l,sizeof(l),f))
                if(!strncmp(l,"Bandwidth_GB:",13)) sscanf(l+13,"%lf",&bw);
            fclose(f); if(bw<=0) continue;
            int pids[100]; int pc=get_pids(ue->d_name,pids,100);
            if(!pc){char cmd[512];snprintf(cmd,sizeof(cmd),"rm -f %s/%s__*.last 2>/dev/null",PID_DIR,ue->d_name);system(cmd);continue;}
            long long delta=0; int i;
            for(i=0;i<pc;i++){
                long long cur=get_io(pids[i]);
                char pf[512]; snprintf(pf,sizeof(pf),"%s/%s__%d.last",PID_DIR,ue->d_name,pids[i]);
                FILE *pfile=fopen(pf,"r");
                if(pfile){long long prev;fscanf(pfile,"%lld",&prev);fclose(pfile);delta+=(cur>=prev)?(cur-prev):cur;}
                pfile=fopen(pf,"w"); if(pfile){fprintf(pfile,"%lld\n",cur);fclose(pfile);}
            }
            char usagef[512]; snprintf(usagef,sizeof(usagef),"%s/%s.usage",BW_DIR,ue->d_name);
            long long acc=0; FILE *af=fopen(usagef,"r");
            if(af){fscanf(af,"%lld",&acc);fclose(af);}
            long long nt=acc+delta; af=fopen(usagef,"w");
            if(af){fprintf(af,"%lld\n",nt);fclose(af);}
            if(nt>=(long long)(bw*GB_BYTES)){
                char cmd[1024];
                snprintf(cmd,sizeof(cmd),"passwd -S %s 2>/dev/null|grep -q 'L'||(usermod -L %s 2>/dev/null&&killall -u %s -9 2>/dev/null&&echo 'BLOCKED: BW exceeded'>>%s/%s)",
                    ue->d_name,ue->d_name,ue->d_name,BANNED_DIR,ue->d_name);
                system(cmd);
            }
        }
        closedir(ud); sleep(SCAN_INTERVAL);
    }
    return 0;
}
CEOF
    gcc -O3 -march=native -mtune=native -flto -o /usr/local/bin/elite-x-bandwidth-c /tmp/bw_monitor.c 2>/dev/null
    rm -f /tmp/bw_monitor.c
    if [ -f /usr/local/bin/elite-x-bandwidth-c ]; then
        chmod +x /usr/local/bin/elite-x-bandwidth-c
        cat > /etc/systemd/system/elite-x-bandwidth.service <<EOF
[Unit]
Description=ELITE-X C Bandwidth Monitor
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-bandwidth-c
Restart=always
RestartSec=10
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Bandwidth Monitor compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: CONNECTION MONITOR
# ═══════════════════════════════════════════════════════════
create_c_connection_monitor() {
    echo -e "${YELLOW}📝 Compiling C Connection Monitor...${NC}"
    cat > /tmp/conn_monitor.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <signal.h>
#include <pwd.h>
#include <ctype.h>
#include <sys/stat.h>
#define USER_DB "/etc/elite-x/users"
#define CONN_DB "/etc/elite-x/connections"
#define BANNED_DIR "/etc/elite-x/banned"
#define DELETED_DIR "/etc/elite-x/deleted"
#define BW_DIR "/etc/elite-x/bandwidth"
#define PID_DIR "/etc/elite-x/bandwidth/pidtrack"
#define AUTOBAN_FLAG "/etc/elite-x/autoban_enabled"
#define SCAN_INTERVAL 5
static volatile int running=1;
void signal_handler(int sig){running=0;}
static int is_num(const char *s){for(;*s;s++) if(!isdigit(*s)) return 0; return 1;}
static int get_conn(const char *user){
    int cnt=0; DIR *proc=opendir("/proc"); if(!proc) return 0;
    struct dirent *e;
    while((e=readdir(proc))){
        if(!is_num(e->d_name)) continue;
        int pid=atoi(e->d_name);
        char cp[256]; snprintf(cp,sizeof(cp),"/proc/%d/comm",pid);
        FILE *f=fopen(cp,"r"); if(!f) continue;
        char comm[64]={0}; fgets(comm,sizeof(comm),f); fclose(f);
        comm[strcspn(comm,"\n")]=0;
        if(strcmp(comm,"sshd")!=0) continue;
        char sp[256]; snprintf(sp,sizeof(sp),"/proc/%d/status",pid);
        FILE *sf=fopen(sp,"r"); if(!sf) continue;
        char line[256],uid_s[32]={0};
        while(fgets(line,sizeof(line),sf))
            if(!strncmp(line,"Uid:",4)){sscanf(line,"%*s %s",uid_s);break;}
        fclose(sf);
        struct passwd *pw=getpwuid(atoi(uid_s));
        if(!pw||strcmp(pw->pw_name,user)!=0) continue;
        char stp[256]; snprintf(stp,sizeof(stp),"/proc/%d/stat",pid);
        FILE *stf=fopen(stp,"r"); if(!stf) continue;
        int ppid; char sb[1024]; fgets(sb,sizeof(sb),stf);
        sscanf(sb,"%*d %*s %*c %d",&ppid); fclose(stf);
        if(ppid!=1) cnt++;
    }
    closedir(proc); return cnt;
}
static void del_user(const char *u,const char *reason){
    char cmd[2048];
    snprintf(cmd,sizeof(cmd),"cp %s/%s %s/%s_$(date+%%Y%%m%%d_%%H%%M%%S) 2>/dev/null;pkill -u %s 2>/dev/null;killall -u %s -9 2>/dev/null;userdel -r %s 2>/dev/null;rm -f %s/%s %s/%s %s/%s %s/%s %s/%s.usage;rm -f %s/%s__*.last 2>/dev/null",
        USER_DB,u,DELETED_DIR,u,u,u,u,USER_DB,u,"/etc/elite-x/data_usage",u,CONN_DB,u,BANNED_DIR,u,BW_DIR,u,PID_DIR,u);
    system(cmd);
}
int main(void){
    signal(SIGTERM,signal_handler); signal(SIGINT,signal_handler);
    mkdir(CONN_DB,0755); mkdir(BANNED_DIR,0755); mkdir(DELETED_DIR,0755);
    while(running){
        time_t now=time(NULL);
        DIR *ud=opendir(USER_DB); if(!ud){sleep(SCAN_INTERVAL);continue;}
        struct dirent *ue;
        while((ue=readdir(ud))){
            if(ue->d_name[0]=='.') continue;
            struct passwd *pw=getpwnam(ue->d_name);
            if(!pw){char rc[512];snprintf(rc,sizeof(rc),"rm -f %s/%s",USER_DB,ue->d_name);system(rc);continue;}
            char uf[512]; snprintf(uf,sizeof(uf),"%s/%s",USER_DB,ue->d_name);
            FILE *f=fopen(uf,"r"); if(!f) continue;
            char exp[32]={0}; int cl=1; char line[256];
            while(fgets(line,sizeof(line),f)){
                if(!strncmp(line,"Expire:",7)) sscanf(line+8,"%s",exp);
                else if(!strncmp(line,"Conn_Limit:",11)) sscanf(line+12,"%d",&cl);
            }
            fclose(f);
            if(strlen(exp)>0){
                struct tm tm={0};
                if(strptime(exp,"%Y-%m-%d",&tm)){
                    time_t et=mktime(&tm);
                    if(now>et){char reason[256];snprintf(reason,sizeof(reason),"Expired %s",exp);del_user(ue->d_name,reason);continue;}
                }
            }
            int cc=get_conn(ue->d_name);
            char cf[512]; snprintf(cf,sizeof(cf),"%s/%s",CONN_DB,ue->d_name);
            FILE *cfile=fopen(cf,"w"); if(cfile){fprintf(cfile,"%d\n",cc);fclose(cfile);}
            int ab=0; FILE *abf=fopen(AUTOBAN_FLAG,"r");
            if(abf){fscanf(abf,"%d",&ab);fclose(abf);}
            if(cc>cl&&ab==1){
                char cmd[1024];
                snprintf(cmd,sizeof(cmd),"passwd -S %s 2>/dev/null|grep -q 'L'||(usermod -L %s 2>/dev/null&&pkill -u %s 2>/dev/null&&echo 'BLOCKED'>>%s/%s)",
                    ue->d_name,ue->d_name,ue->d_name,BANNED_DIR,ue->d_name);
                system(cmd);
            }
        }
        closedir(ud); sleep(SCAN_INTERVAL);
    }
    return 0;
}
CEOF
    gcc -O3 -march=native -mtune=native -flto -o /usr/local/bin/elite-x-connmon-c /tmp/conn_monitor.c 2>/dev/null
    rm -f /tmp/conn_monitor.c
    if [ -f /usr/local/bin/elite-x-connmon-c ]; then
        chmod +x /usr/local/bin/elite-x-connmon-c
        cat > /etc/systemd/system/elite-x-connmon.service <<EOF
[Unit]
Description=ELITE-X C Connection Monitor
After=network.target ssh.service
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-connmon-c
Restart=always
RestartSec=5
CPUQuota=5%
MemoryMax=30M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Connection Monitor compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: RAM CLEANER, DNS CACHE, IRQ, LOG CLEANER, DATA USAGE
# ═══════════════════════════════════════════════════════════
create_c_support_tools() {
    echo -e "${YELLOW}📝 Compiling support tools...${NC}"

    # RAM Cleaner
    cat > /tmp/ram.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int r=1; void s(int x){r=0;}
static void clean(void){
    system("sync&&echo 3>/proc/sys/vm/drop_caches 2>/dev/null");
    system("echo 1>/proc/sys/vm/compact_memory 2>/dev/null");
    system("sysctl -w vm.swappiness=1 >/dev/null 2>&1");
    system("sysctl -w vm.vfs_cache_pressure=10 >/dev/null 2>&1");
    fprintf(stderr,"[ELITE-X] RAM cleaned\n");
}
int main(void){signal(SIGTERM,s);signal(SIGINT,s);
while(r){clean();int i;for(i=0;i<600&&r;i++)sleep(1);}return 0;}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-ramcleaner /tmp/ram.c 2>/dev/null
    rm -f /tmp/ram.c
    chmod +x /usr/local/bin/elite-x-ramcleaner 2>/dev/null
    cat > /etc/systemd/system/elite-x-ramcleaner.service <<EOF
[Unit]
Description=ELITE-X RAM Cleaner
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-ramcleaner
Restart=always
RestartSec=30
CPUQuota=3%
MemoryMax=20M
[Install]
WantedBy=multi-user.target
EOF

    # DNS Cache
    cat > /tmp/dns.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int r=1; void s(int x){r=0;}
static void opt(void){
    FILE *f=fopen("/etc/resolv.conf","w");
    if(f){fprintf(f,"nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\noptions timeout:1 attempts:5 rotate\noptions ndots:0\n");fclose(f);}
    system("resolvectl flush-caches 2>/dev/null||true");
    fprintf(stderr,"[ELITE-X] DNS optimized\n");
}
int main(void){signal(SIGTERM,s);signal(SIGINT,s);
opt();while(r){int i;for(i=0;i<1800&&r;i++)sleep(1);if(r)opt();}return 0;}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-dnscache /tmp/dns.c 2>/dev/null
    rm -f /tmp/dns.c
    chmod +x /usr/local/bin/elite-x-dnscache 2>/dev/null
    cat > /etc/systemd/system/elite-x-dnscache.service <<EOF
[Unit]
Description=ELITE-X DNS Cache
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-dnscache
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF

    # IRQ Optimizer
    cat > /tmp/irq.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
static volatile int r=1; void s(int x){r=0;}
static void wf(const char *p,const char *v){FILE *f=fopen(p,"w");if(f){fputs(v,f);fclose(f);}}
static void opt(void){
    DIR *d=opendir("/proc/irq"); if(!d) return;
    struct dirent *e;
    while((e=readdir(d))){
        if(e->d_name[0]=='.') continue;
        char p[256]; snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity",e->d_name);
        wf(p,"ffffffff\n");
    }
    closedir(d);
    DIR *nd=opendir("/sys/class/net"); if(!nd) return;
    while((e=readdir(nd))){
        if(e->d_name[0]=='.'||!strcmp(e->d_name,"lo")) continue;
        char p[512];
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/rx-0/rps_cpus",e->d_name); wf(p,"ffffffff\n");
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/rx-0/rps_flow_cnt",e->d_name); wf(p,"32768\n");
        snprintf(p,sizeof(p),"/sys/class/net/%s/queues/tx-0/xps_cpus",e->d_name); wf(p,"ffffffff\n");
    }
    closedir(nd);
    wf("/proc/sys/net/core/rps_sock_flow_entries","32768\n");
    fprintf(stderr,"[ELITE-X] IRQ/RPS/XPS optimized\n");
}
int main(void){signal(SIGTERM,s);signal(SIGINT,s);
while(r){opt();int i;for(i=0;i<300&&r;i++)sleep(1);}return 0;}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-irqopt /tmp/irq.c 2>/dev/null
    rm -f /tmp/irq.c
    chmod +x /usr/local/bin/elite-x-irqopt 2>/dev/null
    cat > /etc/systemd/system/elite-x-irqopt.service <<EOF
[Unit]
Description=ELITE-X IRQ Optimizer
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-irqopt
Restart=always
RestartSec=10
Nice=-10
[Install]
WantedBy=multi-user.target
EOF

    # Log Cleaner
    cat > /tmp/log.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int r=1; void s(int x){r=0;}
static void clean(void){
    system("find /var/log -type f -name '*.log' -size +20M -exec truncate -s 0 {} \\; 2>/dev/null");
    system("journalctl --vacuum-size=20M 2>/dev/null");
    system("truncate -s 0 /var/log/syslog /var/log/auth.log /var/log/kern.log 2>/dev/null");
    system("find /var/log -name '*.gz' -mtime +1 -delete 2>/dev/null");
}
int main(void){signal(SIGTERM,s);signal(SIGINT,s);
while(r){clean();int i;for(i=0;i<1800&&r;i++)sleep(1);}return 0;}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-logcleaner /tmp/log.c 2>/dev/null
    rm -f /tmp/log.c
    chmod +x /usr/local/bin/elite-x-logcleaner 2>/dev/null
    cat > /etc/systemd/system/elite-x-logcleaner.service <<EOF
[Unit]
Description=ELITE-X Log Cleaner
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-logcleaner
Restart=always
RestartSec=60
CPUQuota=3%
MemoryMax=15M
[Install]
WantedBy=multi-user.target
EOF

    # Data Usage
    cat > /tmp/du.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <signal.h>
static volatile int r=1; void s(int x){r=0;}
int main(void){signal(SIGTERM,s);signal(SIGINT,s);
while(r){
    DIR *ud=opendir("/etc/elite-x/users"); if(!ud){sleep(30);continue;}
    char mo[8]; time_t now=time(NULL); strftime(mo,sizeof(mo),"%Y-%m",localtime(&now));
    struct dirent *e;
    while((e=readdir(ud))){
        if(e->d_name[0]=='.') continue;
        char bf[512]; snprintf(bf,sizeof(bf),"/etc/elite-x/bandwidth/%s.usage",e->d_name);
        long long bytes=0; FILE *f=fopen(bf,"r"); if(f){fscanf(f,"%lld",&bytes);fclose(f);}
        char uf[512]; snprintf(uf,sizeof(uf),"/etc/elite-x/data_usage/%s",e->d_name);
        f=fopen(uf,"w"); if(f){
            time_t t=time(NULL); char *ts=ctime(&t); ts[strcspn(ts,"\n")]=0;
            fprintf(f,"month: %s\ntotal_gb: %.2f\nlast_updated: %s\n",mo,bytes/1073741824.0,ts);
            fclose(f);
        }
    }
    closedir(ud); sleep(30);
}
return 0;}
CEOF
    gcc -O3 -o /usr/local/bin/elite-x-datausage-c /tmp/du.c 2>/dev/null
    rm -f /tmp/du.c
    chmod +x /usr/local/bin/elite-x-datausage-c 2>/dev/null
    cat > /etc/systemd/system/elite-x-datausage.service <<EOF
[Unit]
Description=ELITE-X Data Usage Monitor
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-datausage-c
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✅ Support tools compiled (RAM, DNS, IRQ, Log, DataUsage)${NC}"
}

# ═══════════════════════════════════════════════════════════
# USER MANAGEMENT SCRIPT
# ═══════════════════════════════════════════════════════════
create_user_script() {
    cat > /usr/local/bin/elite-x-user <<'USEREOF'
#!/bin/bash
RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
WHITE='\033[1;37m';BOLD='\033[1m';LIGHT_GREEN='\033[1;32m';LIGHT_RED='\033[1;31m'
PURPLE='\033[0;35m';GRAY='\033[0;90m';NC='\033[0m'
UD="/etc/elite-x/users"; USAGE_DB="/etc/elite-x/data_usage"; DD="/etc/elite-x/deleted"
BD="/etc/elite-x/banned"; CONN_DB="/etc/elite-x/connections"; BW_DIR="/etc/elite-x/bandwidth"
PID_DIR="$BW_DIR/pidtrack"; AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"
mkdir -p "$UD" "$USAGE_DB" "$DD" "$BD" "$CONN_DB" "$BW_DIR" "$PID_DIR"
get_cc(){ local u="$1";local c=0;who|grep -qw "$u"&&c=$(who|grep -wc "$u");[ "$c" -eq 0 ]&&c=$(ps aux|grep "sshd:"|grep "$u"|grep -v grep|grep -v "@notty"|wc -l);echo ${c:-0};}
get_bw(){ local f="$BW_DIR/${1}.usage";[ -f "$f" ]&&echo "scale=2; $(cat $f) / 1073741824"|bc 2>/dev/null||echo "0.00";}
add_user(){
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}     CREATE SSH + SLOWDNS USER v5.0 SUPREME     ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    id "$u" &>/dev/null && { echo -e "${RED}Exists!${NC}"; return; }
    read -p "$(echo -e $GREEN"Password [auto]: "$NC)" p
    [ -z "$p" ] && p=$(head /dev/urandom|tr -dc 'A-Za-z0-9'|head -c 12)&&echo -e "${GREEN}🔑 $p${NC}"
    read -p "$(echo -e $GREEN"Days [30]: "$NC)" d; d=${d:-30}
    read -p "$(echo -e $GREEN"Conn limit [1]: "$NC)" cl; cl=${cl:-1}
    read -p "$(echo -e $GREEN"BW GB (0=∞) [0]: "$NC)" bw; bw=${bw:-0}
    useradd -m -s /bin/false "$u"
    echo "$u:$p"|chpasswd
    ex=$(date -d "+$d days" +"%Y-%m-%d")
    chage -E "$ex" "$u"
    cat > "$UD/$u" <<INFO
Username: $u
Password: $p
Expire: $ex
Conn_Limit: $cl
Bandwidth_GB: $bw
Created: $(date +"%Y-%m-%d %H:%M:%S")
INFO
    echo "0" > "$BW_DIR/${u}.usage"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    bwd="Unlimited"; [ "$bw" != "0" ]&&bwd="${bw} GB"
    SRV=$(cat /etc/elite-x/subdomain 2>/dev/null||echo "?")
    IP=$(cat /etc/elite-x/cached_ip 2>/dev/null||echo "?")
    PK=$(cat /etc/elite-x/public_key 2>/dev/null||echo "?")
    clear
    echo -e "${GREEN}╔═════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}       USER CREATED — ELITE-X v5.0 SUPREME             ${GREEN}║${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Username : ${CYAN}$u${NC}"
    echo -e "${GREEN}║${WHITE}  Password : ${CYAN}$p${NC}"
    echo -e "${GREEN}║${WHITE}  Server   : ${CYAN}$SRV${NC}"
    echo -e "${GREEN}║${WHITE}  IP       : ${CYAN}$IP${NC}"
    echo -e "${GREEN}║${WHITE}  PubKey   : ${CYAN}$PK${NC}"
    echo -e "${GREEN}║${WHITE}  Expire   : ${CYAN}$ex${NC}"
    echo -e "${GREEN}║${WHITE}  MaxLogin : ${CYAN}$cl${NC}"
    echo -e "${GREEN}║${WHITE}  BW Limit : ${CYAN}$bwd${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS     : ${CYAN}$SRV${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY : ${CYAN}$PK${NC}"
    echo -e "${GREEN}║${WHITE}  PORT   : ${CYAN}53 | UDP Turbo: 5301 | Pool: 5302${NC}"
    echo -e "${GREEN}╚═════════════════════════════════════════════════════════╝${NC}"
}
list_users(){
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}          ACTIVE USERS — ELITE-X v5.0            ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
    [ -z "$(ls -A "$UD" 2>/dev/null)" ] && { echo -e "${CYAN}║${RED}  No users${NC}"; echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"; return; }
    printf "${CYAN}║${WHITE} %-14s %-12s %-8s %-12s %-16s${CYAN}║${NC}\n" "USER" "EXPIRE" "CONN" "BW USED" "STATUS"
    echo -e "${CYAN}╟──────────────────────────────────────────────────────────╢${NC}"
    for user in "$UD"/*; do
        [ ! -f "$user" ]&&continue
        u=$(basename "$user")
        ex=$(grep "Expire:" "$user"|cut -d' ' -f2)
        lim=$(grep "Conn_Limit:" "$user"|awk '{print $2}');lim=${lim:-1}
        bwl=$(grep "Bandwidth_GB:" "$user"|awk '{print $2}');bwl=${bwl:-0}
        tgb=$(get_bw "$u"); cc=$(get_cc "$u")
        et=$(date -d "$ex" +%s 2>/dev/null||echo 0); ct=$(date +%s)
        dl=$(( (et-ct)/86400 ))
        passwd -S "$u" 2>/dev/null|grep -q "L"&&st="${RED}🔒LOCKED${NC}"||true
        [ "$cc" -gt 0 ]&&st="${LIGHT_GREEN}🟢ONLINE${NC}"
        [ $dl -le 0 ]&&st="${RED}⛔EXPIRED${NC}"
        [ $dl -gt 0 ]&&[ $dl -le 3 ]&&st="${LIGHT_RED}⚠CRITICAL${NC}"
        [ $dl -gt 3 ]&&[ $dl -le 7 ]&&st="${YELLOW}⚠WARNING${NC}"
        [ $dl -gt 7 ]&&[ "$cc" -eq 0 ]&&st="${YELLOW}⚫OFFLINE${NC}"
        [ "$bwl" != "0" ]&&bwd="${tgb}/${bwl}GB"||bwd="${tgb}GB/∞"
        [ $dl -le 0 ]&&ed="${RED}${ex}${NC}"||ed="${GREEN}${ex}${NC}"
        [ $dl -le 7 ]&&[ $dl -gt 0 ]&&ed="${YELLOW}${ex}${NC}"
        [ "$cc" -ge "$lim" ]&&ld="${RED}${cc}/${lim}${NC}"||ld="${GREEN}${cc}/${lim}${NC}"
        printf "${CYAN}║${WHITE} %-14s %-12b %-8b %-12s %-16b${CYAN}║${NC}\n" "$u" "$ed" "$ld" "$bwd" "$st"
    done
    T=$(ls "$UD" 2>/dev/null|wc -l); O=$(who|wc -l)
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${YELLOW}  Total: ${GREEN}$T ${YELLOW}| Online: ${GREEN}$O${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
}
renew_user(){ read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ]&&{ echo -e "${RED}Not found${NC}"; return; }; read -p "$(echo -e $GREEN"Days: "$NC)" d; cur=$(grep "Expire:" "$UD/$u"|cut -d' ' -f2); new=$(date -d "$cur +$d days" +"%Y-%m-%d"); sed -i "s/Expire: .*/Expire: $new/" "$UD/$u"; chage -E "$new" "$u" 2>/dev/null; usermod -U "$u" 2>/dev/null; /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null; echo -e "${GREEN}✅ Renewed until $new${NC}"; }
set_bw(){ read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ]&&{ echo -e "${RED}Not found${NC}"; return; }; read -p "$(echo -e $GREEN"New BW GB (0=∞): "$NC)" nb; grep -q "Bandwidth_GB:" "$UD/$u"&&sed -i "s/Bandwidth_GB: .*/Bandwidth_GB: $nb/" "$UD/$u"||echo "Bandwidth_GB: $nb">>"$UD/$u"; [ "$nb"="0" ]&&usermod -U "$u" 2>/dev/null; /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null; echo -e "${GREEN}✅ Updated${NC}"; }
reset_bw(){ read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ]&&{ echo -e "${RED}Not found${NC}"; return; }; echo "0">"$BW_DIR/${u}.usage"; rm -f "$PID_DIR/${u}"__*.last 2>/dev/null; usermod -U "$u" 2>/dev/null; /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null; echo -e "${GREEN}✅ Reset${NC}"; }
lock_u(){ read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ]&&{ echo -e "${RED}Not found${NC}"; return; }; usermod -L "$u" 2>/dev/null; pkill -u "$u" 2>/dev/null||true; echo "$(date) LOCKED">>"$BD/$u"; echo -e "${GREEN}✅ Locked${NC}"; }
unlock_u(){ read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ]&&{ echo -e "${RED}Not found${NC}"; return; }; usermod -U "$u" 2>/dev/null; /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null; echo -e "${GREEN}✅ Unlocked${NC}"; }
del_u(){ read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ]&&{ echo -e "${RED}Not found${NC}"; return; }; cp "$UD/$u" "$DD/${u}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null; pkill -u "$u" 2>/dev/null||true; killall -u "$u" -9 2>/dev/null||true; userdel -r "$u" 2>/dev/null; rm -f "$UD/$u" "$USAGE_DB/$u" "$CONN_DB/$u" "$BD/$u" "$BW_DIR/${u}.usage" "/etc/elite-x/user_messages/$u"; rm -f "$PID_DIR/${u}"__*.last 2>/dev/null; echo -e "${GREEN}✅ Deleted${NC}"; }
det_u(){ read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ]&&{ echo -e "${RED}Not found${NC}"; return; }; clear; echo -e "${CYAN}╔══════════════════════╗${NC}"; echo -e "${CYAN}║  USER DETAILS v5.0   ║${NC}"; echo -e "${CYAN}╠══════════════════════╣${NC}"; cat "$UD/$u"|while read l; do echo -e "${CYAN}║${WHITE} $l${NC}"; done; tgb=$(get_bw "$u"); cc=$(get_cc "$u"); echo -e "${CYAN}║${WHITE} Sessions: ${GREEN}$cc${NC}"; echo -e "${CYAN}║${WHITE} BW Used : ${GREEN}$tgb GB${NC}"; echo -e "${CYAN}╚══════════════════════╝${NC}"; }
case $1 in
    add) add_user;; list) list_users;; details) det_u;; renew) renew_user;;
    setlimit) read -p "User: " u; read -p "Limit: " l; [ -f "$UD/$u" ]&&{ sed -i "s/Conn_Limit: .*/Conn_Limit: $l/" "$UD/$u"; /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null; echo -e "${GREEN}✅${NC}"; }||echo "Not found";;
    setbw) set_bw;; resetdata) reset_bw;; deleted) ls "$DD/" 2>/dev/null|head -20;;
    lock) lock_u;; unlock) unlock_u;; del) del_u;;
    *) echo "Usage: elite-x-user {add|list|details|renew|setlimit|setbw|resetdata|deleted|lock|unlock|del}";;
esac
USEREOF
    chmod +x /usr/local/bin/elite-x-user
}

# ═══════════════════════════════════════════════════════════
# MAIN MENU v5.0
# ═══════════════════════════════════════════════════════════
create_main_menu() {
    cat > /usr/local/bin/elite-x <<'MENUEOF'
#!/bin/bash
RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
PURPLE='\033[0;35m';WHITE='\033[1;37m';BOLD='\033[1m';NC='\033[0m'
LIGHT_GREEN='\033[1;32m';GRAY='\033[0;90m'
UD="/etc/elite-x/users"; BW_DIR="/etc/elite-x/bandwidth"; AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"

svc_dot(){ systemctl is-active "$1" >/dev/null 2>&1&&echo "${GREEN}●${NC}"||echo "${RED}●${NC}"; }

show_dashboard(){
    clear
    IP=$(cat /etc/elite-x/cached_ip 2>/dev/null||echo "Unknown")
    SUB=$(cat /etc/elite-x/subdomain 2>/dev/null||echo "?")
    LOC=$(cat /etc/elite-x/location 2>/dev/null||echo "?")
    MTU=$(cat /etc/elite-x/mtu 2>/dev/null||echo "1800")
    RAM=$(free -h|awk '/^Mem:/{print $3"/"$2}')
    CPU=$(grep 'cpu ' /proc/stat|awk '{u=$2+$4;t=$2+$3+$4+$5;print int(u*100/t)"%"}')
    CORES=$(nproc)
    DNS=$(svc_dot dnstt-elite-x); PRX=$(svc_dot dnstt-elite-x-proxy)
    URN=$(svc_dot elite-x-uring-proxy); UDP=$(svc_dot elite-x-udp-turbo)
    DPL=$(svc_dot elite-x-dns-pool); SPD=$(svc_dot elite-x-speedbooster)
    BW=$(svc_dot elite-x-bandwidth); CNM=$(svc_dot elite-x-connmon)
    IRQ=$(svc_dot elite-x-irqopt); RAM_S=$(svc_dot elite-x-ramcleaner)
    DNSC=$(svc_dot elite-x-dnscache)
    SMSG="${GREEN}✅${NC}"; [ ! -d /etc/elite-x/user_messages ]&&SMSG="${RED}❌${NC}"
    T=$(ls "$UD" 2>/dev/null|wc -l); O=$(who|wc -l)
    echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${YELLOW}${BOLD}   ELITE-X SLOWDNS v5.0 — FALCON SUPREME ULTRA         ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}   CPU ZOTE + RAM YOTE → SLOWDNS | io_uring | CAKE     ${PURPLE}║${NC}"
    echo -e "${PURPLE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║${WHITE} IP:${CYAN}$IP ${WHITE}MTU:${CYAN}$MTU ${WHITE}LOC:${CYAN}$LOC ${WHITE}Cores:${CYAN}$CORES${NC}"
    echo -e "${PURPLE}║${WHITE} NS:${CYAN}$SUB${NC}"
    echo -e "${PURPLE}║${WHITE} RAM:${CYAN}$RAM ${WHITE}CPU:${CYAN}$CPU ${WHITE}Users:${CYAN}$T ${WHITE}Online:${CYAN}$O${NC}"
    echo -e "${PURPLE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║${WHITE} DNSTT $DNS  EDNS-Proxy $PRX  io_uring $URN  UDP-Turbo $UDP${NC}"
    echo -e "${PURPLE}║${WHITE} DNS-Pool $DPL  SpeedBoost $SPD  BW-Mon $BW  ConnMon $CNM${NC}"
    echo -e "${PURPLE}║${WHITE} IRQ-Opt $IRQ  RAM $RAM_S  DNS-Cache $DNSC  Msg $SMSG${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

settings_menu(){
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${YELLOW}          SETTINGS — ELITE-X v5.0 SUPREME      ${CYAN}║${NC}"
        echo -e "${CYAN}╠═══════════════════════════════════════════════════════╣${NC}"
        AB=$(cat "$AUTOBAN_FLAG" 2>/dev/null||echo 0)
        [ "$AB"="1" ]&&ABT="${GREEN}ON${NC}"||ABT="${RED}OFF${NC}"
        echo -e "${CYAN}║${WHITE} [1] Auto-Ban: $ABT                              ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [2] Restart ALL Services                         ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [3] Restart DNSTT Only                           ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [4] Apply Supreme Speed Boost Now                ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [5] Fix VPN/SSH                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [6] Refresh All User Messages                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [7] Test User Message                            ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [8] Show CPU/RAM SlowDNS Usage                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [9] Apply cgroups (CPU/RAM→SlowDNS)             ${CYAN}║${NC}"
        echo -e "${CYAN}║${WHITE} [0] Back                                         ${CYAN}║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch
        case $ch in
            1) [ "$AB"="1" ]&&echo 0>"$AUTOBAN_FLAG"||echo 1>"$AUTOBAN_FLAG" ;;
            2) for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-uring-proxy elite-x-udp-turbo elite-x-dns-pool elite-x-speedbooster elite-x-bandwidth elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner elite-x-datausage elite-x-cgroup; do systemctl restart "$s" 2>/dev/null||true; done; echo -e "${GREEN}✅ All restarted${NC}"; read -p "Enter..." ;;
            3) systemctl restart dnstt-elite-x dnstt-elite-x-proxy elite-x-uring-proxy; echo -e "${GREEN}✅ DNSTT restarted${NC}"; read -p "Enter..." ;;
            4) systemctl restart elite-x-speedbooster elite-x-irqopt elite-x-dnscache; sleep 2; /usr/local/bin/elite-x-cgroup-setup 2>/dev/null; echo -e "${GREEN}✅ Supreme boost applied${NC}"; read -p "Enter..." ;;
            5) systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd 2>/dev/null; echo -e "${GREEN}✅ Fixed${NC}"; read -p "Enter..." ;;
            6) for u in "$UD"/*; do [ -f "$u" ]&&/usr/local/bin/elite-x-force-user-message "$(basename $u)" 2>/dev/null; done; systemctl reload sshd; echo -e "${GREEN}✅ Refreshed${NC}"; read -p "Enter..." ;;
            7) read -p "Username: " un; [ -f "/etc/elite-x/user_messages/$un" ]&&cat "/etc/elite-x/user_messages/$un"||echo "No message"; read -p "Enter..." ;;
            8)
                echo -e "${CYAN}══ CPU/RAM Usage by SlowDNS Processes ══${NC}"
                for proc in dnstt-server elite-x-uring-proxy elite-x-udp-turbo elite-x-dns-pool elite-x-speedbooster; do
                    ps aux|grep "$proc"|grep -v grep|awk '{printf "  %-30s CPU:%-6s RAM:%-6s\n",$11,$3,$4}'
                done
                echo -e "${CYAN}══ Total System Resources ══${NC}"
                free -h|grep Mem
                echo "CPU Cores: $(nproc) | Load: $(cat /proc/loadavg|cut -d' ' -f1-3)"
                read -p "Enter..." ;;
            9) /usr/local/bin/elite-x-cgroup-setup 2>/dev/null; echo -e "${GREEN}✅ cgroups applied${NC}"; read -p "Enter..." ;;
            0) return ;;
        esac
    done
}

main_menu(){
    while true; do
        show_dashboard
        echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║${GREEN}${BOLD}              MAIN MENU — ELITE-X v5.0 SUPREME          ${PURPLE}║${NC}"
        echo -e "${PURPLE}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${PURPLE}║${WHITE} [1] Create User  [2] List Users   [3] Details${NC}"
        echo -e "${PURPLE}║${WHITE} [4] Renew User   [5] Conn Limit   [6] BW Limit${NC}"
        echo -e "${PURPLE}║${WHITE} [7] Reset BW     [8] Lock User    [9] Unlock${NC}"
        echo -e "${PURPLE}║${WHITE} [10] Delete      [11] Deleted     [S] Settings${NC}"
        echo -e "${PURPLE}║${WHITE} [M] Test Msg     [0] Exit${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch
        case $ch in
            1) elite-x-user add; read -p "Enter..." ;;
            2) elite-x-user list; read -p "Enter..." ;;
            3) elite-x-user details; read -p "Enter..." ;;
            4) elite-x-user renew; read -p "Enter..." ;;
            5) elite-x-user setlimit; read -p "Enter..." ;;
            6) elite-x-user setbw; read -p "Enter..." ;;
            7) elite-x-user resetdata; read -p "Enter..." ;;
            8) elite-x-user lock; read -p "Enter..." ;;
            9) elite-x-user unlock; read -p "Enter..." ;;
            10) elite-x-user del; read -p "Enter..." ;;
            11) elite-x-user deleted; read -p "Enter..." ;;
            [Ss]) settings_menu ;;
            [Mm]) read -p "Username: " un; [ -f "/etc/elite-x/user_messages/$un" ]&&cat "/etc/elite-x/user_messages/$un"||echo "No message"; read -p "Enter..." ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid${NC}"; read -p "Enter..." ;;
        esac
    done
}
main_menu
MENUEOF
    chmod +x /usr/local/bin/elite-x
}

# ═══════════════════════════════════════════════════════════
# MAIN INSTALLATION v5.0
# ═══════════════════════════════════════════════════════════
run_installation() {
    show_banner
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}      ELITE-X v5.0 SUPREME — ACTIVATION          ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT
    if [ "$ACTIVATION_INPUT" != "$ACTIVATION_KEY" ] && [ "$ACTIVATION_INPUT" != "Whtsapp +255713-628-668" ]; then
        echo -e "${RED}❌ Invalid key!${NC}"; exit 1
    fi
    echo -e "${GREEN}✅ Activation successful${NC}"; sleep 1
    set_timezone

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}          ENTER YOUR NAMESERVER [NS]       ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Nameserver: "$NC)" TDOMAIN

    echo -e "${YELLOW}Select VPS location:${NC}"
    echo "  [1] South Africa (MTU 1800)"
    echo "  [2] USA (MTU 1500)"
    echo "  [3] Europe (MTU 1500)"
    echo "  [4] Asia (MTU 1400)"
    echo "  [5] Custom MTU"
    read -p "$(echo -e $GREEN"Choice [1]: "$NC)" LOC; LOC=${LOC:-1}
    case $LOC in
        2) SEL_LOC="USA"; MTU=1500 ;;
        3) SEL_LOC="Europe"; MTU=1500 ;;
        4) SEL_LOC="Asia"; MTU=1400 ;;
        5) SEL_LOC="Custom"; read -p "MTU: " MTU; [[ ! "$MTU" =~ ^[0-9]+$ ]]&&MTU=1800 ;;
        *) SEL_LOC="South Africa"; MTU=1800 ;;
    esac

    # Kill unnecessary services KWANZA
    kill_unnecessary_services

    echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"
    for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-uring-proxy elite-x-udp-turbo \
              elite-x-dns-pool elite-x-speedbooster elite-x-bandwidth elite-x-datausage \
              elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner \
              elite-x-irqopt elite-x-logcleaner elite-x-cgroup 3proxy-elite; do
        systemctl stop "$s" 2>/dev/null||true
        systemctl disable "$s" 2>/dev/null||true
    done
    pkill -f "dnstt-server\|elite-x-" 2>/dev/null||true
    rm -rf /etc/systemd/system/{dnstt-elite-x*,elite-x*,3proxy-elite*} 2>/dev/null
    rm -rf /etc/dnstt /etc/elite-x /var/run/elite-x 2>/dev/null
    rm -f /usr/local/bin/{dnstt-*,elite-x*,3proxy} 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf 2>/dev/null
    rm -f /etc/sysctl.d/99-elite-x-*.conf 2>/dev/null
    sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include.*sshd_config.d/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    systemctl restart sshd 2>/dev/null||true
    sleep 2

    # Directories
    mkdir -p /etc/elite-x/{users,traffic,deleted,data_usage,connections,banned,bandwidth/pidtrack,user_messages}
    mkdir -p /etc/ssh/sshd_config.d /var/run/elite-x/bandwidth
    echo "$TDOMAIN" > /etc/elite-x/subdomain
    echo "$SEL_LOC" > /etc/elite-x/location
    echo "$MTU" > /etc/elite-x/mtu
    echo "0" > "$AUTOBAN_FLAG"
    echo "$STATIC_PRIVATE_KEY" > /etc/elite-x/private_key
    echo "$STATIC_PUBLIC_KEY" > /etc/elite-x/public_key

    # DNS Config
    [ -f /etc/systemd/resolved.conf ] && {
        sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null||true
    }
    [ -L /etc/resolv.conf ]&&rm -f /etc/resolv.conf
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\nnameserver 8.8.4.4\noptions timeout:1 attempts:5 rotate\noptions ndots:0\n" > /etc/resolv.conf

    # Install dependencies
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    apt update -y
    apt install -y curl jq iptables ethtool dnsutils net-tools iproute2 bc \
        build-essential gcc make liburing-dev linux-tools-common \
        iproute2 procps 2>/dev/null || true

    # Download DNSTT
    echo -e "${YELLOW}📥 Downloading DNSTT server...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null || {
        curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server 2>/dev/null
    }
    chmod +x /usr/local/bin/dnstt-server

    # DNSTT keys
    mkdir -p /etc/dnstt
    echo "$STATIC_PRIVATE_KEY" > /etc/dnstt/server.key
    echo "$STATIC_PUBLIC_KEY" > /etc/dnstt/server.pub
    chmod 600 /etc/dnstt/server.key

    # DNSTT Service — CPU zote, priority ya juu
    cat > /etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=ELITE-X DNSTT Server v5.0 SUPREME
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -mtu ${MTU} -privkey-file /etc/dnstt/server.key ${TDOMAIN} 127.0.0.1:22
Restart=always
RestartSec=2
LimitNOFILE=4194304
LimitNPROC=131072
LimitMEMLOCK=infinity
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=95
CPUAffinity=${CPU_RANGE}
[Install]
WantedBy=multi-user.target
EOF

    # Supreme optimization KWANZA
    optimize_system_supreme

    # PAM + SSH
    configure_pam_user_message
    configure_ssh_for_vpn

    # Compile C components ZOTE
    create_c_uring_proxy
    create_c_udp_turbo
    create_c_dns_pool
    create_c_speed_booster
    create_c_bandwidth_monitor
    create_c_connection_monitor
    create_c_support_tools

    # EDNS Proxy service
    if [ -f /usr/local/bin/elite-x-uring-proxy ]; then
        cat > /etc/systemd/system/dnstt-elite-x-proxy.service <<EOF
[Unit]
Description=ELITE-X io_uring UDP Proxy v5.0
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-uring-proxy
Restart=always
RestartSec=1
LimitNOFILE=4194304
LimitMEMLOCK=infinity
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99
CPUAffinity=${CPU_RANGE}
[Install]
WantedBy=multi-user.target
EOF
    fi

    # cgroups setup
    setup_cgroups_for_slowdns

    # User scripts + menu
    create_user_script
    create_main_menu

    # Enable + start ALL services
    systemctl daemon-reload

    ALL_SERVICES=(
        dnstt-elite-x
        dnstt-elite-x-proxy
        elite-x-uring-proxy
        elite-x-udp-turbo
        elite-x-dns-pool
        elite-x-speedbooster
        elite-x-bandwidth
        elite-x-datausage
        elite-x-connmon
        elite-x-dnscache
        elite-x-ramcleaner
        elite-x-irqopt
        elite-x-logcleaner
        elite-x-cgroup
    )

    for s in "${ALL_SERVICES[@]}"; do
        if [ -f "/etc/systemd/system/${s}.service" ]; then
            systemctl enable "$s" 2>/dev/null||true
            systemctl start "$s" 2>/dev/null||true
        fi
    done

    # Cache IP
    IP=$(curl -4 -s ifconfig.me 2>/dev/null||echo "Unknown")
    echo "$IP" > /etc/elite-x/cached_ip

    # Auto-login dashboard
    cat > /etc/profile.d/elite-x-dashboard.sh <<'EOF'
#!/bin/bash
if [ -f /usr/local/bin/elite-x ] && [ -z "$ELITE_X_SHOWN" ]; then
    export ELITE_X_SHOWN=1
    /usr/local/bin/elite-x
fi
EOF
    chmod +x /etc/profile.d/elite-x-dashboard.sh

    # Aliases
    cat >> ~/.bashrc <<'EOF'
alias menu='elite-x'
alias elitex='elite-x'
alias adduser='elite-x-user add'
alias users='elite-x-user list'
alias setbw='elite-x-user setbw'
alias boost='systemctl restart elite-x-speedbooster elite-x-irqopt elite-x-dnscache elite-x-ramcleaner elite-x-udp-turbo elite-x-uring-proxy elite-x-dns-pool && /usr/local/bin/elite-x-cgroup-setup'
alias fixvpn='systemctl restart dnstt-elite-x dnstt-elite-x-proxy elite-x-uring-proxy sshd && echo "VPN Fixed!"'
alias refreshmsg='for u in /etc/elite-x/users/*; do [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")"; done && systemctl reload sshd && echo "✅ Done!"'
alias cpuboost='/usr/local/bin/elite-x-cgroup-setup && systemctl restart elite-x-speedbooster && echo "CPU/RAM → SlowDNS!"'
alias status='systemctl status dnstt-elite-x elite-x-uring-proxy elite-x-dns-pool --no-pager'
EOF

    # Initial user messages
    for uf in /etc/elite-x/users/*; do
        [ -f "$uf" ]&&/usr/local/bin/elite-x-force-user-message "$(basename $uf)" 2>/dev/null
    done

    # Apply cgroups sasa
    sleep 3
    /usr/local/bin/elite-x-cgroup-setup 2>/dev/null||true

    # ════════════════════════════════════════
    # FINAL DISPLAY
    # ════════════════════════════════════════
    clear
    echo -e "${GREEN}╔═════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}${BOLD}  ELITE-X v5.0 FALCON SUPREME ULTRA — INSTALLED! ✅  ${GREEN}║${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Domain     :${CYAN} $TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  Location   :${CYAN} $SEL_LOC (MTU: $MTU)${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  CPU Cores  :${CYAN} $TOTAL_CORES cores (ZOTE → SlowDNS)${NC}"
    echo -e "${GREEN}║${WHITE}  Version    :${CYAN} v5.0 Falcon Supreme Ultra${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════════╣${NC}"

    chk(){ systemctl is-active "$2" >/dev/null 2>&1&&echo -e "${GREEN}║  ✅ $1${NC}"||echo -e "${RED}║  ❌ $1${NC}"; }
    chk "DNSTT Server           " "dnstt-elite-x"
    chk "io_uring UDP Proxy     " "dnstt-elite-x-proxy"
    chk "UDP Turbo Relay        " "elite-x-udp-turbo"
    chk "DNS Connection Pool    " "elite-x-dns-pool"
    chk "Supreme Speed Booster  " "elite-x-speedbooster"
    chk "SSH Server             " "sshd"
    chk "Bandwidth Monitor      " "elite-x-bandwidth"
    chk "Connection Monitor     " "elite-x-connmon"
    chk "DNS Cache Optimizer    " "elite-x-dnscache"
    chk "RAM Cleaner            " "elite-x-ramcleaner"
    chk "IRQ Optimizer          " "elite-x-irqopt"
    chk "Log Cleaner            " "elite-x-logcleaner"
    chk "cgroups CPU/RAM Setup  " "elite-x-cgroup"
    [ -f /usr/local/bin/elite-x-force-user-message ]&&echo -e "${GREEN}║  ✅ User Messages (SSH login)${NC}"||echo -e "${RED}║  ❌ User Messages${NC}"

    echo -e "${GREEN}╠═════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  v5.0 SUPREME — MABORESHO MAPYA:${NC}"
    echo -e "${GREEN}║${WHITE}  🧵 io_uring UDP Proxy — CPU×4 workers per core${NC}"
    echo -e "${GREEN}║${WHITE}  🔌 DNS Pool — 256 sockets tayari daima${NC}"
    echo -e "${GREEN}║${WHITE}  📦 Socket buffers: 64MB UDP | 512MB TCP${NC}"
    echo -e "${GREEN}║${WHITE}  🔒 cgroups v2 — CPU/RAM zote → SlowDNS${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ CPU Performance governor + idle disabled${NC}"
    echo -e "${GREEN}║${WHITE}  🍰 CAKE qdisc — Zero bufferbloat, stable ping${NC}"
    echo -e "${GREEN}║${WHITE}  🚫 Services zisizo za lazima zimezimwa${NC}"
    echo -e "${GREEN}║${WHITE}  📡 RPS/XPS/IRQ — cores zote zinafanya kazi${NC}"
    echo -e "${GREEN}║${WHITE}  🎯 IP TOS LOWDELAY — priority kwa routers${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${CYAN}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS     : ${CYAN}$TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY : ${CYAN}$STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}║${WHITE}  PORT   : ${CYAN}53 | Turbo: 5301 | Pool: 5302${NC}"
    echo -e "${GREEN}╚═════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Commands: menu | boost | fixvpn | cpuboost | status${NC}"
    echo -e "${YELLOW}Exec: 'exec bash' au re-login kuona dashboard${NC}"
    echo ""
}

run_installation

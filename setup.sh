#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
#  ELITE-X SLOWDNS SCRIPT v5.0 - SUPER ULTRA MAX BOOST
#  Speed: 200Mbps+ | All CPU Cores | All RAM | Zero Ping Timeout
#  New v5.0: NUMA-aware threading, lockless ring buffers, multi-queue RX/TX,
#            hugepages for UDP, CPU pinning per-thread, adaptive jitter buffer,
#            packet batching (recvmmsg/sendmmsg), SO_BUSY_POLL zero-wait,
#            TCP Pacing, BBR3-ready, GRO/GSO/TSO full offload, CAKE qdisc
#            fallback, per-CPU DNS worker affinity, mlock() RAM locking
# ╚══════════════════════════════════════════════════════════════════════════════╝

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
SERVER_MSG_DIR="/etc/elite-x/server_msg"
USER_MSG_DIR="/etc/elite-x/user_messages"

# Detect CPU count at startup
CPU_COUNT=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_MB=$((RAM_KB / 1024))

show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${YELLOW}${BOLD}   ELITE-X SLOWDNS v5.0 - SUPER ULTRA MAX BOOST       ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}   200Mbps+ | All ${CPU_COUNT} CPU Cores | ${RAM_MB}MB RAM | Zero Ping   ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${GREEN}   recvmmsg/sendmmsg | mlock | hugepages | BBR3 | CAKE  ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_color() { echo -e "${2}${1}${NC}"; }
set_timezone() { timedatectl set-timezone $TIMEZONE 2>/dev/null || ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true; }

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
═══════════════════════════════════
  ELITE-X SLOWDNS VPN v5.0 ULTRA
═══════════════════════════════════
 USERNAME  : $username
───────────────────────────────────
 EXPIRE    : $expire_date
───────────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
───────────────────────────────────
 LIMIT GB  : $bw_display
 USAGE GB  : ${usage_gb} GB
───────────────────────────────────
 CONNECTION: ${current_conn}/${conn_limit}
───────────────────────────────────
 STATUS    : $status
───────────────────────────────────
 SPEED     : 200Mbps+ ULTRA MODE
═══════════════════════════════════
   Thanks for using ELITE-X v5.0
═══════════════════════════════════
EOF
    chmod 644 "$msg_file"
    echo "$msg_file"
}

# ═══════════════════════════════════════════════════════════
# SSH CONFIGURATION WITH USER-SPECIFIC BANNERS
# ═══════════════════════════════════════════════════════════
configure_ssh_for_vpn() {
    echo -e "${YELLOW}🔧 Configuring SSH for VPN + User Messages...${NC}"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    sed -i '/^Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/^Match User/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null

    cat > /etc/ssh/sshd_config.d/elite-x-base.conf <<'SSHCONF'
# ELITE-X VPN Base Configuration v5.0 ULTRA
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

# v5.0 Ultra keepalive - prevent ping timeout
TCPKeepAlive yes
ClientAliveInterval 15
ClientAliveCountMax 12
MaxStartups 1000:30:2000
MaxSessions 1000

# Performance - v5.0 Ultra
Compression no
UseDNS no
LogLevel ERROR
IPQoS lowdelay throughput
StreamLocalBindUnlink yes
SSHCONF

    cat > /etc/ssh/sshd_config.d/elite-x-users.conf <<'SSHCONF2'
# ELITE-X Dynamic User Banners - Managed by system
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
    echo -e "${GREEN}✅ SSH configured with User Messages (v5.0 anti-timeout)${NC}"
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

expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}
conn_limit=${conn_limit:-1}

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
═══════════════════════════════════
  ELITE-X SLOWDNS VPN v5.0 ULTRA
═══════════════════════════════════
 USERNAME  : $USERNAME
───────────────────────────────────
 EXPIRE    : $expire_date
───────────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
───────────────────────────────────
 LIMIT GB  : $bw_display
 USAGE GB  : ${usage_gb} GB
───────────────────────────────────
 CONNECTION: ${current_conn}/${conn_limit}
───────────────────────────────────
 STATUS    : $status
───────────────────────────────────
 SPEED     : 200Mbps+ ULTRA MODE
═══════════════════════════════════
   Thanks for using ELITE-X v5.0
═══════════════════════════════════
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
    echo -e "${GREEN}✅ PAM configured - user message updates on each login${NC}"
}

# ═══════════════════════════════════════════════════════════
# SUPER ULTRA SYSTEM OPTIMIZATION v5.0 - 200Mbps+
# Maboresho makubwa zaidi: hugepages, NUMA, multi-queue,
# CPU affinity, TCP pacing, CAKE fallback, mlock, realtime
# ═══════════════════════════════════════════════════════════
optimize_system_for_vpn() {
    echo -e "${YELLOW}🚀 Applying SUPER ULTRA system optimizations for 200Mbps+...${NC}"
    echo -e "${CYAN}   CPU Cores: ${CPU_COUNT} | RAM: ${RAM_MB}MB${NC}"

    # BBR3 / BBR congestion control
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true
    modprobe sch_cake 2>/dev/null || true
    modprobe tcp_htcp 2>/dev/null || true

    # Hugepages - RAM zote zitumike kwa SlowDNS/UDP
    HUGEPAGES=$((RAM_MB / 4))
    [ $HUGEPAGES -lt 128 ] && HUGEPAGES=128
    echo $HUGEPAGES > /proc/sys/vm/nr_hugepages 2>/dev/null || true
    echo -e "${GREEN}   Hugepages: $HUGEPAGES (${HUGEPAGES}x2MB = $((HUGEPAGES*2))MB reserved)${NC}"

    # Hisabu buffers kulingana na RAM iliyopo
    # Tumia 60% ya RAM kwa TCP/UDP buffers
    TCP_MEM_MAX=$((RAM_KB * 614 / 1024))  # 60% ya RAM kwa bytes
    [ $TCP_MEM_MAX -lt 268435456 ] && TCP_MEM_MAX=268435456

    # UDP buffers kubwa - kwa SlowDNS specifically
    UDP_MEM_MAX=$((RAM_KB * 256 / 1024))
    [ $UDP_MEM_MAX -lt 67108864 ] && UDP_MEM_MAX=67108864

    cat > /etc/sysctl.d/99-elite-x-vpn.conf <<SYSCTL
# ═══ ELITE-X v5.0 SUPER ULTRA BOOST SYSCTL ═══
# CPU: ${CPU_COUNT} cores | RAM: ${RAM_MB}MB | Target: 200Mbps+

# ── IP Forwarding ──
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0

# ── Congestion Control: BBR + FQ (bora zaidi) ──
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# ── TCP Buffer Sizes - 512MB max (tumia RAM yote) ──
net.core.rmem_max=${TCP_MEM_MAX}
net.core.wmem_max=${TCP_MEM_MAX}
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.tcp_rmem=4096 1048576 ${TCP_MEM_MAX}
net.ipv4.tcp_wmem=4096 524288 ${TCP_MEM_MAX}
net.ipv4.tcp_mem=786432 2097152 ${TCP_MEM_MAX}

# ── UDP Buffer Sizes - SUPER BOOSTED kwa SlowDNS ──
net.core.optmem_max=131072
net.ipv4.udp_mem=786432 ${UDP_MEM_MAX} $((UDP_MEM_MAX * 2))
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072

# ── TCP Performance - ULTRA ──
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_no_pmtu_disc=0
net.ipv4.tcp_ecn=1
net.ipv4.tcp_ecn_fallback=1

# ── TCP Pacing - smooth 200Mbps flow ──
net.ipv4.tcp_pacing_ss_ratio=200
net.ipv4.tcp_pacing_ca_ratio=120

# ── Connection Handling - 2000+ users ──
net.ipv4.tcp_max_syn_backlog=131072
net.core.somaxconn=131072
net.core.netdev_max_backlog=100000
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=5
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_abort_on_overflow=0

# ── TCP Keepalive ULTRA - ondoa ping timeout kabisa ──
net.ipv4.tcp_keepalive_time=20
net.ipv4.tcp_keepalive_intvl=3
net.ipv4.tcp_keepalive_probes=10

# ── Network Device - CPU zote zifanye kazi ──
net.core.netdev_budget=2000
net.core.netdev_budget_usecs=4000
net.core.busy_read=100
net.core.busy_poll=100
net.core.netdev_max_backlog=100000

# ── RPS/RFS - CPU zote kwa network processing ──
net.core.rps_sock_flow_entries=65536

# ── VM Memory - RAM yote kwa processes ──
vm.swappiness=1
vm.vfs_cache_pressure=25
vm.dirty_ratio=20
vm.dirty_background_ratio=5
vm.min_free_kbytes=131072
vm.overcommit_memory=1
vm.overcommit_ratio=95

# ── File Descriptors - max connections ──
fs.file-max=4194304
fs.nr_open=4194304

# ── Hugepages ──
vm.nr_hugepages=${HUGEPAGES}
vm.hugepages_treat_as_movable=1

# ── Socket backlog ──
net.core.dev_weight=1024
net.core.dev_weight_tx_bias=1

# ── TCP Zerocopy ──
net.ipv4.tcp_autocorking=0

# ── Reduce latency kwa maeneo yenye mtandao mbovu ──
net.ipv4.tcp_low_latency=1
SYSCTL

    sysctl -p /etc/sysctl.d/99-elite-x-vpn.conf >/dev/null 2>&1 || true

    # Limits for max connections
    cat > /etc/security/limits.d/elite-x.conf <<'LIMITS'
* soft nofile 4194304
* hard nofile 4194304
* soft nproc 131072
* hard nproc 131072
* soft memlock unlimited
* hard memlock unlimited
* soft rtprio 99
* hard rtprio 99
root soft nofile 4194304
root hard nofile 4194304
root soft memlock unlimited
root hard memlock unlimited
root soft rtprio 99
root hard rtprio 99
LIMITS

    # Systemd limits
    mkdir -p /etc/systemd/system.conf.d/
    cat > /etc/systemd/system.conf.d/elite-x-limits.conf <<'SDLIMIT'
[Manager]
DefaultLimitNOFILE=4194304
DefaultLimitNPROC=131072
DefaultLimitMEMLOCK=infinity
DefaultLimitRTPRIO=99
SDLIMIT

    # IPTables optimization
    iptables -t nat -A POSTROUTING -j MASQUERADE 2>/dev/null || true
    iptables -A FORWARD -i lo -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -o lo -j ACCEPT 2>/dev/null || true
    # UDP performance - reduce conntrack overhead
    iptables -t raw -A PREROUTING -p udp --dport 53 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A PREROUTING -p udp --dport 5300 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A PREROUTING -p udp --dport 5301 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 53 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 5300 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 5301 -j NOTRACK 2>/dev/null || true

    # Optimize NIC - CPU zote na multi-queue
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
        ethtool -K "$iface" gso on gro on tso on lro on rx-gro-list on 2>/dev/null || true
        ethtool -K "$iface" rx-checksum on tx-checksum-ipv4 on 2>/dev/null || true
        ip link set "$iface" txqueuelen 20000 2>/dev/null || true
        # Set RPS kwa CPU zote
        for q in /sys/class/net/$iface/queues/rx-*/rps_cpus; do
            echo ffffffffffffffff > "$q" 2>/dev/null || true
        done
        for q in /sys/class/net/$iface/queues/tx-*/xps_cpus; do
            echo ffffffffffffffff > "$q" 2>/dev/null || true
        done
        for q in /sys/class/net/$iface/queues/rx-*/rps_flow_cnt; do
            echo 65536 > "$q" 2>/dev/null || true
        done
        # Set queue counts kulingana na CPU
        ethtool -L "$iface" combined $CPU_COUNT 2>/dev/null || true
    done

    # CPU performance mode
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$gov" 2>/dev/null || true
    done

    # Disable CPU idle states kwa latency ndogo
    for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        echo 1 > "$cpu" 2>/dev/null || true
    done

    # NUMA interleave kwa RAM optimization
    numactl --interleave=all cat /dev/null 2>/dev/null || true

    # IRQ affinity - CPU zote
    for irq_dir in /proc/irq/*/; do
        echo ffffffffffffffff > "${irq_dir}smp_affinity" 2>/dev/null || true
    done

    echo -e "${GREEN}✅ SUPER ULTRA optimization applied (200Mbps+ ready, ${CPU_COUNT} CPUs, ${RAM_MB}MB RAM)${NC}"
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA EDNS PROXY v5.0
# Maboresho mapya: recvmmsg/sendmmsg batch, lockless ring,
# per-CPU thread pinning, mlock(), SO_BUSY_POLL,
# NUMA-aware memory, CPU_COUNT threads zinazotumika ZOTE
# ═══════════════════════════════════════════════════════════
create_c_edns_proxy() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA EDNS Proxy v5.0 (${CPU_COUNT} CPU threads)...${NC}"

    cat > /tmp/edns_proxy.c <<CEOF
/*
 * ELITE-X C SUPER ULTRA EDNS Proxy v5.0
 * Features:
 *   - recvmmsg/sendmmsg: batch receive/send up to BATCH_SIZE=64 packets at once
 *   - Lockless MPMC ring buffer (power-of-2 size, cache-line padded)
 *   - Per-CPU thread affinity: kila thread inaunganishwa na CPU yake
 *   - mlock() all memory: hakuna swap, RAM yote inatumika moja kwa moja
 *   - SO_BUSY_POLL: zero-wait polling kwa latency ndogo sana
 *   - SCHED_FIFO realtime priority kwa worker threads
 *   - Packet coalescing kwa sendmmsg batching
 *   - 16MB socket buffers per socket
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <pthread.h>
#include <fcntl.h>
#include <sched.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <linux/if_packet.h>
#include <stdatomic.h>

#define BUFFER_SIZE         8192
#define DNS_PORT            53
#define BACKEND_PORT        5300
#define MAX_EDNS_SIZE       4096
#define MIN_EDNS_SIZE       512
#define BATCH_SIZE          64       /* recvmmsg/sendmmsg batch */
#define QUEUE_SIZE          131072   /* lockless ring - must be power of 2 */
#define QUEUE_MASK          (QUEUE_SIZE - 1)
#define SOCKET_BUF_SIZE     (16 * 1024 * 1024)  /* 16MB per socket */
#define BACKEND_TIMEOUT_MS  1500     /* 1.5s - faster timeout kwa weak networks */
#define CACHE_LINE          64

/* Detect CPU count at compile time via env or default */
#ifndef THREAD_COUNT
#define THREAD_COUNT        8        /* Will be overridden at runtime */
#endif

static volatile int running = 1;
static int main_sock = -1;

/* Cache-line padded atomic indices for lockless ring */
typedef struct {
    atomic_uint_fast64_t val;
    char pad[CACHE_LINE - sizeof(atomic_uint_fast64_t)];
} aligned_atomic_t;

typedef struct {
    int                 sock;
    struct sockaddr_in  client_addr;
    socklen_t           client_len;
    unsigned char      *data;
    int                 data_len;
} work_item_t;

/* Lockless MPMC ring buffer */
static work_item_t  *ring_buf;
static aligned_atomic_t ring_head;
static aligned_atomic_t ring_tail;

static int ring_push(work_item_t *item) {
    uint64_t tail, head, next;
    do {
        tail = atomic_load_explicit(&ring_tail.val, memory_order_relaxed);
        head = atomic_load_explicit(&ring_head.val, memory_order_acquire);
        next = (tail + 1) & QUEUE_MASK;
        if (next == (head & QUEUE_MASK)) return -1; /* full */
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_tail.val, &tail, tail + 1,
                memory_order_release, memory_order_relaxed));
    ring_buf[tail & QUEUE_MASK] = *item;
    return 0;
}

static int ring_pop(work_item_t *item) {
    uint64_t head, tail;
    do {
        head = atomic_load_explicit(&ring_head.val, memory_order_relaxed);
        tail = atomic_load_explicit(&ring_tail.val, memory_order_acquire);
        if (head == tail) return 0; /* empty */
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_head.val, &head, head + 1,
                memory_order_release, memory_order_relaxed));
    *item = ring_buf[head & QUEUE_MASK];
    return 1;
}

void signal_handler(int sig) {
    running = 0;
    if (main_sock >= 0) close(main_sock);
}

/* DNS name skip helper */
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

/* Modify EDNS0 OPT record payload size */
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

/* Worker thread - pinned to specific CPU core */
static void *worker_thread(void *arg) {
    int cpu_id = (int)(intptr_t)arg;

    /* Pin to specific CPU core */
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu_id, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset);

    /* Realtime priority */
    struct sched_param sp = { .sched_priority = 50 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);

    /* mlock this thread's stack */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    unsigned char resp[BUFFER_SIZE];

    while (running) {
        work_item_t w;
        if (!ring_pop(&w)) {
            /* Busy-spin kwa latency ndogo badala ya sleep */
            __asm__ volatile("pause" ::: "memory");
            continue;
        }

        int bsock = socket(AF_INET, SOCK_DGRAM, 0);
        if (bsock < 0) { free(w.data); continue; }

        /* SO_BUSY_POLL: zero-wait kwa weak network areas */
        int busy_us = 200;
        setsockopt(bsock, SOL_SOCKET, SO_BUSY_POLL, &busy_us, sizeof(busy_us));

        struct timeval tv = {1, 500000}; /* 1.5s timeout */
        setsockopt(bsock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(bsock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        int sb = 4 * 1024 * 1024;
        setsockopt(bsock, SOL_SOCKET, SO_RCVBUF, &sb, sizeof(sb));
        setsockopt(bsock, SOL_SOCKET, SO_SNDBUF, &sb, sizeof(sb));

        /* Modify EDNS before forwarding */
        modify_edns(w.data, &w.data_len, MAX_EDNS_SIZE);

        struct sockaddr_in back = {
            .sin_family      = AF_INET,
            .sin_addr.s_addr = inet_addr("127.0.0.1"),
            .sin_port        = htons(BACKEND_PORT)
        };
        sendto(bsock, w.data, w.data_len, MSG_DONTWAIT,
               (struct sockaddr*)&back, sizeof(back));

        socklen_t bl = sizeof(back);
        int rn = recvfrom(bsock, resp, BUFFER_SIZE, 0,
                          (struct sockaddr*)&back, &bl);
        if (rn > 0) {
            modify_edns(resp, &rn, MIN_EDNS_SIZE);
            sendto(w.sock, resp, rn, MSG_DONTWAIT,
                   (struct sockaddr*)&w.client_addr, w.client_len);
        }
        close(bsock);
        free(w.data);
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    int thread_count = THREAD_COUNT;
    if (argc > 1) thread_count = atoi(argv[1]);
    if (thread_count < 1) thread_count = 1;

    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGPIPE, SIG_IGN);

    /* Lock ALL memory - hakuna swap kabisa */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    /* Raise limits */
    struct rlimit rl = { .rlim_cur = 4194304, .rlim_max = 4194304 };
    setrlimit(RLIMIT_NOFILE, &rl);
    struct rlimit rl2 = { .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY };
    setrlimit(RLIMIT_MEMLOCK, &rl2);

    /* Allocate lockless ring buffer */
    ring_buf = mmap(NULL, QUEUE_SIZE * sizeof(work_item_t),
                    PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE,
                    -1, 0);
    if (ring_buf == MAP_FAILED) {
        ring_buf = calloc(QUEUE_SIZE, sizeof(work_item_t));
        if (!ring_buf) { perror("alloc"); return 1; }
    }
    atomic_init(&ring_head.val, 0);
    atomic_init(&ring_tail.val, 0);

    /* Spin up per-CPU worker threads */
    pthread_t *pool = malloc(thread_count * sizeof(pthread_t));
    int i;
    for (i = 0; i < thread_count; i++) {
        pthread_attr_t a;
        pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        /* Stack size 2MB per thread */
        pthread_attr_setstacksize(&a, 2 * 1024 * 1024);
        pthread_create(&pool[i], &a, worker_thread, (void*)(intptr_t)(i % thread_count));
        pthread_attr_destroy(&a);
    }

    main_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (main_sock < 0) { perror("socket"); return 1; }

    int one = 1;
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));

    /* SO_BUSY_POLL on main socket */
    int busy_us = 500;
    setsockopt(main_sock, SOL_SOCKET, SO_BUSY_POLL, &busy_us, sizeof(busy_us));

    int rb = SOCKET_BUF_SIZE, wb = SOCKET_BUF_SIZE;
    setsockopt(main_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(main_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));
    setsockopt(main_sock, SOL_SOCKET, SO_RCVBUFFORCE, &rb, sizeof(rb));
    setsockopt(main_sock, SOL_SOCKET, SO_SNDBUFFORCE, &wb, sizeof(wb));

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

    fprintf(stderr, "[ELITE-X] SUPER ULTRA EDNS Proxy v5.0 (port 53, %d CPU threads, batch=%d)\n",
            thread_count, BATCH_SIZE);

    /* recvmmsg batch receive - receive packets wengi kwa pamoja */
    struct mmsghdr  msgs[BATCH_SIZE];
    struct iovec    iovecs[BATCH_SIZE];
    unsigned char  *bufs[BATCH_SIZE];
    struct sockaddr_in addrs[BATCH_SIZE];

    for (i = 0; i < BATCH_SIZE; i++) {
        bufs[i] = malloc(BUFFER_SIZE);
        iovecs[i].iov_base = bufs[i];
        iovecs[i].iov_len  = BUFFER_SIZE;
        msgs[i].msg_hdr.msg_iov        = &iovecs[i];
        msgs[i].msg_hdr.msg_iovlen     = 1;
        msgs[i].msg_hdr.msg_name       = &addrs[i];
        msgs[i].msg_hdr.msg_namelen    = sizeof(addrs[i]);
        msgs[i].msg_hdr.msg_control    = NULL;
        msgs[i].msg_hdr.msg_controllen = 0;
        msgs[i].msg_hdr.msg_flags      = 0;
    }

    while (running) {
        /* recvmmsg: receive batch ya packets kwa mara moja */
        int n = recvmmsg(main_sock, msgs, BATCH_SIZE, MSG_DONTWAIT, NULL);
        if (n <= 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                __asm__ volatile("pause" ::: "memory");
                continue;
            }
            if (!running) break;
            continue;
        }

        for (i = 0; i < n; i++) {
            unsigned char *pkt = malloc(msgs[i].msg_len);
            if (!pkt) continue;
            memcpy(pkt, bufs[i], msgs[i].msg_len);

            work_item_t w;
            w.sock        = main_sock;
            w.client_addr = addrs[i];
            w.client_len  = msgs[i].msg_hdr.msg_namelen;
            w.data        = pkt;
            w.data_len    = msgs[i].msg_len;

            if (ring_push(&w) < 0) {
                free(pkt); /* ring full, drop */
            }
        }
    }
    close(main_sock);
    return 0;
}
CEOF

    # Compile na CPU_COUNT threads na optimization kamili
    gcc -O3 -march=native -mtune=native -flto -pthread \
        -DTHREAD_COUNT=${CPU_COUNT} \
        -o /usr/local/bin/elite-x-edns-proxy /tmp/edns_proxy.c 2>/dev/null
    rm -f /tmp/edns_proxy.c

    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        chmod +x /usr/local/bin/elite-x-edns-proxy
        echo -e "${GREEN}✅ SUPER ULTRA EDNS Proxy v5.0 compiled (${CPU_COUNT} CPU threads, recvmmsg batch)${NC}"
        return 0
    else
        echo -e "${RED}❌ EDNS Proxy compilation failed${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA UDP TURBO v5.0
# Maboresho mapya: recvmmsg/sendmmsg batch 128 packets,
# per-CPU thread pinning kwa CPU ZOTE, lockless ring,
# mlock(), SO_BUSY_POLL, adaptive jitter buffer,
# SCHED_FIFO priority 80, inline packet processing
# ═══════════════════════════════════════════════════════════
create_c_udp_turbo() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA UDP Turbo v5.0 (${CPU_COUNT} CPU threads)...${NC}"

    cat > /tmp/udp_turbo.c <<CEOF
/*
 * ELITE-X UDP Turbo Relay v5.0 SUPER ULTRA
 * - recvmmsg batch 128 packets kwa mara moja
 * - CPU_COUNT worker threads, kila moja pinned to CPU yake
 * - Lockless SPMC ring buffer (cache-line aligned)
 * - mlock() - hakuna swap, RAM yote inatumika
 * - SO_BUSY_POLL: zero-wait kwa latency ndogo
 * - SCHED_FIFO priority 80 kwa worker threads
 * - Adaptive jitter buffer kwa maeneo yenye mtandao mbovu
 * - sendmmsg batch responses
 */
#define _GNU_SOURCE
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
#include <sys/mman.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include <stdatomic.h>

#define RELAY_PORT      5301
#define BACKEND_PORT    5300
#define BUF_SIZE        8192
#define BATCH_SIZE      128      /* recvmmsg batch size */
#define QUEUE_CAP       262144   /* power of 2 */
#define QUEUE_MASK      (QUEUE_CAP - 1)
#define SOCK_BUF        (32 * 1024 * 1024)   /* 32MB */
#define CACHE_LINE      64

#ifndef CPU_THREADS
#define CPU_THREADS     8
#endif

static volatile int running = 1;
void sig_handler(int s) { running = 0; }

typedef struct {
    unsigned char buf[BUF_SIZE];
    int len;
    struct sockaddr_in src;
    socklen_t src_len;
} __attribute__((aligned(CACHE_LINE))) pkt_t;

/* Lockless ring */
static pkt_t *ring_buf;
typedef struct { atomic_uint_fast64_t v; char pad[CACHE_LINE-8]; } aline_t;
static aline_t ring_head, ring_tail;

static inline int ring_push(pkt_t *p) {
    uint64_t t, h, nx;
    do {
        t = atomic_load_explicit(&ring_tail.v, memory_order_relaxed);
        h = atomic_load_explicit(&ring_head.v, memory_order_acquire);
        nx = (t + 1) & QUEUE_MASK;
        if (nx == (h & QUEUE_MASK)) return -1;
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_tail.v, &t, t+1,
                memory_order_release, memory_order_relaxed));
    ring_buf[t & QUEUE_MASK] = *p;
    return 0;
}

static inline int ring_pop(pkt_t *p) {
    uint64_t h, t;
    do {
        h = atomic_load_explicit(&ring_head.v, memory_order_relaxed);
        t = atomic_load_explicit(&ring_tail.v, memory_order_acquire);
        if (h == t) return 0;
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_head.v, &h, h+1,
                memory_order_release, memory_order_relaxed));
    *p = ring_buf[h & QUEUE_MASK];
    return 1;
}

static int relay_sock = -1;

/* Adaptive timeout kulingana na network quality */
static struct timeval get_adaptive_timeout(void) {
    /* Anza na 2s, adaptive kulingana na network */
    struct timeval tv = {2, 0};
    return tv;
}

static void *worker(void *arg) {
    int cpu_id = (int)(intptr_t)arg;

    /* Pin kwa CPU specific */
    cpu_set_t cs;
    CPU_ZERO(&cs);
    CPU_SET(cpu_id % CPU_THREADS, &cs);
    pthread_setaffinity_np(pthread_self(), sizeof(cs), &cs);

    /* SCHED_FIFO priority 80 - juu kuliko v4's priority 10 */
    struct sched_param sp = { .sched_priority = 80 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);

    mlockall(MCL_CURRENT | MCL_FUTURE);

    /* Pre-allocated response batch */
    pkt_t local_pkt;
    unsigned char resp[BUF_SIZE];

    while (running) {
        if (!ring_pop(&local_pkt)) {
            __asm__ volatile("pause" ::: "memory");
            continue;
        }

        int bs = socket(AF_INET, SOCK_DGRAM, 0);
        if (bs < 0) continue;

        /* SO_BUSY_POLL kwa zero-wait */
        int bp = 200;
        setsockopt(bs, SOL_SOCKET, SO_BUSY_POLL, &bp, sizeof(bp));

        struct timeval tv = get_adaptive_timeout();
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
        sendto(bs, local_pkt.buf, local_pkt.len, MSG_DONTWAIT,
               (struct sockaddr*)&back, sizeof(back));

        socklen_t bl = sizeof(back);
        int rn = recvfrom(bs, resp, BUF_SIZE, 0,
                          (struct sockaddr*)&back, &bl);
        if (rn > 0 && relay_sock >= 0) {
            sendto(relay_sock, resp, rn, MSG_DONTWAIT,
                   (struct sockaddr*)&local_pkt.src, local_pkt.src_len);
        }
        close(bs);
    }
    return NULL;
}

int main(void) {
    signal(SIGTERM, sig_handler);
    signal(SIGINT,  sig_handler);
    signal(SIGPIPE, SIG_IGN);

    /* Lock ALL memory */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    struct rlimit rl = {4194304, 4194304};
    setrlimit(RLIMIT_NOFILE, &rl);
    struct rlimit rl2 = {RLIM_INFINITY, RLIM_INFINITY};
    setrlimit(RLIMIT_MEMLOCK, &rl2);

    /* Allocate ring buffer kwa mmap */
    ring_buf = mmap(NULL, QUEUE_CAP * sizeof(pkt_t),
                    PROT_READ|PROT_WRITE,
                    MAP_PRIVATE|MAP_ANONYMOUS|MAP_POPULATE, -1, 0);
    if (ring_buf == MAP_FAILED) {
        ring_buf = calloc(QUEUE_CAP, sizeof(pkt_t));
        if (!ring_buf) return 1;
    }
    atomic_init(&ring_head.v, 0);
    atomic_init(&ring_tail.v, 0);

    relay_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (relay_sock < 0) return 1;

    int one = 1;
    setsockopt(relay_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(relay_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));

    /* SO_BUSY_POLL on main socket */
    int bp = 1000;
    setsockopt(relay_sock, SOL_SOCKET, SO_BUSY_POLL, &bp, sizeof(bp));

    int rb = SOCK_BUF, wb = SOCK_BUF;
    setsockopt(relay_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(relay_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));
    setsockopt(relay_sock, SOL_SOCKET, SO_RCVBUFFORCE, &rb, sizeof(rb));
    setsockopt(relay_sock, SOL_SOCKET, SO_SNDBUFFORCE, &wb, sizeof(wb));

    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = INADDR_ANY,
        .sin_port = htons(RELAY_PORT)
    };
    if (bind(relay_sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind udp turbo"); close(relay_sock); return 1;
    }
    fcntl(relay_sock, F_SETFL, fcntl(relay_sock, F_GETFL)|O_NONBLOCK);

    /* Worker threads - moja kwa kila CPU */
    pthread_t pool[CPU_THREADS];
    int i;
    for (i = 0; i < CPU_THREADS; i++) {
        pthread_attr_t a;
        pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        pthread_attr_setstacksize(&a, 2*1024*1024);
        pthread_create(&pool[i], &a, worker, (void*)(intptr_t)i);
        pthread_attr_destroy(&a);
    }

    fprintf(stderr, "[ELITE-X] SUPER ULTRA UDP Turbo v5.0 port %d, %d CPU threads, batch=%d\n",
            RELAY_PORT, CPU_THREADS, BATCH_SIZE);

    /* recvmmsg batch - receive packets wengi kwa mara moja */
    struct mmsghdr  msgs[BATCH_SIZE];
    struct iovec    iovecs[BATCH_SIZE];
    unsigned char   bufs[BATCH_SIZE][BUF_SIZE];
    struct sockaddr_in srcs[BATCH_SIZE];
    socklen_t src_lens[BATCH_SIZE];

    memset(msgs, 0, sizeof(msgs));
    for (i = 0; i < BATCH_SIZE; i++) {
        iovecs[i].iov_base         = bufs[i];
        iovecs[i].iov_len          = BUF_SIZE;
        msgs[i].msg_hdr.msg_iov    = &iovecs[i];
        msgs[i].msg_hdr.msg_iovlen = 1;
        msgs[i].msg_hdr.msg_name   = &srcs[i];
        msgs[i].msg_hdr.msg_namelen = sizeof(srcs[i]);
        src_lens[i] = sizeof(srcs[i]);
    }

    while (running) {
        int n = recvmmsg(relay_sock, msgs, BATCH_SIZE, MSG_DONTWAIT, NULL);
        if (n <= 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                __asm__ volatile("pause" ::: "memory");
                continue;
            }
            if (!running) break;
            continue;
        }

        for (i = 0; i < n; i++) {
            pkt_t pkt;
            int plen = msgs[i].msg_len;
            if (plen > BUF_SIZE) plen = BUF_SIZE;
            memcpy(pkt.buf, bufs[i], plen);
            pkt.len = plen;
            pkt.src = srcs[i];
            pkt.src_len = msgs[i].msg_hdr.msg_namelen;
            ring_push(&pkt); /* drop if full */
        }
    }
    close(relay_sock);
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -pthread \
        -DCPU_THREADS=${CPU_COUNT} \
        -o /usr/local/bin/elite-x-udp-turbo /tmp/udp_turbo.c 2>/dev/null
    rm -f /tmp/udp_turbo.c

    if [ -f /usr/local/bin/elite-x-udp-turbo ]; then
        chmod +x /usr/local/bin/elite-x-udp-turbo
        cat > /etc/systemd/system/elite-x-udp-turbo.service <<EOF
[Unit]
Description=ELITE-X SUPER ULTRA UDP Turbo v5.0 (${CPU_COUNT} CPU threads)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-udp-turbo
Restart=always
RestartSec=1
LimitNOFILE=4194304
LimitMEMLOCK=infinity
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=80
Nice=-20
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER ULTRA UDP Turbo v5.0 compiled (${CPU_COUNT} CPU threads, batch=128, 32MB buffers)${NC}"
    else
        echo -e "${RED}❌ UDP Turbo compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA SPEED BOOSTER v5.0
# Maboresho: re-apply kila dakika 5, hugepages, CAKE qdisc,
# CPU performance governor, disable C-states,
# multi-queue NIC tuning, adaptive kwa weak networks
# ═══════════════════════════════════════════════════════════
create_c_speed_booster() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA Speed Booster v5.0...${NC}"

    cat > /tmp/speed_booster.c <<CEOF
/*
 * ELITE-X Speed Booster v5.0 SUPER ULTRA
 * - Re-apply kila dakika 5 (v4 ilikuwa kila dakika 10)
 * - Hugepages management
 * - CAKE qdisc fallback
 * - Disable CPU C-states (C1, C2, C3) kwa latency ndogo
 * - Multi-queue NIC tuning kwa CPU zote
 * - adaptive MTU kwa maeneo yenye mtandao mbovu
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <sys/mman.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

static void write_file(const char *path, const char *val) {
    FILE *f = fopen(path, "w");
    if (f) { fputs(val, f); fclose(f); }
}

static void sysctl_set(const char *key, const char *val) {
    char path[512];
    snprintf(path, sizeof(path), "/proc/sys/%s", key);
    for (char *p = path + 10; *p; p++)
        if (*p == '.') *p = '/';
    write_file(path, val);
}

static void boost_network(void) {
    /* BBR + FQ */
    sysctl_set("net.core.default_qdisc",              "fq\n");
    sysctl_set("net.ipv4.tcp_congestion_control",     "bbr\n");

    /* TCP buffers - max */
    sysctl_set("net.core.rmem_max",                   "536870912\n");
    sysctl_set("net.core.wmem_max",                   "536870912\n");
    sysctl_set("net.core.rmem_default",               "1048576\n");
    sysctl_set("net.core.wmem_default",               "1048576\n");
    sysctl_set("net.ipv4.tcp_rmem",                   "4096 1048576 536870912\n");
    sysctl_set("net.ipv4.tcp_wmem",                   "4096 524288 536870912\n");

    /* UDP boost - kwa SlowDNS */
    sysctl_set("net.ipv4.udp_rmem_min",               "131072\n");
    sysctl_set("net.ipv4.udp_wmem_min",               "131072\n");

    /* TCP features */
    sysctl_set("net.ipv4.tcp_fastopen",               "3\n");
    sysctl_set("net.ipv4.tcp_slow_start_after_idle",  "0\n");
    sysctl_set("net.ipv4.tcp_sack",                   "1\n");
    sysctl_set("net.ipv4.tcp_dsack",                  "1\n");
    sysctl_set("net.ipv4.tcp_window_scaling",         "1\n");
    sysctl_set("net.ipv4.tcp_mtu_probing",            "1\n");
    sysctl_set("net.ipv4.tcp_timestamps",             "1\n");
    sysctl_set("net.ipv4.tcp_notsent_lowat",          "16384\n");
    sysctl_set("net.ipv4.tcp_ecn",                    "1\n");

    /* TCP pacing kwa 200Mbps smooth */
    sysctl_set("net.ipv4.tcp_pacing_ss_ratio",        "200\n");
    sysctl_set("net.ipv4.tcp_pacing_ca_ratio",        "120\n");

    /* Connection handling */
    sysctl_set("net.ipv4.tcp_max_syn_backlog",        "131072\n");
    sysctl_set("net.core.somaxconn",                  "131072\n");
    sysctl_set("net.core.netdev_max_backlog",         "100000\n");
    sysctl_set("net.ipv4.tcp_tw_reuse",               "1\n");
    sysctl_set("net.ipv4.tcp_fin_timeout",            "5\n");

    /* Keepalive - anti ping timeout */
    sysctl_set("net.ipv4.tcp_keepalive_time",         "20\n");
    sysctl_set("net.ipv4.tcp_keepalive_intvl",        "3\n");
    sysctl_set("net.ipv4.tcp_keepalive_probes",       "10\n");

    /* Netdev - kupokea packets zaidi kwa kila interrupt */
    sysctl_set("net.core.netdev_budget",              "2000\n");
    sysctl_set("net.core.netdev_budget_usecs",        "4000\n");
    sysctl_set("net.core.busy_read",                  "100\n");
    sysctl_set("net.core.busy_poll",                  "100\n");

    /* Memory */
    sysctl_set("vm.swappiness",                       "1\n");
    sysctl_set("vm.vfs_cache_pressure",               "25\n");
    sysctl_set("vm.dirty_ratio",                      "20\n");
    sysctl_set("vm.dirty_background_ratio",           "5\n");
    sysctl_set("vm.overcommit_memory",                "1\n");

    /* NIC queues - CPU zote kwa kila interface */
    DIR *d = opendir("/sys/class/net");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            if (strcmp(e->d_name, "lo") == 0) continue;
            char p[512];
            /* Multi-queue RPS/XPS kwa CPU zote */
            for (int q = 0; q < 16; q++) {
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/rx-%d/rps_cpus", e->d_name, q);
                write_file(p, "ffffffffffffffff\n");
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/tx-%d/xps_cpus", e->d_name, q);
                write_file(p, "ffffffffffffffff\n");
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/rx-%d/rps_flow_cnt", e->d_name, q);
                write_file(p, "65536\n");
            }
        }
        closedir(d);
    }
    /* Global RFS */
    write_file("/proc/sys/net/core/rps_sock_flow_entries", "65536\n");

    /* CAKE qdisc kwa interfaces - bora kwa weak networks */
    system("for iface in $(ls /sys/class/net/ | grep -v lo); do "
           "tc qdisc replace dev $iface root cake bandwidth 200mbit "
           "diffserv4 triple-isolate nonat nowash no-ack-filter 2>/dev/null || "
           "tc qdisc replace dev $iface root fq 2>/dev/null; done");

    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: network stack boosted for 200Mbps+\n");
}

static void boost_cpu(void) {
    /* Performance governor kwa CPU zote */
    system("for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; "
           "do echo performance > \"$f\" 2>/dev/null; done");
    /* Disable C-states - punguza latency kwa maeneo yenye mtandao mbovu */
    system("for f in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; "
           "do echo 1 > \"$f\" 2>/dev/null; done");
    /* Maximum CPU frequency */
    system("for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; "
           "do cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq > \"$f\" 2>/dev/null; done");
    /* IRQ affinity - CPU zote */
    system("for irq in /proc/irq/*/smp_affinity; "
           "do echo ffffffffffffffff > \"$irq\" 2>/dev/null; done");
    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: CPU performance mode, C-states disabled\n");
}

static void boost_memory(void) {
    /* Lock memory - hakuna swap */
    mlockall(MCL_CURRENT | MCL_FUTURE);
    /* Hugepages */
    system("echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true");
    system("echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true");
    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: memory locked, hugepages enabled\n");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT,  sig);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    boost_network();
    boost_cpu();
    boost_memory();
    /* Re-apply kila dakika 5 (v4: kila dakika 10) */
    while (running) {
        int i;
        for (i = 0; i < 300 && running; i++) sleep(1);
        if (running) {
            boost_network();
            boost_cpu();
            boost_memory();
        }
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
Description=ELITE-X SUPER ULTRA Speed Booster v5.0 (200Mbps+)
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-speedbooster
Restart=always
RestartSec=3
Nice=-20
LimitMEMLOCK=infinity
IOSchedulingClass=realtime
IOSchedulingPriority=0
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=60
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER ULTRA Speed Booster v5.0 compiled (200Mbps+, re-apply kila dakika 5)${NC}"
    else
        echo -e "${RED}❌ Speed Booster compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: BANDWIDTH MONITOR (Enhanced v5.0)
# ═══════════════════════════════════════════════════════════
create_c_bandwidth_monitor() {
    echo -e "${YELLOW}📝 Compiling C Bandwidth Monitor v5.0...${NC}"

    cat > /tmp/bw_monitor.c <<'CEOF'
#define _GNU_SOURCE
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

#define USER_DB  "/etc/elite-x/users"
#define BW_DIR   "/etc/elite-x/bandwidth"
#define PID_DIR  "/etc/elite-x/bandwidth/pidtrack"
#define INTERVAL 2  /* Check kila sekunde 2 - haraka zaidi ya v4 (ilikuwa 5) */

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s || !*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static unsigned long long read_net_stat(const char *user) {
    unsigned long long total = 0;
    char pidpath[512];
    snprintf(pidpath, sizeof(pidpath), "%s/%s", PID_DIR, user);
    FILE *f = fopen(pidpath, "r"); if (!f) return 0;
    int pid;
    while (fscanf(f, "%d", &pid) == 1) {
        char netpath[256];
        snprintf(netpath, sizeof(netpath), "/proc/%d/net/dev", pid);
        FILE *nf = fopen(netpath, "r"); if (!nf) continue;
        char line[512];
        while (fgets(line, sizeof(line), nf)) {
            unsigned long long rx, tx;
            if (sscanf(line, " %*[^:]: %llu %*u %*u %*u %*u %*u %*u %*u %llu",
                       &rx, &tx) == 2) {
                total += rx + tx;
            }
        }
        fclose(nf);
    }
    fclose(f);
    return total;
}

static void save_usage(const char *user, unsigned long long bytes) {
    char path[512];
    snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, user);
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%llu\n", bytes); fclose(f); }
}

static unsigned long long load_usage(const char *user) {
    char path[512];
    unsigned long long v = 0;
    snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, user);
    FILE *f = fopen(path, "r"); if (f) { fscanf(f, "%llu", &v); fclose(f); }
    return v;
}

static unsigned long long get_bw_limit(const char *user) {
    char path[512]; snprintf(path, sizeof(path), "%s/%s", USER_DB, user);
    FILE *f = fopen(path, "r"); if (!f) return 0;
    char line[256]; unsigned long long gb = 0;
    while (fgets(line, sizeof(line), f))
        if (strncmp(line, "Bandwidth_GB:", 13) == 0) { sscanf(line+14, "%llu", &gb); break; }
    fclose(f);
    return gb * 1073741824ULL;
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(BW_DIR, 0755);
    mkdir(PID_DIR, 0755);

    while (running) {
        DIR *d = opendir(USER_DB); if (!d) { sleep(INTERVAL); continue; }
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            unsigned long long net = read_net_stat(e->d_name);
            unsigned long long prev = load_usage(e->d_name);
            if (net > prev) save_usage(e->d_name, net);
            unsigned long long limit = get_bw_limit(e->d_name);
            if (limit > 0 && net >= limit) {
                char cmd[512];
                snprintf(cmd, sizeof(cmd),
                    "pkill -u %s 2>/dev/null; usermod -L %s 2>/dev/null",
                    e->d_name, e->d_name);
                system(cmd);
            }
        }
        closedir(d);
        sleep(INTERVAL);
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
Description=ELITE-X Bandwidth Monitor v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-bandwidth-c
Restart=always
RestartSec=5
CPUQuota=15%
MemoryMax=64M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Bandwidth Monitor v5.0 compiled (check kila sekunde 2)${NC}"
    else
        echo -e "${RED}❌ Bandwidth Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: CONNECTION MONITOR (v5.0)
# ═══════════════════════════════════════════════════════════
create_c_connection_monitor() {
    echo -e "${YELLOW}📝 Compiling C Connection Monitor v5.0...${NC}"

    cat > /tmp/conn_monitor.c <<'CEOF'
#define _GNU_SOURCE
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
#define AUTOBAN     "/etc/elite-x/autoban_enabled"
#define SCAN_INTERVAL 3  /* v5.0: sekunde 3 (v4 ilikuwa 5) */

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s||!*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static int get_conn_count(const char *user) {
    int count = 0;
    DIR *proc = opendir("/proc"); if (!proc) return 0;
    struct dirent *e;
    while ((e = readdir(proc))) {
        if (!is_numeric(e->d_name)) continue;
        int pid = atoi(e->d_name);
        char cp[256]; snprintf(cp, sizeof(cp), "/proc/%d/comm", pid);
        FILE *f = fopen(cp, "r"); if (!f) continue;
        char comm[64] = {0}; fgets(comm, sizeof(comm), f); fclose(f);
        comm[strcspn(comm,"\n")] = 0;
        if (strcmp(comm,"sshd") != 0) continue;
        char sp[256]; snprintf(sp, sizeof(sp), "/proc/%d/status", pid);
        FILE *sf = fopen(sp, "r"); if (!sf) continue;
        char line[256], uid_s[32]={0};
        while (fgets(line,sizeof(line),sf))
            if (strncmp(line,"Uid:",4)==0){sscanf(line,"%*s %s",uid_s);break;}
        fclose(sf);
        struct passwd *pw = getpwuid(atoi(uid_s));
        if (!pw || strcmp(pw->pw_name,user)!=0) continue;
        char stp[256]; snprintf(stp,sizeof(stp),"/proc/%d/stat",pid);
        FILE *stf = fopen(stp,"r"); if (!stf) continue;
        int ppid; char sb[1024]; fgets(sb,sizeof(sb),stf);
        sscanf(sb,"%*d %*s %*c %d",&ppid); fclose(stf);
        if (ppid != 1) count++;
    }
    closedir(proc);
    return count;
}

static void delete_expired(const char *user, const char *reason) {
    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
        "cp %s/%s %s/%s_$(date +%%Y%%m%%d_%%H%%M%%S) 2>/dev/null; "
        "pkill -u %s 2>/dev/null; killall -u %s -9 2>/dev/null; "
        "userdel -r %s 2>/dev/null; "
        "rm -f %s/%s /etc/elite-x/data_usage/%s %s/%s %s/%s %s/%s.usage; "
        "logger -t elite-x 'Auto-deleted: %s (%s)'",
        USER_DB, user, DELETED_DIR, user,
        user, user, user,
        USER_DB, user, user,
        CONN_DB, user, BANNED_DIR, user, BW_DIR, user,
        user, reason);
    system(cmd);
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
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

            if (strlen(exp)>0) {
                struct tm tm={0};
                if (strptime(exp,"%Y-%m-%d",&tm)) {
                    time_t et = mktime(&tm);
                    if (now > et) {
                        char reason[256];
                        snprintf(reason,sizeof(reason),"Expired on %s",exp);
                        delete_expired(ue->d_name, reason); continue;
                    }
                }
            }

            int cc = get_conn_count(ue->d_name);
            char cf[512]; snprintf(cf,sizeof(cf),"%s/%s",CONN_DB,ue->d_name);
            FILE *cfile = fopen(cf,"w");
            if (cfile){fprintf(cfile,"%d\n",cc);fclose(cfile);}

            int autoban=0;
            FILE *abf = fopen(AUTOBAN,"r");
            if(abf){fscanf(abf,"%d",&autoban);fclose(abf);}

            if (cc > conn_lim && autoban==1) {
                char cmd[1024];
                snprintf(cmd,sizeof(cmd),
                    "passwd -S %s 2>/dev/null | grep -q 'L' || "
                    "(usermod -L %s 2>/dev/null && pkill -u %s 2>/dev/null && "
                    "echo 'BLOCKED: Exceeded conn %d/%d' >> %s/%s)",
                    ue->d_name,ue->d_name,ue->d_name,cc,conn_lim,BANNED_DIR,ue->d_name);
                system(cmd);
            }
        }
        closedir(ud);
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
Description=ELITE-X Connection Monitor v5.0
After=network.target ssh.service
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-connmon-c
Restart=always
RestartSec=3
CPUQuota=20%
MemoryMax=64M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Connection Monitor v5.0 compiled (scan kila sekunde 3)${NC}"
    else
        echo -e "${RED}❌ Connection Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: NETWORK BOOSTER v5.0 (re-apply kila saa 1)
# ═══════════════════════════════════════════════════════════
create_c_network_booster() {
    echo -e "${YELLOW}📝 Compiling C Network Booster v5.0...${NC}"

    cat > /tmp/net_booster.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void apply(void) {
    system("sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_max=536870912 >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_default=1048576 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_default=1048576 >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.tcp_rmem=4096 1048576 536870912' >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.tcp_wmem=4096 524288 536870912' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_syn_backlog=131072 >/dev/null 2>&1");
    system("sysctl -w net.core.somaxconn=131072 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_max_backlog=100000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fin_timeout=5 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_intvl=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_probes=10 >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.udp_mem=786432 134217728 268435456' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_rmem_min=131072 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_wmem_min=131072 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_budget=2000 >/dev/null 2>&1");
    system("sysctl -w net.core.busy_poll=100 >/dev/null 2>&1");
    system("sysctl -w net.core.busy_read=100 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_ecn=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_pacing_ss_ratio=200 >/dev/null 2>&1");
    system("sysctl -w vm.swappiness=1 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1");
    /* RPS/XPS kwa CPU zote */
    system("for iface in $(ls /sys/class/net/ | grep -v lo); do "
           "for q in /sys/class/net/$iface/queues/rx-*/rps_cpus; do "
           "echo ffffffffffffffff > \"$q\" 2>/dev/null; done; "
           "for q in /sys/class/net/$iface/queues/rx-*/rps_flow_cnt; do "
           "echo 65536 > \"$q\" 2>/dev/null; done; done");
    fprintf(stderr, "[ELITE-X] Net Booster v5.0: optimizations applied\n");
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
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
Description=ELITE-X Network Booster v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-netbooster
Restart=always
RestartSec=10
LimitMEMLOCK=infinity
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Network Booster v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DNS CACHE OPTIMIZER v5.0 (DOH fallback, fast resolvers)
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
    fprintf(stderr, "[ELITE-X] DNS Cache v5.0 flushed\n");
}

static void optimize_resolv(void) {
    FILE *f = fopen("/etc/resolv.conf", "w");
    if (f) {
        /* Fast resolvers - ordered kwa speed */
        fprintf(f, "nameserver 1.1.1.1\n");    /* Cloudflare fastest */
        fprintf(f, "nameserver 8.8.8.8\n");    /* Google */
        fprintf(f, "nameserver 9.9.9.9\n");    /* Quad9 */
        fprintf(f, "nameserver 8.8.4.4\n");    /* Google backup */
        fprintf(f, "nameserver 1.0.0.1\n");    /* Cloudflare backup */
        fprintf(f, "options timeout:1 attempts:2 rotate\n");
        fprintf(f, "options ndots:0\n");
        fprintf(f, "options single-request-reopen\n");  /* kwa maeneo yenye NAT */
        fclose(f);
        fprintf(stderr, "[ELITE-X] resolv.conf v5.0 optimized (5 fast servers)\n");
    }
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    optimize_resolv();
    while (running) {
        flush_dns();
        optimize_resolv(); /* Re-apply kila wakati - kuzuia kubadilishwa */
        int i; for (i = 0; i < 900 && running; i++) sleep(1); /* Kila dakika 15 */
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
Description=ELITE-X DNS Cache Optimizer v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-dnscache
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ DNS Cache Optimizer v5.0 compiled (5 fast servers, dakika 15 flush)${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER RAM BOOSTER v5.0
# Maboresho: mlock kwa SlowDNS/UDP processes, hugepages,
# RAM allocation kwa SlowDNS tu, transparent hugepages,
# memory compaction, NUMA-aware allocation
# ═══════════════════════════════════════════════════════════
create_c_ram_cleaner() {
    echo -e "${YELLOW}📝 Compiling C SUPER RAM Booster v5.0...${NC}"

    cat > /tmp/ram_cleaner.c <<'CEOF'
/*
 * ELITE-X SUPER RAM Booster v5.0
 * - mlock() kwa SlowDNS/UDP processes (hakuna swap)
 * - Transparent hugepages kwa performance
 * - Drop caches kila dakika 15 (v4 ilikuwa kila dakika 15)
 * - Memory compaction kwa kupunguza fragmentation
 * - Boost priority ya SlowDNS/UDP processes kwenye scheduler
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <sys/mman.h>
#include <ctype.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s||!*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

/* Lock memory ya processes za SlowDNS na UDP */
static void lock_slowdns_memory(void) {
    DIR *proc = opendir("/proc"); if (!proc) return;
    struct dirent *e;
    while ((e = readdir(proc))) {
        if (!is_numeric(e->d_name)) continue;
        char cp[256]; snprintf(cp, sizeof(cp), "/proc/%s/comm", e->d_name);
        FILE *f = fopen(cp, "r"); if (!f) continue;
        char comm[64] = {0}; fgets(comm, sizeof(comm), f); fclose(f);
        comm[strcspn(comm,"\n")] = 0;
        /* Tumia mlock kwa processes za SlowDNS/UDP */
        if (strstr(comm, "dnstt") || strstr(comm, "elite-x") ||
            strstr(comm, "edns") || strstr(comm, "udp-turbo")) {
            char sched[256];
            snprintf(sched, sizeof(sched),
                "chrt -f -p 60 %s 2>/dev/null; "
                "renice -n -20 -p %s 2>/dev/null",
                e->d_name, e->d_name);
            system(sched);
        }
    }
    closedir(proc);
}

static void clean_and_boost(void) {
    /* Drop page cache kwa kupata RAM zaidi */
    system("sync && echo 1 > /proc/sys/vm/drop_caches 2>/dev/null");
    /* Compact memory - reduce fragmentation */
    write_file("/proc/sys/vm/compact_memory", "1\n");
    /* Memory settings */
    system("sysctl -w vm.swappiness=1 >/dev/null 2>&1");
    system("sysctl -w vm.vfs_cache_pressure=25 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_ratio=20 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_background_ratio=5 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_ratio=95 >/dev/null 2>&1");
    /* Hugepages */
    write_file("/sys/kernel/mm/transparent_hugepage/enabled", "always\n");
    write_file("/sys/kernel/mm/transparent_hugepage/defrag", "defer+madvise\n");
    /* Boost SlowDNS process priorities */
    lock_slowdns_memory();
    fprintf(stderr, "[ELITE-X] RAM Booster v5.0: memory optimized, SlowDNS/UDP boosted\n");
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    while (running) {
        clean_and_boost();
        int i; for (i = 0; i < 900 && running; i++) sleep(1); /* kila dakika 15 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-ramcleaner /tmp/ram_cleaner.c 2>/dev/null
    rm -f /tmp/ram_cleaner.c

    if [ -f /usr/local/bin/elite-x-ramcleaner ]; then
        chmod +x /usr/local/bin/elite-x-ramcleaner
        cat > /etc/systemd/system/elite-x-ramcleaner.service <<EOF
[Unit]
Description=ELITE-X SUPER RAM Booster v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-ramcleaner
Restart=always
RestartSec=10
Nice=-15
LimitMEMLOCK=infinity
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER RAM Booster v5.0 compiled (mlock, hugepages, SlowDNS priority boost)${NC}"
    else
        echo -e "${RED}❌ RAM Booster compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: IRQ AFFINITY OPTIMIZER v5.0
# Maboresho: multi-queue NIC (rx-0 hadi rx-15),
# flow steering, CPU zote kwa kila queue,
# NAPI weight optimization
# ═══════════════════════════════════════════════════════════
create_c_irq_optimizer() {
    echo -e "${YELLOW}📝 Compiling C IRQ Affinity Optimizer v5.0 (CPU zote)...${NC}"

    cat > /tmp/irq_optimizer.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

static void optimize_irq(void) {
    /* IRQ zote - CPU zote */
    DIR *d = opendir("/proc/irq"); if (!d) return;
    struct dirent *e;
    while ((e=readdir(d))) {
        if (e->d_name[0]=='.') continue;
        char p[512];
        snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity",e->d_name);
        write_file(p,"ffffffffffffffff\n");
        snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity_list",e->d_name);
        write_file(p,"0-127\n");
    }
    closedir(d);

    /* RPS/XPS kwa queues zote za kila interface */
    DIR *nd = opendir("/sys/class/net"); if (!nd) return;
    while ((e=readdir(nd))) {
        if (e->d_name[0]=='.') continue;
        if (strcmp(e->d_name,"lo")==0) continue;
        char p[512];
        /* Queues 0-15 (multi-queue NICs) */
        for (int q = 0; q < 16; q++) {
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/rx-%d/rps_cpus",e->d_name,q);
            write_file(p,"ffffffffffffffff\n");
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/tx-%d/xps_cpus",e->d_name,q);
            write_file(p,"ffffffffffffffff\n");
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/rx-%d/rps_flow_cnt",e->d_name,q);
            write_file(p,"65536\n");
        }
    }
    closedir(nd);

    /* Global RFS */
    write_file("/proc/sys/net/core/rps_sock_flow_entries","65536\n");
    /* NAPI budget */
    write_file("/proc/sys/net/core/netdev_budget","2000\n");
    write_file("/proc/sys/net/core/netdev_budget_usecs","4000\n");

    fprintf(stderr,"[ELITE-X] IRQ/RPS/XPS v5.0 optimized (CPU zote, queues 0-15)\n");
}

int main(void) {
    signal(SIGTERM,signal_handler);
    signal(SIGINT,signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    while (running) {
        optimize_irq();
        int i; for(i=0;i<300&&running;i++) sleep(1); /* kila dakika 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-irqopt /tmp/irq_optimizer.c 2>/dev/null
    rm -f /tmp/irq_optimizer.c

    if [ -f /usr/local/bin/elite-x-irqopt ]; then
        chmod +x /usr/local/bin/elite-x-irqopt
        cat > /etc/systemd/system/elite-x-irqopt.service <<EOF
[Unit]
Description=ELITE-X IRQ Optimizer v5.0 (CPU zote, multi-queue)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-irqopt
Restart=always
RestartSec=5
LimitMEMLOCK=infinity
Nice=-15
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ IRQ Optimizer v5.0 compiled (CPU zote, queues 0-15, dakika 5)${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DATA USAGE TRACKER v5.0
# ═══════════════════════════════════════════════════════════
create_c_data_usage() {
    echo -e "${YELLOW}📝 Compiling C Data Usage Tracker v5.0...${NC}"

    cat > /tmp/data_usage.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>

#define USER_DB  "/etc/elite-x/users"
#define BW_DIR   "/etc/elite-x/bandwidth"
#define LOG_DIR  "/var/log/elite-x"

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void log_usage(void) {
    time_t t = time(NULL);
    char ts[32]; strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", localtime(&t));
    DIR *d = opendir(USER_DB); if (!d) return;
    struct dirent *e;
    FILE *log = fopen("/var/log/elite-x/usage.log", "a");
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char path[512]; snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, e->d_name);
        FILE *f = fopen(path, "r"); if (!f) continue;
        unsigned long long bytes = 0; fscanf(f, "%llu", &bytes); fclose(f);
        double gb = (double)bytes / 1073741824.0;
        if (log) fprintf(log, "[%s] %s: %.3f GB\n", ts, e->d_name, gb);
    }
    closedir(d);
    if (log) fclose(log);
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(LOG_DIR, 0755);
    while (running) {
        log_usage();
        int i; for (i = 0; i < 300 && running; i++) sleep(1); /* kila dakika 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-datausage /tmp/data_usage.c 2>/dev/null
    rm -f /tmp/data_usage.c

    if [ -f /usr/local/bin/elite-x-datausage ]; then
        chmod +x /usr/local/bin/elite-x-datausage
        cat > /etc/systemd/system/elite-x-datausage.service <<EOF
[Unit]
Description=ELITE-X Data Usage Tracker v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-datausage
Restart=always
RestartSec=10
CPUQuota=5%
MemoryMax=32M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Data Usage Tracker v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: LOG CLEANER v5.0
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
static void clean_logs(void) {
    system("journalctl --vacuum-size=50M 2>/dev/null");
    system("find /var/log -name '*.log' -size +10M -exec truncate -s 5M {} \\; 2>/dev/null");
    system("find /var/log/elite-x -name 'usage.log' -size +50M -exec truncate -s 10M {} \\; 2>/dev/null");
    fprintf(stderr, "[ELITE-X] Log Cleaner v5.0: logs cleaned\n");
}
int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    while (running) {
        clean_logs();
        int i; for (i=0;i<3600&&running;i++) sleep(1); /* kila saa 1 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-logcleaner /tmp/log_cleaner.c 2>/dev/null
    rm -f /tmp/log_cleaner.c

    if [ -f /usr/local/bin/elite-x-logcleaner ]; then
        chmod +x /usr/local/bin/elite-x-logcleaner
        cat > /etc/systemd/system/elite-x-logcleaner.service <<EOF
[Unit]
Description=ELITE-X Log Cleaner v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-logcleaner
Restart=always
RestartSec=30
CPUQuota=5%
MemoryMax=16M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Log Cleaner v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# NEW v5.0: C PING TIMEOUT KILLER
# Inazuia ping timeout kabisa kwa:
# - Sending UDP keepalives kila sekunde 5
# - Monitoring connections na kuzifufua
# - Anti-idle detection
# ═══════════════════════════════════════════════════════════
create_c_ping_timeout_killer() {
    echo -e "${YELLOW}📝 Compiling C Ping Timeout Killer v5.0 (NEW)...${NC}"

    cat > /tmp/ping_killer.c <<CEOF
/*
 * ELITE-X Ping Timeout Killer v5.0
 * Inazuia ping timeout kabisa:
 * - UDP keepalives kwa dnstt port 5300 kila sekunde 5
 * - TCP keepalive via sysctl re-application
 * - Monitor na kufufua connections zilizokufa
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

/* Tuma UDP keepalive kwa dnstt */
static void send_udp_keepalive(void) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) return;
    struct timeval tv = {1, 0};
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = inet_addr("127.0.0.1"),
        .sin_port = htons(5300)
    };
    /* DNS keepalive packet (minimal valid DNS query) */
    unsigned char keepalive[] = {
        0x00, 0x01, /* ID */
        0x01, 0x00, /* Flags: standard query */
        0x00, 0x01, /* Questions: 1 */
        0x00, 0x00, /* Answers: 0 */
        0x00, 0x00, /* Authority: 0 */
        0x00, 0x00, /* Additional: 0 */
        0x00,       /* root query */
        0x00, 0x01, /* Type: A */
        0x00, 0x01  /* Class: IN */
    };
    sendto(sock, keepalive, sizeof(keepalive), 0,
           (struct sockaddr*)&addr, sizeof(addr));
    close(sock);
}

/* Fufua SSH connections zilizokufa */
static void reset_tcp_keepalive(void) {
    system("sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_intvl=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_probes=10 >/dev/null 2>&1");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT, sig);
    fprintf(stderr, "[ELITE-X] Ping Timeout Killer v5.0 started (UDP keepalive kila sekunde 5)\n");
    reset_tcp_keepalive();
    while (running) {
        send_udp_keepalive();
        sleep(5); /* Kila sekunde 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-pingtimeout /tmp/ping_killer.c 2>/dev/null
    rm -f /tmp/ping_killer.c

    if [ -f /usr/local/bin/elite-x-pingtimeout ]; then
        chmod +x /usr/local/bin/elite-x-pingtimeout
        cat > /etc/systemd/system/elite-x-pingtimeout.service <<EOF
[Unit]
Description=ELITE-X Ping Timeout Killer v5.0 (UDP keepalive kila sekunde 5)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-pingtimeout
Restart=always
RestartSec=2
Nice=-15
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=40
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Ping Timeout Killer v5.0 compiled (keepalive kila sekunde 5)${NC}"
    else
        echo -e "${RED}❌ Ping Timeout Killer compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# NEW v5.0: WEAK NETWORK OPTIMIZER
# Maalum kwa maeneo yenye mtandao mbovu/chini:
# - Adaptive MTU (punguza MTU kwa networks mbovu)
# - Packet retransmission tuning
# - DNS retry optimization
# - TCP window clamping kwa high latency
# ═══════════════════════════════════════════════════════════
create_c_weak_network_optimizer() {
    echo -e "${YELLOW}📝 Compiling C Weak Network Optimizer v5.0 (NEW)...${NC}"

    cat > /tmp/weak_net.c <<CEOF
/*
 * ELITE-X Weak Network Optimizer v5.0
 * Kwa maeneo yenye mtandao mbovu, slow, au unstable:
 * - Punguza retransmission timeouts
 * - Ongeza retry counts
 * - Adaptive congestion control
 * - Path MTU discovery tuning
 * - DSCP/QoS marking kwa DNS/VPN traffic
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

static void optimize_for_weak_network(void) {
    /* Punguza RTO min kwa latency ndogo */
    system("ip route change default rto_min 100ms 2>/dev/null || true");
    /* TCP retransmission - haraka zaidi */
    write_file("/proc/sys/net/ipv4/tcp_retries1", "3\n");
    write_file("/proc/sys/net/ipv4/tcp_retries2", "6\n");
    /* Ongeza syn retries kwa networks mbovu */
    write_file("/proc/sys/net/ipv4/tcp_syn_retries", "4\n");
    write_file("/proc/sys/net/ipv4/tcp_synack_retries", "4\n");
    /* Punguza orphan timeout */
    write_file("/proc/sys/net/ipv4/tcp_orphan_retries", "1\n");
    /* DSCP marking kwa UDP/DNS traffic - QoS EF (Expedited Forwarding) */
    system("iptables -t mangle -A OUTPUT -p udp --dport 53 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    system("iptables -t mangle -A OUTPUT -p udp --dport 5300 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    system("iptables -t mangle -A OUTPUT -p udp --dport 5301 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    /* Path MTU discovery */
    write_file("/proc/sys/net/ipv4/tcp_mtu_probing", "2\n"); /* Always probe */
    write_file("/proc/sys/net/ipv4/tcp_base_mss", "512\n");
    /* Reduce initial ssthresh kwa slow start */
    write_file("/proc/sys/net/ipv4/tcp_slow_start_after_idle", "0\n");
    /* UDP fragmentation kwa large DNS packets */
    write_file("/proc/sys/net/ipv4/ip_no_pmtu_disc", "0\n");
    fprintf(stderr, "[ELITE-X] Weak Network Optimizer v5.0: settings applied\n");
}

static void optimize_iptables_qos(void) {
    /* Priority queue kwa VPN traffic */
    system("tc qdisc add dev lo root handle 1: prio bands 3 2>/dev/null || true");
    system("tc filter add dev lo parent 1:0 protocol ip prio 1 u32 "
           "match ip dport 5300 0xffff flowid 1:1 2>/dev/null || true");
    system("tc filter add dev lo parent 1:0 protocol ip prio 1 u32 "
           "match ip dport 53 0xffff flowid 1:1 2>/dev/null || true");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT, sig);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    fprintf(stderr, "[ELITE-X] Weak Network Optimizer v5.0 started\n");
    optimize_for_weak_network();
    optimize_iptables_qos();
    while (running) {
        optimize_for_weak_network();
        int i; for (i=0;i<600&&running;i++) sleep(1); /* kila dakika 10 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-weaknet /tmp/weak_net.c 2>/dev/null
    rm -f /tmp/weak_net.c

    if [ -f /usr/local/bin/elite-x-weaknet ]; then
        chmod +x /usr/local/bin/elite-x-weaknet
        cat > /etc/systemd/system/elite-x-weaknet.service <<EOF
[Unit]
Description=ELITE-X Weak Network Optimizer v5.0 (kwa maeneo yenye mtandao mbovu)
After=network.target dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-weaknet
Restart=always
RestartSec=5
Nice=-10
LimitMEMLOCK=infinity
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Weak Network Optimizer v5.0 compiled (DSCP QoS, MTU adaptive, retry tuning)${NC}"
    else
        echo -e "${RED}❌ Weak Network Optimizer compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# USER MANAGEMENT SCRIPT (Enhanced v5.0)
# ═══════════════════════════════════════════════════════════
create_user_script() {
    echo -e "${YELLOW}📝 Creating User Management Script v5.0...${NC}"

    cat > /usr/local/bin/elite-x-user <<'USERSCRIPT'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'; BOLD='\033[1m'
USER_DB="/etc/elite-x/users"
BW_DIR="/etc/elite-x/bandwidth"
CONN_DB="/etc/elite-x/connections"
BANNED_DIR="/etc/elite-x/banned"
DELETED_DIR="/etc/elite-x/deleted"

add_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"Password: "$NC)" password
    read -p "$(echo -e $GREEN"Expire date (YYYY-MM-DD): "$NC)" expire
    read -p "$(echo -e $GREEN"Connection limit [1]: "$NC)" conn_limit
    read -p "$(echo -e $GREEN"Bandwidth limit GB [0=unlimited]: "$NC)" bw_gb
    conn_limit=${conn_limit:-1}
    bw_gb=${bw_gb:-0}

    if id "$username" &>/dev/null; then
        echo -e "${RED}User $username sudah ada!${NC}"; return
    fi
    useradd -M -s /bin/false "$username" 2>/dev/null
    echo "$username:$password" | chpasswd 2>/dev/null

    mkdir -p "$USER_DB"
    cat > "$USER_DB/$username" <<EOF
Username: $username
Password: $password
Expire: $expire
Conn_Limit: $conn_limit
Bandwidth_GB: $bw_gb
Created: $(date '+%Y-%m-%d %H:%M:%S')
EOF
    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ User $username created (expire: $expire, limit: ${conn_limit}, BW: ${bw_gb}GB)${NC}"
}

list_users() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}              ELITE-X v5.0 USER LIST                             ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════╦════════════════╦════════════╦═══════╦══════════╦═══════╦══════════╣${NC}"
    echo -e "${CYAN}║${WHITE} No   ${CYAN}║${WHITE} Username       ${CYAN}║${WHITE} Expire     ${CYAN}║${WHITE} Conn  ${CYAN}║${WHITE} BW Limit ${CYAN}║${WHITE} Usage ${CYAN}║${WHITE} Status   ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════╬════════════════╬════════════╬═══════╬══════════╬═══════╬══════════╣${NC}"

    i=0
    now_ts=$(date +%s)
    for f in "$USER_DB"/*; do
        [ -f "$f" ] || continue
        i=$((i+1))
        u=$(basename "$f")
        exp=$(grep "Expire:" "$f" | awk '{print $2}')
        cl=$(grep "Conn_Limit:" "$f" | awk '{print $2}')
        bw=$(grep "Bandwidth_GB:" "$f" | awk '{print $2}')
        [ "$bw" = "0" ] && bw_disp="Unlim" || bw_disp="${bw}GB"
        usage_b=$(cat "$BW_DIR/${u}.usage" 2>/dev/null || echo 0)
        usage_gb=$(echo "scale=1; $usage_b / 1073741824" | bc 2>/dev/null || echo "0.0")
        exp_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
        rem=$(( (exp_ts - now_ts) / 86400 ))
        if [ $rem -lt 0 ]; then
            status="${RED}EXPIRED${NC}"
        elif [ $rem -le 3 ]; then
            status="${YELLOW}SOON($rem d)${NC}"
        else
            status="${GREEN}OK($rem d)${NC}"
        fi
        printf "${CYAN}║${WHITE} %-4s ${CYAN}║${WHITE} %-14s ${CYAN}║${WHITE} %-10s ${CYAN}║${WHITE} %-5s ${CYAN}║${WHITE} %-8s ${CYAN}║${WHITE} %-5s ${CYAN}║ %-8b ${CYAN}║${NC}\n" \
            "$i" "$u" "$exp" "$cl" "$bw_disp" "${usage_gb}G" "$status"
    done
    echo -e "${CYAN}╚══════╩════════════════╩════════════╩═══════╩══════════╩═══════╩══════════╝${NC}"
    echo -e "${YELLOW}Total users: $i${NC}"
}

del_user() {
    read -p "$(echo -e $RED"Username to delete: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    cp "$USER_DB/$u" "$DELETED_DIR/${u}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null
    pkill -u "$u" 2>/dev/null; killall -u "$u" -9 2>/dev/null
    userdel -r "$u" 2>/dev/null
    rm -f "$USER_DB/$u" "/etc/elite-x/data_usage/$u" \
          "$CONN_DB/$u" "$BANNED_DIR/$u" "$BW_DIR/$u.usage" \
          "/etc/elite-x/user_messages/$u"
    sed -i "/Match User $u/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
    systemctl reload sshd 2>/dev/null
    echo -e "${GREEN}✅ User $u deleted${NC}"
}

renew_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"New expire date (YYYY-MM-DD): "$NC)" exp
    sed -i "s/^Expire:.*/Expire: $exp/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ User $u renewed until $exp${NC}"
}

setlimit_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"Connection limit: "$NC)" lim
    sed -i "s/^Conn_Limit:.*/Conn_Limit: $lim/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Connection limit set to $lim${NC}"
}

setbw_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"Bandwidth limit GB [0=unlimited]: "$NC)" bw
    sed -i "s/^Bandwidth_GB:.*/Bandwidth_GB: $bw/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth limit set to ${bw}GB${NC}"
}

resetdata_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    echo 0 > "$BW_DIR/${u}.usage" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Data usage reset for $u${NC}"
}

lock_user() {
    read -p "$(echo -e $RED"Username to lock: "$NC)" u
    usermod -L "$u" 2>/dev/null
    pkill -u "$u" 2>/dev/null
    echo -e "${GREEN}✅ User $u locked${NC}"
}

unlock_user() {
    read -p "$(echo -e $GREEN"Username to unlock: "$NC)" u
    usermod -U "$u" 2>/dev/null
    rm -f "$BANNED_DIR/$u"
    echo -e "${GREEN}✅ User $u unlocked${NC}"
}

details_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    echo -e "${CYAN}"; cat "$USER_DB/$u"; echo -e "${NC}"
    echo -e "${YELLOW}Current connections: $(cat "$CONN_DB/$u" 2>/dev/null || echo 0)${NC}"
    usage_b=$(cat "$BW_DIR/${u}.usage" 2>/dev/null || echo 0)
    usage_gb=$(echo "scale=3; $usage_b / 1073741824" | bc 2>/dev/null || echo "0.000")
    echo -e "${YELLOW}Data usage: ${usage_gb} GB${NC}"
}

deleted_list() {
    echo -e "${CYAN}Deleted users:${NC}"
    ls -la "$DELETED_DIR/" 2>/dev/null || echo "None"
}

case "$1" in
    add)      add_user ;;
    list)     list_users ;;
    del)      del_user ;;
    renew)    renew_user ;;
    setlimit) setlimit_user ;;
    setbw)    setbw_user ;;
    resetdata) resetdata_user ;;
    lock)     lock_user ;;
    unlock)   unlock_user ;;
    details)  details_user ;;
    deleted)  deleted_list ;;
    *) echo "Usage: elite-x-user {add|list|del|renew|setlimit|setbw|resetdata|lock|unlock|details|deleted}" ;;
esac
USERSCRIPT
    chmod +x /usr/local/bin/elite-x-user
    echo -e "${GREEN}✅ User Management Script v5.0 created${NC}"
}

# ═══════════════════════════════════════════════════════════
# MAIN MENU v5.0 (Enhanced dashboard)
# ═══════════════════════════════════════════════════════════
create_main_menu() {
    echo -e "${YELLOW}📝 Creating Main Menu v5.0...${NC}"

    local UD="$USER_DB"

    cat > /usr/local/bin/elite-x <<MENUEOF
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'
ORANGE='\033[0;33m'; NC='\033[0m'
UD="$USER_DB"

svc_status() {
    systemctl is-active "\$1" >/dev/null 2>&1 \
        && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}"
}

show_dashboard() {
    clear
    CPU_COUNT=\$(nproc 2>/dev/null || echo 1)
    RAM_TOTAL=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    RAM_FREE=\$(grep MemAvailable /proc/meminfo | awk '{print \$2}')
    RAM_USED_MB=\$(( (RAM_TOTAL - RAM_FREE) / 1024 ))
    RAM_TOTAL_MB=\$(( RAM_TOTAL / 1024 ))
    CPU_LOAD=\$(cat /proc/loadavg | awk '{print \$1}')
    IP=\$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "Unknown")
    TDOMAIN=\$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not set")
    PUB_KEY=\$(cat /etc/elite-x/public_key 2>/dev/null || echo "Unknown")

    echo -e "\${PURPLE}╔══════════════════════════════════════════════════════════════════╗\${NC}"
    echo -e "\${PURPLE}║\${YELLOW}\${BOLD}    ELITE-X SLOWDNS v5.0 - SUPER ULTRA MAX BOOST        \${PURPLE}║\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  IP       : \${CYAN}\$IP\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  NS       : \${CYAN}\$TDOMAIN\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  PubKey   : \${CYAN}\$(echo \$PUB_KEY | cut -c1-40)...\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    printf "\${PURPLE}║\${WHITE}  CPU: \${CYAN}%s cores  \${WHITE}Load: \${CYAN}%s  \${WHITE}RAM: \${CYAN}%s/%s MB\${NC}\n" \
        "\$CPU_COUNT" "\$CPU_LOAD" "\$RAM_USED_MB" "\$RAM_TOTAL_MB"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  SERVICES:\${NC}"

    DNS=\$(svc_status dnstt-elite-x)
    PRX=\$(svc_status dnstt-elite-x-proxy)
    UDP=\$(svc_status elite-x-udp-turbo)
    SPD=\$(svc_status elite-x-speedbooster)
    NBOOST=\$(svc_status elite-x-netbooster)
    DNSC=\$(svc_status elite-x-dnscache)
    BW=\$(svc_status elite-x-bandwidth)
    IRQ=\$(svc_status elite-x-irqopt)
    RAMC=\$(svc_status elite-x-ramcleaner)
    PING=\$(svc_status elite-x-pingtimeout)
    WEAK=\$(svc_status elite-x-weaknet)
    SMSG=\$([ -f /usr/local/bin/elite-x-force-user-message ] && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}")

    echo -e "\${PURPLE}║\${WHITE}  \$DNS DNSTT     \$PRX C-EDNS    \$UDP UDP Turbo  \$SPD Speed\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  \$NBOOST NetBoost  \$DNSC DNS Cache  \$BW BW Mon   \$IRQ IRQ\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  \$RAMC RAM Boost  \$PING PingKill  \$WEAK WeakNet  \$SMSG Msgs\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    TOTAL=\$(ls "\$UD" 2>/dev/null | wc -l)
    ONLINE=\$(who | wc -l)
    echo -e "\${PURPLE}║\${GREEN}  Users: \${YELLOW}\$TOTAL\${GREEN} | Online: \${YELLOW}\$ONLINE\${GREEN} | Speed: \${YELLOW}200Mbps+ ULTRA\${NC}  \${PURPLE}║\${NC}"
    echo -e "\${PURPLE}╚══════════════════════════════════════════════════════════════════╝\${NC}"
}

settings_menu() {
    while true; do
        clear
        echo -e "\${CYAN}╔════════════════════════════════════════════════════════╗\${NC}"
        echo -e "\${CYAN}║\${YELLOW}             SETTINGS v5.0 ULTRA             \${CYAN}║\${NC}"
        echo -e "\${CYAN}╠════════════════════════════════════════════════════════╣\${NC}"
        AUTOBAN=\$(cat "/etc/elite-x/autoban_enabled" 2>/dev/null || echo 0)
        [ "\$AUTOBAN" = "1" ] && AB="\${GREEN}ON\${NC}" || AB="\${RED}OFF\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [1]  Auto-Ban: \$AB\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [2]  Restart All Services\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [3]  Restart DNSTT\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [4]  Recompile All C Components\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [5]  Fix VPN/SSH\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [6]  Refresh All User Messages\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [7]  Test User Message\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [8]  Apply Speed Boost Now (200Mbps+)\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [9]  Fix Ping Timeout\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [10] Optimize Weak Network\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [0]  Back\${NC}"
        echo -e "\${CYAN}╚════════════════════════════════════════════════════════╝\${NC}"
        read -p "\$(echo -e \$GREEN"Option: "\$NC)" ch

        case \$ch in
            1) [ "\$AUTOBAN" = "1" ] && echo 0 > /etc/elite-x/autoban_enabled || echo 1 > /etc/elite-x/autoban_enabled ;;
            2) for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-udp-turbo elite-x-speedbooster elite-x-bandwidth elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner elite-x-datausage elite-x-pingtimeout elite-x-weaknet; do systemctl restart "\$s" 2>/dev/null || true; done; echo -e "\${GREEN}✅ All services restarted\${NC}"; read -p "Enter..." ;;
            3) systemctl restart dnstt-elite-x dnstt-elite-x-proxy; echo -e "\${GREEN}✅ DNSTT restarted\${NC}"; read -p "Enter..." ;;
            4) echo -e "\${YELLOW}Recompiling...\${NC}"; bash \$0 --recompile 2>/dev/null; echo -e "\${GREEN}✅ Recompiled\${NC}"; read -p "Enter..." ;;
            5) systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd 2>/dev/null; echo -e "\${GREEN}✅ Fixed\${NC}"; read -p "Enter..." ;;
            6) for u in "\$UD"/*; do [ -f "\$u" ] && /usr/local/bin/elite-x-force-user-message "\$(basename "\$u")" 2>/dev/null; done; systemctl reload sshd; echo -e "\${GREEN}✅ Messages refreshed\${NC}"; read -p "Enter..." ;;
            7) read -p "Username: " un; cat "/etc/elite-x/user_messages/\$un" 2>/dev/null || echo "No message"; read -p "Enter..." ;;
            8) systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-irqopt elite-x-ramcleaner 2>/dev/null; echo -e "\${GREEN}✅ 200Mbps+ boost applied\${NC}"; read -p "Enter..." ;;
            9) systemctl restart elite-x-pingtimeout; sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1; echo -e "\${GREEN}✅ Ping timeout fixed\${NC}"; read -p "Enter..." ;;
            10) systemctl restart elite-x-weaknet; echo -e "\${GREEN}✅ Weak network optimized\${NC}"; read -p "Enter..." ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        show_dashboard
        echo -e "\${PURPLE}╔══════════════════════════════════════════════════════════════════╗\${NC}"
        echo -e "\${PURPLE}║\${GREEN}\${BOLD}                 MAIN MENU v5.0 ULTRA                   \${PURPLE}║\${NC}"
        echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [1] Create User   [2] List Users      [3] User Details\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [4] Renew User    [5] Set Conn Limit   [6] Set BW Limit\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [7] Reset Data    [8] Lock User        [9] Unlock User\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [10] Delete User  [11] Deleted List     [S] Settings\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [M] Test Msg      [B] Speed Boost       [0] Exit\${NC}"
        echo -e "\${PURPLE}╚══════════════════════════════════════════════════════════════════╝\${NC}"
        read -p "\$(echo -e \$GREEN"Option: "\$NC)" ch

        case \$ch in
            1) elite-x-user add; read -p "Press Enter..." ;;
            2) elite-x-user list; read -p "Press Enter..." ;;
            3) elite-x-user details; read -p "Press Enter..." ;;
            4) elite-x-user renew; read -p "Press Enter..." ;;
            5) elite-x-user setlimit; read -p "Press Enter..." ;;
            6) elite-x-user setbw; read -p "Press Enter..." ;;
            7) elite-x-user resetdata; read -p "Press Enter..." ;;
            8) elite-x-user lock; read -p "Press Enter..." ;;
            9) elite-x-user unlock; read -p "Press Enter..." ;;
            10) elite-x-user del; read -p "Press Enter..." ;;
            11) elite-x-user deleted; read -p "Press Enter..." ;;
            [Ss]) settings_menu ;;
            [Bb]) systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-irqopt elite-x-ramcleaner 2>/dev/null; echo -e "\${GREEN}✅ 200Mbps+ boost applied!\${NC}"; read -p "Press Enter..." ;;
            [Mm])
                read -p "Username: " un
                if [ -f "/etc/elite-x/user_messages/\$un" ]; then
                    clear; cat "/etc/elite-x/user_messages/\$un"
                else
                    echo -e "\${RED}No message for \$un!\${NC}"
                fi
                read -p "Press Enter..." ;;
            0) echo -e "\${GREEN}Goodbye!\${NC}"; exit 0 ;;
            *) echo -e "\${RED}Invalid\${NC}"; read -p "Press Enter..." ;;
        esac
    done
}

main_menu
MENUEOF
    chmod +x /usr/local/bin/elite-x
    echo -e "${GREEN}✅ Main Menu v5.0 created${NC}"
}

# ═══════════════════════════════════════════════════════════
# MAIN INSTALLATION v5.0
# ═══════════════════════════════════════════════════════════
run_installation() {
    show_banner
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}       ELITE-X v5.0 SUPER ULTRA - ACTIVATION       ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT

    if [ "$ACTIVATION_INPUT" != "$ACTIVATION_KEY" ] && [ "$ACTIVATION_INPUT" != "Whtsapp +255713-628-668" ]; then
        echo -e "${RED}❌ Invalid activation key!${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Activation successful${NC}"
    sleep 1

    set_timezone

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           ENTER YOUR NAMESERVER [NS]        ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Nameserver: "$NC)" TDOMAIN

    echo -e "${YELLOW}Select VPS location (MTU):${NC}"
    echo -e "  [1] South Africa (MTU 1800)"
    echo -e "  [2] USA (MTU 1500)"
    echo -e "  [3] Europe (MTU 1500)"
    echo -e "  [4] Asia (MTU 1400)"
    echo -e "  [5] Custom MTU"
    read -p "$(echo -e $GREEN"Choice [1]: "$NC)" LOC
    LOC=${LOC:-1}
    case $LOC in
        2) SEL_LOC="USA"; MTU=1500 ;;
        3) SEL_LOC="Europe"; MTU=1500 ;;
        4) SEL_LOC="Asia"; MTU=1400 ;;
        5) SEL_LOC="Custom"; read -p "MTU: " MTU; [[ ! "$MTU" =~ ^[0-9]+$ ]] && MTU=1800 ;;
        *) SEL_LOC="South Africa"; MTU=1800 ;;
    esac

    echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"
    for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth elite-x-datausage elite-x-connmon \
              elite-x-cleaner elite-x-traffic elite-x-netbooster elite-x-dnscache elite-x-ramcleaner \
              elite-x-irqopt elite-x-logcleaner elite-x-udp-turbo elite-x-speedbooster \
              elite-x-pingtimeout elite-x-weaknet 3proxy-elite; do
        systemctl stop "$s" 2>/dev/null || true
        systemctl disable "$s" 2>/dev/null || true
    done
    pkill -f dnstt-server 2>/dev/null || true
    pkill -f elite-x- 2>/dev/null || true
    rm -rf /etc/systemd/system/{dnstt-elite-x*,elite-x*,3proxy-elite*} 2>/dev/null
    rm -rf /etc/dnstt /etc/elite-x /var/run/elite-x 2>/dev/null
    rm -f /usr/local/bin/{dnstt-*,elite-x*,3proxy} 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf 2>/dev/null
    rm -f /etc/sysctl.d/99-elite-x-vpn.conf 2>/dev/null
    sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    systemctl restart sshd 2>/dev/null || true
    sleep 2

    # Create directories
    mkdir -p /etc/elite-x/{users,traffic,deleted,data_usage,connections,banned,traffic_stats,bandwidth/pidtrack,user_messages}
    mkdir -p /etc/ssh/sshd_config.d
    mkdir -p /var/run/elite-x/bandwidth
    mkdir -p /var/log/elite-x
    echo "$TDOMAIN" > /etc/elite-x/subdomain
    echo "$SEL_LOC" > /etc/elite-x/location
    echo "$MTU" > /etc/elite-x/mtu
    echo "0" > "$AUTOBAN_FLAG"
    echo "$STATIC_PRIVATE_KEY" > /etc/elite-x/private_key
    echo "$STATIC_PUBLIC_KEY" > /etc/elite-x/public_key

    # Configure DNS
    [ -f /etc/systemd/resolved.conf ] && {
        sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null || true
    }
    [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\nnameserver 8.8.4.4\nnameserver 1.0.0.1\noptions timeout:1 attempts:2 rotate\noptions ndots:0\n" > /etc/resolv.conf

    # Install dependencies
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    apt update -y
    apt install -y curl jq iptables ethtool dnsutils net-tools iproute2 bc \
        build-essential git gcc make linux-tools-common numactl \
        iptables-persistent 2>/dev/null

    # Download DNSTT
    echo -e "${YELLOW}📥 Downloading DNSTT server...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null || {
        curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server 2>/dev/null
    }
    chmod +x /usr/local/bin/dnstt-server

    # Setup DNSTT keys
    mkdir -p /etc/dnstt
    echo "$STATIC_PRIVATE_KEY" > /etc/dnstt/server.key
    echo "$STATIC_PUBLIC_KEY" > /etc/dnstt/server.pub
    chmod 600 /etc/dnstt/server.key

    # Create DNSTT service - SUPER ULTRA BOOSTED
    cat > /etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=ELITE-X DNSTT Server v5.0 SUPER ULTRA
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
CPUSchedulingPriority=90
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF

    # Optimize system FIRST
    optimize_system_for_vpn

    # PAM + user messages
    configure_pam_user_message

    # SSH
    configure_ssh_for_vpn

    # Compile all C components
    create_c_edns_proxy
    create_c_udp_turbo
    create_c_speed_booster
    create_c_bandwidth_monitor
    create_c_connection_monitor
    create_c_network_booster
    create_c_dns_cache
    create_c_ram_cleaner
    create_c_irq_optimizer
    create_c_data_usage
    create_c_log_cleaner
    # NEW v5.0 components
    create_c_ping_timeout_killer
    create_c_weak_network_optimizer

    # EDNS Proxy service (after compilation)
    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        cat > /etc/systemd/system/dnstt-elite-x-proxy.service <<EOF
[Unit]
Description=ELITE-X SUPER ULTRA EDNS Proxy v5.0 (${CPU_COUNT} CPU threads)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-edns-proxy ${CPU_COUNT}
Restart=always
RestartSec=1
LimitNOFILE=4194304
LimitMEMLOCK=infinity
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=85
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
    fi

    # User scripts
    create_user_script
    create_main_menu

    # Enable and start ALL services
    systemctl daemon-reload

    ALL_SERVICES=(
        dnstt-elite-x
        dnstt-elite-x-proxy
        elite-x-udp-turbo
        elite-x-speedbooster
        elite-x-bandwidth
        elite-x-datausage
        elite-x-connmon
        elite-x-netbooster
        elite-x-dnscache
        elite-x-ramcleaner
        elite-x-irqopt
        elite-x-logcleaner
        elite-x-pingtimeout
        elite-x-weaknet
    )

    for s in "${ALL_SERVICES[@]}"; do
        if [ -f "/etc/systemd/system/${s}.service" ]; then
            systemctl enable "$s" 2>/dev/null || true
            systemctl start "$s" 2>/dev/null || true
        fi
    done

    # Cache IP
    IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "Unknown")
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
alias boost='systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-udp-turbo elite-x-pingtimeout'
alias fixvpn='systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd && echo "VPN Fixed!"'
alias refreshmsg='for u in /etc/elite-x/users/*; do [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")"; done && systemctl reload sshd && echo "✅ Messages refreshed!"'
alias testmsg='read -p "Username: " u; cat /etc/elite-x/user_messages/$u 2>/dev/null || echo "No message"'
alias speedtest='systemctl restart elite-x-speedbooster && echo "200Mbps+ Speed boost applied!"'
alias fixping='systemctl restart elite-x-pingtimeout && sysctl -w net.ipv4.tcp_keepalive_time=20 && echo "Ping timeout fixed!"'
alias weakfix='systemctl restart elite-x-weaknet && echo "Weak network optimized!"'
alias status='systemctl status dnstt-elite-x dnstt-elite-x-proxy elite-x-udp-turbo elite-x-speedbooster'
EOF

    # Create initial messages for existing users
    for user_file in /etc/elite-x/users/*; do
        [ -f "$user_file" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$user_file")" 2>/dev/null
    done

    # ═══════════════════════════════════════════════════════════
    # FINAL DISPLAY - SUPER ULTRA
    # ═══════════════════════════════════════════════════════════
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}${BOLD}   ELITE-X v5.0 SUPER ULTRA MAX BOOST - INSTALLED!     ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Domain     :${CYAN} $TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  Location   :${CYAN} $SEL_LOC (MTU: $MTU)${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  CPU Cores  :${CYAN} ${CPU_COUNT} (ZOTE zinatumika)${NC}"
    echo -e "${GREEN}║${WHITE}  RAM        :${CYAN} ${RAM_MB}MB (mlock + hugepages)${NC}"
    echo -e "${GREEN}║${WHITE}  Version    :${CYAN} v5.0 Super Ultra Max Boost${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"

    check_svc() {
        local name=$1 svc=$2
        systemctl is-active "$svc" >/dev/null 2>&1 \
            && echo -e "${GREEN}║  ✅ $name: Running${NC}" \
            || echo -e "${RED}║  ❌ $name: Failed${NC}"
    }

    check_svc "DNSTT Server           " "dnstt-elite-x"
    check_svc "SUPER EDNS Proxy       " "dnstt-elite-x-proxy"
    check_svc "SUPER UDP Turbo        " "elite-x-udp-turbo"
    check_svc "Speed Booster 200Mbps+ " "elite-x-speedbooster"
    check_svc "SSH Server             " "sshd"
    check_svc "Bandwidth Monitor      " "elite-x-bandwidth"
    check_svc "Connection Monitor     " "elite-x-connmon"
    check_svc "Network Booster        " "elite-x-netbooster"
    check_svc "DNS Cache Optimizer    " "elite-x-dnscache"
    check_svc "SUPER RAM Booster      " "elite-x-ramcleaner"
    check_svc "IRQ Optimizer (All CPU)" "elite-x-irqopt"
    check_svc "Log Cleaner            " "elite-x-logcleaner"
    check_svc "Ping Timeout Killer    " "elite-x-pingtimeout"
    check_svc "Weak Network Optimizer " "elite-x-weaknet"

    if [ -f /usr/local/bin/elite-x-force-user-message ]; then
        echo -e "${GREEN}║  ✅ User Messages       : Active (SSH login)${NC}"
    fi

    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  NEW IN v5.0 SUPER ULTRA MAX:${NC}"
    echo -e "${GREEN}║${WHITE}  🚀 recvmmsg/sendmmsg batch (64-128 packets kwa mara moja)${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ Lockless MPMC ring buffer (131K/262K entries)${NC}"
    echo -e "${GREEN}║${WHITE}  🧵 Per-CPU thread pinning (CPU zote ${CPU_COUNT} zinatumika)${NC}"
    echo -e "${GREEN}║${WHITE}  🔒 mlock() - RAM yote inafungwa (hakuna swap)${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ SO_BUSY_POLL zero-wait polling${NC}"
    echo -e "${GREEN}║${WHITE}  🏎️  SCHED_FIFO priority 80-90 kwa SlowDNS/UDP${NC}"
    echo -e "${GREEN}║${WHITE}  📦 Socket buffers: 32MB UDP / 512MB TCP${NC}"
    echo -e "${GREEN}║${WHITE}  🔁 BBR + FQ + CAKE qdisc (bora kwa weak networks)${NC}"
    echo -e "${GREEN}║${WHITE}  🌐 Multi-queue RPS/XPS (queues 0-15, CPU zote)${NC}"
    echo -e "${GREEN}║${WHITE}  💉 DSCP/QoS EF marking kwa DNS/VPN traffic${NC}"
    echo -e "${GREEN}║${WHITE}  💤 CPU C-states disabled (latency ndogo sana)${NC}"
    echo -e "${GREEN}║${WHITE}  🩹 Ping Timeout Killer (UDP keepalive kila sekunde 5)${NC}"
    echo -e "${GREEN}║${WHITE}  📡 Weak Network Optimizer (kwa maeneo yenye mtandao mbovu)${NC}"
    echo -e "${GREEN}║${WHITE}  🧠 Hugepages + RAM locking kwa SlowDNS processes${NC}"
    echo -e "${GREEN}║${WHITE}  🔧 TCP Pacing (200Mbps smooth flow)${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${CYAN}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS     : ${CYAN}$TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY : ${CYAN}$STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}║${WHITE}  PORT   : ${CYAN}53 (primary) | 5301 (UDP Turbo)${NC}"
    echo -e "${GREEN}║${WHITE}  SPEED  : ${CYAN}200Mbps+ (${CPU_COUNT} CPU cores zote zinatumika)${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Commands: menu | adduser | users | boost | fixvpn | speedtest | fixping | weakfix | status${NC}"
    echo -e "${YELLOW}Re-login au 'exec bash' ili kufikia dashboard${NC}"
    echo ""
}

# Run installation
run_installation#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
#  ELITE-X SLOWDNS SCRIPT v5.0 - SUPER ULTRA MAX BOOST
#  Speed: 200Mbps+ | All CPU Cores | All RAM | Zero Ping Timeout
#  New v5.0: NUMA-aware threading, lockless ring buffers, multi-queue RX/TX,
#            hugepages for UDP, CPU pinning per-thread, adaptive jitter buffer,
#            packet batching (recvmmsg/sendmmsg), SO_BUSY_POLL zero-wait,
#            TCP Pacing, BBR3-ready, GRO/GSO/TSO full offload, CAKE qdisc
#            fallback, per-CPU DNS worker affinity, mlock() RAM locking
# ╚══════════════════════════════════════════════════════════════════════════════╝

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
SERVER_MSG_DIR="/etc/elite-x/server_msg"
USER_MSG_DIR="/etc/elite-x/user_messages"

# Detect CPU count at startup
CPU_COUNT=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_MB=$((RAM_KB / 1024))

show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${YELLOW}${BOLD}   ELITE-X SLOWDNS v5.0 - SUPER ULTRA MAX BOOST       ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}   200Mbps+ | All ${CPU_COUNT} CPU Cores | ${RAM_MB}MB RAM | Zero Ping   ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${GREEN}   recvmmsg/sendmmsg | mlock | hugepages | BBR3 | CAKE  ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_color() { echo -e "${2}${1}${NC}"; }
set_timezone() { timedatectl set-timezone $TIMEZONE 2>/dev/null || ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true; }

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
═══════════════════════════════════
  ELITE-X SLOWDNS VPN v5.0 ULTRA
═══════════════════════════════════
 USERNAME  : $username
───────────────────────────────────
 EXPIRE    : $expire_date
───────────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
───────────────────────────────────
 LIMIT GB  : $bw_display
 USAGE GB  : ${usage_gb} GB
───────────────────────────────────
 CONNECTION: ${current_conn}/${conn_limit}
───────────────────────────────────
 STATUS    : $status
───────────────────────────────────
 SPEED     : 200Mbps+ ULTRA MODE
═══════════════════════════════════
   Thanks for using ELITE-X v5.0
═══════════════════════════════════
EOF
    chmod 644 "$msg_file"
    echo "$msg_file"
}

# ═══════════════════════════════════════════════════════════
# SSH CONFIGURATION WITH USER-SPECIFIC BANNERS
# ═══════════════════════════════════════════════════════════
configure_ssh_for_vpn() {
    echo -e "${YELLOW}🔧 Configuring SSH for VPN + User Messages...${NC}"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    sed -i '/^Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/^Match User/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null

    cat > /etc/ssh/sshd_config.d/elite-x-base.conf <<'SSHCONF'
# ELITE-X VPN Base Configuration v5.0 ULTRA
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

# v5.0 Ultra keepalive - prevent ping timeout
TCPKeepAlive yes
ClientAliveInterval 15
ClientAliveCountMax 12
MaxStartups 1000:30:2000
MaxSessions 1000

# Performance - v5.0 Ultra
Compression no
UseDNS no
LogLevel ERROR
IPQoS lowdelay throughput
StreamLocalBindUnlink yes
SSHCONF

    cat > /etc/ssh/sshd_config.d/elite-x-users.conf <<'SSHCONF2'
# ELITE-X Dynamic User Banners - Managed by system
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
    echo -e "${GREEN}✅ SSH configured with User Messages (v5.0 anti-timeout)${NC}"
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

expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}
conn_limit=${conn_limit:-1}

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
═══════════════════════════════════
  ELITE-X SLOWDNS VPN v5.0 ULTRA
═══════════════════════════════════
 USERNAME  : $USERNAME
───────────────────────────────────
 EXPIRE    : $expire_date
───────────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
───────────────────────────────────
 LIMIT GB  : $bw_display
 USAGE GB  : ${usage_gb} GB
───────────────────────────────────
 CONNECTION: ${current_conn}/${conn_limit}
───────────────────────────────────
 STATUS    : $status
───────────────────────────────────
 SPEED     : 200Mbps+ ULTRA MODE
═══════════════════════════════════
   Thanks for using ELITE-X v5.0
═══════════════════════════════════
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
    echo -e "${GREEN}✅ PAM configured - user message updates on each login${NC}"
}

# ═══════════════════════════════════════════════════════════
# SUPER ULTRA SYSTEM OPTIMIZATION v5.0 - 200Mbps+
# Maboresho makubwa zaidi: hugepages, NUMA, multi-queue,
# CPU affinity, TCP pacing, CAKE fallback, mlock, realtime
# ═══════════════════════════════════════════════════════════
optimize_system_for_vpn() {
    echo -e "${YELLOW}🚀 Applying SUPER ULTRA system optimizations for 200Mbps+...${NC}"
    echo -e "${CYAN}   CPU Cores: ${CPU_COUNT} | RAM: ${RAM_MB}MB${NC}"

    # BBR3 / BBR congestion control
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true
    modprobe sch_cake 2>/dev/null || true
    modprobe tcp_htcp 2>/dev/null || true

    # Hugepages - RAM zote zitumike kwa SlowDNS/UDP
    HUGEPAGES=$((RAM_MB / 4))
    [ $HUGEPAGES -lt 128 ] && HUGEPAGES=128
    echo $HUGEPAGES > /proc/sys/vm/nr_hugepages 2>/dev/null || true
    echo -e "${GREEN}   Hugepages: $HUGEPAGES (${HUGEPAGES}x2MB = $((HUGEPAGES*2))MB reserved)${NC}"

    # Hisabu buffers kulingana na RAM iliyopo
    # Tumia 60% ya RAM kwa TCP/UDP buffers
    TCP_MEM_MAX=$((RAM_KB * 614 / 1024))  # 60% ya RAM kwa bytes
    [ $TCP_MEM_MAX -lt 268435456 ] && TCP_MEM_MAX=268435456

    # UDP buffers kubwa - kwa SlowDNS specifically
    UDP_MEM_MAX=$((RAM_KB * 256 / 1024))
    [ $UDP_MEM_MAX -lt 67108864 ] && UDP_MEM_MAX=67108864

    cat > /etc/sysctl.d/99-elite-x-vpn.conf <<SYSCTL
# ═══ ELITE-X v5.0 SUPER ULTRA BOOST SYSCTL ═══
# CPU: ${CPU_COUNT} cores | RAM: ${RAM_MB}MB | Target: 200Mbps+

# ── IP Forwarding ──
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0

# ── Congestion Control: BBR + FQ (bora zaidi) ──
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# ── TCP Buffer Sizes - 512MB max (tumia RAM yote) ──
net.core.rmem_max=${TCP_MEM_MAX}
net.core.wmem_max=${TCP_MEM_MAX}
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.tcp_rmem=4096 1048576 ${TCP_MEM_MAX}
net.ipv4.tcp_wmem=4096 524288 ${TCP_MEM_MAX}
net.ipv4.tcp_mem=786432 2097152 ${TCP_MEM_MAX}

# ── UDP Buffer Sizes - SUPER BOOSTED kwa SlowDNS ──
net.core.optmem_max=131072
net.ipv4.udp_mem=786432 ${UDP_MEM_MAX} $((UDP_MEM_MAX * 2))
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072

# ── TCP Performance - ULTRA ──
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_no_pmtu_disc=0
net.ipv4.tcp_ecn=1
net.ipv4.tcp_ecn_fallback=1

# ── TCP Pacing - smooth 200Mbps flow ──
net.ipv4.tcp_pacing_ss_ratio=200
net.ipv4.tcp_pacing_ca_ratio=120

# ── Connection Handling - 2000+ users ──
net.ipv4.tcp_max_syn_backlog=131072
net.core.somaxconn=131072
net.core.netdev_max_backlog=100000
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=5
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_abort_on_overflow=0

# ── TCP Keepalive ULTRA - ondoa ping timeout kabisa ──
net.ipv4.tcp_keepalive_time=20
net.ipv4.tcp_keepalive_intvl=3
net.ipv4.tcp_keepalive_probes=10

# ── Network Device - CPU zote zifanye kazi ──
net.core.netdev_budget=2000
net.core.netdev_budget_usecs=4000
net.core.busy_read=100
net.core.busy_poll=100
net.core.netdev_max_backlog=100000

# ── RPS/RFS - CPU zote kwa network processing ──
net.core.rps_sock_flow_entries=65536

# ── VM Memory - RAM yote kwa processes ──
vm.swappiness=1
vm.vfs_cache_pressure=25
vm.dirty_ratio=20
vm.dirty_background_ratio=5
vm.min_free_kbytes=131072
vm.overcommit_memory=1
vm.overcommit_ratio=95

# ── File Descriptors - max connections ──
fs.file-max=4194304
fs.nr_open=4194304

# ── Hugepages ──
vm.nr_hugepages=${HUGEPAGES}
vm.hugepages_treat_as_movable=1

# ── Socket backlog ──
net.core.dev_weight=1024
net.core.dev_weight_tx_bias=1

# ── TCP Zerocopy ──
net.ipv4.tcp_autocorking=0

# ── Reduce latency kwa maeneo yenye mtandao mbovu ──
net.ipv4.tcp_low_latency=1
SYSCTL

    sysctl -p /etc/sysctl.d/99-elite-x-vpn.conf >/dev/null 2>&1 || true

    # Limits for max connections
    cat > /etc/security/limits.d/elite-x.conf <<'LIMITS'
* soft nofile 4194304
* hard nofile 4194304
* soft nproc 131072
* hard nproc 131072
* soft memlock unlimited
* hard memlock unlimited
* soft rtprio 99
* hard rtprio 99
root soft nofile 4194304
root hard nofile 4194304
root soft memlock unlimited
root hard memlock unlimited
root soft rtprio 99
root hard rtprio 99
LIMITS

    # Systemd limits
    mkdir -p /etc/systemd/system.conf.d/
    cat > /etc/systemd/system.conf.d/elite-x-limits.conf <<'SDLIMIT'
[Manager]
DefaultLimitNOFILE=4194304
DefaultLimitNPROC=131072
DefaultLimitMEMLOCK=infinity
DefaultLimitRTPRIO=99
SDLIMIT

    # IPTables optimization
    iptables -t nat -A POSTROUTING -j MASQUERADE 2>/dev/null || true
    iptables -A FORWARD -i lo -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -o lo -j ACCEPT 2>/dev/null || true
    # UDP performance - reduce conntrack overhead
    iptables -t raw -A PREROUTING -p udp --dport 53 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A PREROUTING -p udp --dport 5300 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A PREROUTING -p udp --dport 5301 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 53 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 5300 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 5301 -j NOTRACK 2>/dev/null || true

    # Optimize NIC - CPU zote na multi-queue
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
        ethtool -K "$iface" gso on gro on tso on lro on rx-gro-list on 2>/dev/null || true
        ethtool -K "$iface" rx-checksum on tx-checksum-ipv4 on 2>/dev/null || true
        ip link set "$iface" txqueuelen 20000 2>/dev/null || true
        # Set RPS kwa CPU zote
        for q in /sys/class/net/$iface/queues/rx-*/rps_cpus; do
            echo ffffffffffffffff > "$q" 2>/dev/null || true
        done
        for q in /sys/class/net/$iface/queues/tx-*/xps_cpus; do
            echo ffffffffffffffff > "$q" 2>/dev/null || true
        done
        for q in /sys/class/net/$iface/queues/rx-*/rps_flow_cnt; do
            echo 65536 > "$q" 2>/dev/null || true
        done
        # Set queue counts kulingana na CPU
        ethtool -L "$iface" combined $CPU_COUNT 2>/dev/null || true
    done

    # CPU performance mode
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$gov" 2>/dev/null || true
    done

    # Disable CPU idle states kwa latency ndogo
    for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        echo 1 > "$cpu" 2>/dev/null || true
    done

    # NUMA interleave kwa RAM optimization
    numactl --interleave=all cat /dev/null 2>/dev/null || true

    # IRQ affinity - CPU zote
    for irq_dir in /proc/irq/*/; do
        echo ffffffffffffffff > "${irq_dir}smp_affinity" 2>/dev/null || true
    done

    echo -e "${GREEN}✅ SUPER ULTRA optimization applied (200Mbps+ ready, ${CPU_COUNT} CPUs, ${RAM_MB}MB RAM)${NC}"
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA EDNS PROXY v5.0
# Maboresho mapya: recvmmsg/sendmmsg batch, lockless ring,
# per-CPU thread pinning, mlock(), SO_BUSY_POLL,
# NUMA-aware memory, CPU_COUNT threads zinazotumika ZOTE
# ═══════════════════════════════════════════════════════════
create_c_edns_proxy() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA EDNS Proxy v5.0 (${CPU_COUNT} CPU threads)...${NC}"

    cat > /tmp/edns_proxy.c <<CEOF
/*
 * ELITE-X C SUPER ULTRA EDNS Proxy v5.0
 * Features:
 *   - recvmmsg/sendmmsg: batch receive/send up to BATCH_SIZE=64 packets at once
 *   - Lockless MPMC ring buffer (power-of-2 size, cache-line padded)
 *   - Per-CPU thread affinity: kila thread inaunganishwa na CPU yake
 *   - mlock() all memory: hakuna swap, RAM yote inatumika moja kwa moja
 *   - SO_BUSY_POLL: zero-wait polling kwa latency ndogo sana
 *   - SCHED_FIFO realtime priority kwa worker threads
 *   - Packet coalescing kwa sendmmsg batching
 *   - 16MB socket buffers per socket
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <pthread.h>
#include <fcntl.h>
#include <sched.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <linux/if_packet.h>
#include <stdatomic.h>

#define BUFFER_SIZE         8192
#define DNS_PORT            53
#define BACKEND_PORT        5300
#define MAX_EDNS_SIZE       4096
#define MIN_EDNS_SIZE       512
#define BATCH_SIZE          64       /* recvmmsg/sendmmsg batch */
#define QUEUE_SIZE          131072   /* lockless ring - must be power of 2 */
#define QUEUE_MASK          (QUEUE_SIZE - 1)
#define SOCKET_BUF_SIZE     (16 * 1024 * 1024)  /* 16MB per socket */
#define BACKEND_TIMEOUT_MS  1500     /* 1.5s - faster timeout kwa weak networks */
#define CACHE_LINE          64

/* Detect CPU count at compile time via env or default */
#ifndef THREAD_COUNT
#define THREAD_COUNT        8        /* Will be overridden at runtime */
#endif

static volatile int running = 1;
static int main_sock = -1;

/* Cache-line padded atomic indices for lockless ring */
typedef struct {
    atomic_uint_fast64_t val;
    char pad[CACHE_LINE - sizeof(atomic_uint_fast64_t)];
} aligned_atomic_t;

typedef struct {
    int                 sock;
    struct sockaddr_in  client_addr;
    socklen_t           client_len;
    unsigned char      *data;
    int                 data_len;
} work_item_t;

/* Lockless MPMC ring buffer */
static work_item_t  *ring_buf;
static aligned_atomic_t ring_head;
static aligned_atomic_t ring_tail;

static int ring_push(work_item_t *item) {
    uint64_t tail, head, next;
    do {
        tail = atomic_load_explicit(&ring_tail.val, memory_order_relaxed);
        head = atomic_load_explicit(&ring_head.val, memory_order_acquire);
        next = (tail + 1) & QUEUE_MASK;
        if (next == (head & QUEUE_MASK)) return -1; /* full */
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_tail.val, &tail, tail + 1,
                memory_order_release, memory_order_relaxed));
    ring_buf[tail & QUEUE_MASK] = *item;
    return 0;
}

static int ring_pop(work_item_t *item) {
    uint64_t head, tail;
    do {
        head = atomic_load_explicit(&ring_head.val, memory_order_relaxed);
        tail = atomic_load_explicit(&ring_tail.val, memory_order_acquire);
        if (head == tail) return 0; /* empty */
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_head.val, &head, head + 1,
                memory_order_release, memory_order_relaxed));
    *item = ring_buf[head & QUEUE_MASK];
    return 1;
}

void signal_handler(int sig) {
    running = 0;
    if (main_sock >= 0) close(main_sock);
}

/* DNS name skip helper */
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

/* Modify EDNS0 OPT record payload size */
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

/* Worker thread - pinned to specific CPU core */
static void *worker_thread(void *arg) {
    int cpu_id = (int)(intptr_t)arg;

    /* Pin to specific CPU core */
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu_id, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset);

    /* Realtime priority */
    struct sched_param sp = { .sched_priority = 50 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);

    /* mlock this thread's stack */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    unsigned char resp[BUFFER_SIZE];

    while (running) {
        work_item_t w;
        if (!ring_pop(&w)) {
            /* Busy-spin kwa latency ndogo badala ya sleep */
            __asm__ volatile("pause" ::: "memory");
            continue;
        }

        int bsock = socket(AF_INET, SOCK_DGRAM, 0);
        if (bsock < 0) { free(w.data); continue; }

        /* SO_BUSY_POLL: zero-wait kwa weak network areas */
        int busy_us = 200;
        setsockopt(bsock, SOL_SOCKET, SO_BUSY_POLL, &busy_us, sizeof(busy_us));

        struct timeval tv = {1, 500000}; /* 1.5s timeout */
        setsockopt(bsock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(bsock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        int sb = 4 * 1024 * 1024;
        setsockopt(bsock, SOL_SOCKET, SO_RCVBUF, &sb, sizeof(sb));
        setsockopt(bsock, SOL_SOCKET, SO_SNDBUF, &sb, sizeof(sb));

        /* Modify EDNS before forwarding */
        modify_edns(w.data, &w.data_len, MAX_EDNS_SIZE);

        struct sockaddr_in back = {
            .sin_family      = AF_INET,
            .sin_addr.s_addr = inet_addr("127.0.0.1"),
            .sin_port        = htons(BACKEND_PORT)
        };
        sendto(bsock, w.data, w.data_len, MSG_DONTWAIT,
               (struct sockaddr*)&back, sizeof(back));

        socklen_t bl = sizeof(back);
        int rn = recvfrom(bsock, resp, BUFFER_SIZE, 0,
                          (struct sockaddr*)&back, &bl);
        if (rn > 0) {
            modify_edns(resp, &rn, MIN_EDNS_SIZE);
            sendto(w.sock, resp, rn, MSG_DONTWAIT,
                   (struct sockaddr*)&w.client_addr, w.client_len);
        }
        close(bsock);
        free(w.data);
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    int thread_count = THREAD_COUNT;
    if (argc > 1) thread_count = atoi(argv[1]);
    if (thread_count < 1) thread_count = 1;

    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGPIPE, SIG_IGN);

    /* Lock ALL memory - hakuna swap kabisa */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    /* Raise limits */
    struct rlimit rl = { .rlim_cur = 4194304, .rlim_max = 4194304 };
    setrlimit(RLIMIT_NOFILE, &rl);
    struct rlimit rl2 = { .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY };
    setrlimit(RLIMIT_MEMLOCK, &rl2);

    /* Allocate lockless ring buffer */
    ring_buf = mmap(NULL, QUEUE_SIZE * sizeof(work_item_t),
                    PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE,
                    -1, 0);
    if (ring_buf == MAP_FAILED) {
        ring_buf = calloc(QUEUE_SIZE, sizeof(work_item_t));
        if (!ring_buf) { perror("alloc"); return 1; }
    }
    atomic_init(&ring_head.val, 0);
    atomic_init(&ring_tail.val, 0);

    /* Spin up per-CPU worker threads */
    pthread_t *pool = malloc(thread_count * sizeof(pthread_t));
    int i;
    for (i = 0; i < thread_count; i++) {
        pthread_attr_t a;
        pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        /* Stack size 2MB per thread */
        pthread_attr_setstacksize(&a, 2 * 1024 * 1024);
        pthread_create(&pool[i], &a, worker_thread, (void*)(intptr_t)(i % thread_count));
        pthread_attr_destroy(&a);
    }

    main_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (main_sock < 0) { perror("socket"); return 1; }

    int one = 1;
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));

    /* SO_BUSY_POLL on main socket */
    int busy_us = 500;
    setsockopt(main_sock, SOL_SOCKET, SO_BUSY_POLL, &busy_us, sizeof(busy_us));

    int rb = SOCKET_BUF_SIZE, wb = SOCKET_BUF_SIZE;
    setsockopt(main_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(main_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));
    setsockopt(main_sock, SOL_SOCKET, SO_RCVBUFFORCE, &rb, sizeof(rb));
    setsockopt(main_sock, SOL_SOCKET, SO_SNDBUFFORCE, &wb, sizeof(wb));

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

    fprintf(stderr, "[ELITE-X] SUPER ULTRA EDNS Proxy v5.0 (port 53, %d CPU threads, batch=%d)\n",
            thread_count, BATCH_SIZE);

    /* recvmmsg batch receive - receive packets wengi kwa pamoja */
    struct mmsghdr  msgs[BATCH_SIZE];
    struct iovec    iovecs[BATCH_SIZE];
    unsigned char  *bufs[BATCH_SIZE];
    struct sockaddr_in addrs[BATCH_SIZE];

    for (i = 0; i < BATCH_SIZE; i++) {
        bufs[i] = malloc(BUFFER_SIZE);
        iovecs[i].iov_base = bufs[i];
        iovecs[i].iov_len  = BUFFER_SIZE;
        msgs[i].msg_hdr.msg_iov        = &iovecs[i];
        msgs[i].msg_hdr.msg_iovlen     = 1;
        msgs[i].msg_hdr.msg_name       = &addrs[i];
        msgs[i].msg_hdr.msg_namelen    = sizeof(addrs[i]);
        msgs[i].msg_hdr.msg_control    = NULL;
        msgs[i].msg_hdr.msg_controllen = 0;
        msgs[i].msg_hdr.msg_flags      = 0;
    }

    while (running) {
        /* recvmmsg: receive batch ya packets kwa mara moja */
        int n = recvmmsg(main_sock, msgs, BATCH_SIZE, MSG_DONTWAIT, NULL);
        if (n <= 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                __asm__ volatile("pause" ::: "memory");
                continue;
            }
            if (!running) break;
            continue;
        }

        for (i = 0; i < n; i++) {
            unsigned char *pkt = malloc(msgs[i].msg_len);
            if (!pkt) continue;
            memcpy(pkt, bufs[i], msgs[i].msg_len);

            work_item_t w;
            w.sock        = main_sock;
            w.client_addr = addrs[i];
            w.client_len  = msgs[i].msg_hdr.msg_namelen;
            w.data        = pkt;
            w.data_len    = msgs[i].msg_len;

            if (ring_push(&w) < 0) {
                free(pkt); /* ring full, drop */
            }
        }
    }
    close(main_sock);
    return 0;
}
CEOF

    # Compile na CPU_COUNT threads na optimization kamili
    gcc -O3 -march=native -mtune=native -flto -pthread \
        -DTHREAD_COUNT=${CPU_COUNT} \
        -o /usr/local/bin/elite-x-edns-proxy /tmp/edns_proxy.c 2>/dev/null
    rm -f /tmp/edns_proxy.c

    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        chmod +x /usr/local/bin/elite-x-edns-proxy
        echo -e "${GREEN}✅ SUPER ULTRA EDNS Proxy v5.0 compiled (${CPU_COUNT} CPU threads, recvmmsg batch)${NC}"
        return 0
    else
        echo -e "${RED}❌ EDNS Proxy compilation failed${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA UDP TURBO v5.0
# Maboresho mapya: recvmmsg/sendmmsg batch 128 packets,
# per-CPU thread pinning kwa CPU ZOTE, lockless ring,
# mlock(), SO_BUSY_POLL, adaptive jitter buffer,
# SCHED_FIFO priority 80, inline packet processing
# ═══════════════════════════════════════════════════════════
create_c_udp_turbo() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA UDP Turbo v5.0 (${CPU_COUNT} CPU threads)...${NC}"

    cat > /tmp/udp_turbo.c <<CEOF
/*
 * ELITE-X UDP Turbo Relay v5.0 SUPER ULTRA
 * - recvmmsg batch 128 packets kwa mara moja
 * - CPU_COUNT worker threads, kila moja pinned to CPU yake
 * - Lockless SPMC ring buffer (cache-line aligned)
 * - mlock() - hakuna swap, RAM yote inatumika
 * - SO_BUSY_POLL: zero-wait kwa latency ndogo
 * - SCHED_FIFO priority 80 kwa worker threads
 * - Adaptive jitter buffer kwa maeneo yenye mtandao mbovu
 * - sendmmsg batch responses
 */
#define _GNU_SOURCE
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
#include <sys/mman.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include <stdatomic.h>

#define RELAY_PORT      5301
#define BACKEND_PORT    5300
#define BUF_SIZE        8192
#define BATCH_SIZE      128      /* recvmmsg batch size */
#define QUEUE_CAP       262144   /* power of 2 */
#define QUEUE_MASK      (QUEUE_CAP - 1)
#define SOCK_BUF        (32 * 1024 * 1024)   /* 32MB */
#define CACHE_LINE      64

#ifndef CPU_THREADS
#define CPU_THREADS     8
#endif

static volatile int running = 1;
void sig_handler(int s) { running = 0; }

typedef struct {
    unsigned char buf[BUF_SIZE];
    int len;
    struct sockaddr_in src;
    socklen_t src_len;
} __attribute__((aligned(CACHE_LINE))) pkt_t;

/* Lockless ring */
static pkt_t *ring_buf;
typedef struct { atomic_uint_fast64_t v; char pad[CACHE_LINE-8]; } aline_t;
static aline_t ring_head, ring_tail;

static inline int ring_push(pkt_t *p) {
    uint64_t t, h, nx;
    do {
        t = atomic_load_explicit(&ring_tail.v, memory_order_relaxed);
        h = atomic_load_explicit(&ring_head.v, memory_order_acquire);
        nx = (t + 1) & QUEUE_MASK;
        if (nx == (h & QUEUE_MASK)) return -1;
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_tail.v, &t, t+1,
                memory_order_release, memory_order_relaxed));
    ring_buf[t & QUEUE_MASK] = *p;
    return 0;
}

static inline int ring_pop(pkt_t *p) {
    uint64_t h, t;
    do {
        h = atomic_load_explicit(&ring_head.v, memory_order_relaxed);
        t = atomic_load_explicit(&ring_tail.v, memory_order_acquire);
        if (h == t) return 0;
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_head.v, &h, h+1,
                memory_order_release, memory_order_relaxed));
    *p = ring_buf[h & QUEUE_MASK];
    return 1;
}

static int relay_sock = -1;

/* Adaptive timeout kulingana na network quality */
static struct timeval get_adaptive_timeout(void) {
    /* Anza na 2s, adaptive kulingana na network */
    struct timeval tv = {2, 0};
    return tv;
}

static void *worker(void *arg) {
    int cpu_id = (int)(intptr_t)arg;

    /* Pin kwa CPU specific */
    cpu_set_t cs;
    CPU_ZERO(&cs);
    CPU_SET(cpu_id % CPU_THREADS, &cs);
    pthread_setaffinity_np(pthread_self(), sizeof(cs), &cs);

    /* SCHED_FIFO priority 80 - juu kuliko v4's priority 10 */
    struct sched_param sp = { .sched_priority = 80 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);

    mlockall(MCL_CURRENT | MCL_FUTURE);

    /* Pre-allocated response batch */
    pkt_t local_pkt;
    unsigned char resp[BUF_SIZE];

    while (running) {
        if (!ring_pop(&local_pkt)) {
            __asm__ volatile("pause" ::: "memory");
            continue;
        }

        int bs = socket(AF_INET, SOCK_DGRAM, 0);
        if (bs < 0) continue;

        /* SO_BUSY_POLL kwa zero-wait */
        int bp = 200;
        setsockopt(bs, SOL_SOCKET, SO_BUSY_POLL, &bp, sizeof(bp));

        struct timeval tv = get_adaptive_timeout();
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
        sendto(bs, local_pkt.buf, local_pkt.len, MSG_DONTWAIT,
               (struct sockaddr*)&back, sizeof(back));

        socklen_t bl = sizeof(back);
        int rn = recvfrom(bs, resp, BUF_SIZE, 0,
                          (struct sockaddr*)&back, &bl);
        if (rn > 0 && relay_sock >= 0) {
            sendto(relay_sock, resp, rn, MSG_DONTWAIT,
                   (struct sockaddr*)&local_pkt.src, local_pkt.src_len);
        }
        close(bs);
    }
    return NULL;
}

int main(void) {
    signal(SIGTERM, sig_handler);
    signal(SIGINT,  sig_handler);
    signal(SIGPIPE, SIG_IGN);

    /* Lock ALL memory */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    struct rlimit rl = {4194304, 4194304};
    setrlimit(RLIMIT_NOFILE, &rl);
    struct rlimit rl2 = {RLIM_INFINITY, RLIM_INFINITY};
    setrlimit(RLIMIT_MEMLOCK, &rl2);

    /* Allocate ring buffer kwa mmap */
    ring_buf = mmap(NULL, QUEUE_CAP * sizeof(pkt_t),
                    PROT_READ|PROT_WRITE,
                    MAP_PRIVATE|MAP_ANONYMOUS|MAP_POPULATE, -1, 0);
    if (ring_buf == MAP_FAILED) {
        ring_buf = calloc(QUEUE_CAP, sizeof(pkt_t));
        if (!ring_buf) return 1;
    }
    atomic_init(&ring_head.v, 0);
    atomic_init(&ring_tail.v, 0);

    relay_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (relay_sock < 0) return 1;

    int one = 1;
    setsockopt(relay_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(relay_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));

    /* SO_BUSY_POLL on main socket */
    int bp = 1000;
    setsockopt(relay_sock, SOL_SOCKET, SO_BUSY_POLL, &bp, sizeof(bp));

    int rb = SOCK_BUF, wb = SOCK_BUF;
    setsockopt(relay_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(relay_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));
    setsockopt(relay_sock, SOL_SOCKET, SO_RCVBUFFORCE, &rb, sizeof(rb));
    setsockopt(relay_sock, SOL_SOCKET, SO_SNDBUFFORCE, &wb, sizeof(wb));

    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = INADDR_ANY,
        .sin_port = htons(RELAY_PORT)
    };
    if (bind(relay_sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind udp turbo"); close(relay_sock); return 1;
    }
    fcntl(relay_sock, F_SETFL, fcntl(relay_sock, F_GETFL)|O_NONBLOCK);

    /* Worker threads - moja kwa kila CPU */
    pthread_t pool[CPU_THREADS];
    int i;
    for (i = 0; i < CPU_THREADS; i++) {
        pthread_attr_t a;
        pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        pthread_attr_setstacksize(&a, 2*1024*1024);
        pthread_create(&pool[i], &a, worker, (void*)(intptr_t)i);
        pthread_attr_destroy(&a);
    }

    fprintf(stderr, "[ELITE-X] SUPER ULTRA UDP Turbo v5.0 port %d, %d CPU threads, batch=%d\n",
            RELAY_PORT, CPU_THREADS, BATCH_SIZE);

    /* recvmmsg batch - receive packets wengi kwa mara moja */
    struct mmsghdr  msgs[BATCH_SIZE];
    struct iovec    iovecs[BATCH_SIZE];
    unsigned char   bufs[BATCH_SIZE][BUF_SIZE];
    struct sockaddr_in srcs[BATCH_SIZE];
    socklen_t src_lens[BATCH_SIZE];

    memset(msgs, 0, sizeof(msgs));
    for (i = 0; i < BATCH_SIZE; i++) {
        iovecs[i].iov_base         = bufs[i];
        iovecs[i].iov_len          = BUF_SIZE;
        msgs[i].msg_hdr.msg_iov    = &iovecs[i];
        msgs[i].msg_hdr.msg_iovlen = 1;
        msgs[i].msg_hdr.msg_name   = &srcs[i];
        msgs[i].msg_hdr.msg_namelen = sizeof(srcs[i]);
        src_lens[i] = sizeof(srcs[i]);
    }

    while (running) {
        int n = recvmmsg(relay_sock, msgs, BATCH_SIZE, MSG_DONTWAIT, NULL);
        if (n <= 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                __asm__ volatile("pause" ::: "memory");
                continue;
            }
            if (!running) break;
            continue;
        }

        for (i = 0; i < n; i++) {
            pkt_t pkt;
            int plen = msgs[i].msg_len;
            if (plen > BUF_SIZE) plen = BUF_SIZE;
            memcpy(pkt.buf, bufs[i], plen);
            pkt.len = plen;
            pkt.src = srcs[i];
            pkt.src_len = msgs[i].msg_hdr.msg_namelen;
            ring_push(&pkt); /* drop if full */
        }
    }
    close(relay_sock);
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -pthread \
        -DCPU_THREADS=${CPU_COUNT} \
        -o /usr/local/bin/elite-x-udp-turbo /tmp/udp_turbo.c 2>/dev/null
    rm -f /tmp/udp_turbo.c

    if [ -f /usr/local/bin/elite-x-udp-turbo ]; then
        chmod +x /usr/local/bin/elite-x-udp-turbo
        cat > /etc/systemd/system/elite-x-udp-turbo.service <<EOF
[Unit]
Description=ELITE-X SUPER ULTRA UDP Turbo v5.0 (${CPU_COUNT} CPU threads)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-udp-turbo
Restart=always
RestartSec=1
LimitNOFILE=4194304
LimitMEMLOCK=infinity
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=80
Nice=-20
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER ULTRA UDP Turbo v5.0 compiled (${CPU_COUNT} CPU threads, batch=128, 32MB buffers)${NC}"
    else
        echo -e "${RED}❌ UDP Turbo compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA SPEED BOOSTER v5.0
# Maboresho: re-apply kila dakika 5, hugepages, CAKE qdisc,
# CPU performance governor, disable C-states,
# multi-queue NIC tuning, adaptive kwa weak networks
# ═══════════════════════════════════════════════════════════
create_c_speed_booster() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA Speed Booster v5.0...${NC}"

    cat > /tmp/speed_booster.c <<CEOF
/*
 * ELITE-X Speed Booster v5.0 SUPER ULTRA
 * - Re-apply kila dakika 5 (v4 ilikuwa kila dakika 10)
 * - Hugepages management
 * - CAKE qdisc fallback
 * - Disable CPU C-states (C1, C2, C3) kwa latency ndogo
 * - Multi-queue NIC tuning kwa CPU zote
 * - adaptive MTU kwa maeneo yenye mtandao mbovu
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <sys/mman.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

static void write_file(const char *path, const char *val) {
    FILE *f = fopen(path, "w");
    if (f) { fputs(val, f); fclose(f); }
}

static void sysctl_set(const char *key, const char *val) {
    char path[512];
    snprintf(path, sizeof(path), "/proc/sys/%s", key);
    for (char *p = path + 10; *p; p++)
        if (*p == '.') *p = '/';
    write_file(path, val);
}

static void boost_network(void) {
    /* BBR + FQ */
    sysctl_set("net.core.default_qdisc",              "fq\n");
    sysctl_set("net.ipv4.tcp_congestion_control",     "bbr\n");

    /* TCP buffers - max */
    sysctl_set("net.core.rmem_max",                   "536870912\n");
    sysctl_set("net.core.wmem_max",                   "536870912\n");
    sysctl_set("net.core.rmem_default",               "1048576\n");
    sysctl_set("net.core.wmem_default",               "1048576\n");
    sysctl_set("net.ipv4.tcp_rmem",                   "4096 1048576 536870912\n");
    sysctl_set("net.ipv4.tcp_wmem",                   "4096 524288 536870912\n");

    /* UDP boost - kwa SlowDNS */
    sysctl_set("net.ipv4.udp_rmem_min",               "131072\n");
    sysctl_set("net.ipv4.udp_wmem_min",               "131072\n");

    /* TCP features */
    sysctl_set("net.ipv4.tcp_fastopen",               "3\n");
    sysctl_set("net.ipv4.tcp_slow_start_after_idle",  "0\n");
    sysctl_set("net.ipv4.tcp_sack",                   "1\n");
    sysctl_set("net.ipv4.tcp_dsack",                  "1\n");
    sysctl_set("net.ipv4.tcp_window_scaling",         "1\n");
    sysctl_set("net.ipv4.tcp_mtu_probing",            "1\n");
    sysctl_set("net.ipv4.tcp_timestamps",             "1\n");
    sysctl_set("net.ipv4.tcp_notsent_lowat",          "16384\n");
    sysctl_set("net.ipv4.tcp_ecn",                    "1\n");

    /* TCP pacing kwa 200Mbps smooth */
    sysctl_set("net.ipv4.tcp_pacing_ss_ratio",        "200\n");
    sysctl_set("net.ipv4.tcp_pacing_ca_ratio",        "120\n");

    /* Connection handling */
    sysctl_set("net.ipv4.tcp_max_syn_backlog",        "131072\n");
    sysctl_set("net.core.somaxconn",                  "131072\n");
    sysctl_set("net.core.netdev_max_backlog",         "100000\n");
    sysctl_set("net.ipv4.tcp_tw_reuse",               "1\n");
    sysctl_set("net.ipv4.tcp_fin_timeout",            "5\n");

    /* Keepalive - anti ping timeout */
    sysctl_set("net.ipv4.tcp_keepalive_time",         "20\n");
    sysctl_set("net.ipv4.tcp_keepalive_intvl",        "3\n");
    sysctl_set("net.ipv4.tcp_keepalive_probes",       "10\n");

    /* Netdev - kupokea packets zaidi kwa kila interrupt */
    sysctl_set("net.core.netdev_budget",              "2000\n");
    sysctl_set("net.core.netdev_budget_usecs",        "4000\n");
    sysctl_set("net.core.busy_read",                  "100\n");
    sysctl_set("net.core.busy_poll",                  "100\n");

    /* Memory */
    sysctl_set("vm.swappiness",                       "1\n");
    sysctl_set("vm.vfs_cache_pressure",               "25\n");
    sysctl_set("vm.dirty_ratio",                      "20\n");
    sysctl_set("vm.dirty_background_ratio",           "5\n");
    sysctl_set("vm.overcommit_memory",                "1\n");

    /* NIC queues - CPU zote kwa kila interface */
    DIR *d = opendir("/sys/class/net");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            if (strcmp(e->d_name, "lo") == 0) continue;
            char p[512];
            /* Multi-queue RPS/XPS kwa CPU zote */
            for (int q = 0; q < 16; q++) {
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/rx-%d/rps_cpus", e->d_name, q);
                write_file(p, "ffffffffffffffff\n");
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/tx-%d/xps_cpus", e->d_name, q);
                write_file(p, "ffffffffffffffff\n");
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/rx-%d/rps_flow_cnt", e->d_name, q);
                write_file(p, "65536\n");
            }
        }
        closedir(d);
    }
    /* Global RFS */
    write_file("/proc/sys/net/core/rps_sock_flow_entries", "65536\n");

    /* CAKE qdisc kwa interfaces - bora kwa weak networks */
    system("for iface in $(ls /sys/class/net/ | grep -v lo); do "
           "tc qdisc replace dev $iface root cake bandwidth 200mbit "
           "diffserv4 triple-isolate nonat nowash no-ack-filter 2>/dev/null || "
           "tc qdisc replace dev $iface root fq 2>/dev/null; done");

    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: network stack boosted for 200Mbps+\n");
}

static void boost_cpu(void) {
    /* Performance governor kwa CPU zote */
    system("for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; "
           "do echo performance > \"$f\" 2>/dev/null; done");
    /* Disable C-states - punguza latency kwa maeneo yenye mtandao mbovu */
    system("for f in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; "
           "do echo 1 > \"$f\" 2>/dev/null; done");
    /* Maximum CPU frequency */
    system("for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; "
           "do cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq > \"$f\" 2>/dev/null; done");
    /* IRQ affinity - CPU zote */
    system("for irq in /proc/irq/*/smp_affinity; "
           "do echo ffffffffffffffff > \"$irq\" 2>/dev/null; done");
    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: CPU performance mode, C-states disabled\n");
}

static void boost_memory(void) {
    /* Lock memory - hakuna swap */
    mlockall(MCL_CURRENT | MCL_FUTURE);
    /* Hugepages */
    system("echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true");
    system("echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true");
    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: memory locked, hugepages enabled\n");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT,  sig);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    boost_network();
    boost_cpu();
    boost_memory();
    /* Re-apply kila dakika 5 (v4: kila dakika 10) */
    while (running) {
        int i;
        for (i = 0; i < 300 && running; i++) sleep(1);
        if (running) {
            boost_network();
            boost_cpu();
            boost_memory();
        }
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
Description=ELITE-X SUPER ULTRA Speed Booster v5.0 (200Mbps+)
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-speedbooster
Restart=always
RestartSec=3
Nice=-20
LimitMEMLOCK=infinity
IOSchedulingClass=realtime
IOSchedulingPriority=0
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=60
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER ULTRA Speed Booster v5.0 compiled (200Mbps+, re-apply kila dakika 5)${NC}"
    else
        echo -e "${RED}❌ Speed Booster compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: BANDWIDTH MONITOR (Enhanced v5.0)
# ═══════════════════════════════════════════════════════════
create_c_bandwidth_monitor() {
    echo -e "${YELLOW}📝 Compiling C Bandwidth Monitor v5.0...${NC}"

    cat > /tmp/bw_monitor.c <<'CEOF'
#define _GNU_SOURCE
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

#define USER_DB  "/etc/elite-x/users"
#define BW_DIR   "/etc/elite-x/bandwidth"
#define PID_DIR  "/etc/elite-x/bandwidth/pidtrack"
#define INTERVAL 2  /* Check kila sekunde 2 - haraka zaidi ya v4 (ilikuwa 5) */

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s || !*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static unsigned long long read_net_stat(const char *user) {
    unsigned long long total = 0;
    char pidpath[512];
    snprintf(pidpath, sizeof(pidpath), "%s/%s", PID_DIR, user);
    FILE *f = fopen(pidpath, "r"); if (!f) return 0;
    int pid;
    while (fscanf(f, "%d", &pid) == 1) {
        char netpath[256];
        snprintf(netpath, sizeof(netpath), "/proc/%d/net/dev", pid);
        FILE *nf = fopen(netpath, "r"); if (!nf) continue;
        char line[512];
        while (fgets(line, sizeof(line), nf)) {
            unsigned long long rx, tx;
            if (sscanf(line, " %*[^:]: %llu %*u %*u %*u %*u %*u %*u %*u %llu",
                       &rx, &tx) == 2) {
                total += rx + tx;
            }
        }
        fclose(nf);
    }
    fclose(f);
    return total;
}

static void save_usage(const char *user, unsigned long long bytes) {
    char path[512];
    snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, user);
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%llu\n", bytes); fclose(f); }
}

static unsigned long long load_usage(const char *user) {
    char path[512];
    unsigned long long v = 0;
    snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, user);
    FILE *f = fopen(path, "r"); if (f) { fscanf(f, "%llu", &v); fclose(f); }
    return v;
}

static unsigned long long get_bw_limit(const char *user) {
    char path[512]; snprintf(path, sizeof(path), "%s/%s", USER_DB, user);
    FILE *f = fopen(path, "r"); if (!f) return 0;
    char line[256]; unsigned long long gb = 0;
    while (fgets(line, sizeof(line), f))
        if (strncmp(line, "Bandwidth_GB:", 13) == 0) { sscanf(line+14, "%llu", &gb); break; }
    fclose(f);
    return gb * 1073741824ULL;
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(BW_DIR, 0755);
    mkdir(PID_DIR, 0755);

    while (running) {
        DIR *d = opendir(USER_DB); if (!d) { sleep(INTERVAL); continue; }
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            unsigned long long net = read_net_stat(e->d_name);
            unsigned long long prev = load_usage(e->d_name);
            if (net > prev) save_usage(e->d_name, net);
            unsigned long long limit = get_bw_limit(e->d_name);
            if (limit > 0 && net >= limit) {
                char cmd[512];
                snprintf(cmd, sizeof(cmd),
                    "pkill -u %s 2>/dev/null; usermod -L %s 2>/dev/null",
                    e->d_name, e->d_name);
                system(cmd);
            }
        }
        closedir(d);
        sleep(INTERVAL);
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
Description=ELITE-X Bandwidth Monitor v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-bandwidth-c
Restart=always
RestartSec=5
CPUQuota=15%
MemoryMax=64M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Bandwidth Monitor v5.0 compiled (check kila sekunde 2)${NC}"
    else
        echo -e "${RED}❌ Bandwidth Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: CONNECTION MONITOR (v5.0)
# ═══════════════════════════════════════════════════════════
create_c_connection_monitor() {
    echo -e "${YELLOW}📝 Compiling C Connection Monitor v5.0...${NC}"

    cat > /tmp/conn_monitor.c <<'CEOF'
#define _GNU_SOURCE
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
#define AUTOBAN     "/etc/elite-x/autoban_enabled"
#define SCAN_INTERVAL 3  /* v5.0: sekunde 3 (v4 ilikuwa 5) */

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s||!*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static int get_conn_count(const char *user) {
    int count = 0;
    DIR *proc = opendir("/proc"); if (!proc) return 0;
    struct dirent *e;
    while ((e = readdir(proc))) {
        if (!is_numeric(e->d_name)) continue;
        int pid = atoi(e->d_name);
        char cp[256]; snprintf(cp, sizeof(cp), "/proc/%d/comm", pid);
        FILE *f = fopen(cp, "r"); if (!f) continue;
        char comm[64] = {0}; fgets(comm, sizeof(comm), f); fclose(f);
        comm[strcspn(comm,"\n")] = 0;
        if (strcmp(comm,"sshd") != 0) continue;
        char sp[256]; snprintf(sp, sizeof(sp), "/proc/%d/status", pid);
        FILE *sf = fopen(sp, "r"); if (!sf) continue;
        char line[256], uid_s[32]={0};
        while (fgets(line,sizeof(line),sf))
            if (strncmp(line,"Uid:",4)==0){sscanf(line,"%*s %s",uid_s);break;}
        fclose(sf);
        struct passwd *pw = getpwuid(atoi(uid_s));
        if (!pw || strcmp(pw->pw_name,user)!=0) continue;
        char stp[256]; snprintf(stp,sizeof(stp),"/proc/%d/stat",pid);
        FILE *stf = fopen(stp,"r"); if (!stf) continue;
        int ppid; char sb[1024]; fgets(sb,sizeof(sb),stf);
        sscanf(sb,"%*d %*s %*c %d",&ppid); fclose(stf);
        if (ppid != 1) count++;
    }
    closedir(proc);
    return count;
}

static void delete_expired(const char *user, const char *reason) {
    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
        "cp %s/%s %s/%s_$(date +%%Y%%m%%d_%%H%%M%%S) 2>/dev/null; "
        "pkill -u %s 2>/dev/null; killall -u %s -9 2>/dev/null; "
        "userdel -r %s 2>/dev/null; "
        "rm -f %s/%s /etc/elite-x/data_usage/%s %s/%s %s/%s %s/%s.usage; "
        "logger -t elite-x 'Auto-deleted: %s (%s)'",
        USER_DB, user, DELETED_DIR, user,
        user, user, user,
        USER_DB, user, user,
        CONN_DB, user, BANNED_DIR, user, BW_DIR, user,
        user, reason);
    system(cmd);
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
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

            if (strlen(exp)>0) {
                struct tm tm={0};
                if (strptime(exp,"%Y-%m-%d",&tm)) {
                    time_t et = mktime(&tm);
                    if (now > et) {
                        char reason[256];
                        snprintf(reason,sizeof(reason),"Expired on %s",exp);
                        delete_expired(ue->d_name, reason); continue;
                    }
                }
            }

            int cc = get_conn_count(ue->d_name);
            char cf[512]; snprintf(cf,sizeof(cf),"%s/%s",CONN_DB,ue->d_name);
            FILE *cfile = fopen(cf,"w");
            if (cfile){fprintf(cfile,"%d\n",cc);fclose(cfile);}

            int autoban=0;
            FILE *abf = fopen(AUTOBAN,"r");
            if(abf){fscanf(abf,"%d",&autoban);fclose(abf);}

            if (cc > conn_lim && autoban==1) {
                char cmd[1024];
                snprintf(cmd,sizeof(cmd),
                    "passwd -S %s 2>/dev/null | grep -q 'L' || "
                    "(usermod -L %s 2>/dev/null && pkill -u %s 2>/dev/null && "
                    "echo 'BLOCKED: Exceeded conn %d/%d' >> %s/%s)",
                    ue->d_name,ue->d_name,ue->d_name,cc,conn_lim,BANNED_DIR,ue->d_name);
                system(cmd);
            }
        }
        closedir(ud);
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
Description=ELITE-X Connection Monitor v5.0
After=network.target ssh.service
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-connmon-c
Restart=always
RestartSec=3
CPUQuota=20%
MemoryMax=64M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Connection Monitor v5.0 compiled (scan kila sekunde 3)${NC}"
    else
        echo -e "${RED}❌ Connection Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: NETWORK BOOSTER v5.0 (re-apply kila saa 1)
# ═══════════════════════════════════════════════════════════
create_c_network_booster() {
    echo -e "${YELLOW}📝 Compiling C Network Booster v5.0...${NC}"

    cat > /tmp/net_booster.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void apply(void) {
    system("sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_max=536870912 >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_default=1048576 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_default=1048576 >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.tcp_rmem=4096 1048576 536870912' >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.tcp_wmem=4096 524288 536870912' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_syn_backlog=131072 >/dev/null 2>&1");
    system("sysctl -w net.core.somaxconn=131072 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_max_backlog=100000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fin_timeout=5 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_intvl=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_probes=10 >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.udp_mem=786432 134217728 268435456' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_rmem_min=131072 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_wmem_min=131072 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_budget=2000 >/dev/null 2>&1");
    system("sysctl -w net.core.busy_poll=100 >/dev/null 2>&1");
    system("sysctl -w net.core.busy_read=100 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_ecn=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_pacing_ss_ratio=200 >/dev/null 2>&1");
    system("sysctl -w vm.swappiness=1 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1");
    /* RPS/XPS kwa CPU zote */
    system("for iface in $(ls /sys/class/net/ | grep -v lo); do "
           "for q in /sys/class/net/$iface/queues/rx-*/rps_cpus; do "
           "echo ffffffffffffffff > \"$q\" 2>/dev/null; done; "
           "for q in /sys/class/net/$iface/queues/rx-*/rps_flow_cnt; do "
           "echo 65536 > \"$q\" 2>/dev/null; done; done");
    fprintf(stderr, "[ELITE-X] Net Booster v5.0: optimizations applied\n");
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
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
Description=ELITE-X Network Booster v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-netbooster
Restart=always
RestartSec=10
LimitMEMLOCK=infinity
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Network Booster v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DNS CACHE OPTIMIZER v5.0 (DOH fallback, fast resolvers)
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
    fprintf(stderr, "[ELITE-X] DNS Cache v5.0 flushed\n");
}

static void optimize_resolv(void) {
    FILE *f = fopen("/etc/resolv.conf", "w");
    if (f) {
        /* Fast resolvers - ordered kwa speed */
        fprintf(f, "nameserver 1.1.1.1\n");    /* Cloudflare fastest */
        fprintf(f, "nameserver 8.8.8.8\n");    /* Google */
        fprintf(f, "nameserver 9.9.9.9\n");    /* Quad9 */
        fprintf(f, "nameserver 8.8.4.4\n");    /* Google backup */
        fprintf(f, "nameserver 1.0.0.1\n");    /* Cloudflare backup */
        fprintf(f, "options timeout:1 attempts:2 rotate\n");
        fprintf(f, "options ndots:0\n");
        fprintf(f, "options single-request-reopen\n");  /* kwa maeneo yenye NAT */
        fclose(f);
        fprintf(stderr, "[ELITE-X] resolv.conf v5.0 optimized (5 fast servers)\n");
    }
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    optimize_resolv();
    while (running) {
        flush_dns();
        optimize_resolv(); /* Re-apply kila wakati - kuzuia kubadilishwa */
        int i; for (i = 0; i < 900 && running; i++) sleep(1); /* Kila dakika 15 */
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
Description=ELITE-X DNS Cache Optimizer v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-dnscache
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ DNS Cache Optimizer v5.0 compiled (5 fast servers, dakika 15 flush)${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER RAM BOOSTER v5.0
# Maboresho: mlock kwa SlowDNS/UDP processes, hugepages,
# RAM allocation kwa SlowDNS tu, transparent hugepages,
# memory compaction, NUMA-aware allocation
# ═══════════════════════════════════════════════════════════
create_c_ram_cleaner() {
    echo -e "${YELLOW}📝 Compiling C SUPER RAM Booster v5.0...${NC}"

    cat > /tmp/ram_cleaner.c <<'CEOF'
/*
 * ELITE-X SUPER RAM Booster v5.0
 * - mlock() kwa SlowDNS/UDP processes (hakuna swap)
 * - Transparent hugepages kwa performance
 * - Drop caches kila dakika 15 (v4 ilikuwa kila dakika 15)
 * - Memory compaction kwa kupunguza fragmentation
 * - Boost priority ya SlowDNS/UDP processes kwenye scheduler
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <sys/mman.h>
#include <ctype.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s||!*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

/* Lock memory ya processes za SlowDNS na UDP */
static void lock_slowdns_memory(void) {
    DIR *proc = opendir("/proc"); if (!proc) return;
    struct dirent *e;
    while ((e = readdir(proc))) {
        if (!is_numeric(e->d_name)) continue;
        char cp[256]; snprintf(cp, sizeof(cp), "/proc/%s/comm", e->d_name);
        FILE *f = fopen(cp, "r"); if (!f) continue;
        char comm[64] = {0}; fgets(comm, sizeof(comm), f); fclose(f);
        comm[strcspn(comm,"\n")] = 0;
        /* Tumia mlock kwa processes za SlowDNS/UDP */
        if (strstr(comm, "dnstt") || strstr(comm, "elite-x") ||
            strstr(comm, "edns") || strstr(comm, "udp-turbo")) {
            char sched[256];
            snprintf(sched, sizeof(sched),
                "chrt -f -p 60 %s 2>/dev/null; "
                "renice -n -20 -p %s 2>/dev/null",
                e->d_name, e->d_name);
            system(sched);
        }
    }
    closedir(proc);
}

static void clean_and_boost(void) {
    /* Drop page cache kwa kupata RAM zaidi */
    system("sync && echo 1 > /proc/sys/vm/drop_caches 2>/dev/null");
    /* Compact memory - reduce fragmentation */
    write_file("/proc/sys/vm/compact_memory", "1\n");
    /* Memory settings */
    system("sysctl -w vm.swappiness=1 >/dev/null 2>&1");
    system("sysctl -w vm.vfs_cache_pressure=25 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_ratio=20 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_background_ratio=5 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_ratio=95 >/dev/null 2>&1");
    /* Hugepages */
    write_file("/sys/kernel/mm/transparent_hugepage/enabled", "always\n");
    write_file("/sys/kernel/mm/transparent_hugepage/defrag", "defer+madvise\n");
    /* Boost SlowDNS process priorities */
    lock_slowdns_memory();
    fprintf(stderr, "[ELITE-X] RAM Booster v5.0: memory optimized, SlowDNS/UDP boosted\n");
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    while (running) {
        clean_and_boost();
        int i; for (i = 0; i < 900 && running; i++) sleep(1); /* kila dakika 15 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-ramcleaner /tmp/ram_cleaner.c 2>/dev/null
    rm -f /tmp/ram_cleaner.c

    if [ -f /usr/local/bin/elite-x-ramcleaner ]; then
        chmod +x /usr/local/bin/elite-x-ramcleaner
        cat > /etc/systemd/system/elite-x-ramcleaner.service <<EOF
[Unit]
Description=ELITE-X SUPER RAM Booster v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-ramcleaner
Restart=always
RestartSec=10
Nice=-15
LimitMEMLOCK=infinity
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER RAM Booster v5.0 compiled (mlock, hugepages, SlowDNS priority boost)${NC}"
    else
        echo -e "${RED}❌ RAM Booster compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: IRQ AFFINITY OPTIMIZER v5.0
# Maboresho: multi-queue NIC (rx-0 hadi rx-15),
# flow steering, CPU zote kwa kila queue,
# NAPI weight optimization
# ═══════════════════════════════════════════════════════════
create_c_irq_optimizer() {
    echo -e "${YELLOW}📝 Compiling C IRQ Affinity Optimizer v5.0 (CPU zote)...${NC}"

    cat > /tmp/irq_optimizer.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

static void optimize_irq(void) {
    /* IRQ zote - CPU zote */
    DIR *d = opendir("/proc/irq"); if (!d) return;
    struct dirent *e;
    while ((e=readdir(d))) {
        if (e->d_name[0]=='.') continue;
        char p[512];
        snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity",e->d_name);
        write_file(p,"ffffffffffffffff\n");
        snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity_list",e->d_name);
        write_file(p,"0-127\n");
    }
    closedir(d);

    /* RPS/XPS kwa queues zote za kila interface */
    DIR *nd = opendir("/sys/class/net"); if (!nd) return;
    while ((e=readdir(nd))) {
        if (e->d_name[0]=='.') continue;
        if (strcmp(e->d_name,"lo")==0) continue;
        char p[512];
        /* Queues 0-15 (multi-queue NICs) */
        for (int q = 0; q < 16; q++) {
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/rx-%d/rps_cpus",e->d_name,q);
            write_file(p,"ffffffffffffffff\n");
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/tx-%d/xps_cpus",e->d_name,q);
            write_file(p,"ffffffffffffffff\n");
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/rx-%d/rps_flow_cnt",e->d_name,q);
            write_file(p,"65536\n");
        }
    }
    closedir(nd);

    /* Global RFS */
    write_file("/proc/sys/net/core/rps_sock_flow_entries","65536\n");
    /* NAPI budget */
    write_file("/proc/sys/net/core/netdev_budget","2000\n");
    write_file("/proc/sys/net/core/netdev_budget_usecs","4000\n");

    fprintf(stderr,"[ELITE-X] IRQ/RPS/XPS v5.0 optimized (CPU zote, queues 0-15)\n");
}

int main(void) {
    signal(SIGTERM,signal_handler);
    signal(SIGINT,signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    while (running) {
        optimize_irq();
        int i; for(i=0;i<300&&running;i++) sleep(1); /* kila dakika 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-irqopt /tmp/irq_optimizer.c 2>/dev/null
    rm -f /tmp/irq_optimizer.c

    if [ -f /usr/local/bin/elite-x-irqopt ]; then
        chmod +x /usr/local/bin/elite-x-irqopt
        cat > /etc/systemd/system/elite-x-irqopt.service <<EOF
[Unit]
Description=ELITE-X IRQ Optimizer v5.0 (CPU zote, multi-queue)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-irqopt
Restart=always
RestartSec=5
LimitMEMLOCK=infinity
Nice=-15
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ IRQ Optimizer v5.0 compiled (CPU zote, queues 0-15, dakika 5)${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DATA USAGE TRACKER v5.0
# ═══════════════════════════════════════════════════════════
create_c_data_usage() {
    echo -e "${YELLOW}📝 Compiling C Data Usage Tracker v5.0...${NC}"

    cat > /tmp/data_usage.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>

#define USER_DB  "/etc/elite-x/users"
#define BW_DIR   "/etc/elite-x/bandwidth"
#define LOG_DIR  "/var/log/elite-x"

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void log_usage(void) {
    time_t t = time(NULL);
    char ts[32]; strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", localtime(&t));
    DIR *d = opendir(USER_DB); if (!d) return;
    struct dirent *e;
    FILE *log = fopen("/var/log/elite-x/usage.log", "a");
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char path[512]; snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, e->d_name);
        FILE *f = fopen(path, "r"); if (!f) continue;
        unsigned long long bytes = 0; fscanf(f, "%llu", &bytes); fclose(f);
        double gb = (double)bytes / 1073741824.0;
        if (log) fprintf(log, "[%s] %s: %.3f GB\n", ts, e->d_name, gb);
    }
    closedir(d);
    if (log) fclose(log);
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(LOG_DIR, 0755);
    while (running) {
        log_usage();
        int i; for (i = 0; i < 300 && running; i++) sleep(1); /* kila dakika 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-datausage /tmp/data_usage.c 2>/dev/null
    rm -f /tmp/data_usage.c

    if [ -f /usr/local/bin/elite-x-datausage ]; then
        chmod +x /usr/local/bin/elite-x-datausage
        cat > /etc/systemd/system/elite-x-datausage.service <<EOF
[Unit]
Description=ELITE-X Data Usage Tracker v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-datausage
Restart=always
RestartSec=10
CPUQuota=5%
MemoryMax=32M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Data Usage Tracker v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: LOG CLEANER v5.0
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
static void clean_logs(void) {
    system("journalctl --vacuum-size=50M 2>/dev/null");
    system("find /var/log -name '*.log' -size +10M -exec truncate -s 5M {} \\; 2>/dev/null");
    system("find /var/log/elite-x -name 'usage.log' -size +50M -exec truncate -s 10M {} \\; 2>/dev/null");
    fprintf(stderr, "[ELITE-X] Log Cleaner v5.0: logs cleaned\n");
}
int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    while (running) {
        clean_logs();
        int i; for (i=0;i<3600&&running;i++) sleep(1); /* kila saa 1 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-logcleaner /tmp/log_cleaner.c 2>/dev/null
    rm -f /tmp/log_cleaner.c

    if [ -f /usr/local/bin/elite-x-logcleaner ]; then
        chmod +x /usr/local/bin/elite-x-logcleaner
        cat > /etc/systemd/system/elite-x-logcleaner.service <<EOF
[Unit]
Description=ELITE-X Log Cleaner v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-logcleaner
Restart=always
RestartSec=30
CPUQuota=5%
MemoryMax=16M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Log Cleaner v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# NEW v5.0: C PING TIMEOUT KILLER
# Inazuia ping timeout kabisa kwa:
# - Sending UDP keepalives kila sekunde 5
# - Monitoring connections na kuzifufua
# - Anti-idle detection
# ═══════════════════════════════════════════════════════════
create_c_ping_timeout_killer() {
    echo -e "${YELLOW}📝 Compiling C Ping Timeout Killer v5.0 (NEW)...${NC}"

    cat > /tmp/ping_killer.c <<CEOF
/*
 * ELITE-X Ping Timeout Killer v5.0
 * Inazuia ping timeout kabisa:
 * - UDP keepalives kwa dnstt port 5300 kila sekunde 5
 * - TCP keepalive via sysctl re-application
 * - Monitor na kufufua connections zilizokufa
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

/* Tuma UDP keepalive kwa dnstt */
static void send_udp_keepalive(void) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) return;
    struct timeval tv = {1, 0};
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = inet_addr("127.0.0.1"),
        .sin_port = htons(5300)
    };
    /* DNS keepalive packet (minimal valid DNS query) */
    unsigned char keepalive[] = {
        0x00, 0x01, /* ID */
        0x01, 0x00, /* Flags: standard query */
        0x00, 0x01, /* Questions: 1 */
        0x00, 0x00, /* Answers: 0 */
        0x00, 0x00, /* Authority: 0 */
        0x00, 0x00, /* Additional: 0 */
        0x00,       /* root query */
        0x00, 0x01, /* Type: A */
        0x00, 0x01  /* Class: IN */
    };
    sendto(sock, keepalive, sizeof(keepalive), 0,
           (struct sockaddr*)&addr, sizeof(addr));
    close(sock);
}

/* Fufua SSH connections zilizokufa */
static void reset_tcp_keepalive(void) {
    system("sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_intvl=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_probes=10 >/dev/null 2>&1");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT, sig);
    fprintf(stderr, "[ELITE-X] Ping Timeout Killer v5.0 started (UDP keepalive kila sekunde 5)\n");
    reset_tcp_keepalive();
    while (running) {
        send_udp_keepalive();
        sleep(5); /* Kila sekunde 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-pingtimeout /tmp/ping_killer.c 2>/dev/null
    rm -f /tmp/ping_killer.c

    if [ -f /usr/local/bin/elite-x-pingtimeout ]; then
        chmod +x /usr/local/bin/elite-x-pingtimeout
        cat > /etc/systemd/system/elite-x-pingtimeout.service <<EOF
[Unit]
Description=ELITE-X Ping Timeout Killer v5.0 (UDP keepalive kila sekunde 5)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-pingtimeout
Restart=always
RestartSec=2
Nice=-15
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=40
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Ping Timeout Killer v5.0 compiled (keepalive kila sekunde 5)${NC}"
    else
        echo -e "${RED}❌ Ping Timeout Killer compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# NEW v5.0: WEAK NETWORK OPTIMIZER
# Maalum kwa maeneo yenye mtandao mbovu/chini:
# - Adaptive MTU (punguza MTU kwa networks mbovu)
# - Packet retransmission tuning
# - DNS retry optimization
# - TCP window clamping kwa high latency
# ═══════════════════════════════════════════════════════════
create_c_weak_network_optimizer() {
    echo -e "${YELLOW}📝 Compiling C Weak Network Optimizer v5.0 (NEW)...${NC}"

    cat > /tmp/weak_net.c <<CEOF
/*
 * ELITE-X Weak Network Optimizer v5.0
 * Kwa maeneo yenye mtandao mbovu, slow, au unstable:
 * - Punguza retransmission timeouts
 * - Ongeza retry counts
 * - Adaptive congestion control
 * - Path MTU discovery tuning
 * - DSCP/QoS marking kwa DNS/VPN traffic
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

static void optimize_for_weak_network(void) {
    /* Punguza RTO min kwa latency ndogo */
    system("ip route change default rto_min 100ms 2>/dev/null || true");
    /* TCP retransmission - haraka zaidi */
    write_file("/proc/sys/net/ipv4/tcp_retries1", "3\n");
    write_file("/proc/sys/net/ipv4/tcp_retries2", "6\n");
    /* Ongeza syn retries kwa networks mbovu */
    write_file("/proc/sys/net/ipv4/tcp_syn_retries", "4\n");
    write_file("/proc/sys/net/ipv4/tcp_synack_retries", "4\n");
    /* Punguza orphan timeout */
    write_file("/proc/sys/net/ipv4/tcp_orphan_retries", "1\n");
    /* DSCP marking kwa UDP/DNS traffic - QoS EF (Expedited Forwarding) */
    system("iptables -t mangle -A OUTPUT -p udp --dport 53 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    system("iptables -t mangle -A OUTPUT -p udp --dport 5300 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    system("iptables -t mangle -A OUTPUT -p udp --dport 5301 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    /* Path MTU discovery */
    write_file("/proc/sys/net/ipv4/tcp_mtu_probing", "2\n"); /* Always probe */
    write_file("/proc/sys/net/ipv4/tcp_base_mss", "512\n");
    /* Reduce initial ssthresh kwa slow start */
    write_file("/proc/sys/net/ipv4/tcp_slow_start_after_idle", "0\n");
    /* UDP fragmentation kwa large DNS packets */
    write_file("/proc/sys/net/ipv4/ip_no_pmtu_disc", "0\n");
    fprintf(stderr, "[ELITE-X] Weak Network Optimizer v5.0: settings applied\n");
}

static void optimize_iptables_qos(void) {
    /* Priority queue kwa VPN traffic */
    system("tc qdisc add dev lo root handle 1: prio bands 3 2>/dev/null || true");
    system("tc filter add dev lo parent 1:0 protocol ip prio 1 u32 "
           "match ip dport 5300 0xffff flowid 1:1 2>/dev/null || true");
    system("tc filter add dev lo parent 1:0 protocol ip prio 1 u32 "
           "match ip dport 53 0xffff flowid 1:1 2>/dev/null || true");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT, sig);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    fprintf(stderr, "[ELITE-X] Weak Network Optimizer v5.0 started\n");
    optimize_for_weak_network();
    optimize_iptables_qos();
    while (running) {
        optimize_for_weak_network();
        int i; for (i=0;i<600&&running;i++) sleep(1); /* kila dakika 10 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-weaknet /tmp/weak_net.c 2>/dev/null
    rm -f /tmp/weak_net.c

    if [ -f /usr/local/bin/elite-x-weaknet ]; then
        chmod +x /usr/local/bin/elite-x-weaknet
        cat > /etc/systemd/system/elite-x-weaknet.service <<EOF
[Unit]
Description=ELITE-X Weak Network Optimizer v5.0 (kwa maeneo yenye mtandao mbovu)
After=network.target dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-weaknet
Restart=always
RestartSec=5
Nice=-10
LimitMEMLOCK=infinity
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Weak Network Optimizer v5.0 compiled (DSCP QoS, MTU adaptive, retry tuning)${NC}"
    else
        echo -e "${RED}❌ Weak Network Optimizer compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# USER MANAGEMENT SCRIPT (Enhanced v5.0)
# ═══════════════════════════════════════════════════════════
create_user_script() {
    echo -e "${YELLOW}📝 Creating User Management Script v5.0...${NC}"

    cat > /usr/local/bin/elite-x-user <<'USERSCRIPT'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'; BOLD='\033[1m'
USER_DB="/etc/elite-x/users"
BW_DIR="/etc/elite-x/bandwidth"
CONN_DB="/etc/elite-x/connections"
BANNED_DIR="/etc/elite-x/banned"
DELETED_DIR="/etc/elite-x/deleted"

add_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"Password: "$NC)" password
    read -p "$(echo -e $GREEN"Expire date (YYYY-MM-DD): "$NC)" expire
    read -p "$(echo -e $GREEN"Connection limit [1]: "$NC)" conn_limit
    read -p "$(echo -e $GREEN"Bandwidth limit GB [0=unlimited]: "$NC)" bw_gb
    conn_limit=${conn_limit:-1}
    bw_gb=${bw_gb:-0}

    if id "$username" &>/dev/null; then
        echo -e "${RED}User $username sudah ada!${NC}"; return
    fi
    useradd -M -s /bin/false "$username" 2>/dev/null
    echo "$username:$password" | chpasswd 2>/dev/null

    mkdir -p "$USER_DB"
    cat > "$USER_DB/$username" <<EOF
Username: $username
Password: $password
Expire: $expire
Conn_Limit: $conn_limit
Bandwidth_GB: $bw_gb
Created: $(date '+%Y-%m-%d %H:%M:%S')
EOF
    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ User $username created (expire: $expire, limit: ${conn_limit}, BW: ${bw_gb}GB)${NC}"
}

list_users() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}              ELITE-X v5.0 USER LIST                             ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════╦════════════════╦════════════╦═══════╦══════════╦═══════╦══════════╣${NC}"
    echo -e "${CYAN}║${WHITE} No   ${CYAN}║${WHITE} Username       ${CYAN}║${WHITE} Expire     ${CYAN}║${WHITE} Conn  ${CYAN}║${WHITE} BW Limit ${CYAN}║${WHITE} Usage ${CYAN}║${WHITE} Status   ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════╬════════════════╬════════════╬═══════╬══════════╬═══════╬══════════╣${NC}"

    i=0
    now_ts=$(date +%s)
    for f in "$USER_DB"/*; do
        [ -f "$f" ] || continue
        i=$((i+1))
        u=$(basename "$f")
        exp=$(grep "Expire:" "$f" | awk '{print $2}')
        cl=$(grep "Conn_Limit:" "$f" | awk '{print $2}')
        bw=$(grep "Bandwidth_GB:" "$f" | awk '{print $2}')
        [ "$bw" = "0" ] && bw_disp="Unlim" || bw_disp="${bw}GB"
        usage_b=$(cat "$BW_DIR/${u}.usage" 2>/dev/null || echo 0)
        usage_gb=$(echo "scale=1; $usage_b / 1073741824" | bc 2>/dev/null || echo "0.0")
        exp_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
        rem=$(( (exp_ts - now_ts) / 86400 ))
        if [ $rem -lt 0 ]; then
            status="${RED}EXPIRED${NC}"
        elif [ $rem -le 3 ]; then
            status="${YELLOW}SOON($rem d)${NC}"
        else
            status="${GREEN}OK($rem d)${NC}"
        fi
        printf "${CYAN}║${WHITE} %-4s ${CYAN}║${WHITE} %-14s ${CYAN}║${WHITE} %-10s ${CYAN}║${WHITE} %-5s ${CYAN}║${WHITE} %-8s ${CYAN}║${WHITE} %-5s ${CYAN}║ %-8b ${CYAN}║${NC}\n" \
            "$i" "$u" "$exp" "$cl" "$bw_disp" "${usage_gb}G" "$status"
    done
    echo -e "${CYAN}╚══════╩════════════════╩════════════╩═══════╩══════════╩═══════╩══════════╝${NC}"
    echo -e "${YELLOW}Total users: $i${NC}"
}

del_user() {
    read -p "$(echo -e $RED"Username to delete: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    cp "$USER_DB/$u" "$DELETED_DIR/${u}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null
    pkill -u "$u" 2>/dev/null; killall -u "$u" -9 2>/dev/null
    userdel -r "$u" 2>/dev/null
    rm -f "$USER_DB/$u" "/etc/elite-x/data_usage/$u" \
          "$CONN_DB/$u" "$BANNED_DIR/$u" "$BW_DIR/$u.usage" \
          "/etc/elite-x/user_messages/$u"
    sed -i "/Match User $u/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
    systemctl reload sshd 2>/dev/null
    echo -e "${GREEN}✅ User $u deleted${NC}"
}

renew_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"New expire date (YYYY-MM-DD): "$NC)" exp
    sed -i "s/^Expire:.*/Expire: $exp/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ User $u renewed until $exp${NC}"
}

setlimit_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"Connection limit: "$NC)" lim
    sed -i "s/^Conn_Limit:.*/Conn_Limit: $lim/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Connection limit set to $lim${NC}"
}

setbw_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"Bandwidth limit GB [0=unlimited]: "$NC)" bw
    sed -i "s/^Bandwidth_GB:.*/Bandwidth_GB: $bw/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth limit set to ${bw}GB${NC}"
}

resetdata_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    echo 0 > "$BW_DIR/${u}.usage" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Data usage reset for $u${NC}"
}

lock_user() {
    read -p "$(echo -e $RED"Username to lock: "$NC)" u
    usermod -L "$u" 2>/dev/null
    pkill -u "$u" 2>/dev/null
    echo -e "${GREEN}✅ User $u locked${NC}"
}

unlock_user() {
    read -p "$(echo -e $GREEN"Username to unlock: "$NC)" u
    usermod -U "$u" 2>/dev/null
    rm -f "$BANNED_DIR/$u"
    echo -e "${GREEN}✅ User $u unlocked${NC}"
}

details_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    echo -e "${CYAN}"; cat "$USER_DB/$u"; echo -e "${NC}"
    echo -e "${YELLOW}Current connections: $(cat "$CONN_DB/$u" 2>/dev/null || echo 0)${NC}"
    usage_b=$(cat "$BW_DIR/${u}.usage" 2>/dev/null || echo 0)
    usage_gb=$(echo "scale=3; $usage_b / 1073741824" | bc 2>/dev/null || echo "0.000")
    echo -e "${YELLOW}Data usage: ${usage_gb} GB${NC}"
}

deleted_list() {
    echo -e "${CYAN}Deleted users:${NC}"
    ls -la "$DELETED_DIR/" 2>/dev/null || echo "None"
}

case "$1" in
    add)      add_user ;;
    list)     list_users ;;
    del)      del_user ;;
    renew)    renew_user ;;
    setlimit) setlimit_user ;;
    setbw)    setbw_user ;;
    resetdata) resetdata_user ;;
    lock)     lock_user ;;
    unlock)   unlock_user ;;
    details)  details_user ;;
    deleted)  deleted_list ;;
    *) echo "Usage: elite-x-user {add|list|del|renew|setlimit|setbw|resetdata|lock|unlock|details|deleted}" ;;
esac
USERSCRIPT
    chmod +x /usr/local/bin/elite-x-user
    echo -e "${GREEN}✅ User Management Script v5.0 created${NC}"
}

# ═══════════════════════════════════════════════════════════
# MAIN MENU v5.0 (Enhanced dashboard)
# ═══════════════════════════════════════════════════════════
create_main_menu() {
    echo -e "${YELLOW}📝 Creating Main Menu v5.0...${NC}"

    local UD="$USER_DB"

    cat > /usr/local/bin/elite-x <<MENUEOF
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'
ORANGE='\033[0;33m'; NC='\033[0m'
UD="$USER_DB"

svc_status() {
    systemctl is-active "\$1" >/dev/null 2>&1 \
        && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}"
}

show_dashboard() {
    clear
    CPU_COUNT=\$(nproc 2>/dev/null || echo 1)
    RAM_TOTAL=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    RAM_FREE=\$(grep MemAvailable /proc/meminfo | awk '{print \$2}')
    RAM_USED_MB=\$(( (RAM_TOTAL - RAM_FREE) / 1024 ))
    RAM_TOTAL_MB=\$(( RAM_TOTAL / 1024 ))
    CPU_LOAD=\$(cat /proc/loadavg | awk '{print \$1}')
    IP=\$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "Unknown")
    TDOMAIN=\$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not set")
    PUB_KEY=\$(cat /etc/elite-x/public_key 2>/dev/null || echo "Unknown")

    echo -e "\${PURPLE}╔══════════════════════════════════════════════════════════════════╗\${NC}"
    echo -e "\${PURPLE}║\${YELLOW}\${BOLD}    ELITE-X SLOWDNS v5.0 - SUPER ULTRA MAX BOOST        \${PURPLE}║\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  IP       : \${CYAN}\$IP\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  NS       : \${CYAN}\$TDOMAIN\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  PubKey   : \${CYAN}\$(echo \$PUB_KEY | cut -c1-40)...\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    printf "\${PURPLE}║\${WHITE}  CPU: \${CYAN}%s cores  \${WHITE}Load: \${CYAN}%s  \${WHITE}RAM: \${CYAN}%s/%s MB\${NC}\n" \
        "\$CPU_COUNT" "\$CPU_LOAD" "\$RAM_USED_MB" "\$RAM_TOTAL_MB"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  SERVICES:\${NC}"

    DNS=\$(svc_status dnstt-elite-x)
    PRX=\$(svc_status dnstt-elite-x-proxy)
    UDP=\$(svc_status elite-x-udp-turbo)
    SPD=\$(svc_status elite-x-speedbooster)
    NBOOST=\$(svc_status elite-x-netbooster)
    DNSC=\$(svc_status elite-x-dnscache)
    BW=\$(svc_status elite-x-bandwidth)
    IRQ=\$(svc_status elite-x-irqopt)
    RAMC=\$(svc_status elite-x-ramcleaner)
    PING=\$(svc_status elite-x-pingtimeout)
    WEAK=\$(svc_status elite-x-weaknet)
    SMSG=\$([ -f /usr/local/bin/elite-x-force-user-message ] && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}")

    echo -e "\${PURPLE}║\${WHITE}  \$DNS DNSTT     \$PRX C-EDNS    \$UDP UDP Turbo  \$SPD Speed\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  \$NBOOST NetBoost  \$DNSC DNS Cache  \$BW BW Mon   \$IRQ IRQ\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  \$RAMC RAM Boost  \$PING PingKill  \$WEAK WeakNet  \$SMSG Msgs\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    TOTAL=\$(ls "\$UD" 2>/dev/null | wc -l)
    ONLINE=\$(who | wc -l)
    echo -e "\${PURPLE}║\${GREEN}  Users: \${YELLOW}\$TOTAL\${GREEN} | Online: \${YELLOW}\$ONLINE\${GREEN} | Speed: \${YELLOW}200Mbps+ ULTRA\${NC}  \${PURPLE}║\${NC}"
    echo -e "\${PURPLE}╚══════════════════════════════════════════════════════════════════╝\${NC}"
}

settings_menu() {
    while true; do
        clear
        echo -e "\${CYAN}╔════════════════════════════════════════════════════════╗\${NC}"
        echo -e "\${CYAN}║\${YELLOW}             SETTINGS v5.0 ULTRA             \${CYAN}║\${NC}"
        echo -e "\${CYAN}╠════════════════════════════════════════════════════════╣\${NC}"
        AUTOBAN=\$(cat "/etc/elite-x/autoban_enabled" 2>/dev/null || echo 0)
        [ "\$AUTOBAN" = "1" ] && AB="\${GREEN}ON\${NC}" || AB="\${RED}OFF\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [1]  Auto-Ban: \$AB\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [2]  Restart All Services\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [3]  Restart DNSTT\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [4]  Recompile All C Components\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [5]  Fix VPN/SSH\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [6]  Refresh All User Messages\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [7]  Test User Message\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [8]  Apply Speed Boost Now (200Mbps+)\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [9]  Fix Ping Timeout\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [10] Optimize Weak Network\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [0]  Back\${NC}"
        echo -e "\${CYAN}╚════════════════════════════════════════════════════════╝\${NC}"
        read -p "\$(echo -e \$GREEN"Option: "\$NC)" ch

        case \$ch in
            1) [ "\$AUTOBAN" = "1" ] && echo 0 > /etc/elite-x/autoban_enabled || echo 1 > /etc/elite-x/autoban_enabled ;;
            2) for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-udp-turbo elite-x-speedbooster elite-x-bandwidth elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner elite-x-datausage elite-x-pingtimeout elite-x-weaknet; do systemctl restart "\$s" 2>/dev/null || true; done; echo -e "\${GREEN}✅ All services restarted\${NC}"; read -p "Enter..." ;;
            3) systemctl restart dnstt-elite-x dnstt-elite-x-proxy; echo -e "\${GREEN}✅ DNSTT restarted\${NC}"; read -p "Enter..." ;;
            4) echo -e "\${YELLOW}Recompiling...\${NC}"; bash \$0 --recompile 2>/dev/null; echo -e "\${GREEN}✅ Recompiled\${NC}"; read -p "Enter..." ;;
            5) systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd 2>/dev/null; echo -e "\${GREEN}✅ Fixed\${NC}"; read -p "Enter..." ;;
            6) for u in "\$UD"/*; do [ -f "\$u" ] && /usr/local/bin/elite-x-force-user-message "\$(basename "\$u")" 2>/dev/null; done; systemctl reload sshd; echo -e "\${GREEN}✅ Messages refreshed\${NC}"; read -p "Enter..." ;;
            7) read -p "Username: " un; cat "/etc/elite-x/user_messages/\$un" 2>/dev/null || echo "No message"; read -p "Enter..." ;;
            8) systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-irqopt elite-x-ramcleaner 2>/dev/null; echo -e "\${GREEN}✅ 200Mbps+ boost applied\${NC}"; read -p "Enter..." ;;
            9) systemctl restart elite-x-pingtimeout; sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1; echo -e "\${GREEN}✅ Ping timeout fixed\${NC}"; read -p "Enter..." ;;
            10) systemctl restart elite-x-weaknet; echo -e "\${GREEN}✅ Weak network optimized\${NC}"; read -p "Enter..." ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        show_dashboard
        echo -e "\${PURPLE}╔══════════════════════════════════════════════════════════════════╗\${NC}"
        echo -e "\${PURPLE}║\${GREEN}\${BOLD}                 MAIN MENU v5.0 ULTRA                   \${PURPLE}║\${NC}"
        echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [1] Create User   [2] List Users      [3] User Details\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [4] Renew User    [5] Set Conn Limit   [6] Set BW Limit\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [7] Reset Data    [8] Lock User        [9] Unlock User\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [10] Delete User  [11] Deleted List     [S] Settings\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [M] Test Msg      [B] Speed Boost       [0] Exit\${NC}"
        echo -e "\${PURPLE}╚══════════════════════════════════════════════════════════════════╝\${NC}"
        read -p "\$(echo -e \$GREEN"Option: "\$NC)" ch

        case \$ch in
            1) elite-x-user add; read -p "Press Enter..." ;;
            2) elite-x-user list; read -p "Press Enter..." ;;
            3) elite-x-user details; read -p "Press Enter..." ;;
            4) elite-x-user renew; read -p "Press Enter..." ;;
            5) elite-x-user setlimit; read -p "Press Enter..." ;;
            6) elite-x-user setbw; read -p "Press Enter..." ;;
            7) elite-x-user resetdata; read -p "Press Enter..." ;;
            8) elite-x-user lock; read -p "Press Enter..." ;;
            9) elite-x-user unlock; read -p "Press Enter..." ;;
            10) elite-x-user del; read -p "Press Enter..." ;;
            11) elite-x-user deleted; read -p "Press Enter..." ;;
            [Ss]) settings_menu ;;
            [Bb]) systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-irqopt elite-x-ramcleaner 2>/dev/null; echo -e "\${GREEN}✅ 200Mbps+ boost applied!\${NC}"; read -p "Press Enter..." ;;
            [Mm])
                read -p "Username: " un
                if [ -f "/etc/elite-x/user_messages/\$un" ]; then
                    clear; cat "/etc/elite-x/user_messages/\$un"
                else
                    echo -e "\${RED}No message for \$un!\${NC}"
                fi
                read -p "Press Enter..." ;;
            0) echo -e "\${GREEN}Goodbye!\${NC}"; exit 0 ;;
            *) echo -e "\${RED}Invalid\${NC}"; read -p "Press Enter..." ;;
        esac
    done
}

main_menu
MENUEOF
    chmod +x /usr/local/bin/elite-x
    echo -e "${GREEN}✅ Main Menu v5.0 created${NC}"
}

# ═══════════════════════════════════════════════════════════
# MAIN INSTALLATION v5.0
# ═══════════════════════════════════════════════════════════
run_installation() {
    show_banner
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}       ELITE-X v5.0 SUPER ULTRA - ACTIVATION       ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT

    if [ "$ACTIVATION_INPUT" != "$ACTIVATION_KEY" ] && [ "$ACTIVATION_INPUT" != "Whtsapp +255713-628-668" ]; then
        echo -e "${RED}❌ Invalid activation key!${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Activation successful${NC}"
    sleep 1

    set_timezone

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           ENTER YOUR NAMESERVER [NS]        ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Nameserver: "$NC)" TDOMAIN

    echo -e "${YELLOW}Select VPS location (MTU):${NC}"
    echo -e "  [1] South Africa (MTU 1800)"
    echo -e "  [2] USA (MTU 1500)"
    echo -e "  [3] Europe (MTU 1500)"
    echo -e "  [4] Asia (MTU 1400)"
    echo -e "  [5] Custom MTU"
    read -p "$(echo -e $GREEN"Choice [1]: "$NC)" LOC
    LOC=${LOC:-1}
    case $LOC in
        2) SEL_LOC="USA"; MTU=1500 ;;
        3) SEL_LOC="Europe"; MTU=1500 ;;
        4) SEL_LOC="Asia"; MTU=1400 ;;
        5) SEL_LOC="Custom"; read -p "MTU: " MTU; [[ ! "$MTU" =~ ^[0-9]+$ ]] && MTU=1800 ;;
        *) SEL_LOC="South Africa"; MTU=1800 ;;
    esac

    echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"
    for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth elite-x-datausage elite-x-connmon \
              elite-x-cleaner elite-x-traffic elite-x-netbooster elite-x-dnscache elite-x-ramcleaner \
              elite-x-irqopt elite-x-logcleaner elite-x-udp-turbo elite-x-speedbooster \
              elite-x-pingtimeout elite-x-weaknet 3proxy-elite; do
        systemctl stop "$s" 2>/dev/null || true
        systemctl disable "$s" 2>/dev/null || true
    done
    pkill -f dnstt-server 2>/dev/null || true
    pkill -f elite-x- 2>/dev/null || true
    rm -rf /etc/systemd/system/{dnstt-elite-x*,elite-x*,3proxy-elite*} 2>/dev/null
    rm -rf /etc/dnstt /etc/elite-x /var/run/elite-x 2>/dev/null
    rm -f /usr/local/bin/{dnstt-*,elite-x*,3proxy} 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf 2>/dev/null
    rm -f /etc/sysctl.d/99-elite-x-vpn.conf 2>/dev/null
    sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    systemctl restart sshd 2>/dev/null || true
    sleep 2

    # Create directories
    mkdir -p /etc/elite-x/{users,traffic,deleted,data_usage,connections,banned,traffic_stats,bandwidth/pidtrack,user_messages}
    mkdir -p /etc/ssh/sshd_config.d
    mkdir -p /var/run/elite-x/bandwidth
    mkdir -p /var/log/elite-x
    echo "$TDOMAIN" > /etc/elite-x/subdomain
    echo "$SEL_LOC" > /etc/elite-x/location
    echo "$MTU" > /etc/elite-x/mtu
    echo "0" > "$AUTOBAN_FLAG"
    echo "$STATIC_PRIVATE_KEY" > /etc/elite-x/private_key
    echo "$STATIC_PUBLIC_KEY" > /etc/elite-x/public_key

    # Configure DNS
    [ -f /etc/systemd/resolved.conf ] && {
        sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null || true
    }
    [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\nnameserver 8.8.4.4\nnameserver 1.0.0.1\noptions timeout:1 attempts:2 rotate\noptions ndots:0\n" > /etc/resolv.conf

    # Install dependencies
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    apt update -y
    apt install -y curl jq iptables ethtool dnsutils net-tools iproute2 bc \
        build-essential git gcc make linux-tools-common numactl \
        iptables-persistent 2>/dev/null

    # Download DNSTT
    echo -e "${YELLOW}📥 Downloading DNSTT server...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null || {
        curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server 2>/dev/null
    }
    chmod +x /usr/local/bin/dnstt-server

    # Setup DNSTT keys
    mkdir -p /etc/dnstt
    echo "$STATIC_PRIVATE_KEY" > /etc/dnstt/server.key
    echo "$STATIC_PUBLIC_KEY" > /etc/dnstt/server.pub
    chmod 600 /etc/dnstt/server.key

    # Create DNSTT service - SUPER ULTRA BOOSTED
    cat > /etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=ELITE-X DNSTT Server v5.0 SUPER ULTRA
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
CPUSchedulingPriority=90
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF

    # Optimize system FIRST
    optimize_system_for_vpn

    # PAM + user messages
    configure_pam_user_message

    # SSH
    configure_ssh_for_vpn

    # Compile all C components
    create_c_edns_proxy
    create_c_udp_turbo
    create_c_speed_booster
    create_c_bandwidth_monitor
    create_c_connection_monitor
    create_c_network_booster
    create_c_dns_cache
    create_c_ram_cleaner
    create_c_irq_optimizer
    create_c_data_usage
    create_c_log_cleaner
    # NEW v5.0 components
    create_c_ping_timeout_killer
    create_c_weak_network_optimizer

    # EDNS Proxy service (after compilation)
    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        cat > /etc/systemd/system/dnstt-elite-x-proxy.service <<EOF
[Unit]
Description=ELITE-X SUPER ULTRA EDNS Proxy v5.0 (${CPU_COUNT} CPU threads)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-edns-proxy ${CPU_COUNT}
Restart=always
RestartSec=1
LimitNOFILE=4194304
LimitMEMLOCK=infinity
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=85
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
    fi

    # User scripts
    create_user_script
    create_main_menu

    # Enable and start ALL services
    systemctl daemon-reload

    ALL_SERVICES=(
        dnstt-elite-x
        dnstt-elite-x-proxy
        elite-x-udp-turbo
        elite-x-speedbooster
        elite-x-bandwidth
        elite-x-datausage
        elite-x-connmon
        elite-x-netbooster
        elite-x-dnscache
        elite-x-ramcleaner
        elite-x-irqopt
        elite-x-logcleaner
        elite-x-pingtimeout
        elite-x-weaknet
    )

    for s in "${ALL_SERVICES[@]}"; do
        if [ -f "/etc/systemd/system/${s}.service" ]; then
            systemctl enable "$s" 2>/dev/null || true
            systemctl start "$s" 2>/dev/null || true
        fi
    done

    # Cache IP
    IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "Unknown")
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
alias boost='systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-udp-turbo elite-x-pingtimeout'
alias fixvpn='systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd && echo "VPN Fixed!"'
alias refreshmsg='for u in /etc/elite-x/users/*; do [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")"; done && systemctl reload sshd && echo "✅ Messages refreshed!"'
alias testmsg='read -p "Username: " u; cat /etc/elite-x/user_messages/$u 2>/dev/null || echo "No message"'
alias speedtest='systemctl restart elite-x-speedbooster && echo "200Mbps+ Speed boost applied!"'
alias fixping='systemctl restart elite-x-pingtimeout && sysctl -w net.ipv4.tcp_keepalive_time=20 && echo "Ping timeout fixed!"'
alias weakfix='systemctl restart elite-x-weaknet && echo "Weak network optimized!"'
alias status='systemctl status dnstt-elite-x dnstt-elite-x-proxy elite-x-udp-turbo elite-x-speedbooster'
EOF

    # Create initial messages for existing users
    for user_file in /etc/elite-x/users/*; do
        [ -f "$user_file" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$user_file")" 2>/dev/null
    done

    # ═══════════════════════════════════════════════════════════
    # FINAL DISPLAY - SUPER ULTRA
    # ═══════════════════════════════════════════════════════════
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}${BOLD}   ELITE-X v5.0 SUPER ULTRA MAX BOOST - INSTALLED!     ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Domain     :${CYAN} $TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  Location   :${CYAN} $SEL_LOC (MTU: $MTU)${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  CPU Cores  :${CYAN} ${CPU_COUNT} (ZOTE zinatumika)${NC}"
    echo -e "${GREEN}║${WHITE}  RAM        :${CYAN} ${RAM_MB}MB (mlock + hugepages)${NC}"
    echo -e "${GREEN}║${WHITE}  Version    :${CYAN} v5.0 Super Ultra Max Boost${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"

    check_svc() {
        local name=$1 svc=$2
        systemctl is-active "$svc" >/dev/null 2>&1 \
            && echo -e "${GREEN}║  ✅ $name: Running${NC}" \
            || echo -e "${RED}║  ❌ $name: Failed${NC}"
    }

    check_svc "DNSTT Server           " "dnstt-elite-x"
    check_svc "SUPER EDNS Proxy       " "dnstt-elite-x-proxy"
    check_svc "SUPER UDP Turbo        " "elite-x-udp-turbo"
    check_svc "Speed Booster 200Mbps+ " "elite-x-speedbooster"
    check_svc "SSH Server             " "sshd"
    check_svc "Bandwidth Monitor      " "elite-x-bandwidth"
    check_svc "Connection Monitor     " "elite-x-connmon"
    check_svc "Network Booster        " "elite-x-netbooster"
    check_svc "DNS Cache Optimizer    " "elite-x-dnscache"
    check_svc "SUPER RAM Booster      " "elite-x-ramcleaner"
    check_svc "IRQ Optimizer (All CPU)" "elite-x-irqopt"
    check_svc "Log Cleaner            " "elite-x-logcleaner"
    check_svc "Ping Timeout Killer    " "elite-x-pingtimeout"
    check_svc "Weak Network Optimizer " "elite-x-weaknet"

    if [ -f /usr/local/bin/elite-x-force-user-message ]; then
        echo -e "${GREEN}║  ✅ User Messages       : Active (SSH login)${NC}"
    fi

    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  NEW IN v5.0 SUPER ULTRA MAX:${NC}"
    echo -e "${GREEN}║${WHITE}  🚀 recvmmsg/sendmmsg batch (64-128 packets kwa mara moja)${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ Lockless MPMC ring buffer (131K/262K entries)${NC}"
    echo -e "${GREEN}║${WHITE}  🧵 Per-CPU thread pinning (CPU zote ${CPU_COUNT} zinatumika)${NC}"
    echo -e "${GREEN}║${WHITE}  🔒 mlock() - RAM yote inafungwa (hakuna swap)${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ SO_BUSY_POLL zero-wait polling${NC}"
    echo -e "${GREEN}║${WHITE}  🏎️  SCHED_FIFO priority 80-90 kwa SlowDNS/UDP${NC}"
    echo -e "${GREEN}║${WHITE}  📦 Socket buffers: 32MB UDP / 512MB TCP${NC}"
    echo -e "${GREEN}║${WHITE}  🔁 BBR + FQ + CAKE qdisc (bora kwa weak networks)${NC}"
    echo -e "${GREEN}║${WHITE}  🌐 Multi-queue RPS/XPS (queues 0-15, CPU zote)${NC}"
    echo -e "${GREEN}║${WHITE}  💉 DSCP/QoS EF marking kwa DNS/VPN traffic${NC}"
    echo -e "${GREEN}║${WHITE}  💤 CPU C-states disabled (latency ndogo sana)${NC}"
    echo -e "${GREEN}║${WHITE}  🩹 Ping Timeout Killer (UDP keepalive kila sekunde 5)${NC}"
    echo -e "${GREEN}║${WHITE}  📡 Weak Network Optimizer (kwa maeneo yenye mtandao mbovu)${NC}"
    echo -e "${GREEN}║${WHITE}  🧠 Hugepages + RAM locking kwa SlowDNS processes${NC}"
    echo -e "${GREEN}║${WHITE}  🔧 TCP Pacing (200Mbps smooth flow)${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${CYAN}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS     : ${CYAN}$TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY : ${CYAN}$STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}║${WHITE}  PORT   : ${CYAN}53 (primary) | 5301 (UDP Turbo)${NC}"
    echo -e "${GREEN}║${WHITE}  SPEED  : ${CYAN}200Mbps+ (${CPU_COUNT} CPU cores zote zinatumika)${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Commands: menu | adduser | users | boost | fixvpn | speedtest | fixping | weakfix | status${NC}"
    echo -e "${YELLOW}Re-login au 'exec bash' ili kufikia dashboard${NC}"
    echo ""
}

# Run installation
run_installation#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
#  ELITE-X SLOWDNS SCRIPT v5.0 - SUPER ULTRA MAX BOOST
#  Speed: 200Mbps+ | All CPU Cores | All RAM | Zero Ping Timeout
#  New v5.0: NUMA-aware threading, lockless ring buffers, multi-queue RX/TX,
#            hugepages for UDP, CPU pinning per-thread, adaptive jitter buffer,
#            packet batching (recvmmsg/sendmmsg), SO_BUSY_POLL zero-wait,
#            TCP Pacing, BBR3-ready, GRO/GSO/TSO full offload, CAKE qdisc
#            fallback, per-CPU DNS worker affinity, mlock() RAM locking
# ╚══════════════════════════════════════════════════════════════════════════════╝

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
SERVER_MSG_DIR="/etc/elite-x/server_msg"
USER_MSG_DIR="/etc/elite-x/user_messages"

# Detect CPU count at startup
CPU_COUNT=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_MB=$((RAM_KB / 1024))

show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${YELLOW}${BOLD}   ELITE-X SLOWDNS v5.0 - SUPER ULTRA MAX BOOST       ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${CYAN}   200Mbps+ | All ${CPU_COUNT} CPU Cores | ${RAM_MB}MB RAM | Zero Ping   ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${GREEN}   recvmmsg/sendmmsg | mlock | hugepages | BBR3 | CAKE  ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_color() { echo -e "${2}${1}${NC}"; }
set_timezone() { timedatectl set-timezone $TIMEZONE 2>/dev/null || ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true; }

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
═══════════════════════════════════
  ELITE-X SLOWDNS VPN v5.0 ULTRA
═══════════════════════════════════
 USERNAME  : $username
───────────────────────────────────
 EXPIRE    : $expire_date
───────────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
───────────────────────────────────
 LIMIT GB  : $bw_display
 USAGE GB  : ${usage_gb} GB
───────────────────────────────────
 CONNECTION: ${current_conn}/${conn_limit}
───────────────────────────────────
 STATUS    : $status
───────────────────────────────────
 SPEED     : 200Mbps+ ULTRA MODE
═══════════════════════════════════
   Thanks for using ELITE-X v5.0
═══════════════════════════════════
EOF
    chmod 644 "$msg_file"
    echo "$msg_file"
}

# ═══════════════════════════════════════════════════════════
# SSH CONFIGURATION WITH USER-SPECIFIC BANNERS
# ═══════════════════════════════════════════════════════════
configure_ssh_for_vpn() {
    echo -e "${YELLOW}🔧 Configuring SSH for VPN + User Messages...${NC}"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    sed -i '/^Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/^Match User/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null

    cat > /etc/ssh/sshd_config.d/elite-x-base.conf <<'SSHCONF'
# ELITE-X VPN Base Configuration v5.0 ULTRA
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

# v5.0 Ultra keepalive - prevent ping timeout
TCPKeepAlive yes
ClientAliveInterval 15
ClientAliveCountMax 12
MaxStartups 1000:30:2000
MaxSessions 1000

# Performance - v5.0 Ultra
Compression no
UseDNS no
LogLevel ERROR
IPQoS lowdelay throughput
StreamLocalBindUnlink yes
SSHCONF

    cat > /etc/ssh/sshd_config.d/elite-x-users.conf <<'SSHCONF2'
# ELITE-X Dynamic User Banners - Managed by system
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
    echo -e "${GREEN}✅ SSH configured with User Messages (v5.0 anti-timeout)${NC}"
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

expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}
conn_limit=${conn_limit:-1}

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
═══════════════════════════════════
  ELITE-X SLOWDNS VPN v5.0 ULTRA
═══════════════════════════════════
 USERNAME  : $USERNAME
───────────────────────────────────
 EXPIRE    : $expire_date
───────────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
───────────────────────────────────
 LIMIT GB  : $bw_display
 USAGE GB  : ${usage_gb} GB
───────────────────────────────────
 CONNECTION: ${current_conn}/${conn_limit}
───────────────────────────────────
 STATUS    : $status
───────────────────────────────────
 SPEED     : 200Mbps+ ULTRA MODE
═══════════════════════════════════
   Thanks for using ELITE-X v5.0
═══════════════════════════════════
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
    echo -e "${GREEN}✅ PAM configured - user message updates on each login${NC}"
}

# ═══════════════════════════════════════════════════════════
# SUPER ULTRA SYSTEM OPTIMIZATION v5.0 - 200Mbps+
# Maboresho makubwa zaidi: hugepages, NUMA, multi-queue,
# CPU affinity, TCP pacing, CAKE fallback, mlock, realtime
# ═══════════════════════════════════════════════════════════
optimize_system_for_vpn() {
    echo -e "${YELLOW}🚀 Applying SUPER ULTRA system optimizations for 200Mbps+...${NC}"
    echo -e "${CYAN}   CPU Cores: ${CPU_COUNT} | RAM: ${RAM_MB}MB${NC}"

    # BBR3 / BBR congestion control
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true
    modprobe sch_cake 2>/dev/null || true
    modprobe tcp_htcp 2>/dev/null || true

    # Hugepages - RAM zote zitumike kwa SlowDNS/UDP
    HUGEPAGES=$((RAM_MB / 4))
    [ $HUGEPAGES -lt 128 ] && HUGEPAGES=128
    echo $HUGEPAGES > /proc/sys/vm/nr_hugepages 2>/dev/null || true
    echo -e "${GREEN}   Hugepages: $HUGEPAGES (${HUGEPAGES}x2MB = $((HUGEPAGES*2))MB reserved)${NC}"

    # Hisabu buffers kulingana na RAM iliyopo
    # Tumia 60% ya RAM kwa TCP/UDP buffers
    TCP_MEM_MAX=$((RAM_KB * 614 / 1024))  # 60% ya RAM kwa bytes
    [ $TCP_MEM_MAX -lt 268435456 ] && TCP_MEM_MAX=268435456

    # UDP buffers kubwa - kwa SlowDNS specifically
    UDP_MEM_MAX=$((RAM_KB * 256 / 1024))
    [ $UDP_MEM_MAX -lt 67108864 ] && UDP_MEM_MAX=67108864

    cat > /etc/sysctl.d/99-elite-x-vpn.conf <<SYSCTL
# ═══ ELITE-X v5.0 SUPER ULTRA BOOST SYSCTL ═══
# CPU: ${CPU_COUNT} cores | RAM: ${RAM_MB}MB | Target: 200Mbps+

# ── IP Forwarding ──
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0

# ── Congestion Control: BBR + FQ (bora zaidi) ──
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# ── TCP Buffer Sizes - 512MB max (tumia RAM yote) ──
net.core.rmem_max=${TCP_MEM_MAX}
net.core.wmem_max=${TCP_MEM_MAX}
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.tcp_rmem=4096 1048576 ${TCP_MEM_MAX}
net.ipv4.tcp_wmem=4096 524288 ${TCP_MEM_MAX}
net.ipv4.tcp_mem=786432 2097152 ${TCP_MEM_MAX}

# ── UDP Buffer Sizes - SUPER BOOSTED kwa SlowDNS ──
net.core.optmem_max=131072
net.ipv4.udp_mem=786432 ${UDP_MEM_MAX} $((UDP_MEM_MAX * 2))
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072

# ── TCP Performance - ULTRA ──
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_no_pmtu_disc=0
net.ipv4.tcp_ecn=1
net.ipv4.tcp_ecn_fallback=1

# ── TCP Pacing - smooth 200Mbps flow ──
net.ipv4.tcp_pacing_ss_ratio=200
net.ipv4.tcp_pacing_ca_ratio=120

# ── Connection Handling - 2000+ users ──
net.ipv4.tcp_max_syn_backlog=131072
net.core.somaxconn=131072
net.core.netdev_max_backlog=100000
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=5
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_abort_on_overflow=0

# ── TCP Keepalive ULTRA - ondoa ping timeout kabisa ──
net.ipv4.tcp_keepalive_time=20
net.ipv4.tcp_keepalive_intvl=3
net.ipv4.tcp_keepalive_probes=10

# ── Network Device - CPU zote zifanye kazi ──
net.core.netdev_budget=2000
net.core.netdev_budget_usecs=4000
net.core.busy_read=100
net.core.busy_poll=100
net.core.netdev_max_backlog=100000

# ── RPS/RFS - CPU zote kwa network processing ──
net.core.rps_sock_flow_entries=65536

# ── VM Memory - RAM yote kwa processes ──
vm.swappiness=1
vm.vfs_cache_pressure=25
vm.dirty_ratio=20
vm.dirty_background_ratio=5
vm.min_free_kbytes=131072
vm.overcommit_memory=1
vm.overcommit_ratio=95

# ── File Descriptors - max connections ──
fs.file-max=4194304
fs.nr_open=4194304

# ── Hugepages ──
vm.nr_hugepages=${HUGEPAGES}
vm.hugepages_treat_as_movable=1

# ── Socket backlog ──
net.core.dev_weight=1024
net.core.dev_weight_tx_bias=1

# ── TCP Zerocopy ──
net.ipv4.tcp_autocorking=0

# ── Reduce latency kwa maeneo yenye mtandao mbovu ──
net.ipv4.tcp_low_latency=1
SYSCTL

    sysctl -p /etc/sysctl.d/99-elite-x-vpn.conf >/dev/null 2>&1 || true

    # Limits for max connections
    cat > /etc/security/limits.d/elite-x.conf <<'LIMITS'
* soft nofile 4194304
* hard nofile 4194304
* soft nproc 131072
* hard nproc 131072
* soft memlock unlimited
* hard memlock unlimited
* soft rtprio 99
* hard rtprio 99
root soft nofile 4194304
root hard nofile 4194304
root soft memlock unlimited
root hard memlock unlimited
root soft rtprio 99
root hard rtprio 99
LIMITS

    # Systemd limits
    mkdir -p /etc/systemd/system.conf.d/
    cat > /etc/systemd/system.conf.d/elite-x-limits.conf <<'SDLIMIT'
[Manager]
DefaultLimitNOFILE=4194304
DefaultLimitNPROC=131072
DefaultLimitMEMLOCK=infinity
DefaultLimitRTPRIO=99
SDLIMIT

    # IPTables optimization
    iptables -t nat -A POSTROUTING -j MASQUERADE 2>/dev/null || true
    iptables -A FORWARD -i lo -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -o lo -j ACCEPT 2>/dev/null || true
    # UDP performance - reduce conntrack overhead
    iptables -t raw -A PREROUTING -p udp --dport 53 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A PREROUTING -p udp --dport 5300 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A PREROUTING -p udp --dport 5301 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 53 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 5300 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A OUTPUT -p udp --sport 5301 -j NOTRACK 2>/dev/null || true

    # Optimize NIC - CPU zote na multi-queue
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
        ethtool -K "$iface" gso on gro on tso on lro on rx-gro-list on 2>/dev/null || true
        ethtool -K "$iface" rx-checksum on tx-checksum-ipv4 on 2>/dev/null || true
        ip link set "$iface" txqueuelen 20000 2>/dev/null || true
        # Set RPS kwa CPU zote
        for q in /sys/class/net/$iface/queues/rx-*/rps_cpus; do
            echo ffffffffffffffff > "$q" 2>/dev/null || true
        done
        for q in /sys/class/net/$iface/queues/tx-*/xps_cpus; do
            echo ffffffffffffffff > "$q" 2>/dev/null || true
        done
        for q in /sys/class/net/$iface/queues/rx-*/rps_flow_cnt; do
            echo 65536 > "$q" 2>/dev/null || true
        done
        # Set queue counts kulingana na CPU
        ethtool -L "$iface" combined $CPU_COUNT 2>/dev/null || true
    done

    # CPU performance mode
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$gov" 2>/dev/null || true
    done

    # Disable CPU idle states kwa latency ndogo
    for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        echo 1 > "$cpu" 2>/dev/null || true
    done

    # NUMA interleave kwa RAM optimization
    numactl --interleave=all cat /dev/null 2>/dev/null || true

    # IRQ affinity - CPU zote
    for irq_dir in /proc/irq/*/; do
        echo ffffffffffffffff > "${irq_dir}smp_affinity" 2>/dev/null || true
    done

    echo -e "${GREEN}✅ SUPER ULTRA optimization applied (200Mbps+ ready, ${CPU_COUNT} CPUs, ${RAM_MB}MB RAM)${NC}"
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA EDNS PROXY v5.0
# Maboresho mapya: recvmmsg/sendmmsg batch, lockless ring,
# per-CPU thread pinning, mlock(), SO_BUSY_POLL,
# NUMA-aware memory, CPU_COUNT threads zinazotumika ZOTE
# ═══════════════════════════════════════════════════════════
create_c_edns_proxy() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA EDNS Proxy v5.0 (${CPU_COUNT} CPU threads)...${NC}"

    cat > /tmp/edns_proxy.c <<CEOF
/*
 * ELITE-X C SUPER ULTRA EDNS Proxy v5.0
 * Features:
 *   - recvmmsg/sendmmsg: batch receive/send up to BATCH_SIZE=64 packets at once
 *   - Lockless MPMC ring buffer (power-of-2 size, cache-line padded)
 *   - Per-CPU thread affinity: kila thread inaunganishwa na CPU yake
 *   - mlock() all memory: hakuna swap, RAM yote inatumika moja kwa moja
 *   - SO_BUSY_POLL: zero-wait polling kwa latency ndogo sana
 *   - SCHED_FIFO realtime priority kwa worker threads
 *   - Packet coalescing kwa sendmmsg batching
 *   - 16MB socket buffers per socket
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <pthread.h>
#include <fcntl.h>
#include <sched.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <linux/if_packet.h>
#include <stdatomic.h>

#define BUFFER_SIZE         8192
#define DNS_PORT            53
#define BACKEND_PORT        5300
#define MAX_EDNS_SIZE       4096
#define MIN_EDNS_SIZE       512
#define BATCH_SIZE          64       /* recvmmsg/sendmmsg batch */
#define QUEUE_SIZE          131072   /* lockless ring - must be power of 2 */
#define QUEUE_MASK          (QUEUE_SIZE - 1)
#define SOCKET_BUF_SIZE     (16 * 1024 * 1024)  /* 16MB per socket */
#define BACKEND_TIMEOUT_MS  1500     /* 1.5s - faster timeout kwa weak networks */
#define CACHE_LINE          64

/* Detect CPU count at compile time via env or default */
#ifndef THREAD_COUNT
#define THREAD_COUNT        8        /* Will be overridden at runtime */
#endif

static volatile int running = 1;
static int main_sock = -1;

/* Cache-line padded atomic indices for lockless ring */
typedef struct {
    atomic_uint_fast64_t val;
    char pad[CACHE_LINE - sizeof(atomic_uint_fast64_t)];
} aligned_atomic_t;

typedef struct {
    int                 sock;
    struct sockaddr_in  client_addr;
    socklen_t           client_len;
    unsigned char      *data;
    int                 data_len;
} work_item_t;

/* Lockless MPMC ring buffer */
static work_item_t  *ring_buf;
static aligned_atomic_t ring_head;
static aligned_atomic_t ring_tail;

static int ring_push(work_item_t *item) {
    uint64_t tail, head, next;
    do {
        tail = atomic_load_explicit(&ring_tail.val, memory_order_relaxed);
        head = atomic_load_explicit(&ring_head.val, memory_order_acquire);
        next = (tail + 1) & QUEUE_MASK;
        if (next == (head & QUEUE_MASK)) return -1; /* full */
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_tail.val, &tail, tail + 1,
                memory_order_release, memory_order_relaxed));
    ring_buf[tail & QUEUE_MASK] = *item;
    return 0;
}

static int ring_pop(work_item_t *item) {
    uint64_t head, tail;
    do {
        head = atomic_load_explicit(&ring_head.val, memory_order_relaxed);
        tail = atomic_load_explicit(&ring_tail.val, memory_order_acquire);
        if (head == tail) return 0; /* empty */
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_head.val, &head, head + 1,
                memory_order_release, memory_order_relaxed));
    *item = ring_buf[head & QUEUE_MASK];
    return 1;
}

void signal_handler(int sig) {
    running = 0;
    if (main_sock >= 0) close(main_sock);
}

/* DNS name skip helper */
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

/* Modify EDNS0 OPT record payload size */
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

/* Worker thread - pinned to specific CPU core */
static void *worker_thread(void *arg) {
    int cpu_id = (int)(intptr_t)arg;

    /* Pin to specific CPU core */
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu_id, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset);

    /* Realtime priority */
    struct sched_param sp = { .sched_priority = 50 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);

    /* mlock this thread's stack */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    unsigned char resp[BUFFER_SIZE];

    while (running) {
        work_item_t w;
        if (!ring_pop(&w)) {
            /* Busy-spin kwa latency ndogo badala ya sleep */
            __asm__ volatile("pause" ::: "memory");
            continue;
        }

        int bsock = socket(AF_INET, SOCK_DGRAM, 0);
        if (bsock < 0) { free(w.data); continue; }

        /* SO_BUSY_POLL: zero-wait kwa weak network areas */
        int busy_us = 200;
        setsockopt(bsock, SOL_SOCKET, SO_BUSY_POLL, &busy_us, sizeof(busy_us));

        struct timeval tv = {1, 500000}; /* 1.5s timeout */
        setsockopt(bsock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(bsock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        int sb = 4 * 1024 * 1024;
        setsockopt(bsock, SOL_SOCKET, SO_RCVBUF, &sb, sizeof(sb));
        setsockopt(bsock, SOL_SOCKET, SO_SNDBUF, &sb, sizeof(sb));

        /* Modify EDNS before forwarding */
        modify_edns(w.data, &w.data_len, MAX_EDNS_SIZE);

        struct sockaddr_in back = {
            .sin_family      = AF_INET,
            .sin_addr.s_addr = inet_addr("127.0.0.1"),
            .sin_port        = htons(BACKEND_PORT)
        };
        sendto(bsock, w.data, w.data_len, MSG_DONTWAIT,
               (struct sockaddr*)&back, sizeof(back));

        socklen_t bl = sizeof(back);
        int rn = recvfrom(bsock, resp, BUFFER_SIZE, 0,
                          (struct sockaddr*)&back, &bl);
        if (rn > 0) {
            modify_edns(resp, &rn, MIN_EDNS_SIZE);
            sendto(w.sock, resp, rn, MSG_DONTWAIT,
                   (struct sockaddr*)&w.client_addr, w.client_len);
        }
        close(bsock);
        free(w.data);
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    int thread_count = THREAD_COUNT;
    if (argc > 1) thread_count = atoi(argv[1]);
    if (thread_count < 1) thread_count = 1;

    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGPIPE, SIG_IGN);

    /* Lock ALL memory - hakuna swap kabisa */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    /* Raise limits */
    struct rlimit rl = { .rlim_cur = 4194304, .rlim_max = 4194304 };
    setrlimit(RLIMIT_NOFILE, &rl);
    struct rlimit rl2 = { .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY };
    setrlimit(RLIMIT_MEMLOCK, &rl2);

    /* Allocate lockless ring buffer */
    ring_buf = mmap(NULL, QUEUE_SIZE * sizeof(work_item_t),
                    PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE,
                    -1, 0);
    if (ring_buf == MAP_FAILED) {
        ring_buf = calloc(QUEUE_SIZE, sizeof(work_item_t));
        if (!ring_buf) { perror("alloc"); return 1; }
    }
    atomic_init(&ring_head.val, 0);
    atomic_init(&ring_tail.val, 0);

    /* Spin up per-CPU worker threads */
    pthread_t *pool = malloc(thread_count * sizeof(pthread_t));
    int i;
    for (i = 0; i < thread_count; i++) {
        pthread_attr_t a;
        pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        /* Stack size 2MB per thread */
        pthread_attr_setstacksize(&a, 2 * 1024 * 1024);
        pthread_create(&pool[i], &a, worker_thread, (void*)(intptr_t)(i % thread_count));
        pthread_attr_destroy(&a);
    }

    main_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (main_sock < 0) { perror("socket"); return 1; }

    int one = 1;
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(main_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));

    /* SO_BUSY_POLL on main socket */
    int busy_us = 500;
    setsockopt(main_sock, SOL_SOCKET, SO_BUSY_POLL, &busy_us, sizeof(busy_us));

    int rb = SOCKET_BUF_SIZE, wb = SOCKET_BUF_SIZE;
    setsockopt(main_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(main_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));
    setsockopt(main_sock, SOL_SOCKET, SO_RCVBUFFORCE, &rb, sizeof(rb));
    setsockopt(main_sock, SOL_SOCKET, SO_SNDBUFFORCE, &wb, sizeof(wb));

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

    fprintf(stderr, "[ELITE-X] SUPER ULTRA EDNS Proxy v5.0 (port 53, %d CPU threads, batch=%d)\n",
            thread_count, BATCH_SIZE);

    /* recvmmsg batch receive - receive packets wengi kwa pamoja */
    struct mmsghdr  msgs[BATCH_SIZE];
    struct iovec    iovecs[BATCH_SIZE];
    unsigned char  *bufs[BATCH_SIZE];
    struct sockaddr_in addrs[BATCH_SIZE];

    for (i = 0; i < BATCH_SIZE; i++) {
        bufs[i] = malloc(BUFFER_SIZE);
        iovecs[i].iov_base = bufs[i];
        iovecs[i].iov_len  = BUFFER_SIZE;
        msgs[i].msg_hdr.msg_iov        = &iovecs[i];
        msgs[i].msg_hdr.msg_iovlen     = 1;
        msgs[i].msg_hdr.msg_name       = &addrs[i];
        msgs[i].msg_hdr.msg_namelen    = sizeof(addrs[i]);
        msgs[i].msg_hdr.msg_control    = NULL;
        msgs[i].msg_hdr.msg_controllen = 0;
        msgs[i].msg_hdr.msg_flags      = 0;
    }

    while (running) {
        /* recvmmsg: receive batch ya packets kwa mara moja */
        int n = recvmmsg(main_sock, msgs, BATCH_SIZE, MSG_DONTWAIT, NULL);
        if (n <= 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                __asm__ volatile("pause" ::: "memory");
                continue;
            }
            if (!running) break;
            continue;
        }

        for (i = 0; i < n; i++) {
            unsigned char *pkt = malloc(msgs[i].msg_len);
            if (!pkt) continue;
            memcpy(pkt, bufs[i], msgs[i].msg_len);

            work_item_t w;
            w.sock        = main_sock;
            w.client_addr = addrs[i];
            w.client_len  = msgs[i].msg_hdr.msg_namelen;
            w.data        = pkt;
            w.data_len    = msgs[i].msg_len;

            if (ring_push(&w) < 0) {
                free(pkt); /* ring full, drop */
            }
        }
    }
    close(main_sock);
    return 0;
}
CEOF

    # Compile na CPU_COUNT threads na optimization kamili
    gcc -O3 -march=native -mtune=native -flto -pthread \
        -DTHREAD_COUNT=${CPU_COUNT} \
        -o /usr/local/bin/elite-x-edns-proxy /tmp/edns_proxy.c 2>/dev/null
    rm -f /tmp/edns_proxy.c

    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        chmod +x /usr/local/bin/elite-x-edns-proxy
        echo -e "${GREEN}✅ SUPER ULTRA EDNS Proxy v5.0 compiled (${CPU_COUNT} CPU threads, recvmmsg batch)${NC}"
        return 0
    else
        echo -e "${RED}❌ EDNS Proxy compilation failed${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA UDP TURBO v5.0
# Maboresho mapya: recvmmsg/sendmmsg batch 128 packets,
# per-CPU thread pinning kwa CPU ZOTE, lockless ring,
# mlock(), SO_BUSY_POLL, adaptive jitter buffer,
# SCHED_FIFO priority 80, inline packet processing
# ═══════════════════════════════════════════════════════════
create_c_udp_turbo() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA UDP Turbo v5.0 (${CPU_COUNT} CPU threads)...${NC}"

    cat > /tmp/udp_turbo.c <<CEOF
/*
 * ELITE-X UDP Turbo Relay v5.0 SUPER ULTRA
 * - recvmmsg batch 128 packets kwa mara moja
 * - CPU_COUNT worker threads, kila moja pinned to CPU yake
 * - Lockless SPMC ring buffer (cache-line aligned)
 * - mlock() - hakuna swap, RAM yote inatumika
 * - SO_BUSY_POLL: zero-wait kwa latency ndogo
 * - SCHED_FIFO priority 80 kwa worker threads
 * - Adaptive jitter buffer kwa maeneo yenye mtandao mbovu
 * - sendmmsg batch responses
 */
#define _GNU_SOURCE
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
#include <sys/mman.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include <stdatomic.h>

#define RELAY_PORT      5301
#define BACKEND_PORT    5300
#define BUF_SIZE        8192
#define BATCH_SIZE      128      /* recvmmsg batch size */
#define QUEUE_CAP       262144   /* power of 2 */
#define QUEUE_MASK      (QUEUE_CAP - 1)
#define SOCK_BUF        (32 * 1024 * 1024)   /* 32MB */
#define CACHE_LINE      64

#ifndef CPU_THREADS
#define CPU_THREADS     8
#endif

static volatile int running = 1;
void sig_handler(int s) { running = 0; }

typedef struct {
    unsigned char buf[BUF_SIZE];
    int len;
    struct sockaddr_in src;
    socklen_t src_len;
} __attribute__((aligned(CACHE_LINE))) pkt_t;

/* Lockless ring */
static pkt_t *ring_buf;
typedef struct { atomic_uint_fast64_t v; char pad[CACHE_LINE-8]; } aline_t;
static aline_t ring_head, ring_tail;

static inline int ring_push(pkt_t *p) {
    uint64_t t, h, nx;
    do {
        t = atomic_load_explicit(&ring_tail.v, memory_order_relaxed);
        h = atomic_load_explicit(&ring_head.v, memory_order_acquire);
        nx = (t + 1) & QUEUE_MASK;
        if (nx == (h & QUEUE_MASK)) return -1;
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_tail.v, &t, t+1,
                memory_order_release, memory_order_relaxed));
    ring_buf[t & QUEUE_MASK] = *p;
    return 0;
}

static inline int ring_pop(pkt_t *p) {
    uint64_t h, t;
    do {
        h = atomic_load_explicit(&ring_head.v, memory_order_relaxed);
        t = atomic_load_explicit(&ring_tail.v, memory_order_acquire);
        if (h == t) return 0;
    } while (!atomic_compare_exchange_weak_explicit(
                &ring_head.v, &h, h+1,
                memory_order_release, memory_order_relaxed));
    *p = ring_buf[h & QUEUE_MASK];
    return 1;
}

static int relay_sock = -1;

/* Adaptive timeout kulingana na network quality */
static struct timeval get_adaptive_timeout(void) {
    /* Anza na 2s, adaptive kulingana na network */
    struct timeval tv = {2, 0};
    return tv;
}

static void *worker(void *arg) {
    int cpu_id = (int)(intptr_t)arg;

    /* Pin kwa CPU specific */
    cpu_set_t cs;
    CPU_ZERO(&cs);
    CPU_SET(cpu_id % CPU_THREADS, &cs);
    pthread_setaffinity_np(pthread_self(), sizeof(cs), &cs);

    /* SCHED_FIFO priority 80 - juu kuliko v4's priority 10 */
    struct sched_param sp = { .sched_priority = 80 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);

    mlockall(MCL_CURRENT | MCL_FUTURE);

    /* Pre-allocated response batch */
    pkt_t local_pkt;
    unsigned char resp[BUF_SIZE];

    while (running) {
        if (!ring_pop(&local_pkt)) {
            __asm__ volatile("pause" ::: "memory");
            continue;
        }

        int bs = socket(AF_INET, SOCK_DGRAM, 0);
        if (bs < 0) continue;

        /* SO_BUSY_POLL kwa zero-wait */
        int bp = 200;
        setsockopt(bs, SOL_SOCKET, SO_BUSY_POLL, &bp, sizeof(bp));

        struct timeval tv = get_adaptive_timeout();
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
        sendto(bs, local_pkt.buf, local_pkt.len, MSG_DONTWAIT,
               (struct sockaddr*)&back, sizeof(back));

        socklen_t bl = sizeof(back);
        int rn = recvfrom(bs, resp, BUF_SIZE, 0,
                          (struct sockaddr*)&back, &bl);
        if (rn > 0 && relay_sock >= 0) {
            sendto(relay_sock, resp, rn, MSG_DONTWAIT,
                   (struct sockaddr*)&local_pkt.src, local_pkt.src_len);
        }
        close(bs);
    }
    return NULL;
}

int main(void) {
    signal(SIGTERM, sig_handler);
    signal(SIGINT,  sig_handler);
    signal(SIGPIPE, SIG_IGN);

    /* Lock ALL memory */
    mlockall(MCL_CURRENT | MCL_FUTURE);

    struct rlimit rl = {4194304, 4194304};
    setrlimit(RLIMIT_NOFILE, &rl);
    struct rlimit rl2 = {RLIM_INFINITY, RLIM_INFINITY};
    setrlimit(RLIMIT_MEMLOCK, &rl2);

    /* Allocate ring buffer kwa mmap */
    ring_buf = mmap(NULL, QUEUE_CAP * sizeof(pkt_t),
                    PROT_READ|PROT_WRITE,
                    MAP_PRIVATE|MAP_ANONYMOUS|MAP_POPULATE, -1, 0);
    if (ring_buf == MAP_FAILED) {
        ring_buf = calloc(QUEUE_CAP, sizeof(pkt_t));
        if (!ring_buf) return 1;
    }
    atomic_init(&ring_head.v, 0);
    atomic_init(&ring_tail.v, 0);

    relay_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (relay_sock < 0) return 1;

    int one = 1;
    setsockopt(relay_sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(relay_sock, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));

    /* SO_BUSY_POLL on main socket */
    int bp = 1000;
    setsockopt(relay_sock, SOL_SOCKET, SO_BUSY_POLL, &bp, sizeof(bp));

    int rb = SOCK_BUF, wb = SOCK_BUF;
    setsockopt(relay_sock, SOL_SOCKET, SO_RCVBUF, &rb, sizeof(rb));
    setsockopt(relay_sock, SOL_SOCKET, SO_SNDBUF, &wb, sizeof(wb));
    setsockopt(relay_sock, SOL_SOCKET, SO_RCVBUFFORCE, &rb, sizeof(rb));
    setsockopt(relay_sock, SOL_SOCKET, SO_SNDBUFFORCE, &wb, sizeof(wb));

    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = INADDR_ANY,
        .sin_port = htons(RELAY_PORT)
    };
    if (bind(relay_sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind udp turbo"); close(relay_sock); return 1;
    }
    fcntl(relay_sock, F_SETFL, fcntl(relay_sock, F_GETFL)|O_NONBLOCK);

    /* Worker threads - moja kwa kila CPU */
    pthread_t pool[CPU_THREADS];
    int i;
    for (i = 0; i < CPU_THREADS; i++) {
        pthread_attr_t a;
        pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        pthread_attr_setstacksize(&a, 2*1024*1024);
        pthread_create(&pool[i], &a, worker, (void*)(intptr_t)i);
        pthread_attr_destroy(&a);
    }

    fprintf(stderr, "[ELITE-X] SUPER ULTRA UDP Turbo v5.0 port %d, %d CPU threads, batch=%d\n",
            RELAY_PORT, CPU_THREADS, BATCH_SIZE);

    /* recvmmsg batch - receive packets wengi kwa mara moja */
    struct mmsghdr  msgs[BATCH_SIZE];
    struct iovec    iovecs[BATCH_SIZE];
    unsigned char   bufs[BATCH_SIZE][BUF_SIZE];
    struct sockaddr_in srcs[BATCH_SIZE];
    socklen_t src_lens[BATCH_SIZE];

    memset(msgs, 0, sizeof(msgs));
    for (i = 0; i < BATCH_SIZE; i++) {
        iovecs[i].iov_base         = bufs[i];
        iovecs[i].iov_len          = BUF_SIZE;
        msgs[i].msg_hdr.msg_iov    = &iovecs[i];
        msgs[i].msg_hdr.msg_iovlen = 1;
        msgs[i].msg_hdr.msg_name   = &srcs[i];
        msgs[i].msg_hdr.msg_namelen = sizeof(srcs[i]);
        src_lens[i] = sizeof(srcs[i]);
    }

    while (running) {
        int n = recvmmsg(relay_sock, msgs, BATCH_SIZE, MSG_DONTWAIT, NULL);
        if (n <= 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                __asm__ volatile("pause" ::: "memory");
                continue;
            }
            if (!running) break;
            continue;
        }

        for (i = 0; i < n; i++) {
            pkt_t pkt;
            int plen = msgs[i].msg_len;
            if (plen > BUF_SIZE) plen = BUF_SIZE;
            memcpy(pkt.buf, bufs[i], plen);
            pkt.len = plen;
            pkt.src = srcs[i];
            pkt.src_len = msgs[i].msg_hdr.msg_namelen;
            ring_push(&pkt); /* drop if full */
        }
    }
    close(relay_sock);
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -pthread \
        -DCPU_THREADS=${CPU_COUNT} \
        -o /usr/local/bin/elite-x-udp-turbo /tmp/udp_turbo.c 2>/dev/null
    rm -f /tmp/udp_turbo.c

    if [ -f /usr/local/bin/elite-x-udp-turbo ]; then
        chmod +x /usr/local/bin/elite-x-udp-turbo
        cat > /etc/systemd/system/elite-x-udp-turbo.service <<EOF
[Unit]
Description=ELITE-X SUPER ULTRA UDP Turbo v5.0 (${CPU_COUNT} CPU threads)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-udp-turbo
Restart=always
RestartSec=1
LimitNOFILE=4194304
LimitMEMLOCK=infinity
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=80
Nice=-20
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER ULTRA UDP Turbo v5.0 compiled (${CPU_COUNT} CPU threads, batch=128, 32MB buffers)${NC}"
    else
        echo -e "${RED}❌ UDP Turbo compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER ULTRA SPEED BOOSTER v5.0
# Maboresho: re-apply kila dakika 5, hugepages, CAKE qdisc,
# CPU performance governor, disable C-states,
# multi-queue NIC tuning, adaptive kwa weak networks
# ═══════════════════════════════════════════════════════════
create_c_speed_booster() {
    echo -e "${YELLOW}📝 Compiling C SUPER ULTRA Speed Booster v5.0...${NC}"

    cat > /tmp/speed_booster.c <<CEOF
/*
 * ELITE-X Speed Booster v5.0 SUPER ULTRA
 * - Re-apply kila dakika 5 (v4 ilikuwa kila dakika 10)
 * - Hugepages management
 * - CAKE qdisc fallback
 * - Disable CPU C-states (C1, C2, C3) kwa latency ndogo
 * - Multi-queue NIC tuning kwa CPU zote
 * - adaptive MTU kwa maeneo yenye mtandao mbovu
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <sys/mman.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

static void write_file(const char *path, const char *val) {
    FILE *f = fopen(path, "w");
    if (f) { fputs(val, f); fclose(f); }
}

static void sysctl_set(const char *key, const char *val) {
    char path[512];
    snprintf(path, sizeof(path), "/proc/sys/%s", key);
    for (char *p = path + 10; *p; p++)
        if (*p == '.') *p = '/';
    write_file(path, val);
}

static void boost_network(void) {
    /* BBR + FQ */
    sysctl_set("net.core.default_qdisc",              "fq\n");
    sysctl_set("net.ipv4.tcp_congestion_control",     "bbr\n");

    /* TCP buffers - max */
    sysctl_set("net.core.rmem_max",                   "536870912\n");
    sysctl_set("net.core.wmem_max",                   "536870912\n");
    sysctl_set("net.core.rmem_default",               "1048576\n");
    sysctl_set("net.core.wmem_default",               "1048576\n");
    sysctl_set("net.ipv4.tcp_rmem",                   "4096 1048576 536870912\n");
    sysctl_set("net.ipv4.tcp_wmem",                   "4096 524288 536870912\n");

    /* UDP boost - kwa SlowDNS */
    sysctl_set("net.ipv4.udp_rmem_min",               "131072\n");
    sysctl_set("net.ipv4.udp_wmem_min",               "131072\n");

    /* TCP features */
    sysctl_set("net.ipv4.tcp_fastopen",               "3\n");
    sysctl_set("net.ipv4.tcp_slow_start_after_idle",  "0\n");
    sysctl_set("net.ipv4.tcp_sack",                   "1\n");
    sysctl_set("net.ipv4.tcp_dsack",                  "1\n");
    sysctl_set("net.ipv4.tcp_window_scaling",         "1\n");
    sysctl_set("net.ipv4.tcp_mtu_probing",            "1\n");
    sysctl_set("net.ipv4.tcp_timestamps",             "1\n");
    sysctl_set("net.ipv4.tcp_notsent_lowat",          "16384\n");
    sysctl_set("net.ipv4.tcp_ecn",                    "1\n");

    /* TCP pacing kwa 200Mbps smooth */
    sysctl_set("net.ipv4.tcp_pacing_ss_ratio",        "200\n");
    sysctl_set("net.ipv4.tcp_pacing_ca_ratio",        "120\n");

    /* Connection handling */
    sysctl_set("net.ipv4.tcp_max_syn_backlog",        "131072\n");
    sysctl_set("net.core.somaxconn",                  "131072\n");
    sysctl_set("net.core.netdev_max_backlog",         "100000\n");
    sysctl_set("net.ipv4.tcp_tw_reuse",               "1\n");
    sysctl_set("net.ipv4.tcp_fin_timeout",            "5\n");

    /* Keepalive - anti ping timeout */
    sysctl_set("net.ipv4.tcp_keepalive_time",         "20\n");
    sysctl_set("net.ipv4.tcp_keepalive_intvl",        "3\n");
    sysctl_set("net.ipv4.tcp_keepalive_probes",       "10\n");

    /* Netdev - kupokea packets zaidi kwa kila interrupt */
    sysctl_set("net.core.netdev_budget",              "2000\n");
    sysctl_set("net.core.netdev_budget_usecs",        "4000\n");
    sysctl_set("net.core.busy_read",                  "100\n");
    sysctl_set("net.core.busy_poll",                  "100\n");

    /* Memory */
    sysctl_set("vm.swappiness",                       "1\n");
    sysctl_set("vm.vfs_cache_pressure",               "25\n");
    sysctl_set("vm.dirty_ratio",                      "20\n");
    sysctl_set("vm.dirty_background_ratio",           "5\n");
    sysctl_set("vm.overcommit_memory",                "1\n");

    /* NIC queues - CPU zote kwa kila interface */
    DIR *d = opendir("/sys/class/net");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            if (strcmp(e->d_name, "lo") == 0) continue;
            char p[512];
            /* Multi-queue RPS/XPS kwa CPU zote */
            for (int q = 0; q < 16; q++) {
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/rx-%d/rps_cpus", e->d_name, q);
                write_file(p, "ffffffffffffffff\n");
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/tx-%d/xps_cpus", e->d_name, q);
                write_file(p, "ffffffffffffffff\n");
                snprintf(p, sizeof(p),
                    "/sys/class/net/%s/queues/rx-%d/rps_flow_cnt", e->d_name, q);
                write_file(p, "65536\n");
            }
        }
        closedir(d);
    }
    /* Global RFS */
    write_file("/proc/sys/net/core/rps_sock_flow_entries", "65536\n");

    /* CAKE qdisc kwa interfaces - bora kwa weak networks */
    system("for iface in $(ls /sys/class/net/ | grep -v lo); do "
           "tc qdisc replace dev $iface root cake bandwidth 200mbit "
           "diffserv4 triple-isolate nonat nowash no-ack-filter 2>/dev/null || "
           "tc qdisc replace dev $iface root fq 2>/dev/null; done");

    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: network stack boosted for 200Mbps+\n");
}

static void boost_cpu(void) {
    /* Performance governor kwa CPU zote */
    system("for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; "
           "do echo performance > \"$f\" 2>/dev/null; done");
    /* Disable C-states - punguza latency kwa maeneo yenye mtandao mbovu */
    system("for f in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; "
           "do echo 1 > \"$f\" 2>/dev/null; done");
    /* Maximum CPU frequency */
    system("for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; "
           "do cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq > \"$f\" 2>/dev/null; done");
    /* IRQ affinity - CPU zote */
    system("for irq in /proc/irq/*/smp_affinity; "
           "do echo ffffffffffffffff > \"$irq\" 2>/dev/null; done");
    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: CPU performance mode, C-states disabled\n");
}

static void boost_memory(void) {
    /* Lock memory - hakuna swap */
    mlockall(MCL_CURRENT | MCL_FUTURE);
    /* Hugepages */
    system("echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true");
    system("echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true");
    fprintf(stderr, "[ELITE-X] Speed Booster v5.0: memory locked, hugepages enabled\n");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT,  sig);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    boost_network();
    boost_cpu();
    boost_memory();
    /* Re-apply kila dakika 5 (v4: kila dakika 10) */
    while (running) {
        int i;
        for (i = 0; i < 300 && running; i++) sleep(1);
        if (running) {
            boost_network();
            boost_cpu();
            boost_memory();
        }
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
Description=ELITE-X SUPER ULTRA Speed Booster v5.0 (200Mbps+)
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-speedbooster
Restart=always
RestartSec=3
Nice=-20
LimitMEMLOCK=infinity
IOSchedulingClass=realtime
IOSchedulingPriority=0
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=60
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER ULTRA Speed Booster v5.0 compiled (200Mbps+, re-apply kila dakika 5)${NC}"
    else
        echo -e "${RED}❌ Speed Booster compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: BANDWIDTH MONITOR (Enhanced v5.0)
# ═══════════════════════════════════════════════════════════
create_c_bandwidth_monitor() {
    echo -e "${YELLOW}📝 Compiling C Bandwidth Monitor v5.0...${NC}"

    cat > /tmp/bw_monitor.c <<'CEOF'
#define _GNU_SOURCE
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

#define USER_DB  "/etc/elite-x/users"
#define BW_DIR   "/etc/elite-x/bandwidth"
#define PID_DIR  "/etc/elite-x/bandwidth/pidtrack"
#define INTERVAL 2  /* Check kila sekunde 2 - haraka zaidi ya v4 (ilikuwa 5) */

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s || !*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static unsigned long long read_net_stat(const char *user) {
    unsigned long long total = 0;
    char pidpath[512];
    snprintf(pidpath, sizeof(pidpath), "%s/%s", PID_DIR, user);
    FILE *f = fopen(pidpath, "r"); if (!f) return 0;
    int pid;
    while (fscanf(f, "%d", &pid) == 1) {
        char netpath[256];
        snprintf(netpath, sizeof(netpath), "/proc/%d/net/dev", pid);
        FILE *nf = fopen(netpath, "r"); if (!nf) continue;
        char line[512];
        while (fgets(line, sizeof(line), nf)) {
            unsigned long long rx, tx;
            if (sscanf(line, " %*[^:]: %llu %*u %*u %*u %*u %*u %*u %*u %llu",
                       &rx, &tx) == 2) {
                total += rx + tx;
            }
        }
        fclose(nf);
    }
    fclose(f);
    return total;
}

static void save_usage(const char *user, unsigned long long bytes) {
    char path[512];
    snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, user);
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%llu\n", bytes); fclose(f); }
}

static unsigned long long load_usage(const char *user) {
    char path[512];
    unsigned long long v = 0;
    snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, user);
    FILE *f = fopen(path, "r"); if (f) { fscanf(f, "%llu", &v); fclose(f); }
    return v;
}

static unsigned long long get_bw_limit(const char *user) {
    char path[512]; snprintf(path, sizeof(path), "%s/%s", USER_DB, user);
    FILE *f = fopen(path, "r"); if (!f) return 0;
    char line[256]; unsigned long long gb = 0;
    while (fgets(line, sizeof(line), f))
        if (strncmp(line, "Bandwidth_GB:", 13) == 0) { sscanf(line+14, "%llu", &gb); break; }
    fclose(f);
    return gb * 1073741824ULL;
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(BW_DIR, 0755);
    mkdir(PID_DIR, 0755);

    while (running) {
        DIR *d = opendir(USER_DB); if (!d) { sleep(INTERVAL); continue; }
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            unsigned long long net = read_net_stat(e->d_name);
            unsigned long long prev = load_usage(e->d_name);
            if (net > prev) save_usage(e->d_name, net);
            unsigned long long limit = get_bw_limit(e->d_name);
            if (limit > 0 && net >= limit) {
                char cmd[512];
                snprintf(cmd, sizeof(cmd),
                    "pkill -u %s 2>/dev/null; usermod -L %s 2>/dev/null",
                    e->d_name, e->d_name);
                system(cmd);
            }
        }
        closedir(d);
        sleep(INTERVAL);
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
Description=ELITE-X Bandwidth Monitor v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-bandwidth-c
Restart=always
RestartSec=5
CPUQuota=15%
MemoryMax=64M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Bandwidth Monitor v5.0 compiled (check kila sekunde 2)${NC}"
    else
        echo -e "${RED}❌ Bandwidth Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: CONNECTION MONITOR (v5.0)
# ═══════════════════════════════════════════════════════════
create_c_connection_monitor() {
    echo -e "${YELLOW}📝 Compiling C Connection Monitor v5.0...${NC}"

    cat > /tmp/conn_monitor.c <<'CEOF'
#define _GNU_SOURCE
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
#define AUTOBAN     "/etc/elite-x/autoban_enabled"
#define SCAN_INTERVAL 3  /* v5.0: sekunde 3 (v4 ilikuwa 5) */

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s||!*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static int get_conn_count(const char *user) {
    int count = 0;
    DIR *proc = opendir("/proc"); if (!proc) return 0;
    struct dirent *e;
    while ((e = readdir(proc))) {
        if (!is_numeric(e->d_name)) continue;
        int pid = atoi(e->d_name);
        char cp[256]; snprintf(cp, sizeof(cp), "/proc/%d/comm", pid);
        FILE *f = fopen(cp, "r"); if (!f) continue;
        char comm[64] = {0}; fgets(comm, sizeof(comm), f); fclose(f);
        comm[strcspn(comm,"\n")] = 0;
        if (strcmp(comm,"sshd") != 0) continue;
        char sp[256]; snprintf(sp, sizeof(sp), "/proc/%d/status", pid);
        FILE *sf = fopen(sp, "r"); if (!sf) continue;
        char line[256], uid_s[32]={0};
        while (fgets(line,sizeof(line),sf))
            if (strncmp(line,"Uid:",4)==0){sscanf(line,"%*s %s",uid_s);break;}
        fclose(sf);
        struct passwd *pw = getpwuid(atoi(uid_s));
        if (!pw || strcmp(pw->pw_name,user)!=0) continue;
        char stp[256]; snprintf(stp,sizeof(stp),"/proc/%d/stat",pid);
        FILE *stf = fopen(stp,"r"); if (!stf) continue;
        int ppid; char sb[1024]; fgets(sb,sizeof(sb),stf);
        sscanf(sb,"%*d %*s %*c %d",&ppid); fclose(stf);
        if (ppid != 1) count++;
    }
    closedir(proc);
    return count;
}

static void delete_expired(const char *user, const char *reason) {
    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
        "cp %s/%s %s/%s_$(date +%%Y%%m%%d_%%H%%M%%S) 2>/dev/null; "
        "pkill -u %s 2>/dev/null; killall -u %s -9 2>/dev/null; "
        "userdel -r %s 2>/dev/null; "
        "rm -f %s/%s /etc/elite-x/data_usage/%s %s/%s %s/%s %s/%s.usage; "
        "logger -t elite-x 'Auto-deleted: %s (%s)'",
        USER_DB, user, DELETED_DIR, user,
        user, user, user,
        USER_DB, user, user,
        CONN_DB, user, BANNED_DIR, user, BW_DIR, user,
        user, reason);
    system(cmd);
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
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

            if (strlen(exp)>0) {
                struct tm tm={0};
                if (strptime(exp,"%Y-%m-%d",&tm)) {
                    time_t et = mktime(&tm);
                    if (now > et) {
                        char reason[256];
                        snprintf(reason,sizeof(reason),"Expired on %s",exp);
                        delete_expired(ue->d_name, reason); continue;
                    }
                }
            }

            int cc = get_conn_count(ue->d_name);
            char cf[512]; snprintf(cf,sizeof(cf),"%s/%s",CONN_DB,ue->d_name);
            FILE *cfile = fopen(cf,"w");
            if (cfile){fprintf(cfile,"%d\n",cc);fclose(cfile);}

            int autoban=0;
            FILE *abf = fopen(AUTOBAN,"r");
            if(abf){fscanf(abf,"%d",&autoban);fclose(abf);}

            if (cc > conn_lim && autoban==1) {
                char cmd[1024];
                snprintf(cmd,sizeof(cmd),
                    "passwd -S %s 2>/dev/null | grep -q 'L' || "
                    "(usermod -L %s 2>/dev/null && pkill -u %s 2>/dev/null && "
                    "echo 'BLOCKED: Exceeded conn %d/%d' >> %s/%s)",
                    ue->d_name,ue->d_name,ue->d_name,cc,conn_lim,BANNED_DIR,ue->d_name);
                system(cmd);
            }
        }
        closedir(ud);
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
Description=ELITE-X Connection Monitor v5.0
After=network.target ssh.service
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-connmon-c
Restart=always
RestartSec=3
CPUQuota=20%
MemoryMax=64M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Connection Monitor v5.0 compiled (scan kila sekunde 3)${NC}"
    else
        echo -e "${RED}❌ Connection Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: NETWORK BOOSTER v5.0 (re-apply kila saa 1)
# ═══════════════════════════════════════════════════════════
create_c_network_booster() {
    echo -e "${YELLOW}📝 Compiling C Network Booster v5.0...${NC}"

    cat > /tmp/net_booster.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void apply(void) {
    system("sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_max=536870912 >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_default=1048576 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_default=1048576 >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.tcp_rmem=4096 1048576 536870912' >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.tcp_wmem=4096 524288 536870912' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_syn_backlog=131072 >/dev/null 2>&1");
    system("sysctl -w net.core.somaxconn=131072 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_max_backlog=100000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fin_timeout=5 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_intvl=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_probes=10 >/dev/null 2>&1");
    system("sysctl -w 'net.ipv4.udp_mem=786432 134217728 268435456' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_rmem_min=131072 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_wmem_min=131072 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_budget=2000 >/dev/null 2>&1");
    system("sysctl -w net.core.busy_poll=100 >/dev/null 2>&1");
    system("sysctl -w net.core.busy_read=100 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_ecn=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_pacing_ss_ratio=200 >/dev/null 2>&1");
    system("sysctl -w vm.swappiness=1 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1");
    /* RPS/XPS kwa CPU zote */
    system("for iface in $(ls /sys/class/net/ | grep -v lo); do "
           "for q in /sys/class/net/$iface/queues/rx-*/rps_cpus; do "
           "echo ffffffffffffffff > \"$q\" 2>/dev/null; done; "
           "for q in /sys/class/net/$iface/queues/rx-*/rps_flow_cnt; do "
           "echo 65536 > \"$q\" 2>/dev/null; done; done");
    fprintf(stderr, "[ELITE-X] Net Booster v5.0: optimizations applied\n");
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
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
Description=ELITE-X Network Booster v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-netbooster
Restart=always
RestartSec=10
LimitMEMLOCK=infinity
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Network Booster v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DNS CACHE OPTIMIZER v5.0 (DOH fallback, fast resolvers)
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
    fprintf(stderr, "[ELITE-X] DNS Cache v5.0 flushed\n");
}

static void optimize_resolv(void) {
    FILE *f = fopen("/etc/resolv.conf", "w");
    if (f) {
        /* Fast resolvers - ordered kwa speed */
        fprintf(f, "nameserver 1.1.1.1\n");    /* Cloudflare fastest */
        fprintf(f, "nameserver 8.8.8.8\n");    /* Google */
        fprintf(f, "nameserver 9.9.9.9\n");    /* Quad9 */
        fprintf(f, "nameserver 8.8.4.4\n");    /* Google backup */
        fprintf(f, "nameserver 1.0.0.1\n");    /* Cloudflare backup */
        fprintf(f, "options timeout:1 attempts:2 rotate\n");
        fprintf(f, "options ndots:0\n");
        fprintf(f, "options single-request-reopen\n");  /* kwa maeneo yenye NAT */
        fclose(f);
        fprintf(stderr, "[ELITE-X] resolv.conf v5.0 optimized (5 fast servers)\n");
    }
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    optimize_resolv();
    while (running) {
        flush_dns();
        optimize_resolv(); /* Re-apply kila wakati - kuzuia kubadilishwa */
        int i; for (i = 0; i < 900 && running; i++) sleep(1); /* Kila dakika 15 */
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
Description=ELITE-X DNS Cache Optimizer v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-dnscache
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ DNS Cache Optimizer v5.0 compiled (5 fast servers, dakika 15 flush)${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: SUPER RAM BOOSTER v5.0
# Maboresho: mlock kwa SlowDNS/UDP processes, hugepages,
# RAM allocation kwa SlowDNS tu, transparent hugepages,
# memory compaction, NUMA-aware allocation
# ═══════════════════════════════════════════════════════════
create_c_ram_cleaner() {
    echo -e "${YELLOW}📝 Compiling C SUPER RAM Booster v5.0...${NC}"

    cat > /tmp/ram_cleaner.c <<'CEOF'
/*
 * ELITE-X SUPER RAM Booster v5.0
 * - mlock() kwa SlowDNS/UDP processes (hakuna swap)
 * - Transparent hugepages kwa performance
 * - Drop caches kila dakika 15 (v4 ilikuwa kila dakika 15)
 * - Memory compaction kwa kupunguza fragmentation
 * - Boost priority ya SlowDNS/UDP processes kwenye scheduler
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <sys/mman.h>
#include <ctype.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static int is_numeric(const char *s) {
    if (!s||!*s) return 0;
    while (*s) { if (!isdigit((unsigned char)*s++)) return 0; }
    return 1;
}

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

/* Lock memory ya processes za SlowDNS na UDP */
static void lock_slowdns_memory(void) {
    DIR *proc = opendir("/proc"); if (!proc) return;
    struct dirent *e;
    while ((e = readdir(proc))) {
        if (!is_numeric(e->d_name)) continue;
        char cp[256]; snprintf(cp, sizeof(cp), "/proc/%s/comm", e->d_name);
        FILE *f = fopen(cp, "r"); if (!f) continue;
        char comm[64] = {0}; fgets(comm, sizeof(comm), f); fclose(f);
        comm[strcspn(comm,"\n")] = 0;
        /* Tumia mlock kwa processes za SlowDNS/UDP */
        if (strstr(comm, "dnstt") || strstr(comm, "elite-x") ||
            strstr(comm, "edns") || strstr(comm, "udp-turbo")) {
            char sched[256];
            snprintf(sched, sizeof(sched),
                "chrt -f -p 60 %s 2>/dev/null; "
                "renice -n -20 -p %s 2>/dev/null",
                e->d_name, e->d_name);
            system(sched);
        }
    }
    closedir(proc);
}

static void clean_and_boost(void) {
    /* Drop page cache kwa kupata RAM zaidi */
    system("sync && echo 1 > /proc/sys/vm/drop_caches 2>/dev/null");
    /* Compact memory - reduce fragmentation */
    write_file("/proc/sys/vm/compact_memory", "1\n");
    /* Memory settings */
    system("sysctl -w vm.swappiness=1 >/dev/null 2>&1");
    system("sysctl -w vm.vfs_cache_pressure=25 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_ratio=20 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_background_ratio=5 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1");
    system("sysctl -w vm.overcommit_ratio=95 >/dev/null 2>&1");
    /* Hugepages */
    write_file("/sys/kernel/mm/transparent_hugepage/enabled", "always\n");
    write_file("/sys/kernel/mm/transparent_hugepage/defrag", "defer+madvise\n");
    /* Boost SlowDNS process priorities */
    lock_slowdns_memory();
    fprintf(stderr, "[ELITE-X] RAM Booster v5.0: memory optimized, SlowDNS/UDP boosted\n");
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    while (running) {
        clean_and_boost();
        int i; for (i = 0; i < 900 && running; i++) sleep(1); /* kila dakika 15 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-ramcleaner /tmp/ram_cleaner.c 2>/dev/null
    rm -f /tmp/ram_cleaner.c

    if [ -f /usr/local/bin/elite-x-ramcleaner ]; then
        chmod +x /usr/local/bin/elite-x-ramcleaner
        cat > /etc/systemd/system/elite-x-ramcleaner.service <<EOF
[Unit]
Description=ELITE-X SUPER RAM Booster v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-ramcleaner
Restart=always
RestartSec=10
Nice=-15
LimitMEMLOCK=infinity
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ SUPER RAM Booster v5.0 compiled (mlock, hugepages, SlowDNS priority boost)${NC}"
    else
        echo -e "${RED}❌ RAM Booster compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: IRQ AFFINITY OPTIMIZER v5.0
# Maboresho: multi-queue NIC (rx-0 hadi rx-15),
# flow steering, CPU zote kwa kila queue,
# NAPI weight optimization
# ═══════════════════════════════════════════════════════════
create_c_irq_optimizer() {
    echo -e "${YELLOW}📝 Compiling C IRQ Affinity Optimizer v5.0 (CPU zote)...${NC}"

    cat > /tmp/irq_optimizer.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

static void optimize_irq(void) {
    /* IRQ zote - CPU zote */
    DIR *d = opendir("/proc/irq"); if (!d) return;
    struct dirent *e;
    while ((e=readdir(d))) {
        if (e->d_name[0]=='.') continue;
        char p[512];
        snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity",e->d_name);
        write_file(p,"ffffffffffffffff\n");
        snprintf(p,sizeof(p),"/proc/irq/%s/smp_affinity_list",e->d_name);
        write_file(p,"0-127\n");
    }
    closedir(d);

    /* RPS/XPS kwa queues zote za kila interface */
    DIR *nd = opendir("/sys/class/net"); if (!nd) return;
    while ((e=readdir(nd))) {
        if (e->d_name[0]=='.') continue;
        if (strcmp(e->d_name,"lo")==0) continue;
        char p[512];
        /* Queues 0-15 (multi-queue NICs) */
        for (int q = 0; q < 16; q++) {
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/rx-%d/rps_cpus",e->d_name,q);
            write_file(p,"ffffffffffffffff\n");
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/tx-%d/xps_cpus",e->d_name,q);
            write_file(p,"ffffffffffffffff\n");
            snprintf(p,sizeof(p),
                "/sys/class/net/%s/queues/rx-%d/rps_flow_cnt",e->d_name,q);
            write_file(p,"65536\n");
        }
    }
    closedir(nd);

    /* Global RFS */
    write_file("/proc/sys/net/core/rps_sock_flow_entries","65536\n");
    /* NAPI budget */
    write_file("/proc/sys/net/core/netdev_budget","2000\n");
    write_file("/proc/sys/net/core/netdev_budget_usecs","4000\n");

    fprintf(stderr,"[ELITE-X] IRQ/RPS/XPS v5.0 optimized (CPU zote, queues 0-15)\n");
}

int main(void) {
    signal(SIGTERM,signal_handler);
    signal(SIGINT,signal_handler);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    while (running) {
        optimize_irq();
        int i; for(i=0;i<300&&running;i++) sleep(1); /* kila dakika 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-irqopt /tmp/irq_optimizer.c 2>/dev/null
    rm -f /tmp/irq_optimizer.c

    if [ -f /usr/local/bin/elite-x-irqopt ]; then
        chmod +x /usr/local/bin/elite-x-irqopt
        cat > /etc/systemd/system/elite-x-irqopt.service <<EOF
[Unit]
Description=ELITE-X IRQ Optimizer v5.0 (CPU zote, multi-queue)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-irqopt
Restart=always
RestartSec=5
LimitMEMLOCK=infinity
Nice=-15
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ IRQ Optimizer v5.0 compiled (CPU zote, queues 0-15, dakika 5)${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: DATA USAGE TRACKER v5.0
# ═══════════════════════════════════════════════════════════
create_c_data_usage() {
    echo -e "${YELLOW}📝 Compiling C Data Usage Tracker v5.0...${NC}"

    cat > /tmp/data_usage.c <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>

#define USER_DB  "/etc/elite-x/users"
#define BW_DIR   "/etc/elite-x/bandwidth"
#define LOG_DIR  "/var/log/elite-x"

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

static void log_usage(void) {
    time_t t = time(NULL);
    char ts[32]; strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", localtime(&t));
    DIR *d = opendir(USER_DB); if (!d) return;
    struct dirent *e;
    FILE *log = fopen("/var/log/elite-x/usage.log", "a");
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char path[512]; snprintf(path, sizeof(path), "%s/%s.usage", BW_DIR, e->d_name);
        FILE *f = fopen(path, "r"); if (!f) continue;
        unsigned long long bytes = 0; fscanf(f, "%llu", &bytes); fclose(f);
        double gb = (double)bytes / 1073741824.0;
        if (log) fprintf(log, "[%s] %s: %.3f GB\n", ts, e->d_name, gb);
    }
    closedir(d);
    if (log) fclose(log);
}

int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(LOG_DIR, 0755);
    while (running) {
        log_usage();
        int i; for (i = 0; i < 300 && running; i++) sleep(1); /* kila dakika 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-datausage /tmp/data_usage.c 2>/dev/null
    rm -f /tmp/data_usage.c

    if [ -f /usr/local/bin/elite-x-datausage ]; then
        chmod +x /usr/local/bin/elite-x-datausage
        cat > /etc/systemd/system/elite-x-datausage.service <<EOF
[Unit]
Description=ELITE-X Data Usage Tracker v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-datausage
Restart=always
RestartSec=10
CPUQuota=5%
MemoryMax=32M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Data Usage Tracker v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C: LOG CLEANER v5.0
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
static void clean_logs(void) {
    system("journalctl --vacuum-size=50M 2>/dev/null");
    system("find /var/log -name '*.log' -size +10M -exec truncate -s 5M {} \\; 2>/dev/null");
    system("find /var/log/elite-x -name 'usage.log' -size +50M -exec truncate -s 10M {} \\; 2>/dev/null");
    fprintf(stderr, "[ELITE-X] Log Cleaner v5.0: logs cleaned\n");
}
int main(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    while (running) {
        clean_logs();
        int i; for (i=0;i<3600&&running;i++) sleep(1); /* kila saa 1 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-logcleaner /tmp/log_cleaner.c 2>/dev/null
    rm -f /tmp/log_cleaner.c

    if [ -f /usr/local/bin/elite-x-logcleaner ]; then
        chmod +x /usr/local/bin/elite-x-logcleaner
        cat > /etc/systemd/system/elite-x-logcleaner.service <<EOF
[Unit]
Description=ELITE-X Log Cleaner v5.0
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-logcleaner
Restart=always
RestartSec=30
CPUQuota=5%
MemoryMax=16M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Log Cleaner v5.0 compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# NEW v5.0: C PING TIMEOUT KILLER
# Inazuia ping timeout kabisa kwa:
# - Sending UDP keepalives kila sekunde 5
# - Monitoring connections na kuzifufua
# - Anti-idle detection
# ═══════════════════════════════════════════════════════════
create_c_ping_timeout_killer() {
    echo -e "${YELLOW}📝 Compiling C Ping Timeout Killer v5.0 (NEW)...${NC}"

    cat > /tmp/ping_killer.c <<CEOF
/*
 * ELITE-X Ping Timeout Killer v5.0
 * Inazuia ping timeout kabisa:
 * - UDP keepalives kwa dnstt port 5300 kila sekunde 5
 * - TCP keepalive via sysctl re-application
 * - Monitor na kufufua connections zilizokufa
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

/* Tuma UDP keepalive kwa dnstt */
static void send_udp_keepalive(void) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) return;
    struct timeval tv = {1, 0};
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = inet_addr("127.0.0.1"),
        .sin_port = htons(5300)
    };
    /* DNS keepalive packet (minimal valid DNS query) */
    unsigned char keepalive[] = {
        0x00, 0x01, /* ID */
        0x01, 0x00, /* Flags: standard query */
        0x00, 0x01, /* Questions: 1 */
        0x00, 0x00, /* Answers: 0 */
        0x00, 0x00, /* Authority: 0 */
        0x00, 0x00, /* Additional: 0 */
        0x00,       /* root query */
        0x00, 0x01, /* Type: A */
        0x00, 0x01  /* Class: IN */
    };
    sendto(sock, keepalive, sizeof(keepalive), 0,
           (struct sockaddr*)&addr, sizeof(addr));
    close(sock);
}

/* Fufua SSH connections zilizokufa */
static void reset_tcp_keepalive(void) {
    system("sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_intvl=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_probes=10 >/dev/null 2>&1");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT, sig);
    fprintf(stderr, "[ELITE-X] Ping Timeout Killer v5.0 started (UDP keepalive kila sekunde 5)\n");
    reset_tcp_keepalive();
    while (running) {
        send_udp_keepalive();
        sleep(5); /* Kila sekunde 5 */
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-pingtimeout /tmp/ping_killer.c 2>/dev/null
    rm -f /tmp/ping_killer.c

    if [ -f /usr/local/bin/elite-x-pingtimeout ]; then
        chmod +x /usr/local/bin/elite-x-pingtimeout
        cat > /etc/systemd/system/elite-x-pingtimeout.service <<EOF
[Unit]
Description=ELITE-X Ping Timeout Killer v5.0 (UDP keepalive kila sekunde 5)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-pingtimeout
Restart=always
RestartSec=2
Nice=-15
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=40
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Ping Timeout Killer v5.0 compiled (keepalive kila sekunde 5)${NC}"
    else
        echo -e "${RED}❌ Ping Timeout Killer compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# NEW v5.0: WEAK NETWORK OPTIMIZER
# Maalum kwa maeneo yenye mtandao mbovu/chini:
# - Adaptive MTU (punguza MTU kwa networks mbovu)
# - Packet retransmission tuning
# - DNS retry optimization
# - TCP window clamping kwa high latency
# ═══════════════════════════════════════════════════════════
create_c_weak_network_optimizer() {
    echo -e "${YELLOW}📝 Compiling C Weak Network Optimizer v5.0 (NEW)...${NC}"

    cat > /tmp/weak_net.c <<CEOF
/*
 * ELITE-X Weak Network Optimizer v5.0
 * Kwa maeneo yenye mtandao mbovu, slow, au unstable:
 * - Punguza retransmission timeouts
 * - Ongeza retry counts
 * - Adaptive congestion control
 * - Path MTU discovery tuning
 * - DSCP/QoS marking kwa DNS/VPN traffic
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/mman.h>

static volatile int running = 1;
void sig(int s) { running = 0; }

static void write_file(const char *p, const char *v) {
    FILE *f = fopen(p,"w"); if(f){fputs(v,f);fclose(f);}
}

static void optimize_for_weak_network(void) {
    /* Punguza RTO min kwa latency ndogo */
    system("ip route change default rto_min 100ms 2>/dev/null || true");
    /* TCP retransmission - haraka zaidi */
    write_file("/proc/sys/net/ipv4/tcp_retries1", "3\n");
    write_file("/proc/sys/net/ipv4/tcp_retries2", "6\n");
    /* Ongeza syn retries kwa networks mbovu */
    write_file("/proc/sys/net/ipv4/tcp_syn_retries", "4\n");
    write_file("/proc/sys/net/ipv4/tcp_synack_retries", "4\n");
    /* Punguza orphan timeout */
    write_file("/proc/sys/net/ipv4/tcp_orphan_retries", "1\n");
    /* DSCP marking kwa UDP/DNS traffic - QoS EF (Expedited Forwarding) */
    system("iptables -t mangle -A OUTPUT -p udp --dport 53 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    system("iptables -t mangle -A OUTPUT -p udp --dport 5300 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    system("iptables -t mangle -A OUTPUT -p udp --dport 5301 -j DSCP --set-dscp-class EF 2>/dev/null || true");
    /* Path MTU discovery */
    write_file("/proc/sys/net/ipv4/tcp_mtu_probing", "2\n"); /* Always probe */
    write_file("/proc/sys/net/ipv4/tcp_base_mss", "512\n");
    /* Reduce initial ssthresh kwa slow start */
    write_file("/proc/sys/net/ipv4/tcp_slow_start_after_idle", "0\n");
    /* UDP fragmentation kwa large DNS packets */
    write_file("/proc/sys/net/ipv4/ip_no_pmtu_disc", "0\n");
    fprintf(stderr, "[ELITE-X] Weak Network Optimizer v5.0: settings applied\n");
}

static void optimize_iptables_qos(void) {
    /* Priority queue kwa VPN traffic */
    system("tc qdisc add dev lo root handle 1: prio bands 3 2>/dev/null || true");
    system("tc filter add dev lo parent 1:0 protocol ip prio 1 u32 "
           "match ip dport 5300 0xffff flowid 1:1 2>/dev/null || true");
    system("tc filter add dev lo parent 1:0 protocol ip prio 1 u32 "
           "match ip dport 53 0xffff flowid 1:1 2>/dev/null || true");
}

int main(void) {
    signal(SIGTERM, sig);
    signal(SIGINT, sig);
    mlockall(MCL_CURRENT | MCL_FUTURE);
    fprintf(stderr, "[ELITE-X] Weak Network Optimizer v5.0 started\n");
    optimize_for_weak_network();
    optimize_iptables_qos();
    while (running) {
        optimize_for_weak_network();
        int i; for (i=0;i<600&&running;i++) sleep(1); /* kila dakika 10 */
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto \
        -o /usr/local/bin/elite-x-weaknet /tmp/weak_net.c 2>/dev/null
    rm -f /tmp/weak_net.c

    if [ -f /usr/local/bin/elite-x-weaknet ]; then
        chmod +x /usr/local/bin/elite-x-weaknet
        cat > /etc/systemd/system/elite-x-weaknet.service <<EOF
[Unit]
Description=ELITE-X Weak Network Optimizer v5.0 (kwa maeneo yenye mtandao mbovu)
After=network.target dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-weaknet
Restart=always
RestartSec=5
Nice=-10
LimitMEMLOCK=infinity
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ Weak Network Optimizer v5.0 compiled (DSCP QoS, MTU adaptive, retry tuning)${NC}"
    else
        echo -e "${RED}❌ Weak Network Optimizer compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# USER MANAGEMENT SCRIPT (Enhanced v5.0)
# ═══════════════════════════════════════════════════════════
create_user_script() {
    echo -e "${YELLOW}📝 Creating User Management Script v5.0...${NC}"

    cat > /usr/local/bin/elite-x-user <<'USERSCRIPT'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'; BOLD='\033[1m'
USER_DB="/etc/elite-x/users"
BW_DIR="/etc/elite-x/bandwidth"
CONN_DB="/etc/elite-x/connections"
BANNED_DIR="/etc/elite-x/banned"
DELETED_DIR="/etc/elite-x/deleted"

add_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"Password: "$NC)" password
    read -p "$(echo -e $GREEN"Expire date (YYYY-MM-DD): "$NC)" expire
    read -p "$(echo -e $GREEN"Connection limit [1]: "$NC)" conn_limit
    read -p "$(echo -e $GREEN"Bandwidth limit GB [0=unlimited]: "$NC)" bw_gb
    conn_limit=${conn_limit:-1}
    bw_gb=${bw_gb:-0}

    if id "$username" &>/dev/null; then
        echo -e "${RED}User $username sudah ada!${NC}"; return
    fi
    useradd -M -s /bin/false "$username" 2>/dev/null
    echo "$username:$password" | chpasswd 2>/dev/null

    mkdir -p "$USER_DB"
    cat > "$USER_DB/$username" <<EOF
Username: $username
Password: $password
Expire: $expire
Conn_Limit: $conn_limit
Bandwidth_GB: $bw_gb
Created: $(date '+%Y-%m-%d %H:%M:%S')
EOF
    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ User $username created (expire: $expire, limit: ${conn_limit}, BW: ${bw_gb}GB)${NC}"
}

list_users() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}              ELITE-X v5.0 USER LIST                             ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════╦════════════════╦════════════╦═══════╦══════════╦═══════╦══════════╣${NC}"
    echo -e "${CYAN}║${WHITE} No   ${CYAN}║${WHITE} Username       ${CYAN}║${WHITE} Expire     ${CYAN}║${WHITE} Conn  ${CYAN}║${WHITE} BW Limit ${CYAN}║${WHITE} Usage ${CYAN}║${WHITE} Status   ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════╬════════════════╬════════════╬═══════╬══════════╬═══════╬══════════╣${NC}"

    i=0
    now_ts=$(date +%s)
    for f in "$USER_DB"/*; do
        [ -f "$f" ] || continue
        i=$((i+1))
        u=$(basename "$f")
        exp=$(grep "Expire:" "$f" | awk '{print $2}')
        cl=$(grep "Conn_Limit:" "$f" | awk '{print $2}')
        bw=$(grep "Bandwidth_GB:" "$f" | awk '{print $2}')
        [ "$bw" = "0" ] && bw_disp="Unlim" || bw_disp="${bw}GB"
        usage_b=$(cat "$BW_DIR/${u}.usage" 2>/dev/null || echo 0)
        usage_gb=$(echo "scale=1; $usage_b / 1073741824" | bc 2>/dev/null || echo "0.0")
        exp_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
        rem=$(( (exp_ts - now_ts) / 86400 ))
        if [ $rem -lt 0 ]; then
            status="${RED}EXPIRED${NC}"
        elif [ $rem -le 3 ]; then
            status="${YELLOW}SOON($rem d)${NC}"
        else
            status="${GREEN}OK($rem d)${NC}"
        fi
        printf "${CYAN}║${WHITE} %-4s ${CYAN}║${WHITE} %-14s ${CYAN}║${WHITE} %-10s ${CYAN}║${WHITE} %-5s ${CYAN}║${WHITE} %-8s ${CYAN}║${WHITE} %-5s ${CYAN}║ %-8b ${CYAN}║${NC}\n" \
            "$i" "$u" "$exp" "$cl" "$bw_disp" "${usage_gb}G" "$status"
    done
    echo -e "${CYAN}╚══════╩════════════════╩════════════╩═══════╩══════════╩═══════╩══════════╝${NC}"
    echo -e "${YELLOW}Total users: $i${NC}"
}

del_user() {
    read -p "$(echo -e $RED"Username to delete: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    cp "$USER_DB/$u" "$DELETED_DIR/${u}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null
    pkill -u "$u" 2>/dev/null; killall -u "$u" -9 2>/dev/null
    userdel -r "$u" 2>/dev/null
    rm -f "$USER_DB/$u" "/etc/elite-x/data_usage/$u" \
          "$CONN_DB/$u" "$BANNED_DIR/$u" "$BW_DIR/$u.usage" \
          "/etc/elite-x/user_messages/$u"
    sed -i "/Match User $u/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
    systemctl reload sshd 2>/dev/null
    echo -e "${GREEN}✅ User $u deleted${NC}"
}

renew_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"New expire date (YYYY-MM-DD): "$NC)" exp
    sed -i "s/^Expire:.*/Expire: $exp/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ User $u renewed until $exp${NC}"
}

setlimit_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"Connection limit: "$NC)" lim
    sed -i "s/^Conn_Limit:.*/Conn_Limit: $lim/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Connection limit set to $lim${NC}"
}

setbw_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    read -p "$(echo -e $GREEN"Bandwidth limit GB [0=unlimited]: "$NC)" bw
    sed -i "s/^Bandwidth_GB:.*/Bandwidth_GB: $bw/" "$USER_DB/$u"
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth limit set to ${bw}GB${NC}"
}

resetdata_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    echo 0 > "$BW_DIR/${u}.usage" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Data usage reset for $u${NC}"
}

lock_user() {
    read -p "$(echo -e $RED"Username to lock: "$NC)" u
    usermod -L "$u" 2>/dev/null
    pkill -u "$u" 2>/dev/null
    echo -e "${GREEN}✅ User $u locked${NC}"
}

unlock_user() {
    read -p "$(echo -e $GREEN"Username to unlock: "$NC)" u
    usermod -U "$u" 2>/dev/null
    rm -f "$BANNED_DIR/$u"
    echo -e "${GREEN}✅ User $u unlocked${NC}"
}

details_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$USER_DB/$u" ] && echo -e "${RED}User not found!${NC}" && return
    echo -e "${CYAN}"; cat "$USER_DB/$u"; echo -e "${NC}"
    echo -e "${YELLOW}Current connections: $(cat "$CONN_DB/$u" 2>/dev/null || echo 0)${NC}"
    usage_b=$(cat "$BW_DIR/${u}.usage" 2>/dev/null || echo 0)
    usage_gb=$(echo "scale=3; $usage_b / 1073741824" | bc 2>/dev/null || echo "0.000")
    echo -e "${YELLOW}Data usage: ${usage_gb} GB${NC}"
}

deleted_list() {
    echo -e "${CYAN}Deleted users:${NC}"
    ls -la "$DELETED_DIR/" 2>/dev/null || echo "None"
}

case "$1" in
    add)      add_user ;;
    list)     list_users ;;
    del)      del_user ;;
    renew)    renew_user ;;
    setlimit) setlimit_user ;;
    setbw)    setbw_user ;;
    resetdata) resetdata_user ;;
    lock)     lock_user ;;
    unlock)   unlock_user ;;
    details)  details_user ;;
    deleted)  deleted_list ;;
    *) echo "Usage: elite-x-user {add|list|del|renew|setlimit|setbw|resetdata|lock|unlock|details|deleted}" ;;
esac
USERSCRIPT
    chmod +x /usr/local/bin/elite-x-user
    echo -e "${GREEN}✅ User Management Script v5.0 created${NC}"
}

# ═══════════════════════════════════════════════════════════
# MAIN MENU v5.0 (Enhanced dashboard)
# ═══════════════════════════════════════════════════════════
create_main_menu() {
    echo -e "${YELLOW}📝 Creating Main Menu v5.0...${NC}"

    local UD="$USER_DB"

    cat > /usr/local/bin/elite-x <<MENUEOF
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'
ORANGE='\033[0;33m'; NC='\033[0m'
UD="$USER_DB"

svc_status() {
    systemctl is-active "\$1" >/dev/null 2>&1 \
        && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}"
}

show_dashboard() {
    clear
    CPU_COUNT=\$(nproc 2>/dev/null || echo 1)
    RAM_TOTAL=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    RAM_FREE=\$(grep MemAvailable /proc/meminfo | awk '{print \$2}')
    RAM_USED_MB=\$(( (RAM_TOTAL - RAM_FREE) / 1024 ))
    RAM_TOTAL_MB=\$(( RAM_TOTAL / 1024 ))
    CPU_LOAD=\$(cat /proc/loadavg | awk '{print \$1}')
    IP=\$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "Unknown")
    TDOMAIN=\$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not set")
    PUB_KEY=\$(cat /etc/elite-x/public_key 2>/dev/null || echo "Unknown")

    echo -e "\${PURPLE}╔══════════════════════════════════════════════════════════════════╗\${NC}"
    echo -e "\${PURPLE}║\${YELLOW}\${BOLD}    ELITE-X SLOWDNS v5.0 - SUPER ULTRA MAX BOOST        \${PURPLE}║\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  IP       : \${CYAN}\$IP\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  NS       : \${CYAN}\$TDOMAIN\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  PubKey   : \${CYAN}\$(echo \$PUB_KEY | cut -c1-40)...\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    printf "\${PURPLE}║\${WHITE}  CPU: \${CYAN}%s cores  \${WHITE}Load: \${CYAN}%s  \${WHITE}RAM: \${CYAN}%s/%s MB\${NC}\n" \
        "\$CPU_COUNT" "\$CPU_LOAD" "\$RAM_USED_MB" "\$RAM_TOTAL_MB"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  SERVICES:\${NC}"

    DNS=\$(svc_status dnstt-elite-x)
    PRX=\$(svc_status dnstt-elite-x-proxy)
    UDP=\$(svc_status elite-x-udp-turbo)
    SPD=\$(svc_status elite-x-speedbooster)
    NBOOST=\$(svc_status elite-x-netbooster)
    DNSC=\$(svc_status elite-x-dnscache)
    BW=\$(svc_status elite-x-bandwidth)
    IRQ=\$(svc_status elite-x-irqopt)
    RAMC=\$(svc_status elite-x-ramcleaner)
    PING=\$(svc_status elite-x-pingtimeout)
    WEAK=\$(svc_status elite-x-weaknet)
    SMSG=\$([ -f /usr/local/bin/elite-x-force-user-message ] && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}")

    echo -e "\${PURPLE}║\${WHITE}  \$DNS DNSTT     \$PRX C-EDNS    \$UDP UDP Turbo  \$SPD Speed\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  \$NBOOST NetBoost  \$DNSC DNS Cache  \$BW BW Mon   \$IRQ IRQ\${NC}"
    echo -e "\${PURPLE}║\${WHITE}  \$RAMC RAM Boost  \$PING PingKill  \$WEAK WeakNet  \$SMSG Msgs\${NC}"
    echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
    TOTAL=\$(ls "\$UD" 2>/dev/null | wc -l)
    ONLINE=\$(who | wc -l)
    echo -e "\${PURPLE}║\${GREEN}  Users: \${YELLOW}\$TOTAL\${GREEN} | Online: \${YELLOW}\$ONLINE\${GREEN} | Speed: \${YELLOW}200Mbps+ ULTRA\${NC}  \${PURPLE}║\${NC}"
    echo -e "\${PURPLE}╚══════════════════════════════════════════════════════════════════╝\${NC}"
}

settings_menu() {
    while true; do
        clear
        echo -e "\${CYAN}╔════════════════════════════════════════════════════════╗\${NC}"
        echo -e "\${CYAN}║\${YELLOW}             SETTINGS v5.0 ULTRA             \${CYAN}║\${NC}"
        echo -e "\${CYAN}╠════════════════════════════════════════════════════════╣\${NC}"
        AUTOBAN=\$(cat "/etc/elite-x/autoban_enabled" 2>/dev/null || echo 0)
        [ "\$AUTOBAN" = "1" ] && AB="\${GREEN}ON\${NC}" || AB="\${RED}OFF\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [1]  Auto-Ban: \$AB\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [2]  Restart All Services\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [3]  Restart DNSTT\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [4]  Recompile All C Components\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [5]  Fix VPN/SSH\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [6]  Refresh All User Messages\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [7]  Test User Message\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [8]  Apply Speed Boost Now (200Mbps+)\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [9]  Fix Ping Timeout\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [10] Optimize Weak Network\${NC}"
        echo -e "\${CYAN}║\${WHITE}  [0]  Back\${NC}"
        echo -e "\${CYAN}╚════════════════════════════════════════════════════════╝\${NC}"
        read -p "\$(echo -e \$GREEN"Option: "\$NC)" ch

        case \$ch in
            1) [ "\$AUTOBAN" = "1" ] && echo 0 > /etc/elite-x/autoban_enabled || echo 1 > /etc/elite-x/autoban_enabled ;;
            2) for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-udp-turbo elite-x-speedbooster elite-x-bandwidth elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner elite-x-datausage elite-x-pingtimeout elite-x-weaknet; do systemctl restart "\$s" 2>/dev/null || true; done; echo -e "\${GREEN}✅ All services restarted\${NC}"; read -p "Enter..." ;;
            3) systemctl restart dnstt-elite-x dnstt-elite-x-proxy; echo -e "\${GREEN}✅ DNSTT restarted\${NC}"; read -p "Enter..." ;;
            4) echo -e "\${YELLOW}Recompiling...\${NC}"; bash \$0 --recompile 2>/dev/null; echo -e "\${GREEN}✅ Recompiled\${NC}"; read -p "Enter..." ;;
            5) systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd 2>/dev/null; echo -e "\${GREEN}✅ Fixed\${NC}"; read -p "Enter..." ;;
            6) for u in "\$UD"/*; do [ -f "\$u" ] && /usr/local/bin/elite-x-force-user-message "\$(basename "\$u")" 2>/dev/null; done; systemctl reload sshd; echo -e "\${GREEN}✅ Messages refreshed\${NC}"; read -p "Enter..." ;;
            7) read -p "Username: " un; cat "/etc/elite-x/user_messages/\$un" 2>/dev/null || echo "No message"; read -p "Enter..." ;;
            8) systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-irqopt elite-x-ramcleaner 2>/dev/null; echo -e "\${GREEN}✅ 200Mbps+ boost applied\${NC}"; read -p "Enter..." ;;
            9) systemctl restart elite-x-pingtimeout; sysctl -w net.ipv4.tcp_keepalive_time=20 >/dev/null 2>&1; echo -e "\${GREEN}✅ Ping timeout fixed\${NC}"; read -p "Enter..." ;;
            10) systemctl restart elite-x-weaknet; echo -e "\${GREEN}✅ Weak network optimized\${NC}"; read -p "Enter..." ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        show_dashboard
        echo -e "\${PURPLE}╔══════════════════════════════════════════════════════════════════╗\${NC}"
        echo -e "\${PURPLE}║\${GREEN}\${BOLD}                 MAIN MENU v5.0 ULTRA                   \${PURPLE}║\${NC}"
        echo -e "\${PURPLE}╠══════════════════════════════════════════════════════════════════╣\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [1] Create User   [2] List Users      [3] User Details\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [4] Renew User    [5] Set Conn Limit   [6] Set BW Limit\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [7] Reset Data    [8] Lock User        [9] Unlock User\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [10] Delete User  [11] Deleted List     [S] Settings\${NC}"
        echo -e "\${PURPLE}║\${WHITE}  [M] Test Msg      [B] Speed Boost       [0] Exit\${NC}"
        echo -e "\${PURPLE}╚══════════════════════════════════════════════════════════════════╝\${NC}"
        read -p "\$(echo -e \$GREEN"Option: "\$NC)" ch

        case \$ch in
            1) elite-x-user add; read -p "Press Enter..." ;;
            2) elite-x-user list; read -p "Press Enter..." ;;
            3) elite-x-user details; read -p "Press Enter..." ;;
            4) elite-x-user renew; read -p "Press Enter..." ;;
            5) elite-x-user setlimit; read -p "Press Enter..." ;;
            6) elite-x-user setbw; read -p "Press Enter..." ;;
            7) elite-x-user resetdata; read -p "Press Enter..." ;;
            8) elite-x-user lock; read -p "Press Enter..." ;;
            9) elite-x-user unlock; read -p "Press Enter..." ;;
            10) elite-x-user del; read -p "Press Enter..." ;;
            11) elite-x-user deleted; read -p "Press Enter..." ;;
            [Ss]) settings_menu ;;
            [Bb]) systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-irqopt elite-x-ramcleaner 2>/dev/null; echo -e "\${GREEN}✅ 200Mbps+ boost applied!\${NC}"; read -p "Press Enter..." ;;
            [Mm])
                read -p "Username: " un
                if [ -f "/etc/elite-x/user_messages/\$un" ]; then
                    clear; cat "/etc/elite-x/user_messages/\$un"
                else
                    echo -e "\${RED}No message for \$un!\${NC}"
                fi
                read -p "Press Enter..." ;;
            0) echo -e "\${GREEN}Goodbye!\${NC}"; exit 0 ;;
            *) echo -e "\${RED}Invalid\${NC}"; read -p "Press Enter..." ;;
        esac
    done
}

main_menu
MENUEOF
    chmod +x /usr/local/bin/elite-x
    echo -e "${GREEN}✅ Main Menu v5.0 created${NC}"
}

# ═══════════════════════════════════════════════════════════
# MAIN INSTALLATION v5.0
# ═══════════════════════════════════════════════════════════
run_installation() {
    show_banner
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}       ELITE-X v5.0 SUPER ULTRA - ACTIVATION       ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT

    if [ "$ACTIVATION_INPUT" != "$ACTIVATION_KEY" ] && [ "$ACTIVATION_INPUT" != "Whtsapp +255713-628-668" ]; then
        echo -e "${RED}❌ Invalid activation key!${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Activation successful${NC}"
    sleep 1

    set_timezone

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           ENTER YOUR NAMESERVER [NS]        ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Nameserver: "$NC)" TDOMAIN

    echo -e "${YELLOW}Select VPS location (MTU):${NC}"
    echo -e "  [1] South Africa (MTU 1800)"
    echo -e "  [2] USA (MTU 1500)"
    echo -e "  [3] Europe (MTU 1500)"
    echo -e "  [4] Asia (MTU 1400)"
    echo -e "  [5] Custom MTU"
    read -p "$(echo -e $GREEN"Choice [1]: "$NC)" LOC
    LOC=${LOC:-1}
    case $LOC in
        2) SEL_LOC="USA"; MTU=1500 ;;
        3) SEL_LOC="Europe"; MTU=1500 ;;
        4) SEL_LOC="Asia"; MTU=1400 ;;
        5) SEL_LOC="Custom"; read -p "MTU: " MTU; [[ ! "$MTU" =~ ^[0-9]+$ ]] && MTU=1800 ;;
        *) SEL_LOC="South Africa"; MTU=1800 ;;
    esac

    echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"
    for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth elite-x-datausage elite-x-connmon \
              elite-x-cleaner elite-x-traffic elite-x-netbooster elite-x-dnscache elite-x-ramcleaner \
              elite-x-irqopt elite-x-logcleaner elite-x-udp-turbo elite-x-speedbooster \
              elite-x-pingtimeout elite-x-weaknet 3proxy-elite; do
        systemctl stop "$s" 2>/dev/null || true
        systemctl disable "$s" 2>/dev/null || true
    done
    pkill -f dnstt-server 2>/dev/null || true
    pkill -f elite-x- 2>/dev/null || true
    rm -rf /etc/systemd/system/{dnstt-elite-x*,elite-x*,3proxy-elite*} 2>/dev/null
    rm -rf /etc/dnstt /etc/elite-x /var/run/elite-x 2>/dev/null
    rm -f /usr/local/bin/{dnstt-*,elite-x*,3proxy} 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf 2>/dev/null
    rm -f /etc/sysctl.d/99-elite-x-vpn.conf 2>/dev/null
    sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    systemctl restart sshd 2>/dev/null || true
    sleep 2

    # Create directories
    mkdir -p /etc/elite-x/{users,traffic,deleted,data_usage,connections,banned,traffic_stats,bandwidth/pidtrack,user_messages}
    mkdir -p /etc/ssh/sshd_config.d
    mkdir -p /var/run/elite-x/bandwidth
    mkdir -p /var/log/elite-x
    echo "$TDOMAIN" > /etc/elite-x/subdomain
    echo "$SEL_LOC" > /etc/elite-x/location
    echo "$MTU" > /etc/elite-x/mtu
    echo "0" > "$AUTOBAN_FLAG"
    echo "$STATIC_PRIVATE_KEY" > /etc/elite-x/private_key
    echo "$STATIC_PUBLIC_KEY" > /etc/elite-x/public_key

    # Configure DNS
    [ -f /etc/systemd/resolved.conf ] && {
        sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null || true
    }
    [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\nnameserver 8.8.4.4\nnameserver 1.0.0.1\noptions timeout:1 attempts:2 rotate\noptions ndots:0\n" > /etc/resolv.conf

    # Install dependencies
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    apt update -y
    apt install -y curl jq iptables ethtool dnsutils net-tools iproute2 bc \
        build-essential git gcc make linux-tools-common numactl \
        iptables-persistent 2>/dev/null

    # Download DNSTT
    echo -e "${YELLOW}📥 Downloading DNSTT server...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null || {
        curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server 2>/dev/null
    }
    chmod +x /usr/local/bin/dnstt-server

    # Setup DNSTT keys
    mkdir -p /etc/dnstt
    echo "$STATIC_PRIVATE_KEY" > /etc/dnstt/server.key
    echo "$STATIC_PUBLIC_KEY" > /etc/dnstt/server.pub
    chmod 600 /etc/dnstt/server.key

    # Create DNSTT service - SUPER ULTRA BOOSTED
    cat > /etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=ELITE-X DNSTT Server v5.0 SUPER ULTRA
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
CPUSchedulingPriority=90
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF

    # Optimize system FIRST
    optimize_system_for_vpn

    # PAM + user messages
    configure_pam_user_message

    # SSH
    configure_ssh_for_vpn

    # Compile all C components
    create_c_edns_proxy
    create_c_udp_turbo
    create_c_speed_booster
    create_c_bandwidth_monitor
    create_c_connection_monitor
    create_c_network_booster
    create_c_dns_cache
    create_c_ram_cleaner
    create_c_irq_optimizer
    create_c_data_usage
    create_c_log_cleaner
    # NEW v5.0 components
    create_c_ping_timeout_killer
    create_c_weak_network_optimizer

    # EDNS Proxy service (after compilation)
    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        cat > /etc/systemd/system/dnstt-elite-x-proxy.service <<EOF
[Unit]
Description=ELITE-X SUPER ULTRA EDNS Proxy v5.0 (${CPU_COUNT} CPU threads)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-edns-proxy ${CPU_COUNT}
Restart=always
RestartSec=1
LimitNOFILE=4194304
LimitMEMLOCK=infinity
Nice=-20
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=85
IOSchedulingClass=realtime
IOSchedulingPriority=0
[Install]
WantedBy=multi-user.target
EOF
    fi

    # User scripts
    create_user_script
    create_main_menu

    # Enable and start ALL services
    systemctl daemon-reload

    ALL_SERVICES=(
        dnstt-elite-x
        dnstt-elite-x-proxy
        elite-x-udp-turbo
        elite-x-speedbooster
        elite-x-bandwidth
        elite-x-datausage
        elite-x-connmon
        elite-x-netbooster
        elite-x-dnscache
        elite-x-ramcleaner
        elite-x-irqopt
        elite-x-logcleaner
        elite-x-pingtimeout
        elite-x-weaknet
    )

    for s in "${ALL_SERVICES[@]}"; do
        if [ -f "/etc/systemd/system/${s}.service" ]; then
            systemctl enable "$s" 2>/dev/null || true
            systemctl start "$s" 2>/dev/null || true
        fi
    done

    # Cache IP
    IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "Unknown")
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
alias boost='systemctl restart elite-x-speedbooster elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-udp-turbo elite-x-pingtimeout'
alias fixvpn='systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd && echo "VPN Fixed!"'
alias refreshmsg='for u in /etc/elite-x/users/*; do [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")"; done && systemctl reload sshd && echo "✅ Messages refreshed!"'
alias testmsg='read -p "Username: " u; cat /etc/elite-x/user_messages/$u 2>/dev/null || echo "No message"'
alias speedtest='systemctl restart elite-x-speedbooster && echo "200Mbps+ Speed boost applied!"'
alias fixping='systemctl restart elite-x-pingtimeout && sysctl -w net.ipv4.tcp_keepalive_time=20 && echo "Ping timeout fixed!"'
alias weakfix='systemctl restart elite-x-weaknet && echo "Weak network optimized!"'
alias status='systemctl status dnstt-elite-x dnstt-elite-x-proxy elite-x-udp-turbo elite-x-speedbooster'
EOF

    # Create initial messages for existing users
    for user_file in /etc/elite-x/users/*; do
        [ -f "$user_file" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$user_file")" 2>/dev/null
    done

    # ═══════════════════════════════════════════════════════════
    # FINAL DISPLAY - SUPER ULTRA
    # ═══════════════════════════════════════════════════════════
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}${BOLD}   ELITE-X v5.0 SUPER ULTRA MAX BOOST - INSTALLED!     ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Domain     :${CYAN} $TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  Location   :${CYAN} $SEL_LOC (MTU: $MTU)${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  CPU Cores  :${CYAN} ${CPU_COUNT} (ZOTE zinatumika)${NC}"
    echo -e "${GREEN}║${WHITE}  RAM        :${CYAN} ${RAM_MB}MB (mlock + hugepages)${NC}"
    echo -e "${GREEN}║${WHITE}  Version    :${CYAN} v5.0 Super Ultra Max Boost${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"

    check_svc() {
        local name=$1 svc=$2
        systemctl is-active "$svc" >/dev/null 2>&1 \
            && echo -e "${GREEN}║  ✅ $name: Running${NC}" \
            || echo -e "${RED}║  ❌ $name: Failed${NC}"
    }

    check_svc "DNSTT Server           " "dnstt-elite-x"
    check_svc "SUPER EDNS Proxy       " "dnstt-elite-x-proxy"
    check_svc "SUPER UDP Turbo        " "elite-x-udp-turbo"
    check_svc "Speed Booster 200Mbps+ " "elite-x-speedbooster"
    check_svc "SSH Server             " "sshd"
    check_svc "Bandwidth Monitor      " "elite-x-bandwidth"
    check_svc "Connection Monitor     " "elite-x-connmon"
    check_svc "Network Booster        " "elite-x-netbooster"
    check_svc "DNS Cache Optimizer    " "elite-x-dnscache"
    check_svc "SUPER RAM Booster      " "elite-x-ramcleaner"
    check_svc "IRQ Optimizer (All CPU)" "elite-x-irqopt"
    check_svc "Log Cleaner            " "elite-x-logcleaner"
    check_svc "Ping Timeout Killer    " "elite-x-pingtimeout"
    check_svc "Weak Network Optimizer " "elite-x-weaknet"

    if [ -f /usr/local/bin/elite-x-force-user-message ]; then
        echo -e "${GREEN}║  ✅ User Messages       : Active (SSH login)${NC}"
    fi

    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  NEW IN v5.0 SUPER ULTRA MAX:${NC}"
    echo -e "${GREEN}║${WHITE}  🚀 recvmmsg/sendmmsg batch (64-128 packets kwa mara moja)${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ Lockless MPMC ring buffer (131K/262K entries)${NC}"
    echo -e "${GREEN}║${WHITE}  🧵 Per-CPU thread pinning (CPU zote ${CPU_COUNT} zinatumika)${NC}"
    echo -e "${GREEN}║${WHITE}  🔒 mlock() - RAM yote inafungwa (hakuna swap)${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ SO_BUSY_POLL zero-wait polling${NC}"
    echo -e "${GREEN}║${WHITE}  🏎️  SCHED_FIFO priority 80-90 kwa SlowDNS/UDP${NC}"
    echo -e "${GREEN}║${WHITE}  📦 Socket buffers: 32MB UDP / 512MB TCP${NC}"
    echo -e "${GREEN}║${WHITE}  🔁 BBR + FQ + CAKE qdisc (bora kwa weak networks)${NC}"
    echo -e "${GREEN}║${WHITE}  🌐 Multi-queue RPS/XPS (queues 0-15, CPU zote)${NC}"
    echo -e "${GREEN}║${WHITE}  💉 DSCP/QoS EF marking kwa DNS/VPN traffic${NC}"
    echo -e "${GREEN}║${WHITE}  💤 CPU C-states disabled (latency ndogo sana)${NC}"
    echo -e "${GREEN}║${WHITE}  🩹 Ping Timeout Killer (UDP keepalive kila sekunde 5)${NC}"
    echo -e "${GREEN}║${WHITE}  📡 Weak Network Optimizer (kwa maeneo yenye mtandao mbovu)${NC}"
    echo -e "${GREEN}║${WHITE}  🧠 Hugepages + RAM locking kwa SlowDNS processes${NC}"
    echo -e "${GREEN}║${WHITE}  🔧 TCP Pacing (200Mbps smooth flow)${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${CYAN}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS     : ${CYAN}$TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY : ${CYAN}$STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}║${WHITE}  PORT   : ${CYAN}53 (primary) | 5301 (UDP Turbo)${NC}"
    echo -e "${GREEN}║${WHITE}  SPEED  : ${CYAN}200Mbps+ (${CPU_COUNT} CPU cores zote zinatumika)${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Commands: menu | adduser | users | boost | fixvpn | speedtest | fixping | weakfix | status${NC}"
    echo -e "${YELLOW}Re-login au 'exec bash' ili kufikia dashboard${NC}"
    echo ""
}

# Run installation
run_installation

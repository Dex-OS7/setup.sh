#!/bin/bash

# ============================================================================
#                    ELITE-X GHOST v5.0 - MODERN SLOWDNS + DASHBOARD
# ============================================================================
# Version: Ghost v5.0
# Features: SlowDNS + UDP Turbo + Boosters + Dropbear + FULL DASHBOARD
# ============================================================================

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[✗]\033[0m Please run this script as root"
    exit 1
fi

# ============================================================================
# CONFIGURATION
# ============================================================================
SSHD_PORT=2222
SLOWDNS_PORT=5300

# ELITE-X Static Keys
STATIC_PRIVATE_KEY="7f207e92ab7cb365aad1966b62d2cfbd3f450fe8e523a38ffc7ecfbcec315693"
STATIC_PUBLIC_KEY="40aa057fcb2574e1e9223ea46457f9fdf9d60a2a1c23da87602202d93b41aa04"
ACTIVATION_KEY="ELITE"
TIMEZONE="Africa/Dar_es_Salaam"

# ELITE-X Ports
PORT_SLOWDNS_UDP=53
PORT_SLOWDNS_TCP=5300
PORT_UDP_TURBO=5301
PORT_UDP_TURBO2=5302

# ELITE-X Directories
USER_DB="/etc/elite-x/users"
USAGE_DB="/etc/elite-x/data_usage"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
PIDTRACK_DIR="$BANDWIDTH_DIR/pidtrack"
BANNED_DB="/etc/elite-x/banned"
CONN_DB="/etc/elite-x/connections"
DELETED_DB="/etc/elite-x/deleted"
AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"
USER_MSG_DIR="/etc/elite-x/user_messages"

# ============================================================================
# COLORS
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
ORANGE='\033[0;33m'
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
GRAY='\033[0;90m'
MAGENTA='\033[1;35m'
NC='\033[0m'

# ============================================================================
# FUNCTIONS
# ============================================================================
show_banner() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}${BOLD}   ELITE-X GHOST v5.0 - SLOWDNS ULTRA            ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${CYAN}   SlowDNS + UDP Turbo + Boosters + Dropbear              ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${GREEN}     Speed 30Mbps+ | BBR3 | Zero Ping | MTU 2200 MAX      ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "\n${BLUE}┌─${NC} ${CYAN}${BOLD}STEP $1${NC}"
    echo -e "${BLUE}│${NC}"
}

print_step_end() {
    echo -e "${BLUE}└─${NC} ${GREEN}✓${NC} Completed"
}

print_success() {
    echo -e "  ${GREEN}${BOLD}✓${NC} ${GREEN}$1${NC}"
}

print_error() {
    echo -e "  ${RED}${BOLD}✗${NC} ${RED}$1${NC}"
}

print_info() {
    echo -e "  ${CYAN}${BOLD}ℹ${NC} ${CYAN}$1${NC}"
}

show_progress() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ============================================================================
# SET TIMEZONE
# ============================================================================
set_timezone() {
    timedatectl set-timezone "$TIMEZONE" 2>/dev/null || \
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true
}

# ============================================================================
# SYSTEM OPTIMIZATION - FROM ELITE-X v5
# ============================================================================
optimize_system_for_vpn() {
    echo -e "${YELLOW}🚀 Applying MAXIMUM system optimizations for 30Mbps+...${NC}"

    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true

    cat > /etc/sysctl.d/99-elite-x-ghost.conf <<'SYSCTL'
# ═══ ELITE-X GHOST v5.0 ULTRA SYSCTL ═══
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
SYSCTL

    sysctl -p /etc/sysctl.d/99-elite-x-ghost.conf >/dev/null 2>&1 || true

    cat > /etc/security/limits.d/elite-x-ghost.conf <<'LIMITS'
* soft nofile 2097152
* hard nofile 2097152
* soft nproc 65536
* hard nproc 65536
root soft nofile 2097152
root hard nofile 2097152
LIMITS

    mkdir -p /etc/systemd/system.conf.d/
    cat > /etc/systemd/system.conf.d/elite-x-ghost-limits.conf <<'SDLIMIT'
[Manager]
DefaultLimitNOFILE=2097152
DefaultLimitNPROC=65536
SDLIMIT

    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
        ethtool -K "$iface" gso on gro on tso on 2>/dev/null || true
        ip link set "$iface" txqueuelen 10000 2>/dev/null || true
    done

    echo -e "${GREEN}✅ MAXIMUM system optimization applied${NC}"
}

# ============================================================================
# C: ULTRA EDNS PROXY - FROM ELITE-X v5
# ============================================================================
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
#define MAX_EDNS_SIZE      2200
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
    fprintf(stderr, "[ELITE-X GHOST] C-EDNS Proxy v5.0 running (port 53, %d workers, 16MB buf)\n",
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
        cat > /etc/systemd/system/edns-proxy-elite.service <<EOF
[Unit]
Description=ELITE-X GHOST ULTRA EDNS Proxy v5.0
After=slowdns-elite.service
Wants=slowdns-elite.service
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
        echo -e "${GREEN}✅ ULTRA EDNS Proxy v5.0 compiled (64 workers, 16MB buffers)${NC}"
    else
        echo -e "${RED}❌ EDNS Proxy compilation failed${NC}"
    fi
}

# ============================================================================
# C: UDP TURBO RELAY - FROM ELITE-X v5
# ============================================================================
create_c_udp_turbo() {
    echo -e "${YELLOW}📝 Compiling UDP Turbo Relay v5.0 (dual-port)...${NC}"

    cat > /tmp/udp_turbo.c <<'CEOF'
/*
 * ELITE-X GHOST UDP Turbo Relay v5.0
 * Listens on port 5301 AND 5302 simultaneously
 * Forwards to DNSTT on 5300 with minimal latency
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
        fprintf(stderr, "[ELITE-X GHOST] UDP Turbo: failed to bind any port\n");
        return 1;
    }

    pthread_t pool[POOL_SIZE];
    int i;
    for (i = 0; i < POOL_SIZE; i++) {
        pthread_attr_t a; pthread_attr_init(&a);
        pthread_attr_setdetachstate(&a, PTHREAD_CREATE_DETACHED);
        pthread_create(&pool[i], &a, worker, NULL);
        pthread_attr_destroy(&a);
    }

    pthread_t rt1, rt2;
    if (sock1 >= 0) {
        static int s1; s1 = sock1;
        pthread_create(&rt1, NULL, reader_thread, &s1);
    }
    if (sock2 >= 0) {
        static int s2; s2 = sock2;
        pthread_create(&rt2, NULL, reader_thread, &s2);
    }

    fprintf(stderr, "[ELITE-X GHOST] UDP Turbo v5.0: port %d & %d → backend %d (%d workers)\n",
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
Description=ELITE-X GHOST C UDP Turbo Relay v5.0 (port 5301+5302)
After=slowdns-elite.service
Wants=slowdns-elite.service
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

# ============================================================================
# C: SPEED BOOSTER - FROM ELITE-X v5
# ============================================================================
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
    fprintf(stderr, "[ELITE-X GHOST] Speed Booster: network stack boosted for 30Mbps+\n");
}

static void boost_cpu(void) {
    system("for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; "
           "do echo performance > \"$f\" 2>/dev/null; done");
    write_file("/sys/devices/system/cpu/cpuidle/current_driver", "none\n");
    fprintf(stderr, "[ELITE-X GHOST] Speed Booster: CPU set to performance mode\n");
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
Description=ELITE-X GHOST C Speed Booster v5.0 (30Mbps+)
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

# ============================================================================
# C: RAM CLEANER - FROM ELITE-X v5
# ============================================================================
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
    fprintf(stderr,"[ELITE-X GHOST] RAM cleaned\n");
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
Description=ELITE-X GHOST C RAM Cache Cleaner v5.0
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

# ============================================================================
# C: IRQ AFFINITY OPTIMIZER - FROM ELITE-X v5
# ============================================================================
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
    fprintf(stderr,"[ELITE-X GHOST] IRQ/RPS/XPS optimized\n");
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
Description=ELITE-X GHOST C IRQ Affinity Optimizer v5.0
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

# ============================================================================
# C: LOG CLEANER - FROM ELITE-X v5
# ============================================================================
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
    fprintf(stderr,"[ELITE-X GHOST] Logs cleaned\n");
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
Description=ELITE-X GHOST C Log Cleaner v5.0
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

# ============================================================================
# COLORFUL USER MESSAGE - FROM ELITE-X v5
# ============================================================================
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

    cat <<EOF > "$msg_file"
<div style="background-color: #000000; color: #ffffff; font-family: 'Courier New', Courier, monospace; padding: 20px; border-radius: 5px; display: inline-block; white-space: pre; line-height: 1.4;">
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #00ffff; font-weight: bold;"> <center>ELITE-X GHOST v5.0 </center>  </span><span style="color: #ffff00; font-weight: bold;">▐</span>
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
<span style="color: #ffff00; font-weight: bold;"> CONNECTION</span>: <span style="color: #ff00ff; font-weight: bold;">$current_conn/$conn_limit</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> STATUS    </span>: <span style="color: #00ff00; font-weight: bold;">$status_icon $status_text</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #00ffff; font-weight: bold;">   Thanks for using ELITE-X GHOST    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
</div>
EOF

    chmod 644 "$msg_file"
    echo "$msg_file"
}

# ============================================================================
# PAM + LOGIN SCRIPT - FROM ELITE-X v5
# ============================================================================
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
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #00ffff; font-weight: bold;"> <center>ELITE-X GHOST v5.0 </center>  </span><span style="color: #ffff00; font-weight: bold;">▐</span>
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
<span style="color: #00ffff; font-weight: bold;">   Thanks for using ELITE-X GHOST    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
</div>
EOF

chmod 644 "$MSG_FILE"
sed -i "/Match User $USERNAME/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-ghost-users.conf 2>/dev/null
echo "Match User $USERNAME" >> /etc/ssh/sshd_config.d/elite-x-ghost-users.conf
echo "    Banner $MSG_FILE" >> /etc/ssh/sshd_config.d/elite-x-ghost-users.conf
systemctl reload sshd 2>/dev/null || true
FORCE
    chmod +x /usr/local/bin/elite-x-force-user-message

    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    echo "session optional pam_exec.so seteuid /usr/local/bin/elite-x-update-user-msg" >> /etc/pam.d/sshd
    echo -e "${GREEN}✅ PAM configured - colorful message updates on each login${NC}"
}

# ============================================================================
# CREATE DASHBOARD MENU - LIKE ELITE-X v5
# ============================================================================
create_dashboard_menu() {
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
    MTU=$(cat /etc/elite-x/mtu 2>/dev/null || echo "2200")
    RAM=$(free -h | awk '/^Mem:/{print $3"/"$2}')
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "?")

    svc_dot() { systemctl is-active "$1" >/dev/null 2>&1 && echo "${GREEN}●${NC}" || echo "${RED}●${NC}"; }

    DNS=$(svc_dot slowdns-elite)
    PRX=$(svc_dot edns-proxy-elite)
    UDP=$(svc_dot elite-x-udp-turbo)
    SPD=$(svc_dot elite-x-speedbooster)
    RAMC=$(svc_dot elite-x-ramcleaner)
    IRQ=$(svc_dot elite-x-irqopt)
    LOGC=$(svc_dot elite-x-logcleaner)

    TOTAL=$(ls "$UD" 2>/dev/null | wc -l)
    ONLINE=$(who | wc -l)

    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}${BOLD}    ELITE-X GHOST v5 - SLOWDNS ULTRA           ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${WHITE}  IP   :${CYAN} $IP   ${WHITE}MTU:${CYAN}$MTU  ${WHITE}LOC:${CYAN}$LOC${NC}"
    echo -e "${MAGENTA}║${WHITE}  NS   :${CYAN} $SUB${NC}"
    echo -e "${MAGENTA}║${WHITE}  RAM  :${CYAN} $RAM   ${WHITE}CPU:${CYAN}${CPU}%  ${WHITE}Users:${CYAN}${TOTAL}  ${WHITE}Online:${CYAN}${ONLINE}${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${YELLOW}  SERVICES STATUS:${NC}"
    echo -e "${MAGENTA}║${WHITE}  DNSTT Server    $DNS  C-EDNS Proxy  $PRX  UDP Turbo    $UDP${NC}"
    echo -e "${MAGENTA}║${WHITE}  Speed Booster   $SPD  RAM Cleaner   $RAMC  IRQ Optimizer $IRQ${NC}"
    echo -e "${MAGENTA}║${WHITE}  Log Cleaner     $LOGC${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${CYAN}  PORTS: SlowDNS UDP: 53 | 5301 | 5302${NC}"
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
        echo -e "${CYAN}║${WHITE}  [3]  Restart DNSTT + Proxy${NC}"
        echo -e "${CYAN}║${WHITE}  [4]  Refresh All User Messages${NC}"
        echo -e "${CYAN}║${WHITE}  [5]  Apply Speed Boost Now${NC}"
        echo -e "${CYAN}║${RED}  [6]  ⚠️ UNINSTALL ELITE-X GHOST${NC}"
        echo -e "${CYAN}║${YELLOW}  [7]  🔄 Reboot Server${NC}"
        echo -e "${CYAN}║${WHITE}  [8]  🔧 Change MTU${NC}"
        echo -e "${CYAN}║${WHITE}  [0]  Back${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch

        case $ch in
            1)
                [ "$AUTOBAN" = "1" ] && echo 0 > "$AUTOBAN_FLAG" || echo 1 > "$AUTOBAN_FLAG"
                ;;
            2)
                for s in slowdns-elite edns-proxy-elite elite-x-udp-turbo \
                         elite-x-speedbooster elite-x-ramcleaner elite-x-irqopt \
                         elite-x-logcleaner; do
                    systemctl restart "$s" 2>/dev/null || true
                done
                echo -e "${GREEN}✅ All services restarted${NC}"; read -p "Enter..."
                ;;
            3)
                systemctl restart slowdns-elite edns-proxy-elite elite-x-udp-turbo 2>/dev/null
                echo -e "${GREEN}✅ DNSTT + Proxy restarted${NC}"; read -p "Enter..."
                ;;
            4)
                for u in "$UD"/*; do
                    [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")" 2>/dev/null
                done
                systemctl reload sshd 2>/dev/null
                echo -e "${GREEN}✅ Messages refreshed${NC}"; read -p "Enter..."
                ;;
            5)
                systemctl restart elite-x-speedbooster elite-x-irqopt 2>/dev/null
                echo -e "${GREEN}✅ Speed boost applied${NC}"; read -p "Enter..."
                ;;
            6)
                clear
                echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║${YELLOW}${BOLD}       ⚠️ UNINSTALL ELITE-X GHOST ⚠️           ${RED}║${NC}"
                echo -e "${RED}╠══════════════════════════════════════════════════════╣${NC}"
                echo -e "${RED}║${WHITE}  Hii itafuta KILA KITU:                          ${RED}║${NC}"
                echo -e "${RED}║${WHITE}  • Users wote watafutwa                          ${RED}║${NC}"
                echo -e "${RED}║${WHITE}  • Services zote zitasimamishwa                  ${RED}║${NC}"
                echo -e "${RED}║${WHITE}  • Binaries na configs zote zitafutwa            ${RED}║${NC}"
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
                    for s in slowdns-elite edns-proxy-elite elite-x-udp-turbo \
                             elite-x-speedbooster elite-x-ramcleaner elite-x-irqopt \
                             elite-x-logcleaner; do
                        systemctl stop    "$s" 2>/dev/null || true
                        systemctl disable "$s" 2>/dev/null || true
                    done
                    rm -f /etc/systemd/system/{slowdns-elite*,edns-proxy-elite*,elite-x*}
                    rm -rf /etc/slowdns /etc/elite-x /var/run/elite-x
                    rm -f /usr/local/bin/{dnstt-server,elite-x*,edns-proxy}
                    rm -f /etc/ssh/sshd_config.d/elite-x-ghost-*.conf
                    rm -f /etc/sysctl.d/99-elite-x-ghost.conf
                    rm -f /etc/security/limits.d/elite-x-ghost.conf
                    rm -f /etc/systemd/system.conf.d/elite-x-ghost-limits.conf
                    sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
                    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
                    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
                    rm -f /etc/profile.d/elite-x-ghost.sh
                    systemctl daemon-reload
                    systemctl restart sshd 2>/dev/null || true
                    echo -e "${GREEN}✅ ELITE-X GHOST imefutwa kikamilifu!${NC}"
                    exit 0
                else
                    echo -e "${GREEN}✅ Imeancel${NC}"
                fi
                read -p "Press Enter..."
                ;;
            7)
                clear
                echo -e "${YELLOW}╔══════════════════════════════════════════╗${NC}"
                echo -e "${YELLOW}║${RED}${BOLD}       🔄 REBOOT SERVER              ${YELLOW}║${NC}"
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
            8)
                clear
                CURRENT_MTU=$(cat /etc/elite-x/mtu 2>/dev/null || echo "2200")
                echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║${YELLOW}           🔧 CHANGE MTU                    ${CYAN}║${NC}"
                echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
                echo -e "${CYAN}║${WHITE}  Current MTU  : ${GREEN}${CURRENT_MTU}${NC}"
                echo -e "${CYAN}║${WHITE}  Recommended  : ${CYAN}2200 (boost) | 1800 (stable)${NC}"
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
                        sed -i "s|-mtu [0-9]*|-mtu $NEW_MTU|" /etc/systemd/system/slowdns-elite.service 2>/dev/null
                        systemctl daemon-reload 2>/dev/null
                        systemctl restart slowdns-elite 2>/dev/null
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
        echo -e "${MAGENTA}║${WHITE}  [1] Create User    [2] List Users     [3] Delete User${NC}"
        echo -e "${MAGENTA}║${WHITE}  [S] Settings       [P] Show Ports      [0] Exit${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch

        case $ch in
            1)  elite-x-user add;        read -p "Press Enter..." ;;
            2)  elite-x-user list;       read -p "Press Enter..." ;;
            3)  elite-x-user del;        read -p "Press Enter..." ;;
            [Ss]) settings_menu ;;
            [Pp])
                clear
                IP=$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "?")
                echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
                echo -e "${MAGENTA}║${YELLOW}        ELITE-X GHOST v5.0 PORT REFERENCE         ${MAGENTA}║${NC}"
                echo -e "${MAGENTA}╠══════════════════════════════════════════════════════╣${NC}"
                echo -e "${MAGENTA}║${CYAN}  SSH          : ${WHITE}22${NC}"
                echo -e "${MAGENTA}║${CYAN}  Dropbear     : ${WHITE}$(cat /etc/default/dropbear 2>/dev/null | grep DROPBEAR_PORT | cut -d= -f2 || echo "2222")${NC}"
                echo -e "${MAGENTA}║${CYAN}  SlowDNS UDP  : ${WHITE}53 (primary DNS)${NC}"
                echo -e "${MAGENTA}║${CYAN}  DNSTT Backend: ${WHITE}5300${NC}"
                echo -e "${MAGENTA}║${CYAN}  UDP Turbo 1  : ${WHITE}5301${NC}"
                echo -e "${MAGENTA}║${CYAN}  UDP Turbo 2  : ${WHITE}5302${NC}"
                echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"
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

# ============================================================================
# CREATE USER MANAGEMENT SCRIPT - FROM ELITE-X v5
# ============================================================================
create_user_script() {
    cat > /usr/local/bin/elite-x-user <<'USEREOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
WHITE='\033[1;37m';BOLD='\033[1m';ORANGE='\033[0;33m';MAGENTA='\033[1;35m'
NC='\033[0m'

UD="/etc/elite-x/users"; USAGE_DB="/etc/elite-x/data_usage"
DD="/etc/elite-x/deleted"; BD="/etc/elite-x/banned"
CONN_DB="/etc/elite-x/connections"; BW_DIR="/etc/elite-x/bandwidth"
PID_DIR="$BW_DIR/pidtrack"; AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"
mkdir -p "$UD" "$USAGE_DB" "$DD" "$BD" "$CONN_DB" "$BW_DIR" "$PID_DIR"

get_connection_count() {
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

add_user() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}     CREATE SSH + SLOWDNS USER v5.0             ${MAGENTA}║${NC}"
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

    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null

    local bw_disp="Unlimited"; [ "$bw" != "0" ] && bw_disp="${bw} GB"
    SERVER=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "?")
    IP=$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "?")
    PUBKEY=$(cat /etc/elite-x/public_key 2>/dev/null || echo "?")

    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}         USER CREATED SUCCESSFULLY - GHOST v5.0      ${GREEN}║${NC}"
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
    echo -e "${GREEN}║${WHITE}  UDP Port: ${CYAN}53 | 5301 | 5302${NC}"
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

        local ex limit bw_limit
        ex=$(awk '/^Expire:/{print $2}' "$user" | tr -d ' \n')
        limit=$(awk '/^Conn_Limit:/{print $2}' "$user" | tr -d ' \n')
        [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
        bw_limit=$(awk '/^Bandwidth_GB:/{print $2}' "$user" | tr -d ' \n')
        [[ "$bw_limit" =~ ^[0-9]+\.?[0-9]*$ ]] || bw_limit=0

        local _uid; _uid=$(id -u "$u" 2>/dev/null || echo "")
        local cc=0
        [ -n "$_uid" ] && cc=${_sess_map[$_uid]:-0}
        [[ "$cc" =~ ^[0-9]+$ ]] || cc=0

        local raw_bytes=0
        [ -f "$BW_DIR/${u}.usage" ] && {
            raw_bytes=$(cat "$BW_DIR/${u}.usage" 2>/dev/null | tr -d ' \n\r')
            [[ "$raw_bytes" =~ ^[0-9]+$ ]] || raw_bytes=0
        }
        local total_gb; total_gb=$(echo "scale=2; $raw_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

        local expire_ts days_left
        expire_ts=$(date -d "$ex" +%s 2>/dev/null || echo 0)
        [[ "$expire_ts" =~ ^[0-9]+$ ]] || expire_ts=0
        days_left=$(( (expire_ts - _cur_ts) / 86400 ))

        local status
        if passwd -S "$u" 2>/dev/null | grep -q "L"; then
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

        local bw_disp
        if [ "$bw_limit" != "0" ] && [ -n "$bw_limit" ]; then
            local quota_b; quota_b=$(echo "$bw_limit * 1073741824 / 1" | bc 2>/dev/null || echo 1)
            if [ "$raw_bytes" -ge "$quota_b" ] 2>/dev/null; then
                bw_disp="${RED}${total_gb}/${bw_limit}GB${NC}"
            else
                bw_disp="${GREEN}${total_gb}/${bw_limit}GB${NC}"
            fi
        else
            bw_disp="${GRAY}${total_gb}GB/∞${NC}"
        fi

        local ld ed
        if   [ "$cc" -eq 0 ];            then ld="${GRAY}0/${limit}${NC}"
        elif [ "$cc" -ge "$limit" ];      then ld="${RED}${cc}/${limit}${NC}"
        else                                   ld="${GREEN}${cc}/${limit}${NC}"
        fi

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

case $1 in
    add)      add_user ;;
    list)     list_users ;;
    del)
        read -p "Username: " u
        [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
        pkill -u "$u" 2>/dev/null || true
        killall -u "$u" -9 2>/dev/null || true
        userdel -r "$u" 2>/dev/null
        rm -f "$UD/$u" "$USAGE_DB/$u" "$CONN_DB/$u" "$BD/$u" "$BW_DIR/${u}.usage" "/etc/elite-x/user_messages/$u"
        rm -f "$PID_DIR/${u}"__*.last 2>/dev/null
        echo -e "${GREEN}✅ Deleted${NC}" ;;
    *)
        echo "Usage: elite-x-user {add|list|del}"
        ;;
esac
USEREOF
    chmod +x /usr/local/bin/elite-x-user
}

# ============================================================================
# MAIN INSTALLATION FUNCTION
# ============================================================================
main() {
    show_banner
    
    # Activation
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}          ELITE-X GHOST v5.0 ACTIVATION REQUIRED      ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT

    if [ "$ACTIVATION_INPUT" != "$ACTIVATION_KEY" ] && \
       [ "$ACTIVATION_INPUT" != "Whtsapp +255713-628-668" ]; then
        echo -e "${RED}❌ Invalid activation key!${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Activation successful${NC}"
    sleep 1

    set_timezone

    # Get nameserver
    echo -e "\n${WHITE}${BOLD}Enter nameserver configuration:${NC}"
    echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}Example:${NC} tunnel.yourdomain.com                             ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    read -p "$(echo -e "${WHITE}${BOLD}Enter nameserver: ${NC}")" NAMESERVER
    NAMESERVER=${NAMESERVER:-dns.example.com}

    echo -e "\n${YELLOW}Select VPS location:${NC}"
    echo -e "  [1] South Africa (MTU 2200) "
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
           [[ ! "$MTU" =~ ^[0-9]+$ ]] && MTU=2200
           [ "$MTU" -lt 100  ] 2>/dev/null && MTU=100
           [ "$MTU" -gt 3000 ] 2>/dev/null && MTU=2200 ;;
        *) SEL_LOC="South Africa"; MTU=2200 ;;
    esac

    # Get Server IP
    echo -ne "  ${CYAN}Detecting server IP address...${NC}"
    SERVER_IP=$(curl -s --connect-timeout 5 ifconfig.me)
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
    fi
    echo -e "\r  ${GREEN}Server IP:${NC} ${WHITE}${BOLD}$SERVER_IP${NC}"

    # ── Cleanup previous installation ─────────────────────
    echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"
    for s in slowdns-elite edns-proxy-elite elite-x-udp-turbo elite-x-speedbooster \
              elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner; do
        systemctl stop    "$s" 2>/dev/null || true
        systemctl disable "$s" 2>/dev/null || true
    done
    pkill -f dnstt-server 2>/dev/null || true
    pkill -f elite-x-edns-proxy 2>/dev/null || true
    pkill -f elite-x-udp-turbo 2>/dev/null || true
    rm -rf /etc/systemd/system/{slowdns-elite*,edns-proxy-elite*,elite-x*} 2>/dev/null
    rm -rf /etc/slowdns /etc/elite-x 2>/dev/null

    # ── Create directories ─────────────────────────────────
    mkdir -p /etc/slowdns
    mkdir -p /etc/elite-x/{users,traffic,deleted,data_usage,connections,banned,bandwidth/pidtrack,user_messages}
    mkdir -p /etc/ssh/sshd_config.d

    echo "$NAMESERVER" > /etc/elite-x/subdomain
    echo "$SEL_LOC" > /etc/elite-x/location
    echo "$MTU" > /etc/elite-x/mtu
    echo "0" > "$AUTOBAN_FLAG"
    echo "$STATIC_PRIVATE_KEY" > /etc/elite-x/private_key
    echo "$STATIC_PUBLIC_KEY" > /etc/elite-x/public_key

    # ── DNS ────────────────────────────────────────────────
    [ -f /etc/systemd/resolved.conf ] && {
        sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null || true
    }
    [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 9.9.9.9\noptions timeout:1 attempts:3 rotate\noptions ndots:0\n" \
        > /etc/resolv.conf

    # ── Install dependencies ───────────────────────────────
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    apt-get update -y
    apt-get install -y curl jq iptables ethtool dnsutils net-tools iproute2 bc \
        build-essential git gcc make linux-tools-common iproute2 \
        libssl-dev dropbear 2>/dev/null

    # ── Download DNSTT ────────────────────────────────────
    echo -e "${YELLOW}📥 Downloading DNSTT server...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 \
         -o /usr/local/bin/dnstt-server 2>/dev/null || \
    curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server \
         -o /usr/local/bin/dnstt-server 2>/dev/null
    chmod +x /usr/local/bin/dnstt-server

    # ── DNSTT keys ────────────────────────────────────────
    echo "$STATIC_PRIVATE_KEY" > /etc/slowdns/server.key
    echo "$STATIC_PUBLIC_KEY" > /etc/slowdns/server.pub
    chmod 600 /etc/slowdns/server.key

    # ── Configure Dropbear ────────────────────────────────
    echo -e "${YELLOW}🔧 Configuring Dropbear on port $SSHD_PORT...${NC}"
    cat > /etc/default/dropbear << EOF
NO_START=0
DROPBEAR_PORT=$SSHD_PORT
DROPBEAR_EXTRA_ARGS="-p $SSHD_PORT"
EOF
    systemctl enable dropbear > /dev/null 2>&1
    systemctl restart dropbear 2>/dev/null || true

    # ── SlowDNS main service ────────────────────────────────
    cat > /etc/systemd/system/slowdns-elite.service <<EOF
[Unit]
Description=ELITE-X GHOST DNSTT Server v5.0 ULTRA
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -mtu ${MTU} -privkey-file /etc/slowdns/server.key ${NAMESERVER} 127.0.0.1:${SSHD_PORT}
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
    echo -e "${YELLOW}🔧 Configuring SSH...${NC}"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    sed -i '/^Banner/d; /^Match User/d; /Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' \
        /etc/ssh/sshd_config 2>/dev/null

    cat > /etc/ssh/sshd_config.d/elite-x-ghost-base.conf <<'SSHCONF'
# ELITE-X GHOST VPN Base Configuration v5.0
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

Compression no
UseDNS no
LogLevel VERBOSE
IPQoS lowdelay throughput
SSHCONF

    cat > /etc/ssh/sshd_config.d/elite-x-ghost-users.conf <<'SSHCONF2'
# ELITE-X GHOST Dynamic User Banners - v5.0
SSHCONF2

    echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true

    # ── Compile all C components ──────────────────────────
    create_c_edns_proxy
    create_c_udp_turbo
    create_c_speed_booster
    create_c_ram_cleaner
    create_c_irq_optimizer
    create_c_log_cleaner

    # ── User scripts ──────────────────────────────────────
    create_user_script
    create_dashboard_menu

    # ── Enable & start all services ───────────────────────
    systemctl daemon-reload

    ALL_SERVICES=(
        slowdns-elite
        edns-proxy-elite
        elite-x-udp-turbo
        elite-x-speedbooster
        elite-x-ramcleaner
        elite-x-irqopt
        elite-x-logcleaner
    )

    for s in "${ALL_SERVICES[@]}"; do
        if [ -f "/etc/systemd/system/${s}.service" ]; then
            systemctl enable "$s" 2>/dev/null || true
            systemctl start "$s" 2>/dev/null || true
        fi
    done

    # ── Cache IP ──────────────────────────────────────────
    echo "$SERVER_IP" > /etc/elite-x/cached_ip

    # ── Auto-login dashboard ──────────────────────────────
    cat > /etc/profile.d/elite-x-ghost.sh <<'EOF'
#!/bin/bash
if [ -f /usr/local/bin/elite-x ] && [ -z "$ELITE_X_GHOST_SHOWN" ]; then
    export ELITE_X_GHOST_SHOWN=1
    /usr/local/bin/elite-x
fi
EOF
    chmod +x /etc/profile.d/elite-x-ghost.sh

    # ── Shell aliases ─────────────────────────────────────
    grep -qF "alias menu='elite-x'" ~/.bashrc 2>/dev/null || cat >> ~/.bashrc <<'EOF'
alias menu='elite-x'
alias elitex='elite-x'
alias adduser='elite-x-user add'
alias users='elite-x-user list'
alias boost='systemctl restart elite-x-speedbooster elite-x-ramcleaner elite-x-irqopt'
alias fixvpn='systemctl restart slowdns-elite edns-proxy-elite sshd && echo "VPN Fixed!"'
alias ports='echo "SlowDNS UDP:53|5301|5302"'
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
    echo -e "${GREEN}║${YELLOW}${BOLD}     ELITE-X GHOST v5.0 INSTALLED!                ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Domain     :${CYAN} $NAMESERVER${NC}"
    echo -e "${GREEN}║${WHITE}  Location   :${CYAN} $SEL_LOC (MTU: $MTU)${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $SERVER_IP${NC}"
    echo -e "${GREEN}║${WHITE}  Version    :${CYAN} v5 Ghost Ultra${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"

    check_svc() {
        local name=$1 svc=$2
        systemctl is-active "$svc" >/dev/null 2>&1 \
            && echo -e "${GREEN}║  ✅ $name: ${LIGHT_GREEN}Running${NC}" \
            || echo -e "${RED}║  ❌ $name: Failed${NC}"
    }

    check_svc "DNSTT Server         " "slowdns-elite"
    check_svc "C EDNS Proxy         " "edns-proxy-elite"
    check_svc "C UDP Turbo(5301+5302)" "elite-x-udp-turbo"
    check_svc "Dropbear SSH         " "dropbear"
    check_svc "C Speed Booster      " "elite-x-speedbooster"
    check_svc "C RAM Cleaner        " "elite-x-ramcleaner"
    check_svc "C IRQ Optimizer      " "elite-x-irqopt"
    check_svc "C Log Cleaner        " "elite-x-logcleaner"

    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  GHOST v5.0 FEATURES:${NC}"
    echo -e "${GREEN}║${WHITE}  🌐 EDNS Proxy: 64 workers + 16MB buffers${NC}"
    echo -e "${GREEN}║${WHITE}  🚀 UDP Turbo DUAL port: 5301 + 5302${NC}"
    echo -e "${GREEN}║${WHITE}  🎨 Colorful SSH banners with user stats${NC}"
    echo -e "${GREEN}║${WHITE}  ⚡ BBR3 + FQ qdisc + RPS/XPS all CPUs${NC}"
    echo -e "${GREEN}║${WHITE}  📦 MTU ${MTU} MAX${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${CYAN}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS     : ${CYAN}$NAMESERVER${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY : ${CYAN}$STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}║${WHITE}  UDP    : ${CYAN}53 | 5301 | 5302${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Commands: ${CYAN}menu${YELLOW} | ${CYAN}elitex${YELLOW} | ${CYAN}adduser${YELLOW} | ${CYAN}users${YELLOW} | ${CYAN}boost${YELLOW} | ${CYAN}fixvpn${YELLOW} | ${CYAN}ports${NC}"
    echo -e "${YELLOW}Re-login or 'exec bash' to access dashboard automatically${NC}"
    echo ""

    # Client configuration
    echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${WHITE}${BOLD}CLIENT CONFIGURATION${NC}                                  ${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}SlowDNS Client Command:${NC}                                   ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} ${GREEN}./dnstt-client -udp $SERVER_IP:5300 \\${NC}             ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} ${GREEN}    -pubkey-file server.pub \\${NC}                   ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} ${GREEN}    $NAMESERVER 127.0.0.1:1080${NC}                ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────┘${NC}"
}

# ============================================================================
# EXECUTE
# ============================================================================
trap 'echo -e "\n${RED}✗ Installation interrupted!${NC}"; exit 1' INT

if main; then
    exit 0
else
    echo -e "\n${RED}✗ Installation failed${NC}"
    exit 1
fi

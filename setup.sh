#!/bin/bash
# ============================================================================
#  MODED-V1 - ELITE-X SLOWDNS + DROPBEAR
#  Mchanganyiko wa Amokhan V3 na moded.sh
#  Inatumia Dropbear kwa SlowDNS tunneling + Dashboard za ELITE-X
# ============================================================================

set -euo pipefail

# ============================================================================
# RANGI
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
MAGENTA='\033[1;35m'
NC='\033[0m'

print_color() { echo -e "${2}${1}${NC}"; }

# ============================================================================
# SELF DESTRUCT
# ============================================================================
self_destruct() {
    echo -e "${YELLOW}🧹 Cleaning installation traces...${NC}"
    history -c 2>/dev/null || true
    cat /dev/null > ~/.bash_history 2>/dev/null || true
    cat /dev/null > /root/.bash_history 2>/dev/null || true
    if [ -f "$0" ] && [ "$0" != "/usr/local/bin/moded" ]; then
        local script_path=$(readlink -f "$0")
        rm -f "$script_path" 2>/dev/null || true
    fi
    sed -i '/moded/d' /var/log/auth.log 2>/dev/null || true
    echo -e "${GREEN}✅ Cleanup complete!${NC}"
}

# ============================================================================
# BANNER NA QUOTE
# ============================================================================
show_quote() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}            MODED-V1 - ELITE-X + DROPBEAR             ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_banner() {
    clear
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}${BOLD}              MODED-V1 - ELITE-X + DROPBEAR            ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${GREEN}${BOLD}         SlowDNS VPN • Super Fast • Unlimited          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${CYAN}${BOLD}            🎨 Colorful User Messages 🎨                  ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# CONFIGURATION
# ============================================================================
ACTIVATION_KEY="ELITE-X"
ACTIVATION_FILE="/etc/moded/activated"
KEY_FILE="/etc/moded/key"
TIMEZONE="Africa/Dar_es_Salaam"
DROPBEAR_PORT=2222
SLOWDNS_PORT=5300

BANDWIDTH_DIR="/etc/moded/bandwidth"
PIDTRACK_DIR="$BANDWIDTH_DIR/pidtrack"
USER_MSG_DIR="/etc/moded/user_messages"
SERVER_MSG_DIR="/etc/moded/server_msg"

set_timezone() {
    timedatectl set-timezone $TIMEZONE 2>/dev/null || ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true
}

activate_script() {
    local input_key="$1"
    mkdir -p /etc/moded
    if [ "$input_key" = "$ACTIVATION_KEY" ] || [ "$input_key" = "Whtsapp 0765-566-877" ]; then
        echo "$ACTIVATION_KEY" > "$ACTIVATION_FILE"
        echo "$ACTIVATION_KEY" > "$KEY_FILE"
        echo -e "${GREEN}✅ Activation successful - Unlimited Version${NC}"
        return 0
    fi
    return 1
}

# ============================================================================
# COLORFUL USER MESSAGE (HTML + ANSI - KAMA V5)
# ============================================================================
force_user_message() {
    local username="$1"
    local msg_file="$USER_MSG_DIR/$username"
    mkdir -p "$USER_MSG_DIR"

    local expire_date bandwidth_gb conn_limit
    expire_date=$(grep "Expire:" "/etc/moded/users/$username" 2>/dev/null | awk '{print $2}')
    bandwidth_gb=$(grep "Bandwidth_GB:" "/etc/moded/users/$username" 2>/dev/null | awk '{print $2}')
    conn_limit=$(grep "Conn_Limit:" "/etc/moded/users/$username" 2>/dev/null | awk '{print $2}')
    bandwidth_gb=${bandwidth_gb:-0}
    conn_limit=${conn_limit:-2}

    local usage_bytes usage_gb
    usage_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
    usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

    # Accurate connection count via /proc
    local current_conn=0
    local _uid; _uid=$(id -u "$username" 2>/dev/null || echo "")
    if [ -n "$_uid" ]; then
        for _pid_dir in /proc/[0-9]*/; do
            local _pid="${_pid_dir%/}"; _pid="${_pid##*/proc/}"
            [ -f "${_pid_dir}comm" ] || continue
            [ "$(cat "${_pid_dir}comm" 2>/dev/null)" = "dropbear" ] || continue
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
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #00ffff; font-weight: bold;">     MODED-V1 - ELITE-X VPN      </span><span style="color: #ffff00; font-weight: bold;">▐</span>
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
<span style="background-color: #00ff00; color: #ffffff; font-weight: bold; display: block; text-align: center;">   Thanks for using MODED-V1 VPN    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #00ff00; font-weight: bold;"> Whatsapp| +255713-628-668       </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
</div>
EOF

    chmod 644 "$msg_file"
    echo "$msg_file"
}

# ============================================================================
# CONFIGURE DROPBEAR (Badala ya OpenSSH)
# ============================================================================
configure_dropbear() {
    echo -e "${YELLOW}🔧 Configuring Dropbear on port $DROPBEAR_PORT...${NC}"
    
    # Install Dropbear if not installed
    if ! command -v dropbear &>/dev/null; then
        apt update -y && apt install -y dropbear
    fi
    
    # Configure Dropbear
    cat > /etc/default/dropbear <<EOF
NO_START=0
DROPBEAR_PORT=$DROPBEAR_PORT
DROPBEAR_EXTRA_ARGS="-p $DROPBEAR_PORT -B -W 65536 -K 60 -I 600"
EOF
    
    # Create Dropbear banner directory
    mkdir -p /etc/dropbear
    
    # Create base banner
    cat > /etc/dropbear/banner <<'EOF'
===============================================
      WELCOME TO MODED-V1 - ELITE-X VPN
      SlowDNS • Dropbear • Super Fast
===============================================
EOF
    
    systemctl enable dropbear 2>/dev/null || true
    systemctl restart dropbear 2>/dev/null || {
        dropbear -p $DROPBEAR_PORT -B -W 65536 -K 60 -I 600 &
    }
    
    echo -e "${GREEN}✅ Dropbear running on port $DROPBEAR_PORT${NC}"
}

# ============================================================================
# CONFIGURE SSH BANNERS KWA DROPBEAR (Per User)
# ============================================================================
configure_dropbear_banners() {
    echo -e "${YELLOW}🔧 Configuring Dropbear user banners...${NC}"
    
    # Dropbear uses a single banner file, but we can use PAM or custom scripts
    # We'll use a dynamic banner script that updates on login
    
    cat > /usr/local/bin/moded-update-banner <<'SCRIPT'
#!/bin/bash
USERNAME="$1"
if [ -n "$USERNAME" ] && [ -f "/etc/moded/users/$USERNAME" ]; then
    /usr/local/bin/moded-force-user-message "$USERNAME" 2>/dev/null
fi
SCRIPT
    chmod +x /usr/local/bin/moded-update-banner
    
    # Force user message script
    cat > /usr/local/bin/moded-force-user-message <<'FORCE'
#!/bin/bash
USERNAME="$1"
USER_DB="/etc/moded/users"
BANDWIDTH_DIR="/etc/moded/bandwidth"
USER_MSG_DIR="/etc/moded/user_messages"

if [ -z "$USERNAME" ] || [ ! -f "$USER_DB/$USERNAME" ]; then exit 0; fi
mkdir -p "$USER_MSG_DIR"
MSG_FILE="$USER_MSG_DIR/$USERNAME"

expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}
conn_limit=${conn_limit:-2}

usage_bytes=$(cat "$BANDWIDTH_DIR/${USERNAME}.usage" 2>/dev/null || echo 0)
usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

# Connection count via /proc (dropbear)
current_conn=0
_uid=$(id -u "$USERNAME" 2>/dev/null || echo "")
if [ -n "$_uid" ]; then
    for _pd in /proc/[0-9]*/; do
        [ -f "${_pd}comm" ] || continue
        [ "$(cat "${_pd}comm" 2>/dev/null)" = "dropbear" ] || continue
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
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #00ffff; font-weight: bold;">     MODED-V1 - ELITE-X VPN      </span><span style="color: #ffff00; font-weight: bold;">▐</span>
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
<span style="background-color: #00ff00; color: #ffffff; font-weight: bold; display: block; text-align: center;">   Thanks for using MODED-V1 VPN    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #00ff00; font-weight: bold;"> Whatsapp| +255713-628-668       </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
</div>
EOF

chmod 644 "$MSG_FILE"
# Update dropbear banner symlink
ln -sf "$MSG_FILE" /etc/dropbear/banner 2>/dev/null || true
FORCE
    chmod +x /usr/local/bin/moded-force-user-message
    
    echo -e "${GREEN}✅ Dropbear banners configured${NC}"
}

# ============================================================================
# C: BANDWIDTH MONITOR (KUTOKA AMOKHAN V3)
# ============================================================================
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

#define USER_DB "/etc/moded/users"
#define BW_DIR "/etc/moded/bandwidth"
#define PID_DIR "/etc/moded/bandwidth/pidtrack"
#define BANNED_DIR "/etc/moded/banned"
#define SCAN_INTERVAL 30
#define GB_BYTES 1073741824.0

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

long long get_process_io(int pid) {
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

int is_numeric(const char *str) { for (; *str; str++) if (!isdigit(*str)) return 0; return 1; }

int get_dropbear_pids(const char *username, int *pids, int max_pids) {
    int count = 0;
    DIR *proc = opendir("/proc");
    if (!proc) return 0;
    struct dirent *entry;
    while ((entry = readdir(proc)) && count < max_pids) {
        if (!is_numeric(entry->d_name)) continue;
        int pid = atoi(entry->d_name);
        char comm_path[256];
        snprintf(comm_path, sizeof(comm_path), "/proc/%d/comm", pid);
        FILE *f = fopen(comm_path, "r");
        if (!f) continue;
        char comm[256] = {0};
        fgets(comm, sizeof(comm), f);
        fclose(f);
        comm[strcspn(comm, "\n")] = 0;
        if (strcmp(comm, "dropbear") == 0) {
            char status_path[256];
            snprintf(status_path, sizeof(status_path), "/proc/%d/status", pid);
            FILE *sf = fopen(status_path, "r");
            if (!sf) continue;
            char line[256], uid_str[32] = {0};
            while (fgets(line, sizeof(line), sf)) {
                if (strncmp(line, "Uid:", 4) == 0) { sscanf(line, "%*s %s", uid_str); break; }
            }
            fclose(sf);
            int uid = atoi(uid_str);
            struct passwd *pw = getpwuid(uid);
            if (pw && strcmp(pw->pw_name, username) == 0) {
                char stat_path[256];
                snprintf(stat_path, sizeof(stat_path), "/proc/%d/stat", pid);
                FILE *stf = fopen(stat_path, "r");
                if (stf) {
                    int ppid;
                    char stat_buf[1024];
                    fgets(stat_buf, sizeof(stat_buf), stf);
                    sscanf(stat_buf, "%*d %*s %*c %d", &ppid);
                    fclose(stf);
                    if (ppid != 1) pids[count++] = pid;
                }
            }
        }
    }
    closedir(proc);
    return count;
}

int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(BW_DIR, 0755); mkdir(PID_DIR, 0755); mkdir(BANNED_DIR, 0755);
    
    while (running) {
        DIR *user_dir = opendir(USER_DB);
        if (!user_dir) { sleep(SCAN_INTERVAL); continue; }
        struct dirent *user_entry;
        while ((user_entry = readdir(user_dir))) {
            if (user_entry->d_name[0] == '.') continue;
            char user_file[512];
            snprintf(user_file, sizeof(user_file), "%s/%s", USER_DB, user_entry->d_name);
            FILE *uf = fopen(user_file, "r");
            if (!uf) continue;
            double bandwidth_gb = 0;
            char line[256];
            while (fgets(line, sizeof(line), uf)) {
                if (strncmp(line, "Bandwidth_GB:", 13) == 0) sscanf(line + 13, "%lf", &bandwidth_gb);
            }
            fclose(uf);
            if (bandwidth_gb <= 0) continue;
            
            int pids[100];
            int pid_count = get_dropbear_pids(user_entry->d_name, pids, 100);
            if (pid_count == 0) {
                char cmd[512];
                snprintf(cmd, sizeof(cmd), "rm -f %s/%s__*.last 2>/dev/null", PID_DIR, user_entry->d_name);
                system(cmd); continue;
            }
            
            long long delta_total = 0;
            for (int i = 0; i < pid_count; i++) {
                long long cur_io = get_process_io(pids[i]);
                char pidfile[512];
                snprintf(pidfile, sizeof(pidfile), "%s/%s__%d.last", PID_DIR, user_entry->d_name, pids[i]);
                FILE *pf = fopen(pidfile, "r");
                if (pf) { long long prev_io; fscanf(pf, "%lld", &prev_io); fclose(pf); long long d = (cur_io >= prev_io) ? (cur_io - prev_io) : cur_io; delta_total += d; }
                pf = fopen(pidfile, "w");
                if (pf) { fprintf(pf, "%lld\n", cur_io); fclose(pf); }
            }
            
            char usagefile[512];
            snprintf(usagefile, sizeof(usagefile), "%s/%s.usage", BW_DIR, user_entry->d_name);
            long long accumulated = 0;
            FILE *accf = fopen(usagefile, "r");
            if (accf) { fscanf(accf, "%lld", &accumulated); fclose(accf); }
            long long new_total = accumulated + delta_total;
            accf = fopen(usagefile, "w");
            if (accf) { fprintf(accf, "%lld\n", new_total); fclose(accf); }
            
            long long quota_bytes = (long long)(bandwidth_gb * GB_BYTES);
            if (new_total >= quota_bytes) {
                char cmd[1024];
                snprintf(cmd, sizeof(cmd), "passwd -S %s 2>/dev/null | grep -q 'L' || (usermod -L %s 2>/dev/null && killall -u %s -9 2>/dev/null && echo '%s - BLOCKED: Bandwidth quota exceeded %.1fGB' >> %s/%s)", user_entry->d_name, user_entry->d_name, user_entry->d_name, "BLOCKED", bandwidth_gb, BANNED_DIR, user_entry->d_name);
                system(cmd);
            }
        }
        closedir(user_dir);
        sleep(SCAN_INTERVAL);
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -o /usr/local/bin/moded-bandwidth-c /tmp/bw_monitor.c 2>/dev/null
    rm -f /tmp/bw_monitor.c
    
    if [ -f /usr/local/bin/moded-bandwidth-c ]; then
        chmod +x /usr/local/bin/moded-bandwidth-c
        cat > /etc/systemd/system/moded-bandwidth.service <<EOF
[Unit]
Description=MODED-V1 C Bandwidth Monitor (GB Limits)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/moded-bandwidth-c
Restart=always
RestartSec=10
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C Bandwidth Monitor compiled${NC}"
    else
        echo -e "${RED}❌ C Bandwidth Monitor compilation failed${NC}"
    fi
}

# ============================================================================
# BANDWIDTH MANAGER (TC)
# ============================================================================
setup_bandwidth_manager() {
    cat > /usr/local/bin/moded-bandwidth <<'EOF'
#!/bin/bash
USER_DB="/etc/moded/users"
TRAFFIC_DB="/etc/moded/traffic"
BANDWIDTH_DIR="/etc/moded/bandwidth"
BANDWIDTH_LIMIT=10240
TOTAL_BANDWIDTH=102400

setup_tc() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    tc qdisc del dev $interface root 2>/dev/null || true
    tc qdisc add dev $interface root handle 1: htb default 30
    tc class add dev $interface parent 1: classid 1:1 htb rate ${TOTAL_BANDWIDTH}kbit ceil ${TOTAL_BANDWIDTH}kbit
    tc class add dev $interface parent 1:1 classid 1:30 htb rate ${BANDWIDTH_LIMIT}kbit ceil ${BANDWIDTH_LIMIT}kbit
}

add_user_bandwidth() {
    local username=$1
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    local classid=$(printf "%x" $(echo "$username" | cksum | cut -d' ' -f1))
    classid=${classid: -2}
    tc class add dev $interface parent 1:1 classid 1:0x$classid htb rate ${BANDWIDTH_LIMIT}kbit ceil ${BANDWIDTH_LIMIT}kbit 2>/dev/null || true
    tc filter add dev $interface parent 1:0 protocol ip prio 1 u32 match ip sport $DROPBEAR_PORT 0xffff flowid 1:0x$classid 2>/dev/null || true
}

remove_user_bandwidth() {
    local username=$1
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    local classid=$(printf "%x" $(echo "$username" | cksum | cut -d' ' -f1))
    classid=${classid: -2}
    tc filter del dev $interface parent 1:0 prio 1 2>/dev/null || true
    tc class del dev $interface classid 1:0x$classid 2>/dev/null || true
}

set_gb_limit() {
    local username=$2
    local gb_limit=$3
    if [ -f "$USER_DB/$username" ]; then
        if grep -q "Bandwidth_GB:" "$USER_DB/$username"; then
            sed -i "s/Bandwidth_GB: .*/Bandwidth_GB: $gb_limit/" "$USER_DB/$username"
        else
            echo "Bandwidth_GB: $gb_limit" >> "$USER_DB/$username"
        fi
        echo "0" > "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null
        rm -rf "$BANDWIDTH_DIR/pidtrack/${username}" 2>/dev/null
        usermod -U "$username" 2>/dev/null
        /usr/local/bin/moded-force-user-message "$username" 2>/dev/null
        echo "✅ Bandwidth limit set to ${gb_limit} GB for $username"
    else
        echo "❌ User not found!"
    fi
}

reset_bandwidth() {
    local username=$2
    if [ -f "$USER_DB/$username" ]; then
        echo "0" > "$BANDWIDTH_DIR/${username}.usage"
        rm -rf "$BANDWIDTH_DIR/pidtrack/${username}" 2>/dev/null
        usermod -U "$username" 2>/dev/null
        /usr/local/bin/moded-force-user-message "$username" 2>/dev/null
        echo "✅ Bandwidth reset to 0 for $username"
    else
        echo "❌ User not found!"
    fi
}

show_bandwidth() {
    local username=$2
    if [ -f "$USER_DB/$username" ]; then
        local limit=$(grep "Bandwidth_GB:" "$USER_DB/$username" 2>/dev/null | awk '{print $2}')
        limit=${limit:-0}
        local usage_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
        local usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")
        echo "User: $username"
        echo "Bandwidth Limit: ${limit} GB"
        echo "Usage: ${usage_gb} GB"
        if [ "$limit" != "0" ]; then
            local percent=$(echo "scale=1; ($usage_gb / $limit) * 100" | bc 2>/dev/null || echo "0")
            echo "Used: ${percent}%"
        fi
    else
        echo "❌ User not found!"
    fi
}

case "$1" in
    init) setup_tc ;;
    add) add_user_bandwidth "$2" ;;
    remove) remove_user_bandwidth "$2" ;;
    setgb) set_gb_limit "$@" ;;
    resetbw) reset_bandwidth "$@" ;;
    showbw) show_bandwidth "$@" ;;
    *) echo "Usage: moded-bandwidth {init|add|remove|setgb|resetbw|showbw}" ;;
esac
EOF
    chmod +x /usr/local/bin/moded-bandwidth
    /usr/local/bin/moded-bandwidth init
}

# ============================================================================
# CONNECTION MONITOR (KUTOKA AMOKHAN V3)
# ============================================================================
setup_connection_monitor() {
    cat > /usr/local/bin/moded-connmon <<'EOF'
#!/bin/bash
USER_DB="/etc/moded/users"
CONN_DB="/etc/moded/connections"
BAN_DB="/etc/moded/banned"
BANDWIDTH_DIR="/etc/moded/bandwidth"
mkdir -p $CONN_DB $BAN_DB $BANDWIDTH_DIR

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/moded-connmon.log
}

get_connection_count() {
    local username=$1
    # Count dropbear sessions via /proc
    local count=0
    local _uid=$(id -u "$username" 2>/dev/null || echo "")
    if [ -n "$_uid" ]; then
        for _pd in /proc/[0-9]*/; do
            [ -f "${_pd}comm" ] || continue
            [ "$(cat "${_pd}comm" 2>/dev/null)" = "dropbear" ] || continue
            local _puid=$(awk '/^Uid:/{print $2}' "${_pd}status" 2>/dev/null)
            [ "$_puid" = "$_uid" ] || continue
            local _ppid=$(awk '{print $4}' "${_pd}stat" 2>/dev/null)
            [ "$_ppid" = "1" ] && continue
            count=$((count + 1))
        done
    fi
    echo "${count:-0}"
}

block_user() {
    local username=$1
    local reason=$2
    log_message "BLOCKING user $username: $reason"
    usermod -L "$username" 2>/dev/null
    pkill -u "$username" 2>/dev/null
    pkill -f "dropbear.*$username" 2>/dev/null
    for pid in $(ps aux | grep "$username" | grep -v grep | awk '{print $2}'); do
        kill -9 $pid 2>/dev/null || true
    done
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - BLOCKED: $reason" >> "$BAN_DB/$username"
    logger -t "moded" "User $username BLOCKED: $reason"
}

unblock_user() {
    local username=$1
    log_message "UNBLOCKING user $username"
    usermod -U "$username" 2>/dev/null
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - UNBLOCKED" >> "$BAN_DB/$username"
}

monitor_connections() {
    local username=$1
    local limit_file="$USER_DB/$username"
    if [ ! -f "$limit_file" ]; then return; fi
    local conn_limit=$(grep "Conn_Limit:" "$limit_file" | cut -d' ' -f2)
    conn_limit=${conn_limit:-2}
    local current_conn=$(get_connection_count "$username")
    echo "$current_conn" > "$CONN_DB/$username"
    local is_locked=$(passwd -S "$username" 2>/dev/null | grep -q "L" && echo "yes" || echo "no")
    if [ "$current_conn" -gt "$conn_limit" ]; then
        if [ "$is_locked" = "no" ]; then
            block_user "$username" "Exceeded connection limit ($current_conn/$conn_limit)"
        fi
        return 1
    else
        if [ "$is_locked" = "yes" ] && [ -f "$BAN_DB/$username" ]; then
            if grep -q "BLOCKED: Exceeded" "$BAN_DB/$username" 2>/dev/null; then
                unblock_user "$username"
            fi
        fi
    fi
    return 0
}

log_message "REALTIME Connection Monitor started"
while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            if [ -f "$user_file" ]; then
                username=$(basename "$user_file")
                monitor_connections "$username"
            fi
        done
    fi
    sleep 2
done
EOF
    chmod +x /usr/local/bin/moded-connmon

    cat > /etc/systemd/system/moded-connmon.service <<EOF
[Unit]
Description=MODED-V1 REALTIME Connection Monitor with Auto-Ban
After=network.target dropbear.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/moded-connmon
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
EOF
}

# ============================================================================
# TRAFFIC MONITOR
# ============================================================================
setup_traffic_monitor() {
    cat > /usr/local/bin/moded-traffic <<'EOF'
#!/bin/bash
TRAFFIC_DB="/etc/moded/traffic"
USER_DB="/etc/moded/users"
mkdir -p $TRAFFIC_DB

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/moded-traffic.log
}

get_user_traffic() {
    local username="$1"
    local total_bytes=0
    if ! id "$username" &>/dev/null 2>&1; then echo "0"; return; fi
    local pids=$(pgrep -u "$username" 2>/dev/null || echo "")
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if [ -d "/proc/$pid" ]; then
                if [ -f "/proc/$pid/io" ]; then
                    local read_bytes=$(grep "read_bytes" "/proc/$pid/io" 2>/dev/null | awk '{print $2}')
                    local write_bytes=$(grep "write_bytes" "/proc/$pid/io" 2>/dev/null | awk '{print $2}')
                    total_bytes=$((total_bytes + read_bytes + write_bytes))
                fi
            fi
        done
    fi
    echo $((total_bytes / 1048576))
}

log_message "REALTIME Traffic monitor started"
while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            if [ -f "$user_file" ]; then
                username=$(basename "$user_file")
                traffic_mb=$(get_user_traffic "$username")
                echo "$traffic_mb" > "$TRAFFIC_DB/$username"
            fi
        done
    fi
    sleep 10
done
EOF
    chmod +x /usr/local/bin/moded-traffic

    cat > /etc/systemd/system/moded-traffic.service <<EOF
[Unit]
Description=MODED-V1 REALTIME Traffic Monitor
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/moded-traffic
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}

# ============================================================================
# SPEED OPTIMIZER
# ============================================================================
setup_speed_optimizer() {
    cat > /usr/local/bin/moded-speed <<'EOF'
#!/bin/bash
RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';NC='\033[0m'

optimize_network() {
    echo -e "${YELLOW}⚡ Optimizing network for maximum speed...${NC}"
    sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728" >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728" >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=5000 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_time=60 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_intvl=10 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_probes=3 >/dev/null 2>&1
    echo -e "${GREEN}✅ Network optimized!${NC}"
}

optimize_cpu() {
    echo -e "${YELLOW}⚡ Optimizing CPU performance...${NC}"
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu" 2>/dev/null || true
    done
    echo -e "${GREEN}✅ CPU optimized!${NC}"
}

optimize_ram() {
    echo -e "${YELLOW}⚡ Optimizing RAM...${NC}"
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    sysctl -w vm.vfs_cache_pressure=50 >/dev/null 2>&1
    sysctl -w vm.swappiness=10 >/dev/null 2>&1
    echo -e "${GREEN}✅ RAM optimized!${NC}"
}

clean_junk() {
    echo -e "${YELLOW}🧹 Cleaning junk files...${NC}"
    apt clean 2>/dev/null
    apt autoclean 2>/dev/null
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
    journalctl --vacuum-time=3d 2>/dev/null || true
    echo -e "${GREEN}✅ Junk files cleaned!${NC}"
}

case "$1" in
    manual) optimize_network; optimize_cpu; optimize_ram; clean_junk ;;
    clean) clean_junk ;;
    *) echo "Usage: moded-speed {manual|clean}"; exit 1 ;;
esac
EOF
    chmod +x /usr/local/bin/moded-speed
}

# ============================================================================
# AUTO REMOVER
# ============================================================================
setup_auto_remover() {
    cat > /usr/local/bin/moded-cleaner <<'EOF'
#!/bin/bash
USER_DB="/etc/moded/users"
DELETED_DB="/etc/moded/deleted"
TRAFFIC_DB="/etc/moded/traffic"
BANDWIDTH_DIR="/etc/moded/bandwidth"
mkdir -p $DELETED_DB

while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            if [ -f "$user_file" ]; then
                username=$(basename "$user_file")
                expire_date=$(grep "Expire:" "$user_file" | cut -d' ' -f2)
                if [ ! -z "$expire_date" ]; then
                    current_date=$(date +%Y-%m-%d)
                    if [[ "$current_date" > "$expire_date" ]] || [ "$current_date" = "$expire_date" ]; then
                        cp "$user_file" "$DELETED_DB/${username}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
                        pkill -u "$username" 2>/dev/null || true
                        /usr/local/bin/moded-bandwidth remove "$username" 2>/dev/null || true
                        rm -f "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null
                        rm -f "$BANDWIDTH_DIR/pidtrack/${username}__"*.last 2>/dev/null
                        userdel -r "$username" 2>/dev/null || true
                        rm -f "$user_file"
                        rm -f "$TRAFFIC_DB/$username"
                        rm -f "/etc/moded/user_messages/$username" 2>/dev/null
                        echo "Deleted: $(date +%Y-%m-%d %H:%M:%S)" >> "/etc/moded/deleted_users.log"
                    fi
                fi
            fi
        done
    fi
    sleep 3600
done
EOF
    chmod +x /usr/local/bin/moded-cleaner

    cat > /etc/systemd/system/moded-cleaner.service <<EOF
[Unit]
Description=MODED-V1 Auto Remover
[Service]
Type=simple
ExecStart=/usr/local/bin/moded-cleaner
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}

# ============================================================================
# CHECK SUBDOMAIN
# ============================================================================
check_subdomain() {
    local subdomain="$1"
    local vps_ip=$(curl -4 -s ifconfig.me 2>/dev/null || echo "")
    echo -e "${YELLOW}🔍 Checking if subdomain points to this VPS (IPv4)...${NC}"
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}  Subdomain: $subdomain${NC}"
    echo -e "${CYAN}║${WHITE}  VPS IPv4 : $vps_ip${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    if [ -z "$vps_ip" ]; then
        echo -e "${YELLOW}⚠️  Could not detect VPS IPv4, continuing anyway...${NC}"
        return 0
    fi
    local resolved_ip=$(dig +short -4 "$subdomain" 2>/dev/null | head -1)
    if [ -z "$resolved_ip" ]; then
        echo -e "${YELLOW}⚠️  Could not resolve subdomain, continuing anyway...${NC}"
        echo -e "${YELLOW}⚠️  Make sure your subdomain points to: $vps_ip${NC}"
        return 0
    fi
    if [ "$resolved_ip" = "$vps_ip" ]; then
        echo -e "${GREEN}✅ Subdomain correctly points to this VPS!${NC}"
        return 0
    else
        echo -e "${RED}❌ Subdomain points to $resolved_ip, but VPS IP is $vps_ip${NC}"
        echo -e "${YELLOW}⚠️  Please update your DNS record and try again${NC}"
        read -p "Continue anyway? (y/n): " continue_anyway
        if [ "$continue_anyway" != "y" ]; then
            exit 1
        fi
    fi
}

# ============================================================================
# C: EDNS PROXY (ILIOBORESHA KUTOKA moded.sh)
# ============================================================================
create_c_edns_proxy() {
    echo -e "${YELLOW}📝 Compiling C EDNS Proxy...${NC}"
    
    cat > /tmp/edns.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <stdint.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/epoll.h>

#define LISTEN_PORT 53
#define SLOWDNS_PORT 5300
#define BUFFER_SIZE 8192
#define UPSTREAM_POOL 128
#define SOCKET_TIMEOUT 1.0
#define MAX_EVENTS 8192
#define REQ_TABLE_SIZE 131072
#define EXT_EDNS 1800
#define INT_EDNS 50000

typedef struct {
    int fd;
    int busy;
    time_t last_used;
} upstream_t;

typedef struct req_entry {
    uint16_t req_id;
    int upstream_idx;
    double timestamp;
    struct sockaddr_in client_addr;
    socklen_t addr_len;
    struct req_entry *next;
} req_entry_t;

static upstream_t upstreams[UPSTREAM_POOL];
static req_entry_t *req_table[REQ_TABLE_SIZE];
static int sock, epoll_fd;
static volatile sig_atomic_t shutdown_flag = 0;

double now() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

uint16_t get_txid(unsigned char *b) {
    return ((uint16_t)b[0] << 8) | b[1];
}

uint32_t req_hash(uint16_t id) {
    return id & (REQ_TABLE_SIZE - 1);
}

int patch_edns(unsigned char *buf, int len, int size) {
    if (len < 12) return len;
    int off = 12;
    int qd = (buf[4] << 8) | buf[5];
    for (int i=0;i<qd;i++) {
        while (buf[off]) off++;
        off += 5;
    }
    int ar = (buf[10] << 8) | buf[11];
    for (int i=0;i<ar;i++) {
        if (buf[off]==0 && off+4<len && ((buf[off+1]<<8)|buf[off+2])==41) {
            buf[off+3]=size>>8;
            buf[off+4]=size&255;
            return len;
        }
        off++;
    }
    return len;
}

int get_upstream() {
    time_t t = time(NULL);
    for (int i=0;i<UPSTREAM_POOL;i++) {
        if (upstreams[i].busy && t - upstreams[i].last_used > 2)
            upstreams[i].busy = 0;
        if (!upstreams[i].busy) {
            upstreams[i].busy = 1;
            upstreams[i].last_used = t;
            return i;
        }
    }
    return -1;
}

void release_upstream(int i) {
    if (i>=0 && i<UPSTREAM_POOL) upstreams[i].busy = 0;
}

void insert_req(int uidx, unsigned char *buf, struct sockaddr_in *c, socklen_t l) {
    req_entry_t *e = calloc(1,sizeof(*e));
    e->upstream_idx = uidx;
    e->req_id = get_txid(buf);
    e->timestamp = now();
    e->client_addr = *c;
    e->addr_len = l;
    uint32_t h = req_hash(e->req_id);
    e->next = req_table[h];
    req_table[h] = e;
}

req_entry_t *find_req(uint16_t id) {
    uint32_t h = req_hash(id);
    for (req_entry_t *e=req_table[h]; e; e=e->next)
        if (e->req_id == id) return e;
    return NULL;
}

void delete_req(req_entry_t *e) {
    release_upstream(e->upstream_idx);
    uint32_t h = req_hash(e->req_id);
    req_entry_t **pp=&req_table[h];
    while(*pp){
        if(*pp==e){ *pp=e->next; free(e); return; }
        pp=&(*pp)->next;
    }
}

void cleanup_expired() {
    double t=now();
    for(int i=0;i<REQ_TABLE_SIZE;i++){
        req_entry_t **pp=&req_table[i];
        while(*pp){
            if(t-(*pp)->timestamp > SOCKET_TIMEOUT){
                req_entry_t *o=*pp;
                release_upstream(o->upstream_idx);
                *pp=o->next;
                free(o);
            } else pp=&(*pp)->next;
        }
    }
}

void sig_handler(int s){ shutdown_flag=1; }

int main() {
    signal(SIGINT,sig_handler);
    signal(SIGTERM,sig_handler);

    sock=socket(AF_INET,SOCK_DGRAM,0);
    int bufsize = 4 * 1024 * 1024;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF, &bufsize, sizeof(bufsize));
    setsockopt(sock, SOL_SOCKET, SO_SNDBUF, &bufsize, sizeof(bufsize));
    int opt=1;
    setsockopt(sock,SOL_SOCKET,SO_REUSEADDR,&opt,sizeof(opt));
    setsockopt(sock,SOL_SOCKET,SO_REUSEPORT,&opt,sizeof(opt));
    fcntl(sock,F_SETFL,O_NONBLOCK);

    struct sockaddr_in a={0};
    a.sin_family=AF_INET; a.sin_port=htons(LISTEN_PORT);
    a.sin_addr.s_addr=INADDR_ANY;
    bind(sock,(void*)&a,sizeof(a));

    struct sockaddr_in slow={0};
    slow.sin_family=AF_INET; slow.sin_port=htons(SLOWDNS_PORT);
    inet_pton(AF_INET,"127.0.0.1",&slow.sin_addr);

    epoll_fd=epoll_create1(0);
    struct epoll_event ev={.events=EPOLLIN,.data.fd=sock};
    epoll_ctl(epoll_fd,EPOLL_CTL_ADD,sock,&ev);

    for(int i=0;i<UPSTREAM_POOL;i++){
        upstreams[i].fd=socket(AF_INET,SOCK_DGRAM,0);
        int bufsize = 4 * 1024 * 1024;
        setsockopt(upstreams[i].fd, SOL_SOCKET, SO_RCVBUF, &bufsize, sizeof(bufsize));
        setsockopt(upstreams[i].fd, SOL_SOCKET, SO_SNDBUF, &bufsize, sizeof(bufsize));
        fcntl(upstreams[i].fd,F_SETFL,O_NONBLOCK);
        struct epoll_event ue={.events=EPOLLIN,.data.fd=upstreams[i].fd};
        epoll_ctl(epoll_fd,EPOLL_CTL_ADD,upstreams[i].fd,&ue);
    }

    struct epoll_event events[MAX_EVENTS];

    while(!shutdown_flag){
        cleanup_expired();
        int n=epoll_wait(epoll_fd,events,MAX_EVENTS,10);
        for(int i=0;i<n;i++){
            int fd=events[i].data.fd;
            if(fd==sock){
                unsigned char buf[BUFFER_SIZE];
                struct sockaddr_in c; socklen_t l=sizeof(c);
                int len=recvfrom(sock,buf,sizeof(buf),0,(void*)&c,&l);
                if(len>0){
                    patch_edns(buf,len,INT_EDNS);
                    int u=get_upstream();
                    if(u>=0){
                        insert_req(u,buf,&c,l);
                        sendto(upstreams[u].fd,buf,len,0,(void*)&slow,sizeof(slow));
                    }
                }
            } else {
                unsigned char buf[BUFFER_SIZE];
                int len=recv(fd,buf,sizeof(buf),0);
                if(len>0){
                    uint16_t id=get_txid(buf);
                    req_entry_t *e=find_req(id);
                    if(e){
                        patch_edns(buf,len,EXT_EDNS);
                        sendto(sock,buf,len,0,(void*)&e->client_addr,e->addr_len);
                        delete_req(e);
                    }
                }
            }
        }
    }
    return 0;
}
EOF

    gcc -O3 -march=native -flto -funroll-loops -fomit-frame-pointer -pipe /tmp/edns.c -o /usr/local/bin/moded-edns-proxy 2>/dev/null
    rm -f /tmp/edns.c
    
    if [ -f /usr/local/bin/moded-edns-proxy ]; then
        chmod +x /usr/local/bin/moded-edns-proxy
        cat > /etc/systemd/system/moded-edns-proxy.service <<EOF
[Unit]
Description=MODED-V1 EDNS Proxy for SlowDNS
After=moded-slowdns.service
[Service]
Type=simple
ExecStart=/usr/local/bin/moded-edns-proxy
Restart=always
RestartSec=3
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C EDNS Proxy compiled${NC}"
    else
        echo -e "${RED}❌ EDNS Proxy compilation failed${NC}"
    fi
}

# ============================================================================
# INSTALL DNSTT SERVER
# ============================================================================
install_dnstt() {
    echo -e "${YELLOW}📥 Installing DNSTT Server...${NC}"
    
    mkdir -p /etc/moded/dnstt
    
    if ! curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null; then
        curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server 2>/dev/null || {
            echo -e "${RED}❌ Failed to download dnstt-server${NC}"
            exit 1
        }
    fi
    chmod +x /usr/local/bin/dnstt-server
    
    # Generate keys
    cd /etc/moded/dnstt
    /usr/local/bin/dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub 2>/dev/null || {
        # Use static keys if generation fails
        echo "7f207e92ab7cb365aad1966b62d2cfbd3f450fe8e523a38ffc7ecfbcec315693" > server.key
        echo "40aa057fcb2574e1e9223ea46457f9fdf9d60a2a1c23da87602202d93b41aa04" > server.pub
    }
    chmod 600 server.key
    chmod 644 server.pub
    cd ~
    
    # Create service
    cat > /etc/systemd/system/moded-slowdns.service <<EOF
[Unit]
Description=MODED-V1 SlowDNS Server
After=network.target dropbear.service
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :${SLOWDNS_PORT} -mtu 1800 -privkey-file /etc/moded/dnstt/server.key ${TDOMAIN} 127.0.0.1:${DROPBEAR_PORT}
Restart=always
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✅ DNSTT Server installed${NC}"
}

# ============================================================================
# USER MANAGEMENT SCRIPT
# ============================================================================
create_user_script() {
    cat > /usr/local/bin/moded-user <<'EOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
WHITE='\033[1;37m';BOLD='\033[1m';MAGENTA='\033[1;35m';NC='\033[0m'

UD="/etc/moded/users"
TD="/etc/moded/traffic"
CD="/etc/moded/connections"
DD="/etc/moded/deleted"
BD="/etc/moded/banned"
BANDWIDTH_DIR="/etc/moded/bandwidth"
mkdir -p $UD $TD $CD $DD $BD $BANDWIDTH_DIR

user_exists_in_system() { id "$1" &>/dev/null 2>&1; }
get_realtime_traffic() {
    local username="$1"
    if [ -f "$TD/$username" ]; then cat "$TD/$username" 2>/dev/null || echo "0"; else echo "0"; fi
}
get_bandwidth_usage() {
    local username="$1"
    local bw_file="$BANDWIDTH_DIR/${username}.usage"
    if [ -f "$bw_file" ]; then
        local total_bytes=$(cat "$bw_file" 2>/dev/null || echo 0)
        echo "scale=2; $total_bytes / 1073741824" | bc 2>/dev/null || echo "0.00"
    else
        echo "0.00"
    fi
}
get_user_logins() {
    local username="$1"
    if [ -f "$CD/$username" ]; then cat "$CD/$username" 2>/dev/null || echo "0"; else echo "0"; fi
}

add_user() {
    clear
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}              CREATE USER (DROPBEAR)                           ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"Password: "$NC)" password
    read -p "$(echo -e $GREEN"Expire days: "$NC)" days
    read -p "$(echo -e $GREEN"Connection limit (1-10, default 2): "$NC)" conn_limit
    conn_limit=${conn_limit:-2}
    read -p "$(echo -e $GREEN"Bandwidth limit in GB (0=unlimited) [0]: "$NC)" bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if id "$username" &>/dev/null; then echo -e "${RED}User already exists!${NC}"; return; fi
    useradd -m -s /bin/false "$username"
    echo "$username:$password" | chpasswd
    expire_date=$(date -d "+$days days" +"%Y-%m-%d")
    chage -E "$expire_date" "$username"
    cat > $UD/$username <<INFO
Username: $username
Password: $password
Expire: $expire_date
Conn_Limit: $conn_limit
Bandwidth_GB: $bandwidth_gb
Created: $(date +"%Y-%m-%d %H:%M:%S")
INFO
    echo "0" > $TD/$username
    echo "0" > $CD/$username
    echo "0" > "$BANDWIDTH_DIR/${username}.usage"
    /usr/local/bin/moded-bandwidth add "$username" 2>/dev/null || true
    /usr/local/bin/moded-force-user-message "$username" 2>/dev/null
    SERVER=$(cat /etc/moded/subdomain 2>/dev/null || echo "?")
    PUBKEY=$(cat /etc/moded/dnstt/server.pub 2>/dev/null || echo "Not generated")
    local bw_disp="Unlimited"; [ "$bandwidth_gb" != "0" ] && bw_disp="${bandwidth_gb} GB"
    clear
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}                  USER DETAILS                                   ${GREEN}║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Username  :${CYAN} $username${NC}"
    echo -e "${GREEN}║${WHITE}  Password  :${CYAN} $password${NC}"
    echo -e "${GREEN}║${WHITE}  Server    :${CYAN} $SERVER${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key:${CYAN} $PUBKEY${NC}"
    echo -e "${GREEN}║${WHITE}  Expire    :${CYAN} $expire_date${NC}"
    echo -e "${GREEN}║${WHITE}  Max Login :${CYAN} $conn_limit connection(s)${NC}"
    echo -e "${GREEN}║${WHITE}  Bandwidth :${CYAN} $bw_disp${NC}"
    echo -e "${GREEN}║${WHITE}  SSH Port  :${CYAN} $DROPBEAR_PORT (Dropbear)${NC}"
    echo -e "${GREEN}║${WHITE}  SlowDNS   :${CYAN} UDP:$SLOWDNS_PORT${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
}

list_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                     ACTIVE USERS (DROPBEAR)                     ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    if [ -z "$(ls -A $UD 2>/dev/null)" ]; then
        echo -e "${CYAN}║${RED}  No users found${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
        return
    fi
    printf "%-12s %-10s %-10s %-8s %-14s %-8s\n" "USERNAME" "EXPIRE" "LOGIN" "LIMIT" "BANDWIDTH" "STATUS"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    TOTAL_USERS=0; ONLINE_COUNT=0; BLOCKED_COUNT=0
    for user in $UD/*; do
        [ ! -f "$user" ] && continue
        u=$(basename "$user")
        if ! user_exists_in_system "$u"; then
            rm -f "$user" "$TD/$u" "$CD/$u" "$BANDWIDTH_DIR/${u}.usage"
            continue
        fi
        ex=$(grep "Expire:" "$user" | cut -d' ' -f2)
        limit=$(grep "Conn_Limit:" "$user" | cut -d' ' -f2); limit=${limit:-2}
        bw_limit=$(grep "Bandwidth_GB:" "$user" 2>/dev/null | awk '{print $2}'); bw_limit=${bw_limit:-0}
        bw_usage=$(get_bandwidth_usage "$u")
        current_conn=$(get_user_logins "$u")
        [ "$current_conn" -gt 0 ] && ONLINE_COUNT=$((ONLINE_COUNT + 1))
        if [ "$current_conn" -ge "$limit" ]; then login_display="${RED}$current_conn${NC}"
        else login_display="${GREEN}$current_conn${NC}"; fi
        if [ "$bw_limit" != "0" ] && [ -n "$bw_limit" ]; then
            bw_percent=$(echo "scale=1; ($bw_usage / $bw_limit) * 100" | bc 2>/dev/null || echo "0")
            if [ "$(echo "$bw_percent >= 100" | bc 2>/dev/null)" = "1" ]; then
                bw_display="${RED}${bw_usage}/${bw_limit}GB${NC}"
            elif [ "$(echo "$bw_percent > 80" | bc 2>/dev/null)" = "1" ]; then
                bw_display="${YELLOW}${bw_usage}/${bw_limit}GB${NC}"
            else
                bw_display="${GREEN}${bw_usage}/${bw_limit}GB${NC}"
            fi
        else
            bw_display="${GREEN}${bw_usage}GB/∞${NC}"
        fi
        if passwd -S "$u" 2>/dev/null | grep -q "L"; then
            status="${RED}BLOCKED${NC}"; BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
        elif [ "$current_conn" -gt 0 ]; then status="${GREEN}ONLINE${NC}"
        else status="${YELLOW}OFFLINE${NC}"; fi
        days_left=$(( ($(date -d "$ex" +%s) - $(date +%s)) / 86400 ))
        [ $days_left -le 3 ] && ex="${RED}$ex${NC}" || [ $days_left -le 7 ] && ex="${YELLOW}$ex${NC}"
        printf "%-12s %-10b %-10b %-8s %-14b %-8b\n" "$u" "$ex" "$login_display" "$limit" "$bw_display" "$status"
        TOTAL_USERS=$((TOTAL_USERS + 1))
    done
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "Total: ${GREEN}$TOTAL_USERS${NC} | Online: ${CYAN}$ONLINE_COUNT${NC} | Blocked: ${RED}$BLOCKED_COUNT${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
}

show_user_details() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    if [ ! -f "$UD/$username" ]; then echo -e "${RED}User not found!${NC}"; return; fi
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                  USER DETAILS (DROPBEAR)                       ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    while IFS= read -r line; do echo -e "${CYAN}║${WHITE}  $line${NC}"; done < "$UD/$username"
    current_conn=$(get_user_logins "$username")
    limit=$(grep "Conn_Limit:" "$UD/$username" | cut -d' ' -f2)
    echo -e "${CYAN}║${WHITE}  Current Connections: ${YELLOW}$current_conn/$limit${NC}"
    traffic_used=$(get_realtime_traffic "$username")
    echo -e "${CYAN}║${WHITE}  Traffic Used: ${GREEN}${traffic_used} MB${NC}"
    bw_usage=$(get_bandwidth_usage "$username")
    bw_limit=$(grep "Bandwidth_GB:" "$UD/$username" 2>/dev/null | awk '{print $2}'); bw_limit=${bw_limit:-0}
    if [ "$bw_limit" != "0" ]; then
        echo -e "${CYAN}║${WHITE}  Bandwidth: ${GREEN}${bw_usage} GB${NC} / ${YELLOW}${bw_limit} GB${NC}"
    else
        echo -e "${CYAN}║${WHITE}  Bandwidth: ${GREEN}${bw_usage} GB${NC} / ${YELLOW}Unlimited${NC}"
    fi
    if passwd -S "$username" 2>/dev/null | grep -q "L"; then
        echo -e "${CYAN}║${WHITE}  Account Status: ${RED}BLOCKED${NC}"
    else
        echo -e "${CYAN}║${WHITE}  Account Status: ${GREEN}ACTIVE${NC}"
    fi
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
}

renew_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"Additional days: "$NC)" days
    [ ! -f "$UD/$username" ] && { echo -e "${RED}Not found!${NC}"; return; }
    current_expire=$(grep "Expire:" "$UD/$username" | cut -d' ' -f2)
    new_expire=$(date -d "$current_expire +$days days" +"%Y-%m-%d")
    sed -i "s/Expire: .*/Expire: $new_expire/" "$UD/$username"
    chage -E "$new_expire" "$username"
    if passwd -S "$username" 2>/dev/null | grep -q "L"; then
        usermod -U "$username" 2>/dev/null
    fi
    /usr/local/bin/moded-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ Renewed until $new_expire${NC}"
}

set_login_limit() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"New connection limit: "$NC)" new_limit
    [ ! -f "$UD/$username" ] && { echo -e "${RED}Not found!${NC}"; return; }
    grep -q "Conn_Limit:" "$UD/$username" \
        && sed -i "s/Conn_Limit: .*/Conn_Limit: $new_limit/" "$UD/$username" \
        || echo "Conn_Limit: $new_limit" >> "$UD/$username"
    /usr/local/bin/moded-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ Login limit updated${NC}"
}

set_bandwidth_limit() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    [ ! -f "$UD/$username" ] && { echo -e "${RED}Not found!${NC}"; return; }
    current_bw=$(grep "Bandwidth_GB:" "$UD/$username" 2>/dev/null | awk '{print $2}')
    echo -e "${CYAN}Current: ${YELLOW}${current_bw:-Not set} GB${NC}"
    read -p "$(echo -e $GREEN"New limit (0=unlimited): "$NC)" new_bw
    [[ ! "$new_bw" =~ ^[0-9]+\.?[0-9]*$ ]] && { echo -e "${RED}Invalid!${NC}"; return; }
    grep -q "Bandwidth_GB:" "$UD/$username" \
        && sed -i "s/Bandwidth_GB: .*/Bandwidth_GB: $new_bw/" "$UD/$username" \
        || echo "Bandwidth_GB: $new_bw" >> "$UD/$username"
    [ "$new_bw" = "0" ] && usermod -U "$username" 2>/dev/null
    /usr/local/bin/moded-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth updated${NC}"
}

reset_bandwidth() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    [ ! -f "$UD/$username" ] && { echo -e "${RED}Not found!${NC}"; return; }
    echo "0" > "$BANDWIDTH_DIR/${username}.usage"
    rm -rf "$BANDWIDTH_DIR/pidtrack/${username}" 2>/dev/null
    usermod -U "$username" 2>/dev/null
    /usr/local/bin/moded-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth reset${NC}"
}

lock_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    usermod -L "$u" 2>/dev/null
    pkill -u "$u" 2>/dev/null
    echo "$(date) - LOCKED" >> "$BD/$u"
    echo -e "${GREEN}✅ Locked${NC}"
}

unlock_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    usermod -U "$u" 2>/dev/null
    echo "$(date) - UNLOCKED" >> "$BD/$u"
    /usr/local/bin/moded-force-user-message "$u" 2>/dev/null
    echo -e "${GREEN}✅ Unlocked${NC}"
}

delete_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    [ ! -f "$UD/$u" ] && { echo -e "${RED}Not found!${NC}"; return; }
    cp "$UD/$u" "$DD/${u}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null
    /usr/local/bin/moded-bandwidth remove "$u" 2>/dev/null || true
    pkill -u "$u" 2>/dev/null || true
    userdel -r "$u" 2>/dev/null
    rm -f "$UD/$u" "$TD/$u" "$CD/$u" "$BD/$u" "$BANDWIDTH_DIR/${u}.usage"
    rm -rf "$BANDWIDTH_DIR/pidtrack/${u}" 2>/dev/null
    rm -f "/etc/moded/user_messages/$u" 2>/dev/null
    echo -e "${GREEN}✅ Deleted${NC}"
}

view_ban_history() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                      BAN HISTORY                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    if [ -z "$(ls -A $BD 2>/dev/null)" ]; then
        echo -e "${YELLOW}No ban history found${NC}"
    else
        for ban_file in $BD/*; do
            [ -f "$ban_file" ] || continue
            username=$(basename "$ban_file")
            echo -e "${CYAN}User: $username${NC}"
            echo "────────────────"
            cat "$ban_file"
            echo ""
        done
    fi
    read -p "Press Enter to continue..."
}

test_message() {
    read -p "$(echo -e $GREEN"Username: "$NC)" uname
    if [ -f "/etc/moded/user_messages/$uname" ]; then
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${YELLOW}       USER MESSAGE PREVIEW FOR $uname (COLORFUL)         ${CYAN}║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
        cat "/etc/moded/user_messages/$uname"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${RED}No message found!${NC}"
    fi
    read -p "Press Enter to continue..."
}

refresh_all_messages() {
    echo -e "${YELLOW}Refreshing colorful messages...${NC}"
    for user in "$UD"/*; do
        [ -f "$user" ] && /usr/local/bin/moded-force-user-message "$(basename "$user")" 2>/dev/null
    done
    echo -e "${GREEN}✅ Messages refreshed!${NC}"
}

case $1 in
    add) add_user ;;
    list) list_users ;;
    details) show_user_details ;;
    renew) renew_user ;;
    setlimit) set_login_limit ;;
    setbw) set_bandwidth_limit ;;
    resetbw) reset_bandwidth ;;
    deleted) ls "$DD/" 2>/dev/null || echo "No deleted users" ;;
    lock) lock_user ;;
    unlock) unlock_user ;;
    del) delete_user ;;
    banhistory) view_ban_history ;;
    testmsg) test_message ;;
    refreshmsg) refresh_all_messages ;;
    *) echo "Usage: moded-user {add|list|details|renew|setlimit|setbw|resetbw|deleted|lock|unlock|del|banhistory|testmsg|refreshmsg}" ;;
esac
EOF
    chmod +x /usr/local/bin/moded-user
}

# ============================================================================
# MAIN MENU (DASHBOARD)
# ============================================================================
create_main_menu() {
    cat > /usr/local/bin/moded <<'EOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
PURPLE='\033[0;35m';WHITE='\033[1;37m';BOLD='\033[1m';MAGENTA='\033[1;35m';NC='\033[0m'

if [ -f /tmp/moded-running ]; then exit 0; fi
touch /tmp/moded-running
trap 'rm -f /tmp/moded-running' EXIT

show_dashboard() {
    clear
    IP=$(cat /etc/moded/cached_ip 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    LOC=$(cat /etc/moded/cached_location 2>/dev/null || echo "Unknown")
    ISP=$(cat /etc/moded/cached_isp 2>/dev/null || echo "Unknown")
    RAM=$(free -m | awk '/^Mem:/{print $3"/"$2"MB"}')
    SUB=$(cat /etc/moded/subdomain 2>/dev/null || echo "Not configured")
    LOCATION=$(cat /etc/moded/location 2>/dev/null || echo "South Africa")
    CURRENT_MTU=$(cat /etc/moded/mtu 2>/dev/null || echo "1800")
    
    DNS=$(systemctl is-active moded-slowdns 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    PRX=$(systemctl is-active moded-edns-proxy 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    CONN=$(systemctl is-active moded-connmon 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    BW=$(systemctl is-active moded-bandwidth 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    DROP=$(systemctl is-active dropbear 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    
    TOTAL_USERS=$(ls -1 /etc/moded/users 2>/dev/null | wc -l)
    ONLINE_USERS=$(ps aux | grep "dropbear" | grep -v grep | wc -l)
    BLOCKED_USERS=$(passwd -S $(ls /etc/moded/users 2>/dev/null) 2>/dev/null | grep " L " | wc -l)
    
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}${BOLD}              MODED-V1 - ELITE-X + DROPBEAR          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${GREEN}${BOLD}                   🎨 Colorful Dashboard 🎨             ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${WHITE}  Subdomain :${GREEN} $SUB${NC}"
    echo -e "${MAGENTA}║${WHITE}  IP        :${GREEN} $IP${NC}"
    echo -e "${MAGENTA}║${WHITE}  Location  :${GREEN} $LOC${NC}"
    echo -e "${MAGENTA}║${WHITE}  ISP       :${GREEN} $ISP${NC}"
    echo -e "${MAGENTA}║${WHITE}  RAM       :${GREEN} $RAM${NC}"
    echo -e "${MAGENTA}║${WHITE}  VPS Loc   :${GREEN} $LOCATION (MTU: $CURRENT_MTU)${NC}"
    echo -e "${MAGENTA}║${WHITE}  Services  : DNS:$DNS PRX:$PRX MON:$CONN BW:$BW DROP:$DROP${NC}"
    echo -e "${MAGENTA}║${WHITE}  Dropbear  :${GREEN} Port $DROPBEAR_PORT (SlowDNS Backend)${NC}"
    echo -e "${MAGENTA}║${WHITE}  Real-Time :${GREEN} $TOTAL_USERS users, $ONLINE_USERS online, $BLOCKED_USERS blocked${NC}"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${WHITE}  Version   :${YELLOW} v1 - MODED (Dropbear + ELITE-X)${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main_menu() {
    while true; do
        show_dashboard
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}${BOLD}                         MAIN MENU                              ${CYAN}║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${WHITE}  [1] Create User    [2] List Users     [3] User Details${NC}"
        echo -e "${CYAN}║${WHITE}  [4] Renew User     [5] Set Conn Limit  [6] Set BW Limit${NC}"
        echo -e "${CYAN}║${WHITE}  [7] Reset BW       [8] Lock User       [9] Unlock User${NC}"
        echo -e "${CYAN}║${WHITE}  [10] Delete User   [11] Ban History    [12] Test Message${NC}"
        echo -e "${CYAN}║${WHITE}  [13] Refresh Messages               [14] View Public Key${NC}"
        echo -e "${CYAN}║${WHITE}  [S] ⚙️ Settings     [00] Exit${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch
        
        case $ch in
            1) moded-user add; read -p "Press Enter..." ;;
            2) moded-user list; read -p "Press Enter..." ;;
            3) moded-user details; read -p "Press Enter..." ;;
            4) moded-user renew; read -p "Press Enter..." ;;
            5) moded-user setlimit; read -p "Press Enter..." ;;
            6) moded-user setbw; read -p "Press Enter..." ;;
            7) moded-user resetbw; read -p "Press Enter..." ;;
            8) moded-user lock; read -p "Press Enter..." ;;
            9) moded-user unlock; read -p "Press Enter..." ;;
            10) moded-user del; read -p "Press Enter..." ;;
            11) moded-user banhistory; read -p "Press Enter..." ;;
            12) moded-user testmsg; read -p "Press Enter..." ;;
            13) moded-user refreshmsg; read -p "Press Enter..." ;;
            14)
                echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║${YELLOW}                    PUBLIC KEY                                    ${CYAN}║${NC}"
                echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
                echo -e "${CYAN}║${GREEN}  $(cat /etc/moded/dnstt/server.pub 2>/dev/null || echo "Not found")${NC}"
                echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
                read -p "Press Enter..." ;;
            [Ss])
                clear
                echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║${YELLOW}                      SETTINGS                                  ${CYAN}║${NC}"
                echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
                echo -e "${CYAN}║${WHITE}  [1] Restart All Services${NC}"
                echo -e "${CYAN}║${WHITE}  [2] Reboot VPS${NC}"
                echo -e "${CYAN}║${WHITE}  [3] Uninstall${NC}"
                echo -e "${CYAN}║${WHITE}  [4] Manual Speed Optimization${NC}"
                echo -e "${CYAN}║${WHITE}  [0] Back${NC}"
                echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
                read -p "$(echo -e $GREEN"Option: "$NC)" sc
                case $sc in
                    1) systemctl restart moded-slowdns moded-edns-proxy moded-connmon moded-bandwidth dropbear 2>/dev/null; echo -e "${GREEN}✅ Restarted${NC}"; read -p "Enter..." ;;
                    2) read -p "Reboot? (y/n): " c; [ "$c" = "y" ] && reboot ;;
                    3)
                        read -p "Uninstall? (YES): " c
                        [ "$c" = "YES" ] && {
                            for u in /etc/moded/users/*; do [ -f "$u" ] && userdel -r "$(basename "$u")" 2>/dev/null; done
                            systemctl stop moded-slowdns moded-edns-proxy moded-connmon moded-bandwidth dropbear 2>/dev/null
                            rm -rf /etc/moded /etc/systemd/system/moded-* /usr/local/bin/moded*
                            sed -i '/moded/d' ~/.bashrc
                            echo -e "${GREEN}✅ Uninstalled${NC}"
                            rm -f /tmp/moded-running
                            exit 0
                        }
                        read -p "Enter..." ;;
                    4) moded-speed manual; read -p "Enter..." ;;
                    0) continue ;;
                esac
                ;;
            00|0) rm -f /tmp/moded-running; echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid${NC}"; read -p "Enter..." ;;
        esac
    done
}

main_menu
EOF
    chmod +x /usr/local/bin/moded
}

# ============================================================================
# MAIN INSTALLATION
# ============================================================================
main_install() {
    show_banner
    
    # Activation
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}                    ACTIVATION REQUIRED                          ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${WHITE}Available Keys:${NC}"
    echo -e "${GREEN}  Activation Key: Whtsapp 0765-556-877${NC}"
    echo ""
    read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT
    
    mkdir -p /etc/moded
    if ! activate_script "$ACTIVATION_INPUT"; then
        echo -e "${RED}❌ Invalid activation key!${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Activation successful!${NC}"
    sleep 2
    
    set_timezone
    
    # Get subdomain
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}                  ENTER YOUR SUBDOMAIN                          ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${WHITE}  Example: ns-ex.elitex.com                                 ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "$(echo -e $GREEN"Subdomain: "$NC)" TDOMAIN
    echo "$TDOMAIN" > /etc/moded/subdomain
    
    check_subdomain "$TDOMAIN"
    
    # Location selection
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}           NETWORK LOCATION OPTIMIZATION                          ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${WHITE}  Select your VPS location:                                    ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${GREEN}  1. South Africa (MTU 1800)                                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${CYAN}  2. USA (MTU 1500)                                              ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${BLUE}  3. Europe (MTU 1500)                                           ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${PURPLE}  4. Asia (MTU 1400)                                             ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${YELLOW}  5. Custom MTU                                                  ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Select location [1-5] [default: 1]: "$NC)" LOCATION_CHOICE
    LOCATION_CHOICE=${LOCATION_CHOICE:-1}
    
    case $LOCATION_CHOICE in
        2) SELECTED_LOCATION="USA"; MTU=1500; echo -e "${CYAN}✅ USA selected${NC}" ;;
        3) SELECTED_LOCATION="Europe"; MTU=1500; echo -e "${BLUE}✅ Europe selected${NC}" ;;
        4) SELECTED_LOCATION="Asia"; MTU=1400; echo -e "${PURPLE}✅ Asia selected${NC}" ;;
        5) SELECTED_LOCATION="Custom"; read -p "Enter MTU (1000-5000): " MTU
           [[ ! "$MTU" =~ ^[0-9]+$ ]] || [ "$MTU" -lt 1000 ] || [ "$MTU" -gt 5000 ] && MTU=1800
           echo -e "${YELLOW}✅ Custom MTU: $MTU${NC}" ;;
        *) SELECTED_LOCATION="South Africa"; MTU=1800; echo -e "${GREEN}✅ South Africa selected${NC}" ;;
    esac
    echo "$SELECTED_LOCATION" > /etc/moded/location
    echo "$MTU" > /etc/moded/mtu
    
    # Install dependencies
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    apt update -y
    apt install -y curl wget jq nano iptables iptables-persistent ethtool dnsutils net-tools iproute2 bc build-essential gcc dropbear
    
    # Clean previous
    echo -e "${YELLOW}🔄 Cleaning previous...${NC}"
    systemctl stop moded-slowdns moded-edns-proxy moded-connmon moded-bandwidth dropbear 2>/dev/null || true
    rm -rf /etc/moded /etc/systemd/system/moded-* /usr/local/bin/moded* 2>/dev/null || true
    
    # Create directories
    mkdir -p /etc/moded/{users,traffic,deleted,connections,banned,bandwidth/pidtrack,user_messages,dns}
    mkdir -p /etc/moded/dnstt
    
    # Configure Dropbear
    configure_dropbear
    configure_dropbear_banners
    
    # Install DNSTT
    install_dnstt
    
    # Compile EDNS Proxy
    create_c_edns_proxy
    
    # Setup bandwidth, connection, traffic, speed, auto-remover
    setup_bandwidth_manager
    setup_connection_monitor
    setup_traffic_monitor
    setup_speed_optimizer
    setup_auto_remover
    create_c_bandwidth_monitor
    
    # Create user script and menu
    create_user_script
    create_main_menu
    
    # Start services
    systemctl daemon-reload
    systemctl enable moded-slowdns moded-edns-proxy moded-connmon moded-bandwidth dropbear 2>/dev/null || true
    systemctl start moded-slowdns moded-edns-proxy moded-connmon moded-bandwidth dropbear 2>/dev/null || true
    
    # Cache IP
    IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "Unknown")
    echo "$IP" > /etc/moded/cached_ip
    if [ "$IP" != "Unknown" ]; then
        LOCATION_INFO=$(curl -s http://ip-api.com/json/$IP 2>/dev/null)
        echo "$LOCATION_INFO" | jq -r '.city + ", " + .country' 2>/dev/null > /etc/moded/cached_location || echo "Unknown" > /etc/moded/cached_location
        echo "$LOCATION_INFO" | jq -r '.isp' 2>/dev/null > /etc/moded/cached_isp || echo "Unknown" > /etc/moded/cached_isp
    fi
    
    # Auto-login
    cat > /etc/profile.d/moded-dashboard.sh <<'EOF'
#!/bin/bash
if [ -f /usr/local/bin/moded ] && [ -z "$MODED_SHOWN" ]; then
    export MODED_SHOWN=1
    /usr/local/bin/moded
fi
EOF
    chmod +x /etc/profile.d/moded-dashboard.sh
    
    cat >> ~/.bashrc <<'EOF'
if [ -f /usr/local/bin/moded ] && [ -z "$MODED_SHOWN" ]; then
    export MODED_SHOWN=1
    /usr/local/bin/moded
fi
alias menu='moded'
alias mod='moded'
EOF
    
    # Final output
    clear
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}${BOLD}           MODED-V1 INSTALLED SUCCESSFULLY!            ${GREEN}║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Domain      :${CYAN} $TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  Location    :${CYAN} $SELECTED_LOCATION (MTU: $MTU)${NC}"
    echo -e "${GREEN}║${WHITE}  IP          :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  Dropbear    :${CYAN} Port $DROPBEAR_PORT${NC}"
    echo -e "${GREEN}║${WHITE}  SlowDNS     :${CYAN} UDP:$SLOWDNS_PORT${NC}"
    echo -e "${GREEN}║${WHITE}  EDNS Proxy  :${CYAN} UDP:53${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key  :${CYAN} $(cat /etc/moded/dnstt/server.pub 2>/dev/null | head -c 40)...${NC}"
    echo -e "${GREEN}║${WHITE}  Version     :${CYAN} MODED-V1 (Dropbear + ELITE-X)${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  Commands: menu | moded-user | moded-speed${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    show_quote
    
    read -p "Open menu now? (y/n): " open
    [ "$open" = "y" ] && /usr/local/bin/moded
    
    self_destruct
}

# ============================================================================
# EXECUTE
# ============================================================================
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ Run as root${NC}"
    exit 1
fi

main_install

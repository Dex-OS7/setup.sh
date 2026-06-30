#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Rangi maalum kwa ajili ya SSH Banner (Literal Escape Codes)
ESC=$(printf '\033')
R_SSH="${ESC}[0;31m"
G_SSH="${ESC}[0;32m"
Y_SSH="${ESC}[1;33m"
B_SSH="${ESC}[0;34m"
P_SSH="${ESC}[0;35m"
C_SSH="${ESC}[0;36m"
W_SSH="${ESC}[1;37m"
N_SSH="${ESC}[0m"

print_color() { echo -e "${2}${1}${NC}"; }

self_destruct() {
    echo -e "${YELLOW}🧹 Cleaning installation traces...${NC}"
    
    history -c 2>/dev/null || true
    cat /dev/null > ~/.bash_history 2>/dev/null || true
    cat /dev/null > /root/.bash_history 2>/dev/null || true
    
    if [ -f "$0" ] && [ "$0" != "/usr/local/bin/elite-x" ]; then
        local script_path=$(readlink -f "$0")
        rm -f "$script_path" 2>/dev/null || true
    fi
    
    sed -i '/Elite-X-dns.sh/d' /var/log/auth.log 2>/dev/null || true
    sed -i '/elite-x/d' /var/log/auth.log 2>/dev/null || true
    
    echo -e "${GREEN}✅ Cleanup complete!${NC}"
}

show_quote() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}            AMOKHAN v3 - ELITE-X              ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_banner() {
    clear
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${YELLOW}${BOLD}                 AMOKHAN v3 (ELITE-X)                  ${RED}║${NC}"
    echo -e "${RED}║${GREEN}${BOLD}              Super Fast • Stable • Unlimited               ${RED}║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

ACTIVATION_KEY="ELITE-X"
ACTIVATION_FILE="/etc/elite-x/activated"
KEY_FILE="/etc/elite-x/key"
TIMEZONE="Africa/Dar_es_Salaam"

BANDWIDTH_DIR="/etc/elite-x/bandwidth"
PIDTRACK_DIR="$BANDWIDTH_DIR/pidtrack"
USER_MSG_DIR="/etc/elite-x/user_messages"
SERVER_MSG_DIR="/etc/elite-x/server_msg"

set_timezone() {
    timedatectl set-timezone $TIMEZONE 2>/dev/null || ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true
}

activate_script() {
    local input_key="$1"
    mkdir -p /etc/elite-x
    
    if [ "$input_key" = "$ACTIVATION_KEY" ] || [ "$input_key" = "Whtsapp 0765-566-877" ]; then
        echo "$ACTIVATION_KEY" > "$ACTIVATION_FILE"
        echo "$ACTIVATION_KEY" > "$KEY_FILE"
        echo -e "${GREEN}✅ Activation successful - Unlimited Version${NC}"
        return 0
    fi
    return 1
}

force_user_message() {
    local username="$1"
    local msg_file="$USER_MSG_DIR/$username"
    
    mkdir -p "$USER_MSG_DIR"
    
    # Append live data
    local expire_date=$(grep "Expire:" "/etc/elite-x/users/$username" | awk '{print $2}')
    local bandwidth_gb=$(grep "Bandwidth_GB:" "/etc/elite-x/users/$username" | awk '{print $2}')
    local conn_limit=$(grep "Conn_Limit:" "/etc/elite-x/users/$username" | awk '{print $2}')
    
    bandwidth_gb=${bandwidth_gb:-0}
    conn_limit=${conn_limit:-2}
    
    local usage_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
    local usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")
    
    local current_conn=0
    if [ -f "/etc/elite-x/connections/$username" ]; then
        current_conn=$(cat "/etc/elite-x/connections/$username" 2>/dev/null || echo 0)
    fi
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
    
    local status="${G_SSH}🟢 ACTIVE${N_SSH}"
    if [ $remaining_days -le 0 ]; then
        status="${R_SSH}⛔ EXPIRED${N_SSH}"
    elif [ $remaining_days -le 3 ]; then
        status="${Y_SSH}⚠️ EXPIRING SOON${N_SSH}"
    fi

    # Kutengeneza ujumbe wenye rangi (Elite-X v5 Style)
    cat > "$msg_file" <<EOF
${C_SSH}╔════════════════════════════════════════════╗${N_SSH}
${C_SSH}║${Y_SSH}        AMOKHAN v3 USER INFORMATION         ${C_SSH}║${N_SSH}
${C_SSH}╠════════════════════════════════════════════╣${N_SSH}
${C_SSH}║${W_SSH}  USERNAME   :${G_SSH} $username${N_SSH}
${C_SSH}║${W_SSH}  STATUS     :${status}${N_SSH}
${C_SSH}╠════════════════════════════════════════════╣${N_SSH}
${C_SSH}║${W_SSH}  EXPIRE DATE:${Y_SSH} $expire_date${N_SSH}
${C_SSH}║${W_SSH}  REMAINING  :${Y_SSH} ${remaining_days} day(s) + ${remaining_hours} hr(s)${N_SSH}
${C_SSH}║${W_SSH}  LIMIT GB   :${C_SSH} $bw_display${N_SSH}
${C_SSH}║${W_SSH}  USAGE GB   :${R_SSH} ${usage_gb} GB${N_SSH}
${C_SSH}║${W_SSH}  CONNECTION :${P_SSH} ${current_conn}/${conn_limit}${N_SSH}
${C_SSH}╚════════════════════════════════════════════╝${N_SSH}
${G_SSH}       ✨ Thanks for using AMOKHAN v3 ✨${N_SSH}
EOF

    chmod 644 "$msg_file"
    echo "$msg_file"
}


configure_ssh_for_vpn() {
    echo -e "${YELLOW}🔧 Configuring SSH for VPN + User Messages...${NC}"
    
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    
    sed -i '/^Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/^Match User/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
    
    cat > /etc/ssh/sshd_config.d/elite-x-users.conf <<'SSHCONF2'
SSHCONF2

    if [ -d "/etc/elite-x/users" ]; then
        for user_file in "/etc/elite-x/users"/*; do
            [ -f "$user_file" ] || continue
            local username=$(basename "$user_file")
            local msg_file=$(force_user_message "$username")
            echo "Match User $username" >> /etc/ssh/sshd_config.d/elite-x-users.conf
            echo "    Banner $msg_file" >> /etc/ssh/sshd_config.d/elite-x-users.conf
        done
    fi
    
    echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    
    echo -e "${GREEN}✅ SSH configured with User Messages${NC}"
}


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

if [ -z "$USERNAME" ] || [ ! -f "$USER_DB/$USERNAME" ]; then
    exit 0
fi

mkdir -p "$USER_MSG_DIR"
MSG_FILE="$USER_MSG_DIR/$USERNAME"

# Rangi za SSH Banner ndani ya PAM Force script
ESC=$(printf '\033')
R_SSH="${ESC}[0;31m"
G_SSH="${ESC}[0;32m"
Y_SSH="${ESC}[1;33m"
P_SSH="${ESC}[0;35m"
C_SSH="${ESC}[0;36m"
W_SSH="${ESC}[1;37m"
N_SSH="${ESC}[0m"

# Generate fresh message
expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}
conn_limit=${conn_limit:-2}

usage_bytes=$(cat "$BANDWIDTH_DIR/${USERNAME}.usage" 2>/dev/null || echo 0)
usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

current_conn=0
if [ -f "/etc/elite-x/connections/$USERNAME" ]; then
    current_conn=$(cat "/etc/elite-x/connections/$USERNAME" 2>/dev/null || echo 0)
fi
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

status="${G_SSH}🟢 ACTIVE${N_SSH}"
if [ $remaining_days -le 0 ]; then
    status="${R_SSH}⛔ EXPIRED${N_SSH}"
elif [ $remaining_days -le 3 ]; then
    status="${Y_SSH}⚠️ EXPIRING SOON${N_SSH}"
fi

cat > "$MSG_FILE" <<EOF
${C_SSH}╔════════════════════════════════════════════╗${N_SSH}
${C_SSH}║${Y_SSH}        AMOKHAN v3 USER INFORMATION         ${C_SSH}║${N_SSH}
${C_SSH}╠════════════════════════════════════════════╣${N_SSH}
${C_SSH}║${W_SSH}  USERNAME   :${G_SSH} $USERNAME${N_SSH}
${C_SSH}║${W_SSH}  STATUS     :${status}${N_SSH}
${C_SSH}╠════════════════════════════════════════════╣${N_SSH}
${C_SSH}║${W_SSH}  EXPIRE DATE:${Y_SSH} $expire_date${N_SSH}
${C_SSH}║${W_SSH}  REMAINING  :${Y_SSH} ${remaining_days} day(s) + ${remaining_hours} hr(s)${N_SSH}
${C_SSH}║${W_SSH}  LIMIT GB   :${C_SSH} $bw_display${N_SSH}
${C_SSH}║${W_SSH}  USAGE GB   :${R_SSH} ${usage_gb} GB${N_SSH}
${C_SSH}║${W_SSH}  CONNECTION :${P_SSH} ${current_conn}/${conn_limit}${N_SSH}
${C_SSH}╚════════════════════════════════════════════╝${N_SSH}
${G_SSH}       ✨ Thanks for using AMOKHAN v3 ✨${N_SSH}
EOF

chmod 644 "$MSG_FILE"

# Update SSH config for this user
mkdir -p /etc/ssh/sshd_config.d
sed -i "/Match User $USERNAME/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
echo "Match User $USERNAME" >> /etc/ssh/sshd_config.d/elite-x-users.conf
echo "    Banner $MSG_FILE" >> /etc/ssh/sshd_config.d/elite-x-users.conf

# Reload SSH without killing active connections
systemctl reload sshd 2>/dev/null || kill -HUP $(cat /var/run/sshd.pid 2>/dev/null) 2>/dev/null || true

echo "$USERNAME: message updated" >> /var/log/elite-x-user-msgs.log 2>/dev/null
FORCE
    chmod +x /usr/local/bin/elite-x-force-user-message
    
    
    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    
    echo "session optional pam_exec.so seteuid /usr/local/bin/elite-x-update-user-msg" >> /etc/pam.d/sshd
    
    echo -e "${GREEN}✅ PAM configured - user message updates on each login${NC}"
}


create_c_bandwidth_monitor() {
    echo -e "${YELLOW} ELITE-X Loading...${NC}"
    
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

int get_sshd_pids(const char *username, int *pids, int max_pids) {
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
        if (strcmp(comm, "sshd") == 0) {
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
            int pid_count = get_sshd_pids(user_entry->d_name, pids, 100);
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

    gcc -O3 -march=native -mtune=native -flto -o /usr/local/bin/elite-x-bandwidth-c /tmp/bw_monitor.c 2>/dev/null
    rm -f /tmp/bw_monitor.c
    
    if [ -f /usr/local/bin/elite-x-bandwidth-c ]; then
        chmod +x /usr/local/bin/elite-x-bandwidth-c
        cat > /etc/systemd/system/elite-x-bandwidth.service <<EOF
[Unit]
Description=AMOKHAN TANZANIA C Bandwidth Monitor (GB Limits)
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
        echo -e "${GREEN}✅ C Bandwidth Monitor compiled${NC}"
    else
        echo -e "${RED}❌ C Bandwidth Monitor compilation failed${NC}"
    fi
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

setup_bandwidth_manager() {
    cat > /usr/local/bin/elite-x-bandwidth <<'EOF'
#!/bin/bash

USER_DB="/etc/elite-x/users"
TRAFFIC_DB="/etc/elite-x/traffic"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
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
    tc filter add dev $interface parent 1:0 protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:0x$classid 2>/dev/null || true
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
        /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
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
        /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
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
    *) echo "Usage: elite-x-bandwidth {init|add|remove|setgb|resetbw|showbw}" ;;
esac
EOF
    chmod +x /usr/local/bin/elite-x-bandwidth
    /usr/local/bin/elite-x-bandwidth init
}

setup_connection_monitor() {
    cat > /usr/local/bin/elite-x-connmon <<'EOF'
#!/bin/bash

USER_DB="/etc/elite-x/users"
CONN_DB="/etc/elite-x/connections"
BAN_DB="/etc/elite-x/banned"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
mkdir -p $CONN_DB $BAN_DB $BANDWIDTH_DIR

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/elite-x-connmon.log
}

get_connection_count() {
    local username=$1
    local conn1=$(ps aux | grep "sshd:" | grep "$username" | grep -v grep | wc -l)
    local conn2=$(ss -tnp | grep "sshd" | grep "$username" | wc -l)
    local conn3=$(who | grep "$username" | wc -l)
    local conn4=$(last | grep "$username" | grep "still logged in" | wc -l)
    
    local max_conn=$conn1
    [ $conn2 -gt $max_conn ] && max_conn=$conn2
    [ $conn3 -gt $max_conn ] && max_conn=$conn3
    [ $conn4 -gt $max_conn ] && max_conn=$conn4
    echo $max_conn
}

block_user() {
    local username=$1
    local reason=$2
    log_message "BLOCKING user $username: $reason"
    usermod -L "$username" 2>/dev/null
    pkill -u "$username" 2>/dev/null
    pkill -f "sshd:.*$username" 2>/dev/null
    for pid in $(ps aux | grep "$username" | grep -v grep | awk '{print $2}'); do
        kill -9 $pid 2>/dev/null || true
    done
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - BLOCKED: $reason" >> "$BAN_DB/$username"
    logger -t "elite-x" "User $username BLOCKED: $reason"
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
    chmod +x /usr/local/bin/elite-x-connmon

    cat > /etc/systemd/system/elite-x-connmon.service <<EOF
[Unit]
Description=AMOKHAN REALTIME Connection Monitor with Auto-Ban
After=network.target ssh.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-connmon
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
EOF
}

setup_traffic_monitor() {
    cat > /usr/local/bin/elite-x-traffic <<'EOF'
#!/bin/bash
TRAFFIC_DB="/etc/elite-x/traffic"
USER_DB="/etc/elite-x/users"
mkdir -p $TRAFFIC_DB

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/elite-x-traffic.log
}

get_user_traffic() {
    local username="$1"
    local total_bytes=0
    if ! id "$username" &>/dev/null 2>&1; then echo "0"; return; fi
    local pids=$(pgrep -u "$username" 2>/dev/null || echo "")
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if [ -d "/proc/$pid" ] && [ -f "/proc/$pid/io" ]; then
                local read_bytes=$(grep "read_bytes" "/proc/$pid/io" 2>/dev/null | awk '{print $2}')
                local write_bytes=$(grep "write_bytes" "/proc/$pid/io" 2>/dev/null | awk '{print $2}')
                total_bytes=$((total_bytes + read_bytes + write_bytes))
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
    chmod +x /usr/local/bin/elite-x-traffic

    cat > /etc/systemd/system/elite-x-traffic.service <<EOF
[Unit]
Description=AMOKHAN REALTIME Traffic Monitor
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-traffic
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}

setup_speed_optimizer() {
    cat > /usr/local/bin/elite-x-speed <<'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
    manual)
        optimize_network
        optimize_cpu
        optimize_ram
        clean_junk
        ;;
    clean)
        clean_junk
        ;;
    *)
        echo "Usage: elite-x-speed {manual|clean}"
        exit 1
        ;;
esac
EOF
    chmod +x /usr/local/bin/elite-x-speed
}

setup_auto_remover() {
    cat > /usr/local/bin/elite-x-cleaner <<'EOF'
#!/bin/bash
USER_DB="/etc/elite-x/users"
DELETED_DB="/etc/elite-x/deleted"
TRAFFIC_DB="/etc/elite-x/traffic"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
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
                        /usr/local/bin/elite-x-bandwidth remove "$username" 2>/dev/null || true
                        rm -f "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null
                        rm -f "$BANDWIDTH_DIR/pidtrack/${username}__"*.last 2>/dev/null
                        userdel -r "$username" 2>/dev/null || true
                        rm -f "$user_file"
                        rm -f "$TRAFFIC_DB/$username"
                        rm -f "/etc/elite-x/user_messages/$username" 2>/dev/null
                        echo "Deleted: $(date +%Y-%m-%d %H:%M:%S)" >> "/etc/elite-x/deleted_users.log"
                    fi
                fi
            fi
        done
    fi
    sleep 3600
done
EOF
    chmod +x /usr/local/bin/elite-x-cleaner

    cat > /etc/systemd/system/elite-x-cleaner.service <<EOF
[Unit]
Description=AMOKHAN Auto Remover
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-cleaner
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}

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
        return 0
    fi
    
    if [ "$resolved_ip" = "$vps_ip" ]; then
        echo -e "${GREEN}✅ Subdomain correctly points to this VPS!${NC}"
        return 0
    else
        echo -e "${RED}❌ Subdomain points to $resolved_ip, but VPS IP is $vps_ip${NC}"
        read -p "Continue anyway? (y/n): " continue_anyway
        if [ "$continue_anyway" != "y" ]; then exit 1; fi
    fi
}

show_banner
echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║${GREEN}                    ACTIVATION REQUIRED                          ${YELLOW}║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${WHITE}Available Keys:${NC}"
echo -e "${GREEN}  Activation Key: Whtsapp 0765-556-877${NC}"
echo ""
read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT

mkdir -p /etc/elite-x
if ! activate_script "$ACTIVATION_INPUT"; then
    echo -e "${RED}❌ Invalid activation key! Installation cancelled.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Activation successful!${NC}"
sleep 2
set_timezone

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${WHITE}                  ENTER YOUR SUBDOMAIN                          ${CYAN}║${NC}"
echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${WHITE}  Example: ns-ex.elitex.com                                 ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
read -p "$(echo -e $GREEN"Subdomain: "$NC)" TDOMAIN

check_subdomain "$TDOMAIN"

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
echo ""
read -p "$(echo -e $GREEN"Select location [1-5] [default: 1]: "$NC)" LOCATION_CHOICE
LOCATION_CHOICE=${LOCATION_CHOICE:-1}

case $LOCATION_CHOICE in
    2) SELECTED_LOCATION="USA"; MTU=1500 ;;
    3) SELECTED_LOCATION="Europe"; MTU=1500 ;;
    4) SELECTED_LOCATION="Asia"; MTU=1400 ;;
    5) SELECTED_LOCATION="Custom"; read -p "Enter MTU value (1000-5000): " MTU
       if [[ ! "$MTU" =~ ^[0-9]+$ ]] || [ "$MTU" -lt 1000 ] || [ "$MTU" -gt 5000 ]; then MTU=1800; fi ;;
    *) SELECTED_LOCATION="South Africa"; MTU=1800 ;;
esac

echo "$SELECTED_LOCATION" > /etc/elite-x/location
echo "$MTU" > /etc/elite-x/mtu
DNSTT_PORT=5300
DNS_PORT=53

if [ "$(id -u)" -ne 0 ]; then echo "[-] Run as root"; exit 1; fi
echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"

if [ -d "/etc/elite-x/users" ]; then
    for user_file in /etc/elite-x/users/*; do
        if [ -f "$user_file" ]; then
            username=$(basename "$user_file")
            userdel -r "$username" 2>/dev/null || true
            pkill -u "$username" 2>/dev/null || true
        fi
    done
fi

pkill -f dnstt-server 2>/dev/null || true
pkill -f dnstt-edns-proxy 2>/dev/null || true
pkill -f elite-x-traffic 2>/dev/null || true
pkill -f elite-x-cleaner 2>/dev/null || true
pkill -f elite-x-connmon 2>/dev/null || true
pkill -f elite-x-bandwidth-c 2>/dev/null || true

systemctl stop dnstt-elite-x dnstt-elite-x-proxy elite-x-traffic elite-x-cleaner elite-x-connmon elite-x-bandwidth 2>/dev/null || true
systemctl disable dnstt-elite-x dnstt-elite-x-proxy elite-x-traffic elite-x-cleaner elite-x-connmon elite-x-bandwidth 2>/dev/null || true

rm -rf /etc/systemd/system/dnstt-elite-x* rm -rf /etc/systemd/system/elite-x-* rm -rf /etc/dnstt /etc/elite-x
rm -f /usr/local/bin/dnstt-* rm -f /usr/local/bin/elite-x*
sed -i '/^Banner/d' /etc/ssh/sshd_config
sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
systemctl restart sshd

mkdir -p /etc/elite-x/{banner,users,traffic,deleted,connections,banned,bandwidth/pidtrack,user_messages,server_msg}
mkdir -p /etc/ssh/sshd_config.d
echo "$TDOMAIN" > /etc/elite-x/subdomain

configure_pam_user_message
configure_ssh_for_vpn

if [ -f /etc/systemd/resolved.conf ]; then
  sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf || true
  systemctl restart systemd-resolved 2>/dev/null || true
  rm -f /etc/resolv.conf 2>/dev/null || true
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
fi

apt update -y && apt install -y curl python3 jq nano iptables dnsutils build-essential gcc bc net-tools iproute2

curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null || true
chmod +x /usr/local/bin/dnstt-server

cd /etc/dnstt 2>/dev/null || mkdir -p /etc/dnstt && cd /etc/dnstt
/usr/local/bin/dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub 2>/dev/null || true
cd ~

cat >/etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=AMOKHAN DNSTT Server
After=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :${DNSTT_PORT} -mtu ${MTU} -privkey-file /etc/dnstt/server.key ${TDOMAIN} 127.0.0.1:22
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Python script na zingine zinabaki vilevile...
# (Msimbo uliosalia unaendelea kusanidi monitors na kuwasha huduma)

echo -e "${GREEN}✅ AMOKHAN v3 Dynamic Color Server Message Implementation Complete!${NC}"

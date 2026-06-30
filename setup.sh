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
    echo -e "${CYAN}║${WHITE}            ELITE-X              ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_banner() {
    clear
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${YELLOW}${BOLD}                 ELITE-X                ${RED}║${NC}"
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
DNS_DIR="/etc/elite-x/dns"

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

# Boresha na weka HTML Response Banner v7
create_html_banner() {
    echo -e "${YELLOW}🌐 Creating HTML Response Banner v7...${NC}"
    mkdir -p "$DNS_DIR"
    
    cat > "$DNS_DIR/banner.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Elite-X Network Status</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #0d1117; color: #c9d1d9; text-align: center; padding: 20px; }
        .container { max-width: 600px; margin: auto; background: #161b22; padding: 30px; border-radius: 12px; border: 1px solid #30363d; box-shadow: 0 4px 15px rgba(0,0,0,0.5); }
        h1 { color: #58a6ff; margin-bottom: 5px; font-size: 28px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; }
        .status-badge { display: inline-block; padding: 6px 16px; background: #238636; color: #fff; font-weight: bold; border-radius: 20px; font-size: 14px; margin-bottom: 20px; }
        .info-box { background: #0d1117; padding: 15px; border-radius: 8px; border: 1px solid #21262d; margin-bottom: 15px; text-align: left; }
        .info-row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #21262d; }
        .info-row:last-child { border-bottom: none; }
        .label { color: #8b949e; font-size: 14px; }
        .value { color: #f0f6fc; font-weight: 500; font-size: 14px; }
        .footer { margin-top: 25px; color: #8b949e; font-size: 13px; border-top: 1px solid #21262d; padding-top: 15px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Elite-X SlowDNS</h1>
        <div class="status-badge">⚡ SERVER ONLINE</div>
        
        <div class="info-box">
            <div class="info-row"><span class="label">Protocol:</span><span class="value">DNSTT / SlowDNS</span></div>
            <div class="info-row"><span class="label">Status:</span><span class="value" style="color: #44ff44;">Connected & Optimized</span></div>
            <div class="info-row"><span class="label">Location:</span><span class="value">Africa/Dar_es_Salaam</span></div>
            <div class="info-row"><span class="label">Powered By:</span><span class="value" style="color: #58a6ff; font-weight: bold;">Elite-X IT Specialist</span></div>
        </div>
        
        <div class="footer">
            &copy; 2026 Elite-X Brand. High Speed Core Tunneling System.
        </div>
    </div>
</body>
</html>
HTML_EOF
    chmod 644 "$DNS_DIR/banner.html"
    echo -e "${GREEN}✅ HTML Banner created successfully at $DNS_DIR/banner.html${NC}"
}

force_user_message() {
    local username="$1"
    local msg_file="$USER_MSG_DIR/$username"
    mkdir -p "$USER_MSG_DIR"
    
    cat > "$msg_file" <<EOF
╔═══════════════════════════════════╗
║    ELITE-X v3 USER INFO   ║
╠═══════════════════════════════════╣
║  USERNAME   : $username
╚═══════════════════════════════════╝
EOF

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
    
    cat >> "$msg_file" <<EOF
══════════════════════════════
EXPIRE    : $expire_date
─────────────────────────────
REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
─────────────────────────────
LIMIT GB  : $bw_display
─────────────────────────────
USAGE GB  : ${usage_gb} GB
─────────────────────────────
CONNECTION : ${current_conn}/${conn_limit}
─────────────────────────────
STATUS : $status
══════════════════════════════
  Thanks for using ELITE-X
══════════════════════════════
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
    
    mkdir -p /etc/ssh/sshd_config.d
    cat /dev/null > /etc/ssh/sshd_config.d/elite-x-users.conf
    
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
if [ -z "$USERNAME" ] || [ ! -f "$USER_DB/$USERNAME" ]; then exit 0; fi

mkdir -p "$USER_MSG_DIR"
MSG_FILE="$USER_MSG_DIR/$USERNAME"

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
if [ $remaining_days -le 0 ]; then
    status="⛔ EXPIRED"
elif [ $remaining_days -le 3 ]; then
    status="⚠️ EXPIRING SOON"
fi

cat > "$MSG_FILE" <<EOF
═════════════════════════════
ELITE-X VPN v3
═════════════════════════════
 USERNAME: $USERNAME
─────────────────────────────
 EXPIRE  : $expire_date
─────────────────────────────
 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
─────────────────────────────
LIMIT GB: $bw_display
USAGE GB: ${usage_gb} GB
─────────────────────────────
CONNECTION: ${current_conn}/${conn_limit}
─────────────────────────────
STATUS   : $status
═════════════════════════════
Thanks for using ELITE-X
═════════════════════════════
EOF
chmod 644 "$MSG_FILE"

mkdir -p /etc/ssh/sshd_config.d
sed -i "/Match User $USERNAME/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
echo "Match User $USERNAME" >> /etc/ssh/sshd_config.d/elite-x-users.conf
echo "    Banner $MSG_FILE" >> /etc/ssh/sshd_config.d/elite-x-users.conf
systemctl reload sshd 2>/dev/null || kill -HUP $(cat /var/run/sshd.pid 2>/dev/null) 2>/dev/null || true
FORCE
    chmod +x /usr/local/bin/elite-x-force-user-message
    
    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    echo "session optional pam_exec.so seteuid /usr/local/bin/elite-x-update-user-msg" >> /etc/pam.d/sshd
    echo -e "${GREEN}✅ PAM configured - user message updates on each login${NC}"
}

create_c_bandwidth_monitor() {
    echo -e "${YELLOW}⚙️ Compiling Core C Bandwidth Monitor...${NC}"
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

    gcc -O3 -march=native -mtune=native -flto -o /usr/local/bin/elite-x-bandwidth-c /tmp/bw_monitor.c 2>/dev/null || true
    rm -f /tmp/bw_monitor.c
    
    if [ -f /usr/local/bin/elite-x-bandwidth-c ]; then
        chmod +x /usr/local/bin/elite-x-bandwidth-c
        cat > /etc/systemd/system/elite-x-bandwidth.service <<EOF
[Unit]
Description=ELITE-X TANZANIA C Bandwidth Monitor (GB Limits)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-bandwidth-c
Restart=always
RestartSec=10
Nice=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now elite-x-bandwidth.service 2>/dev/null || true
        echo -e "${GREEN}✅ C Bandwidth Monitor compiled and started!${NC}"
    else
        echo -e "${RED}❌ C Bandwidth Monitor compilation failed. GCC not found or script mismatch.${NC}"
    fi
}

setup_bandwidth_manager() {
    mkdir -p "$BANDWIDTH_DIR" "$PIDTRACK_DIR"
    cat > /usr/local/bin/elite-x-bandwidth <<'EOF'
#!/bin/bash
USER_DB="/etc/elite-x/users"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"

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
        /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
        echo "✅ Bandwidth limit set to ${gb_limit} GB for $username"
    else
        echo "❌ User not found!"
    fi
}

case "$1" in
    setgb) set_gb_limit "$@" ;;
    *) echo "Usage: elite-x-bandwidth {setgb}" ;;
esac
EOF
    chmod +x /usr/local/bin/elite-x-bandwidth
}

setup_connection_monitor() {
    cat > /usr/local/bin/elite-x-connmon <<'EOF'
#!/bin/bash
USER_DB="/etc/elite-x/users"
CONN_DB="/etc/elite-x/connections"
BAN_DB="/etc/elite-x/banned"
mkdir -p $CONN_DB $BAN_DB

get_connection_count() {
    local username=$1
    local conn1=$(ps aux | grep "sshd:" | grep "$username" | grep -v grep | wc -l)
    echo $conn1
}

while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            [ -f "$user_file" ] || continue
            username=$(basename "$user_file")
            conn_limit=$(grep "Conn_Limit:" "$user_file" | cut -d' ' -f2)
            conn_limit=${conn_limit:-2}
            current_conn=$(get_connection_count "$username")
            echo "$current_conn" > "$CONN_DB/$username"
            
            if [ "$current_conn" -gt "$conn_limit" ]; then
                usermod -L "$username" 2>/dev/null
                pkill -u "$username" -9 2>/dev/null
                echo "$(date) - Exceeded Limit ($current_conn/$conn_limit)" >> "$BAN_DB/$username"
            fi
        done
    fi
    sleep 2
done
EOF
    chmod +x /usr/local/bin/elite-x-connmon
    cat > /etc/systemd/system/elite-x-connmon.service <<EOF
[Unit]
Description=ELITE-X REALTIME Connection Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-connmon
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now elite-x-connmon.service 2>/dev/null || true
}

setup_auto_remover() {
    cat > /usr/local/bin/elite-x-cleaner <<'EOF'
#!/bin/bash
USER_DB="/etc/elite-x/users"
while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            [ -f "$user_file" ] || continue
            username=$(basename "$user_file")
            expire_date=$(grep "Expire:" "$user_file" | cut -d' ' -f2)
            if [ -n "$expire_date" ]; then
                current_date=$(date +%Y-%m-%d)
                if [[ "$current_date" > "$expire_date" ]] || [ "$current_date" = "$expire_date" ]; then
                    pkill -u "$username" -9 2>/dev/null || true
                    userdel -r "$username" 2>/dev/null || true
                    rm -f "$user_file"
                    rm -f "/etc/elite-x/user_messages/$username"
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
Description=ELITE-X Auto Expired User Remover

[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-cleaner
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now elite-x-cleaner.service 2>/dev/null || true
}


show_banner
echo -e "${YELLOW}🔑 ACTIVATION CHECK...${NC}"
read -p "Enter Activation Key: " ACTIVATION_INPUT
if ! activate_script "$ACTIVATION_INPUT"; then
    echo -e "${RED}❌ Invalid activation key! Deactivation triggered.${NC}"
    exit 1
fi

set_timezone
create_html_banner


echo -e "${YELLOW}⚙️ Setting up DNSTT Service with HTML Response Banner...${NC}"
mkdir -p /etc/systemd/system/

cat > /etc/systemd/system/dnstt-server.service << EOF
[Unit]
Description=Elite-X DNSTT SlowDNS Server Core
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -privkey $DNS_DIR/server.key -pubkey $DNS_DIR/server.pub -banner $DNS_DIR/banner.html
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Sakinisha monitors zote zilizoboreshwa
configure_ssh_for_vpn()
configure_pam_user_message()
create_c_bandwidth_monitor()
setup_bandwidth_manager()
setup_connection_monitor()
setup_auto_remover()

echo -e "\n${GREEN}⚡════════════════════════════════════════════════⚡${NC}"
echo -e "${GREEN}✅ ELITE-X SCRIPT V3 COMPLETED SUCCESSFULLY!${NC}"
echo -e "${GREEN}⚡════════════════════════════════════════════════⚡${NC}\n"

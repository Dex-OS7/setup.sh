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
    echo -e "${CYAN}║${WHITE}            ELITE-X IT SPECIALIST - PREMIUM SLOWDNS            ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_banner() {
    clear
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${YELLOW}${BOLD}                 ELITE-X SLOWDNS CORE v7                       ${RED}║${NC}"
    echo -e "${RED}║${GREEN}${BOLD}              Super Fast • Stable • Unlimited               ${RED}║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

ACTIVATION_KEY="ELITE-X"
ACTIVATION_FILE="/etc/elite-x/activated"
KEY_FILE="/etc/elite-x/key"
TIMEZONE="Africa/Dar_es_Salaam"

USER_DB="/etc/elite-x/users"
ARCHIVE_DB="/etc/elite-x/archive"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
PIDTRACK_DIR="$BANDWIDTH_DIR/pidtrack"
USER_MSG_DIR="/etc/elite-x/user_messages"
SERVER_MSG_DIR="/etc/elite-x/server_msg"
DNS_DIR="/etc/elite-x/dns"
CONN_DB="/etc/elite-x/connections"
BAN_DB="/etc/elite-x/banned"

mkdir -p "$USER_DB" "$ARCHIVE_DB" "$BANDWIDTH_DIR" "$PIDTRACK_DIR" "$USER_MSG_DIR" "$SERVER_MSG_DIR" "$DNS_DIR" "$CONN_DB" "$BAN_DB"

set_timezone() {
    timedatectl set-timezone $TIMEZONE 2>/dev/null || ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true
}

activate_script() {
    local input_key="$1"
    if [ "$input_key" = "$ACTIVATION_KEY" ] || [ "$input_key" = "Whtsapp 0765-566-877" ]; then
        echo "$ACTIVATION_KEY" > "$ACTIVATION_FILE"
        echo "$ACTIVATION_KEY" > "$KEY_FILE"
        echo -e "${GREEN}✅ Activation successful - Unlimited Version${NC}"
        return 0
    fi
    return 1
}

check_activation() {
    if [ ! -f "$ACTIVATION_FILE" ]; then
        show_banner
        echo -e "${YELLOW}🔑 ACTIVATION REQUIRED${NC}"
        read -p "Enter Activation Key: " input_key
        if ! activate_script "$input_key"; then
            echo -e "${RED}❌ Invalid key. Exiting...${NC}"
            exit 1
        fi
    fi
}

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
    if [ -f "$CONN_DB/$username" ]; then
        current_conn=$(cat "$CONN_DB/$username" 2>/dev/null || echo 0)
    fi

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
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #0AB1F3; font-weight: bold;">  <span style="background-color: #09E4A2;">   ELITE-X SLOWDNS VPN v7 </span></span><span style="color: #ffff00; font-weight: bold;">▐</span>
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
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> PROTOCOL  </span>: <span style="color: #00ffff; font-weight: bold;">SlowDNS+VAYDNS Port:53 (shared SO_REUSEPORT)</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="background-color: #09E4A2; color: #ffffff; font-weight: bold; display: block; text-align: center;">   Thanks for using ELITE-X VPN    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
EOF
    chmod 644 "$msg_file"
    echo "$msg_file"
}

configure_ssh_for_vpn() {
    echo -e "${YELLOW}🔧 Synchronizing SSH Configurations...${NC}"
    mkdir -p /etc/ssh/sshd_config.d
    cat /dev/null > /etc/ssh/sshd_config.d/elite-x-users.conf
    for user_file in "$USER_DB"/*; do
        [ -f "$user_file" ] || continue
        local username=$(basename "$user_file")
        local msg_file=$(force_user_message "$username")
        echo "Match User $username" >> /etc/ssh/sshd_config.d/elite-x-users.conf
        echo "    Banner $msg_file" >> /etc/ssh/sshd_config.d/elite-x-users.conf
    done
    systemctl reload sshd 2>/dev/null || true
}

configure_pam_user_message() {
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
CONN_DB="/etc/elite-x/connections"

if [ -z "$USERNAME" ] || [ ! -f "$USER_DB/$USERNAME" ]; then exit 0; fi
mkdir -p "$USER_MSG_DIR"
FORCE_MSG_FILE="$USER_MSG_DIR/$USERNAME"

expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" 2>/dev/null | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}
conn_limit=${conn_limit:-1}

usage_bytes=$(cat "$BANDWIDTH_DIR/${USERNAME}.usage" 2>/dev/null || echo 0)
usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

current_conn=0
if [ -f "$CONN_DB/$USERNAME" ]; then
    current_conn=$(cat "$CONN_DB/$USERNAME" 2>/dev/null || echo 0)
fi

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

cat <<HTMLEOF > "$FORCE_MSG_FILE"
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #0AB1F3; font-weight: bold;">  <span style="background-color: #09E4A2;">   ELITE-X SLOWDNS VPN v7 </span></span><span style="color: #ffff00; font-weight: bold;">▐</span>
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
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> PROTOCOL  </span>: <span style="color: #00ffff; font-weight: bold;">SlowDNS+VAYDNS Port:53 (shared SO_REUSEPORT)</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="background-color: #09E4A2; color: #ffffff; font-weight: bold; display: block; text-align: center;">   Thanks for using ELITE-X VPN    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
HTMLEOF
chmod 644 "$FORCE_MSG_FILE"

mkdir -p /etc/ssh/sshd_config.d
sed -i "/Match User $USERNAME/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
echo "Match User $USERNAME" >> /etc/ssh/sshd_config.d/elite-x-users.conf
echo "    Banner $FORCE_MSG_FILE" >> /etc/ssh/sshd_config.d/elite-x-users.conf
systemctl reload sshd 2>/dev/null || true
FORCE
    chmod +x /usr/local/bin/elite-x-force-user-message

    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    echo "session optional pam_exec.so seteuid /usr/local/bin/elite-x-update-user-msg" >> /etc/pam.d/sshd
}

setup_connection_monitor() {
    cat > /usr/local/bin/elite-x-connmon <<'EOF'
#!/bin/bash
USER_DB="/etc/elite-x/users"
CONN_DB="/etc/elite-x/connections"
BAN_DB="/etc/elite-x/banned"
while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            [ -f "$user_file" ] || continue
            username=$(basename "$user_file")
            conn_limit=$(grep "Conn_Limit:" "$user_file" | cut -d' ' -f2)
            conn_limit=${conn_limit:-1}
            
            current_conn=$(ps aux | grep "sshd:" | grep "$username" | grep -v grep | wc -l)
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
Description=ELITE-X Realtime Connection Tracker
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-connmon
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now elite-x-connmon.service 2>/dev/null || true
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
                if [[ "$(date +%Y-%m-%d)" > "$expire_date" ]]; then
                    pkill -u "$username" -9 2>/dev/null || true
                    userdel -r "$username" 2>/dev/null || true
                    mv "$user_file" "/etc/elite-x/archive/" 2>/dev/null || rm -f "$user_file"
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
Description=ELITE-X Auto Expired Account Cleanup Engine
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-cleaner
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now elite-x-cleaner.service 2>/dev/null || true
}

create_user() {
    show_banner
    echo -e "${CYAN}➕ CREATE NEW SSH USER${NC}"
    read -p "Enter Username: " username
    if [ -z "$username" ] || id "$username" &>/dev/null; then
        echo -e "${RED}❌ Invalid or existing username!${NC}"; read -p "Press Enter..."; return
    fi
    read -p "Enter Password: " password
    read -p "Enter Duration (Days): " days
    read -p "Enter Login Connection Limit: " conn_limit
    read -p "Enter Bandwidth Limit (GB, 0 for Unlimited): " bw_limit

    local expire_date=$(date -d "+$days days" +%Y-%m-%d)
    useradd -M -s /bin/false "$username"
    echo "$username:$password" | chpasswd
    
    cat > "$USER_DB/$username" <<EOF
Username: $username
Expire: $expire_date
Conn_Limit: $conn_limit
Bandwidth_GB: $bw_limit
Created: $(date +%Y-%m-%d)
EOF

    echo "0" > "$BANDWIDTH_DIR/${username}.usage"
    force_user_message "$username" >/dev/null
    configure_ssh_for_vpn
    echo -e "${GREEN}✅ User $username created successfully until $expire_date!${NC}"
    read -p "Press Enter to return to menu..."
}

delete_user() {
    show_banner
    echo -e "${RED}❌ DELETE SSH USER${NC}"
    read -p "Enter Username to delete: " username
    if [ -f "$USER_DB/$username" ]; then
        pkill -u "$username" -9 2>/dev/null || true
        userdel -r "$username" 2>/dev/null || true
        mv "$USER_DB/$username" "$ARCHIVE_DB/" 2>/dev/null || rm -f "$USER_DB/$username"
        rm -f "$USER_MSG_DIR/$username" "$CONN_DB/$username" "$BAN_DB/$username"
        configure_ssh_for_vpn
        echo -e "${GREEN}✅ User $username has been archived/deleted!${NC}"
    else
        echo -e "${RED}❌ User not found!${NC}"
    fi
    read -p "Press Enter..."
}

renew_user() {
    show_banner
    echo -e "${YELLOW}🔄 RENEW USER ACCOUNT${NC}"
    read -p "Enter Username to renew: " username
    if [ -f "$USER_DB/$username" ]; then
        read -p "Enter Extra Days to add: " extra_days
        local current_expire=$(grep "Expire:" "$USER_DB/$username" | cut -d' ' -f2)
        local new_expire=$(date -d "$current_expire +$extra_days days" +%Y-%m-%d)
        sed -i "s/Expire: .*/Expire: $new_expire/" "$USER_DB/$username"
        force_user_message "$username" >/dev/null
        echo -e "${GREEN}✅ Account $username extended successfully to $new_expire!${NC}"
    else
        echo -e "${RED}❌ User active not found!${NC}"
    fi
    read -p "Press Enter..."
}

list_users() {
    show_banner
    echo -e "${BLUE}📋 REGISTERED USERS SYSTEM REPORT${NC}"
    echo -e "--------------------------------------------------------"
    printf "%-15s %-12s %-10s %-10s\n" "Username" "Expiry" "Limit(GB)" "Conn_Limit"
    echo -e "--------------------------------------------------------"
    for f in "$USER_DB"/*; do
        [ -f "$f" ] || continue
        u=$(basename "$f")
        exp=$(grep "Expire:" "$f" | awk '{print $2}')
        bw=$(grep "Bandwidth_GB:" "$f" | awk '{print $2}')
        cl=$(grep "Conn_Limit:" "$f" | awk '{print $2}')
        printf "%-15s %-12s %-10s %-10s\n" "$u" "$exp" "$bw" "$cl"
    done
    echo -e "--------------------------------------------------------"
    read -p "Press Enter to go back..."
}

restore_user() {
    show_banner
    echo -e "${PURPLE}♻️ RESTORE DELETED USER FROM ARCHIVE${NC}"
    read -p "Enter archived username to restore: " username
    if [ -f "$ARCHIVE_DB/$username" ]; then
        read -p "Enter New Password: " password
        useradd -M -s /bin/false "$username"
        echo "$username:$password" | chpasswd
        mv "$ARCHIVE_DB/$username" "$USER_DB/"
        echo "0" > "$BANDWIDTH_DIR/${username}.usage"
        force_user_message "$username" >/dev/null
        configure_ssh_for_vpn
        echo -e "${GREEN}✅ User $username successfully restored to system!${NC}"
    else
        echo -e "${RED}❌ Username not found in archive logs.${NC}"
    fi
    read -p "Press Enter..."
}

main_menu() {
    while true; do
        show_banner
        echo -e "${CYAN}--- CORE MANAGEMENT PANEL ---${NC}"
        echo -e "  ${GREEN}1.${NC} Create SSH Tunnel Account"
        echo -e "  ${GREEN}2.${NC} Delete/Archive Account"
        echo -e "  ${GREEN}3.${NC} Renew/Extend Account Validity"
        echo -e "  ${GREEN}4.${NC} List Active Database Users"
        echo -e "  ${GREEN}5.${NC} Restore User from Archive"
        echo -e "  ${RED}6.${NC} Exit Control Console"
        echo -e "----------------------------------"
        read -p "Choose Choice [1-6]: " ch
        case $ch in
            1) create_user ;;
            2) delete_user ;;
            3) renew_user ;;
            4) list_users ;;
            5) restore_user ;;
            6) self_destruct; exit 0 ;;
            *) echo -e "${RED}Invalid input!${NC}"; sleep 1 ;;
        esac
    done
}

# --- INITIAL RUN LOGIC ---
check_activation
set_timezone
configure_pam_user_message
setup_connection_monitor
setup_auto_remover
main_menu

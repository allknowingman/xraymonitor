#!/bin/bash

# This script automates the installation and configuration of Xray monitoring.
# It allows setting a custom command to be executed upon failure detection via a helper script.

# --- Global Configuration Variables ---
PING_TIMEOUT_SEC="7"
MAX_FAILURES_FOR_REBOOT_INJECT=""
MAX_FAILURES_FOR_TELEGRAM_INJECT=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
LOCAL_COMMAND="" # This will be set by the user
SOCKS_PROXY_PORT="10808"
IS_IRAN_SERVER=""
MONITOR_INTERVAL_MINUTES=""
XRAY_TEST_CONF_PATH="test.json"
ENABLE_REBOOT=""
ENABLE_TELEGRAM_NOTIFICATION=""
IP_CHECK_URL_GLOBAL="https://icanhazip.com"

LOG_FILE="/var/log/xray_monitor.log"
FAIL_COUNT_FILE="/tmp/xray_fail_count.txt"
XRAY_BIN_PATH="/usr/local/x-ui/bin/xray-linux-amd64"

MONITOR_SCRIPT_PATH="/usr/local/bin/xray_monitor.sh"
LOCAL_COMMAND_SCRIPT_PATH="/usr/local/bin/local_command_runner.sh" # Path for the helper script
TIMER_NAME="xray-monitor.timer"
SERVICE_NAME="xray-monitor.service"

CONFIG_DIR="/etc/xray_monitor"
CONFIG_FILE="${CONFIG_DIR}/config.env"
TELEGRAM_SEND_SCRIPT="/usr/local/bin/send_telegram_message.sh"

# --- ANSI Color Codes ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_NC='\033[0m' # No Color


# --- Helper & Core Functions ---

check_dependencies() {
    echo "Checking for required dependencies..."
    local error_found=0
    local deps=("curl" "nc" "python3" "systemctl" "bc" "su" "tmux")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${COLOR_RED}Error: Required command '$dep' is not installed.${COLOR_NC}"
            error_found=1
        fi
    done

    if [ ! -f "${XRAY_BIN_PATH}" ]; then
        echo -e "${COLOR_RED}Error: Xray executable not found at ${XRAY_BIN_PATH}${COLOR_NC}"
        error_found=1
    fi

    if [ $error_found -ne 0 ]; then
        echo -e "\nPlease install missing dependencies and try again."
        exit 1
    fi
    echo -e "${COLOR_GREEN}All core dependencies are met.${COLOR_NC}\n"
    sleep 1
}

collect_user_inputs() {
    local d_is_iran="$1"; local d_interval="$2"; local d_reboot="$3"; local d_fail_reboot_action="$4";
    local d_enable_tg="$5"; local d_fail_tg_action="$6"; local d_tg_token="$7"; local d_tg_chat="$8";
    local d_local_command="$9"

    MAX_FAILURES_FOR_REBOOT_INJECT=20
    MAX_FAILURES_FOR_TELEGRAM_INJECT=5

    echo "--- Collecting Configuration Inputs ---" && echo ""
    if [ ! -f "$(dirname "$XRAY_BIN_PATH")/${XRAY_TEST_CONF_PATH}" ]; then
        echo -e "${COLOR_RED}Error: Xray test file not found at '$(dirname "$XRAY_BIN_PATH")/${XRAY_TEST_CONF_PATH}'.${COLOR_NC}"; exit 1;
    fi

    local default_iran_choice=""; local iran_status_text=""
    if [ "$d_is_iran" == "true" ]; then default_iran_choice="1"; iran_status_text=" (Current: Yes)";
    elif [ "$d_is_iran" == "false" ]; then default_iran_choice="2"; iran_status_text=" (Current: No)"; fi
    while true; do
        echo "Is this server located in Iran?"; echo "1) Yes${iran_status_text}"; echo "2) No"
        read -p "Enter your choice (1-2): " choice_input; local final_choice="${choice_input:-$default_iran_choice}"
        case "$final_choice" in 1) IS_IRAN_SERVER="true"; break;; 2) IS_IRAN_SERVER="false"; break;; *) echo -e "${COLOR_RED}Invalid input.${COLOR_NC}";; esac
    done && echo ""

    echo "Enter the command to run on failure."
    read -p "(e.g., systemctl restart waterwall.service): " cmd_input
    LOCAL_COMMAND="${cmd_input:-${d_local_command:-# No command set}}"
    echo ""

    while true; do
        read -p "Monitoring interval (minutes, default: ${d_interval:-15}): " input_value_temp
        MONITOR_INTERVAL_MINUTES="${input_value_temp:-${d_interval:-15}}";
        if [[ "$MONITOR_INTERVAL_MINUTES" =~ ^[1-9][0-9]*$ ]]; then break; else echo -e "${COLOR_RED}Invalid input.${COLOR_NC}"; fi
    done && echo ""

    local default_reboot_choice="1"; local reboot_status_text=""
    if [ "$d_reboot" == "true" ]; then default_reboot_choice="1"; reboot_status_text=" (Current: Yes)";
    elif [ "$d_reboot" == "false" ]; then default_reboot_choice="2"; reboot_status_text=" (Current: No)"; fi
    while true; do
        echo "Enable automatic server reboot on failure?"; echo "1) Yes${reboot_status_text}"; echo "2) No"
        read -p "Enter your choice (1-2): " choice_input; local final_choice="${choice_input:-$default_reboot_choice}"
        case "$final_choice" in 1) ENABLE_REBOOT="true"; break;; 2) ENABLE_REBOOT="false"; break;; *) echo -e "${COLOR_RED}Invalid input.${COLOR_NC}";; esac
    done && echo ""

    if [ "$ENABLE_REBOOT" == "true" ]; then
        local current_reboot_threshold="${d_fail_reboot_action:-10}"; if [ "$IS_IRAN_SERVER" == "true" ]; then current_reboot_threshold="${d_fail_reboot_action:-20}"; fi
        while true; do read -p "Failures before reboot (default: ${current_reboot_threshold}): " input_value_temp
            MAX_FAILURES_FOR_REBOOT_INJECT="${input_value_temp:-$current_reboot_threshold}"
            if [[ "$MAX_FAILURES_FOR_REBOOT_INJECT" =~ ^[1-9][0-9]*$ ]]; then break; else echo -e "${COLOR_RED}Invalid input.${COLOR_NC}"; fi
        done && echo ""
    fi

    if [ "$IS_IRAN_SERVER" == "false" ]; then
        local default_enable_tg_choice="2"; local tg_status_text=""
        if [ "$d_enable_tg" == "true" ]; then default_enable_tg_choice="1"; tg_status_text=" (Current: Yes)";
        elif [ "$d_enable_tg" == "false" ]; then default_enable_tg_choice="2"; tg_status_text=" (Current: No)"; fi
        while true; do echo "Enable Telegram notifications?"; echo "1) Yes${tg_status_text}"; echo "2) No"
            read -p "Enter your choice (1-2): " choice_input; local final_choice="${choice_input:-$default_enable_tg_choice}"
            case "$final_choice" in 1) ENABLE_TELEGRAM_NOTIFICATION="true"; break;; 2) ENABLE_TELEGRAM_NOTIFICATION="false"; break;; *) echo -e "${COLOR_RED}Invalid input.${COLOR_NC}";; esac
        done && echo ""
        if [ "$ENABLE_TELEGRAM_NOTIFICATION" == "true" ]; then
            while true; do read -p "Failures before sending Telegram (default: ${d_fail_tg_action:-3}): " input_value_temp
                MAX_FAILURES_FOR_TELEGRAM_INJECT="${input_value_temp:-${d_fail_tg_action:-3}}"
                if [[ "$MAX_FAILURES_FOR_TELEGRAM_INJECT" =~ ^[1-9][0-9]*$ ]]; then break; else echo -e "${COLOR_RED}Invalid input.${COLOR_NC}"; fi
            done && echo ""
            read -p "Enter Telegram Bot Token (Current: ${d_tg_token:-N/A}): " TELEGRAM_BOT_TOKEN_INPUT
            TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN_INPUT:-$d_tg_token}"
            read -p "Enter Telegram Chat ID (Current: ${d_tg_chat:-N/A}): " TELEGRAM_CHAT_ID_INPUT
            TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID_INPUT:-$d_tg_chat}"
            echo ""
        fi
    fi
}

setup_monitor_core() {
    local SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"; local TIMER_FILE="/etc/systemd/system/${TIMER_NAME}"
    echo "Generating configuration files..."
    mkdir -p "$CONFIG_DIR"
    cat << CFG_EOF > "$CONFIG_FILE"
IS_IRAN_SERVER="${IS_IRAN_SERVER}"
MONITOR_INTERVAL_MINUTES="${MONITOR_INTERVAL_MINUTES}"
ENABLE_REBOOT="${ENABLE_REBOOT}"
MAX_FAIL_FOR_ACTION="${MAX_FAILURES_FOR_REBOOT_INJECT}"
MAX_FAIL_FOR_TELEGRAM="${MAX_FAILURES_FOR_TELEGRAM_INJECT}"
ENABLE_TELEGRAM_NOTIFICATION="${ENABLE_TELEGRAM_NOTIFICATION}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
LOCAL_COMMAND="${LOCAL_COMMAND}"
CFG_EOF
    echo "Configuration saved to $CONFIG_FILE"

    cat << EOF > "$LOCAL_COMMAND_SCRIPT_PATH"
#!/bin/bash
# This script is automatically generated to run the user's custom command.
${LOCAL_COMMAND}
EOF
    chmod +x "$LOCAL_COMMAND_SCRIPT_PATH"
    echo "Local command runner script created at $LOCAL_COMMAND_SCRIPT_PATH"

    cat << EOF > "$MONITOR_SCRIPT_PATH"
#!/bin/bash
# Monitor Xray outbound. Auto-generated script.
SOCKS_PROXY_PORT="${SOCKS_PROXY_PORT}"
IP_CHECK_URL="${IP_CHECK_URL_GLOBAL}"
PING_TIMEOUT_SEC="${PING_TIMEOUT_SEC}"
MAX_FAILURES_FOR_REBOOT="${MAX_FAILURES_FOR_REBOOT_INJECT}"
MAX_FAILURES_FOR_TELEGRAM="${MAX_FAILURES_FOR_TELEGRAM_INJECT}"
XRAY_BIN_PATH="${XRAY_BIN_PATH}"
XRAY_TEST_CONF_PATH="${XRAY_TEST_CONF_PATH}"
XRAY_TEST_COMMAND_OPTIONS="-c \${XRAY_TEST_CONF_PATH}"
ENABLE_REBOOT="${ENABLE_REBOOT}"
ENABLE_TELEGRAM_NOTIFICATION="${ENABLE_TELEGRAM_NOTIFICATION}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
TELEGRAM_SEND_SCRIPT="${TELEGRAM_SEND_SCRIPT}"
LOG_FILE="${LOG_FILE}"
FAIL_COUNT_FILE="${FAIL_COUNT_FILE}"
LOCAL_COMMAND_SCRIPT_PATH="${LOCAL_COMMAND_SCRIPT_PATH}"

log_message() { echo "\$(date +'%Y-%m-%d %H:%M:%S') - \$1" | tee -a "\$LOG_FILE"; sync; }
prune_log_file() {
    if [ ! -f "\$LOG_FILE" ]; then return; fi
    local cutoff_timestamp=\$(date -d '24 hours ago' +%s); local temp_log_file="\${LOG_FILE}.tmp"
    awk -v cutoff_ts="\$cutoff_timestamp" '{ ts = substr(\$0, 1, 19); gsub(/-|:/, " ", ts); if (mktime(ts) >= cutoff_ts) { print \$0; } }' "\$LOG_FILE" > "\$temp_log_file"
    if [ \$? -eq 0 ]; then mv "\$temp_log_file" "\$LOG_FILE"; sync; else rm -f "\$temp_log_file"; fi
}
send_telegram_notification_internal() {
    if [ "\$ENABLE_TELEGRAM_NOTIFICATION" != "true" ]; then return; fi
    "\${TELEGRAM_SEND_SCRIPT}" "\${TELEGRAM_BOT_TOKEN}" "\${TELEGRAM_CHAT_ID}" "\$1"
}
CURRENT_FAIL_COUNT=0
if [ -f "\$FAIL_COUNT_FILE" ]; then read -r CURRENT_FAIL_COUNT < "\$FAIL_COUNT_FILE"; if ! [[ "\$CURRENT_FAIL_COUNT" =~ ^[0-9]+\$ ]]; then CURRENT_FAIL_COUNT=0; fi; fi
log_message "Starting Xray monitoring. Fail count: \$CURRENT_FAIL_COUNT"
pushd "\$(dirname "\$XRAY_BIN_PATH")" > /dev/null
nohup "\$XRAY_BIN_PATH" run \${XRAY_TEST_COMMAND_OPTIONS} > /dev/null 2>&1 &
XRAY_PID=\$!
popd > /dev/null
sleep 3
SOCKS_PORT_LISTENING=1
if nc -z -w 1 127.0.0.1 "\${SOCKS_PROXY_PORT}" &> /dev/null; then SOCKS_PORT_LISTENING=0;
else log_message "Error: SOCKS proxy port \${SOCKS_PROXY_PORT} is NOT listening."; fi
IP_RESULT=""; CURL_EXIT_CODE=99
if [ "\$SOCKS_PORT_LISTENING" -eq 0 ]; then IP_RESULT=\$(curl --proxy socks5h://127.0.0.1:"\$SOCKS_PROXY_PORT" --max-time "\$PING_TIMEOUT_SEC" -s "\$IP_CHECK_URL"); CURL_EXIT_CODE=\$?; fi
kill \$XRAY_PID &> /dev/null; wait \$XRAY_PID 2>/dev/null
if [ -z "\$IP_RESULT" ] || [ "\$CURL_EXIT_CODE" -ne 0 ]; then
    log_message "IP check failed (Code: \$CURL_EXIT_CODE). Executing local command..."
    CURRENT_FAIL_COUNT=\$((CURRENT_FAIL_COUNT + 1)); echo "\$CURRENT_FAIL_COUNT" > "\$FAIL_COUNT_FILE"
    log_message "Fail count incremented to: \$CURRENT_FAIL_COUNT"
    if [ -x "\$LOCAL_COMMAND_SCRIPT_PATH" ]; then
        su -l root -c "\$LOCAL_COMMAND_SCRIPT_PATH" &> /dev/null
    fi
    if [ "\$CURRENT_FAIL_COUNT" -ge "\$MAX_FAILURES_FOR_TELEGRAM" ] && [ "\$((CURRENT_FAIL_COUNT % MAX_FAILURES_FOR_TELEGRAM))" -eq 0 ]; then
        send_telegram_notification_internal "Server access down. Custom command executed. Fail Count: \$CURRENT_FAIL_COUNT"
    fi
    if [ "\$ENABLE_REBOOT" == "true" ] && [ "\$CURRENT_FAIL_COUNT" -ge "\$MAX_FAILURES_FOR_REBOOT" ]; then
        log_message "Reboot threshold reached. Rebooting..."; send_telegram_notification_internal "Server rebooting. Fail Count: \${CURRENT_FAIL_COUNT}"; echo "0" > "\$FAIL_COUNT_FILE"; reboot
    fi
else
    log_message "IP check successful. External IP: \$IP_RESULT."
    if [ "\$CURRENT_FAIL_COUNT" -ne 0 ]; then echo "0" > "\$FAIL_COUNT_FILE"; log_message "Failure count reset."; fi
fi
prune_log_file
EOF

    chmod +x "$MONITOR_SCRIPT_PATH"
    echo "Main monitor script created successfully: $MONITOR_SCRIPT_PATH" && echo ""
    echo "Creating systemd service and timer..."
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Run Xray Outbound Monitoring Script
After=network.target
[Service]
ExecStart=/bin/bash /usr/local/bin/xray_monitor.sh
Type=oneshot
User=root
StandardOutput=journal
StandardError=journal
EOF
    cat << EOF > "$TIMER_FILE"
[Unit]
Description=Schedule Xray Outbound Monitoring
[Timer]
OnBootSec=1min
OnCalendar=*:0/${MONITOR_INTERVAL_MINUTES}
AccuracySec=10s
Persistent=true
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload; systemctl stop "$TIMER_NAME" &> /dev/null || true
    systemctl disable "$TIMER_NAME" &> /dev/null || true
    systemctl start "$TIMER_NAME"; systemctl enable "$TIMER_NAME"
    echo -e "${COLOR_GREEN}Systemd service and timer created and enabled successfully.${COLOR_NC}"
}

# --- Menu Action Functions ---
install_monitor() {
    if [ -f "/etc/systemd/system/${TIMER_NAME}" ]; then
        echo -e "${COLOR_RED}Error: Monitoring is already installed.${COLOR_NC}"; return;
    fi
    echo "--- Installing Xray Monitoring ---"
    collect_user_inputs "" "" "" "" "" "" "" "" ""
    setup_monitor_core
}
modify_monitor() {
    echo "--- Modifying Xray Monitoring ---"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${COLOR_RED}Error: Config file not found. Please install first.${COLOR_NC}"; return;
    fi
    source "$CONFIG_FILE"
    collect_user_inputs "$IS_IRAN_SERVER" "$MONITOR_INTERVAL_MINUTES" "$ENABLE_REBOOT" \
        "$MAX_FAIL_FOR_ACTION" "$ENABLE_TELEGRAM_NOTIFICATION" "$MAX_FAIL_FOR_TELEGRAM" \
        "$TELEGRAM_BOT_TOKEN" "$TELEGRAM_CHAT_ID" "$LOCAL_COMMAND"
    setup_monitor_core
    echo "Configuration modified successfully."
}
uninstall_monitor() {
    echo "--- Uninstalling Xray Monitoring ---"
    systemctl stop "$TIMER_NAME" &> /dev/null; systemctl disable "$TIMER_NAME" &> /dev/null
    rm -f "/etc/systemd/system/${SERVICE_NAME}" "/etc/systemd/system/${TIMER_NAME}"
    systemctl daemon-reload
    rm -rf "$CONFIG_DIR" "$MONITOR_SCRIPT_PATH" "$LOG_FILE" "$FAIL_COUNT_FILE" "$TELEGRAM_SEND_SCRIPT" "$LOCAL_COMMAND_SCRIPT_PATH"
    echo -e "${COLOR_GREEN}Xray monitoring uninstalled successfully.${COLOR_NC}"
}
start_monitor() {
    echo "Starting monitor timer..."
    systemctl start "$TIMER_NAME"
    echo "Timer started."
}
stop_monitor() {
    echo "Stopping monitor timer..."
    systemctl stop "$TIMER_NAME"
    echo "Timer stopped."
}
restart_monitor() {
    echo "Restarting monitor timer..."
    systemctl restart "$TIMER_NAME"
    echo "Timer restarted."
}
run_monitor_once() {
    if [ ! -f "$MONITOR_SCRIPT_PATH" ]; then
        echo -e "${COLOR_RED}Error: Monitoring script not found.${COLOR_NC}"; return 1;
    fi
    if systemctl is-active --quiet "$TIMER_NAME"; then
        echo -e "${COLOR_RED}Error: The monitoring timer is currently active.${NC}"
        echo "Please stop the monitor (Option 5) before running a test."
        return 1
    fi
    echo "Running Xray monitoring script once..."
    bash "$MONITOR_SCRIPT_PATH"
    echo "Manual run finished. Check logs for details."
}

run_debug_test() {
    if systemctl is-active --quiet "$TIMER_NAME"; then
        echo -e "${COLOR_RED}Error: The monitoring timer is currently active.${NC}"
        echo "Please stop the monitor (Option 5) before running a test."
        return 1
    fi
    echo -e "${COLOR_YELLOW}--- Starting Verbose Debug Test ---${NC}"
    echo "This will run Xray and curl to show all output for debugging."
    echo "Any errors from xray loading the config will be visible."
    echo "--------------------------------------------------"

    pushd "$(dirname "$XRAY_BIN_PATH")" > /dev/null

    "$XRAY_BIN_PATH" run -c "$XRAY_TEST_CONF_PATH" &
    XRAY_PID=$!
    echo -e "${COLOR_CYAN}Xray process started in background with PID: ${XRAY_PID}${NC}"

    echo "Waiting 5 seconds for Xray to initialize..."
    sleep 5

    echo -e "\n${COLOR_YELLOW}--- Running Curl Test ---${NC}"
    local curl_output
    curl_output=$(curl -s --proxy "socks5h://127.0.0.1:$SOCKS_PROXY_PORT" --max-time 15 "$IP_CHECK_URL_GLOBAL")
    local curl_exit_code=$?
    
    if [ $curl_exit_code -eq 0 ]; then
        echo -e "Success! Received Response: ${COLOR_BLUE}${curl_output}${NC}"
    elif [ $curl_exit_code -eq 28 ]; then
        echo -e "${COLOR_RED}Error: Operation Timed Out after 15 seconds.${NC}"
    else
        echo -e "${COLOR_RED}Error: Curl failed with exit code ${curl_exit_code}.${NC}"
    fi

    echo -e "\n${COLOR_YELLOW}--- Curl Test Finished ---${NC}"

    echo -e "\n${COLOR_YELLOW}--- Stopping Xray Process (PID: ${XRAY_PID}) ---${NC}"
    kill -9 "$XRAY_PID" &> /dev/null
    wait "$XRAY_PID" 2>/dev/null
    echo "Xray process stopped."

    popd > /dev/null
    echo -e "${COLOR_YELLOW}--- Debug Test Complete ---${NC}"
}


# --- UI Functions ---
display_banner_and_menu() {
    clear
    local timer_status="Not Installed"; local color_timer_status="$COLOR_YELLOW"
    local fail_count="0"; local last_run_status="N/A"; local color_last_run="$COLOR_YELLOW"
    local runs_24h="0"; local health_24h="N/A"; local next_run_left="N/A"

    if [ -f "$FAIL_COUNT_FILE" ]; then read -r fail_count < "$FAIL_COUNT_FILE"; fi

    if [ -f "/etc/systemd/system/${TIMER_NAME}" ]; then
        if systemctl is-active --quiet "$TIMER_NAME"; then
            timer_status="Active"; color_timer_status="$COLOR_GREEN"
            local timer_info=$(systemctl list-timers "$TIMER_NAME" --no-pager | grep "$TIMER_NAME")
            next_run_left=$(echo "$timer_info" | awk '{print $4, $5}')
        elif systemctl is-failed --quiet "$TIMER_NAME"; then
            timer_status="Failed"; color_timer_status="$COLOR_RED"
        else
            timer_status="Inactive"
        fi
        
        local journal_output=$(journalctl -u "$SERVICE_NAME" --since "24 hours ago" --no-pager --output=cat)
        if [ -n "$journal_output" ]; then
            runs_24h=$(echo "$journal_output" | grep -Fc "Starting Xray monitoring")
            local failed_runs=$(echo "$journal_output" | grep -Fc "IP check failed")
            local success_runs=$((runs_24h - failed_runs))

            if [ "$success_runs" -lt 0 ]; then success_runs=0; fi
            
            if [ "$runs_24h" -gt 0 ]; then
                health_24h=$(bc <<< "scale=1; ($success_runs * 100) / $runs_24h")
                health_24h="${health_24h}%"
            fi

            local last_run_log=$(echo "$journal_output" | grep "IP check" | tail -n 1)
            if echo "$last_run_log" | grep -q "successful"; then
                local ip=$(echo "$last_run_log" | awk -F': ' '{print $2}')
                last_run_status="Success (IP: ${ip})"
                color_last_run="$COLOR_GREEN"
            else
                local code=$(echo "$last_run_log" | grep -oP 'Code: \K[0-9]+')
                last_run_status="Failed (Code: ${code:-?})"
                color_last_run="$COLOR_RED"
            fi
        fi
    fi
    
    local BORDER_LINE="${COLOR_CYAN}=============================================================${NC}"
    echo -e "$BORDER_LINE"
    echo -e "${COLOR_CYAN}#                 Xray Monitoring Dashboard                 #${NC}"
    echo -e "$BORDER_LINE"
    printf "  ${COLOR_GREEN}%-20s${NC}: %b\n" "Status" "${color_timer_status}${timer_status}${NC}"
    printf "  ${COLOR_GREEN}%-20s${NC}: %b\n" "Next Run In" "${COLOR_YELLOW}${next_run_left:-N/A}${NC}"
    printf "  ${COLOR_GREEN}%-20s${NC}: %b\n" "Last Run Status" "${color_last_run}${last_run_status}${NC}"
    printf "  ${COLOR_GREEN}%-20s${NC}: %b\n" "Health (24h)" "${COLOR_GREEN}${health_24h:-N/A}${NC}"
    printf "  ${COLOR_GREEN}%-20s${NC}: %b\n" "Total Runs (24h)" "${COLOR_YELLOW}${runs_24h}${NC}"
    printf "  ${COLOR_GREEN}%-20s${NC}: %b\n" "Consecutive Fails" "${COLOR_RED}${fail_count}${NC}"
    echo -e "${COLOR_CYAN}-------------------------------------------------------------${NC}"
    echo -e "  ${COLOR_YELLOW}>>>${NC} ${CYAN}test.json${NC} must be in ${CYAN}$(dirname "$XRAY_BIN_PATH")/${NC}"
    echo -e "  >>> SOCKS test port is ${CYAN}${SOCKS_PROXY_PORT}${NC}. Ensure it's in your test.json"
    echo -e "$BORDER_LINE"
    echo ""
    echo "1) Install"
    echo "2) Modify Configuration"
    echo "3) Uninstall"
    echo "4) Start"
    echo "5) Stop"
    echo "6) Restart"
    echo "7) Test : Monitoring"
    echo "8) Test : Xray Log + IP Test"
    echo "9) Exit"
    echo "------------------------------------"
}


# --- Main Execution ---
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${COLOR_RED}This script must be run as root.${COLOR_NC}" >&2; exit 1;
    fi
    check_dependencies
    mkdir -p "$(dirname "${TELEGRAM_SEND_SCRIPT}")" 2>/dev/null
    if [ ! -f "${TELEGRAM_SEND_SCRIPT}" ]; then
        cat << TELEGRAM_EOF > "${TELEGRAM_SEND_SCRIPT}"
#!/bin/bash
BOT_TOKEN="\$1"; CHAT_ID="\$2"; MESSAGE_TEXT="\$3"
if [ -z "\$1" ] || [ -z "\$2" ] || [ -z "\$3" ]; then exit 1; fi
ENCODED_MESSAGE=\$(python3 -c "import urllib.parse;import sys;print(urllib.parse.quote_plus(sys.argv[1]))" "\${MESSAGE_TEXT}")
API_URL="https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage?chat_id=\${CHAT_ID}&text=\${ENCODED_MESSAGE}"
CURL_HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" "\${API_URL}")
if [ "\$?" -eq 0 ] && [ "\$CURL_HTTP_CODE" -eq 200 ]; then exit 0; else exit 1; fi
TELEGRAM_EOF
        chmod +x "${TELEGRAM_SEND_SCRIPT}";
    fi
    while true; do
        display_banner_and_menu
        read -p "Enter your choice (1-9): " CHOICE; clear
        case "$CHOICE" in
            1) install_monitor ;;
            2) modify_monitor ;;
            3) uninstall_monitor ;;
            4) start_monitor ;;
            5) stop_monitor ;;
            6) restart_monitor ;;
            7) run_monitor_once ;;
            8) run_debug_test ;;
            9) echo "Exiting script."; exit 0 ;;
            *) echo -e "${COLOR_RED}Invalid choice.${COLOR_NC}"; sleep 2 ;;
        esac
        if [[ "$CHOICE" =~ ^[1-8]$ ]]; then echo ""; read -p "Press Enter to return to main menu..."; fi
    done
}

main

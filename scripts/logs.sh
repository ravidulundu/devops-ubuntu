#!/bin/bash

# Log Viewer Script for WordPress Server Automation
# ================================================
# Description: Single command to view all system logs
# Usage: logs.sh [options] [log-type]
# Author: DevOps Ubuntu Team

set -euo pipefail

# Source utilities and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Source global configuration for paths
SKIP_DIR_CREATION=1 source "$SCRIPT_DIR/../config/global.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Default options
FOLLOW=false
LINES=50
SEARCH_TERM=""
LOG_TYPE="all"
SHOW_HELP=false

# Log file definitions with their paths and descriptions
declare -A LOG_FILES=(
    ["automation"]="${LOG_DIR}/automation.log|Main automation system log"
    ["monitoring"]="${LOG_DIR}/monitoring-alerts.log|Monitoring and alerting log"
    ["cloudflare"]="${LOG_DIR}/cloudflare.log|Cloudflare dynamic IP log"
    ["openlitespeed"]="/usr/local/lsws/logs/error.log|OpenLiteSpeed error log"
    ["openlitespeed-access"]="/usr/local/lsws/logs/access.log|OpenLiteSpeed access log"
    ["mysql"]="/var/log/mysql/error.log|MySQL/MariaDB error log"
    ["fail2ban"]="/var/log/fail2ban.log|Fail2ban security log"
    ["ufw"]="/var/log/ufw.log|UFW firewall log"
    ["auth"]="/var/log/auth.log|System authentication log"
    ["syslog"]="/var/log/syslog|System log"
    ["mail"]="/var/log/mail.log|Mail system log"
    ["cron"]="/var/log/cron.log|Cron job log"
)

# Usage information
show_usage() {
    cat << 'EOF'
Log Viewer - WordPress Server Automation

USAGE:
    wp-logs [OPTIONS] [LOG_TYPE]

LOG TYPES:
    all                 Show all available logs (default)
    automation          Main automation system log
    monitoring          Monitoring and alerts log
    cloudflare          Cloudflare dynamic IP log
    openlitespeed       OpenLiteSpeed error log
    openlitespeed-access OpenLiteSpeed access log
    mysql               MySQL/MariaDB error log
    fail2ban            Fail2ban security log
    ufw                 UFW firewall log
    auth                System authentication log
    syslog              System log
    mail                Mail system log
    cron                Cron job log

OPTIONS:
    -f, --follow        Follow log files (like tail -f)
    -n, --lines NUM     Show last NUM lines (default: 50)
    -s, --search TERM   Search for specific term in logs
    -l, --list          List all available logs
    -h, --help          Show this help message

EXAMPLES:
    wp-logs                         # Show last 50 lines of all logs
    wp-logs -f automation          # Follow automation log
    wp-logs -n 100 mysql           # Show last 100 lines of MySQL log
    wp-logs -s "error" all         # Search for "error" in all logs
    wp-logs --follow --search "fail"  # Follow all logs, highlight "fail"

ALIASES:
    wp-logs-follow = wp-logs -f all
    wp-logs-errors = wp-logs -s "error\|Error\|ERROR" all
    wp-logs-tail   = wp-logs -n 100 all
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--follow)
                FOLLOW=true
                shift
                ;;
            -n|--lines)
                LINES="$2"
                if ! [[ "$LINES" =~ ^[0-9]+$ ]]; then
                    log_error "Invalid number of lines: $LINES"
                    exit 1
                fi
                shift 2
                ;;
            -s|--search)
                SEARCH_TERM="$2"
                shift 2
                ;;
            -l|--list)
                list_logs
                exit 0
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                LOG_TYPE="$1"
                shift
                ;;
        esac
    done
}

# List all available logs
list_logs() {
    echo -e "${CYAN}Available Log Files:${NC}\n"
    
    printf "%-20s %-40s %s\n" "LOG TYPE" "DESCRIPTION" "STATUS"
    printf "%-20s %-40s %s\n" "--------" "-----------" "------"
    
    for log_type in "${!LOG_FILES[@]}"; do
        IFS='|' read -r log_path log_desc <<< "${LOG_FILES[$log_type]}"
        
        if [[ -f "$log_path" && -r "$log_path" ]]; then
            status="${GREEN}Available${NC}"
            size=$(stat -f%z "$log_path" 2>/dev/null || stat -c%s "$log_path" 2>/dev/null || echo "0")
            size_human=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")
            printf "%-20s %-40s %s (%s)\n" "$log_type" "$log_desc" "$status" "$size_human"
        else
            status="${RED}Missing${NC}"
            printf "%-20s %-40s %s\n" "$log_type" "$log_desc" "$status"
        fi
    done
}

# Show log header
show_log_header() {
    local log_type="$1"
    local log_path="$2"
    local log_desc="$3"
    
    echo -e "\n${CYAN}================================${NC}"
    echo -e "${WHITE}$log_desc${NC}"
    echo -e "${BLUE}File: $log_path${NC}"
    
    if [[ -f "$log_path" ]]; then
        local size=$(stat -f%z "$log_path" 2>/dev/null || stat -c%s "$log_path" 2>/dev/null || echo "0")
        local size_human=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")
        local mod_time=$(stat -f%Sm -t"%Y-%m-%d %H:%M:%S" "$log_path" 2>/dev/null || stat -c%y "$log_path" 2>/dev/null | cut -d. -f1 || echo "Unknown")
        echo -e "${BLUE}Size: $size_human | Modified: $mod_time${NC}"
    fi
    
    echo -e "${CYAN}================================${NC}"
}

# View a single log file
view_single_log() {
    local log_type="$1"
    
    if [[ ! "${LOG_FILES[$log_type]:-}" ]]; then
        log_error "Unknown log type: $log_type"
        echo "Use 'wp-logs --list' to see available logs"
        exit 1
    fi
    
    IFS='|' read -r log_path log_desc <<< "${LOG_FILES[$log_type]}"
    
    if [[ ! -f "$log_path" ]]; then
        log_warning "Log file not found: $log_path"
        return
    fi
    
    if [[ ! -r "$log_path" ]]; then
        log_error "Cannot read log file: $log_path (permission denied)"
        return
    fi
    
    show_log_header "$log_type" "$log_path" "$log_desc"
    
    # Build command based on options
    local cmd=""
    
    if [[ "$FOLLOW" == true ]]; then
        cmd="tail -f -n $LINES"
    else
        cmd="tail -n $LINES"
    fi
    
    # Add search highlighting if specified
    if [[ -n "$SEARCH_TERM" ]]; then
        if [[ "$FOLLOW" == true ]]; then
            $cmd "$log_path" | grep --color=always -i "$SEARCH_TERM" || true
        else
            $cmd "$log_path" | grep --color=always -i "$SEARCH_TERM" || echo -e "${YELLOW}No matches found for '$SEARCH_TERM'${NC}"
        fi
    else
        $cmd "$log_path"
    fi
}

# View all logs
view_all_logs() {
    if [[ "$FOLLOW" == true ]]; then
        log_info "Following all available logs (Ctrl+C to stop)..."
        echo -e "${YELLOW}Note: This shows all logs in real-time. Use 'wp-logs -f [specific-log]' for single log.${NC}\n"
        
        # Build array of existing log files
        local log_files=()
        for log_type in "${!LOG_FILES[@]}"; do
            IFS='|' read -r log_path log_desc <<< "${LOG_FILES[$log_type]}"
            if [[ -f "$log_path" && -r "$log_path" ]]; then
                log_files+=("$log_path")
            fi
        done
        
        if [[ ${#log_files[@]} -gt 0 ]]; then
            if [[ -n "$SEARCH_TERM" ]]; then
                tail -f -n "$LINES" "${log_files[@]}" | grep --color=always -i "$SEARCH_TERM" || true
            else
                tail -f -n "$LINES" "${log_files[@]}"
            fi
        else
            log_warning "No readable log files found"
        fi
    else
        # Show each log separately
        for log_type in automation monitoring cloudflare openlitespeed mysql fail2ban ufw auth; do
            if [[ "${LOG_FILES[$log_type]:-}" ]]; then
                IFS='|' read -r log_path log_desc <<< "${LOG_FILES[$log_type]}"
                if [[ -f "$log_path" && -r "$log_path" ]]; then
                    show_log_header "$log_type" "$log_path" "$log_desc"
                    
                    if [[ -n "$SEARCH_TERM" ]]; then
                        local matches=$(tail -n "$LINES" "$log_path" | grep -i "$SEARCH_TERM" | wc -l)
                        if [[ $matches -gt 0 ]]; then
                            tail -n "$LINES" "$log_path" | grep --color=always -i "$SEARCH_TERM"
                        else
                            echo -e "${YELLOW}No matches found for '$SEARCH_TERM'${NC}"
                        fi
                    else
                        tail -n "$LINES" "$log_path"
                    fi
                    echo
                fi
            fi
        done
    fi
}

# Main function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Show header
    echo -e "${CYAN}WordPress Server Automation - Log Viewer${NC}"
    echo -e "${BLUE}Installation: $INSTALL_TYPE | Log Directory: $LOG_DIR${NC}\n"
    
    # View logs based on type
    if [[ "$LOG_TYPE" == "all" ]]; then
        view_all_logs
    else
        view_single_log "$LOG_TYPE"
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash

# Monitoring & Logging Module for WordPress Server Automation
# ===========================================================
# Description: Collects resource, access, and threat logs; delivers alerts and monitoring
# Dependencies: System tools, email/telegram APIs, log analysis tools
# Author: DevOps Ubuntu Team

set -euo pipefail

# Source utilities and set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
LOGS_DIR="$SCRIPT_DIR/../logs"
source "$SCRIPT_DIR/../scripts/utils.sh"

# Module information
MODULE_NAME="Monitoring & Logging Module"
MODULE_VERSION="1.0.0"

log_info "Starting $MODULE_NAME v$MODULE_VERSION"

# Monitoring configuration variables
MONITORING_DIR="/usr/local/monitoring"
MONITORING_CONFIG_DIR="$CONFIG_DIR/monitoring"
MONITORING_LOG_DIR="$LOG_DIR/monitoring"
MONITORING_SCRIPTS_DIR="$MONITORING_DIR/scripts"
MONITORING_DATA_DIR="$MONITORING_DIR/data"

# Alert thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
LOAD_THRESHOLD=5.0
CONNECTION_THRESHOLD=1000

# Load monitoring configuration
load_monitoring_config() {
    log_info "Loading monitoring configuration..."
    
    mkdir -p "$MONITORING_DIR" "$MONITORING_CONFIG_DIR" "$MONITORING_LOG_DIR" 
    mkdir -p "$MONITORING_SCRIPTS_DIR" "$MONITORING_DATA_DIR"
    
    # Load notification settings
    if [[ -f "$CONFIG_DIR/notifications.conf" ]]; then
        source "$CONFIG_DIR/notifications.conf"
        log_debug "Loaded notification configuration"
    else
        log_info "Creating default notification configuration..."
        create_notification_config
    fi
}

# Create notification configuration
create_notification_config() {
    cat > "$CONFIG_DIR/notifications.conf" <<EOF
# Notification Configuration
EMAIL_NOTIFICATIONS=false
TELEGRAM_NOTIFICATIONS=false
WEBHOOK_NOTIFICATIONS=false

# Email Settings
SMTP_SERVER=""
SMTP_PORT=587
SMTP_USERNAME=""
SMTP_PASSWORD=""
ADMIN_EMAIL=""

# Telegram Settings  
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# Webhook Settings
WEBHOOK_URL=""

# Alert Settings
ENABLE_CPU_ALERTS=true
ENABLE_MEMORY_ALERTS=true
ENABLE_DISK_ALERTS=true
ENABLE_SECURITY_ALERTS=true
ENABLE_SERVICE_ALERTS=true

# Alert Intervals (in minutes)
ALERT_INTERVAL=15
CRITICAL_ALERT_INTERVAL=5
EOF
    
    chmod 600 "$CONFIG_DIR/notifications.conf"
    log_info "Default notification configuration created at $CONFIG_DIR/notifications.conf"
}

# Install monitoring tools
install_monitoring_tools() {
    log_info "Installing monitoring tools..."
    
    local monitoring_packages=(
        "htop"
        "iotop"
        "nethogs"
        "vnstat"
        "sysstat"
        "dstat"
        "ncdu"
        "tree"
        "jq"
        "bc"
        "mailutils"
        "curl"
    )
    
    for package in "${monitoring_packages[@]}"; do
        install_package "$package"
    done
    
    log_success "Monitoring tools installed successfully"
}

# Setup system monitoring
setup_system_monitoring() {
    log_info "Setting up system monitoring..."
    
    # Create system metrics collection script
    cat > "$MONITORING_SCRIPTS_DIR/collect-metrics.sh" <<'EOF'
#!/bin/bash

# System Metrics Collection Script
# Collects CPU, memory, disk, network and other system metrics

set -euo pipefail

METRICS_FILE="__MONITORING_DATA_DIR__/system-metrics.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create metrics JSON
cat > "$METRICS_FILE" <<EOJ
{
    "timestamp": "$TIMESTAMP",
    "hostname": "$(hostname)",
    "uptime": $(awk '{print $1}' /proc/uptime),
    "load": {
        "1min": $(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//'),
        "5min": $(uptime | awk -F'load average:' '{print $2}' | awk '{print $2}' | sed 's/,//'),
        "15min": $(uptime | awk -F'load average:' '{print $2}' | awk '{print $3}')
    },
    "cpu": {
        "usage": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//'),
        "cores": $(nproc)
    },
    "memory": {
        "total": $(free -m | awk 'NR==2{print $2}'),
        "used": $(free -m | awk 'NR==2{print $3}'),
        "free": $(free -m | awk 'NR==2{print $4}'),
        "available": $(free -m | awk 'NR==2{print $7}'),
        "usage_percent": $(free | awk 'NR==2{printf("%.2f"), $3*100/$2}')
    },
    "disk": {
        "root": {
            "total": "$(df -h / | awk 'NR==2{print $2}')",
            "used": "$(df -h / | awk 'NR==2{print $3}')",
            "available": "$(df -h / | awk 'NR==2{print $4}')",
            "usage_percent": $(df / | awk 'NR==2{print $5}' | sed 's/%//')
        }
    },
    "network": {
        "connections": $(netstat -ant | wc -l),
        "tcp_established": $(netstat -ant | grep ESTABLISHED | wc -l),
        "tcp_listen": $(netstat -ant | grep LISTEN | wc -l)
    },
    "processes": {
        "total": $(ps aux | wc -l),
        "running": $(ps aux | awk '$8 ~ /^R/ {count++} END {print count+0}'),
        "sleeping": $(ps aux | awk '$8 ~ /^S/ {count++} END {print count+0}'),
        "zombie": $(ps aux | awk '$8 ~ /^Z/ {count++} END {print count+0}')
    }
}
EOJ

# Save historical data
HISTORY_FILE="__MONITORING_DATA_DIR__/metrics-history.json"
if [[ -f "$HISTORY_FILE" ]]; then
    # Keep last 1440 entries (24 hours with 1-minute intervals)
    tail -n 1439 "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
    mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
fi

cat "$METRICS_FILE" >> "$HISTORY_FILE"
EOF

    # Replace placeholders
    sed -i "s|__MONITORING_DATA_DIR__|$MONITORING_DATA_DIR|g" "$MONITORING_SCRIPTS_DIR/collect-metrics.sh"
    
    chmod +x "$MONITORING_SCRIPTS_DIR/collect-metrics.sh"
    
    log_success "System monitoring setup completed"
}

# Setup service monitoring
setup_service_monitoring() {
    log_info "Setting up service monitoring..."
    
    # Create service monitoring script
    cat > "$MONITORING_SCRIPTS_DIR/check-services.sh" <<'EOF'
#!/bin/bash

# Service Health Check Script
# Monitors critical services and reports status

set -euo pipefail

SERVICES_FILE="__MONITORING_DATA_DIR__/services-status.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Services to monitor
SERVICES=(
    "lsws:OpenLiteSpeed"
    "mysql:MySQL/MariaDB"
    "redis-server:Redis"
    "memcached:Memcached"
    "fail2ban:Fail2ban"
    "ufw:UFW Firewall"
    "cron:Cron Daemon"
    "ssh:SSH Daemon"
)

SERVICE_STATUS="["
FIRST=true

for service_info in "${SERVICES[@]}"; do
    IFS=':' read -r service_name service_desc <<< "$service_info"
    
    if [[ "$FIRST" != true ]]; then
        SERVICE_STATUS+=","
    fi
    FIRST=false
    
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        status="running"
        pid=$(systemctl show -p MainPID --value "$service_name" 2>/dev/null || echo "unknown")
        memory=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1*1024}' || echo 0)
    else
        status="stopped"
        pid="null"
        memory=0
    fi
    
    SERVICE_STATUS+="{
        \"name\": \"$service_name\",
        \"description\": \"$service_desc\", 
        \"status\": \"$status\",
        \"pid\": $pid,
        \"memory_bytes\": $memory
    }"
done

SERVICE_STATUS+="]"

# Create services JSON
cat > "$SERVICES_FILE" <<EOJ
{
    "timestamp": "$TIMESTAMP",
    "hostname": "$(hostname)",
    "services": $SERVICE_STATUS
}
EOJ
EOF

    # Replace placeholders
    sed -i "s|__MONITORING_DATA_DIR__|$MONITORING_DATA_DIR|g" "$MONITORING_SCRIPTS_DIR/check-services.sh"
    
    chmod +x "$MONITORING_SCRIPTS_DIR/check-services.sh"
    
    log_success "Service monitoring setup completed"
}

# Setup log monitoring
setup_log_monitoring() {
    log_info "Setting up log monitoring..."
    
    # Create log analysis script
    cat > "$MONITORING_SCRIPTS_DIR/analyze-logs.sh" <<'EOF'
#!/bin/bash

# Log Analysis Script
# Analyzes system and application logs for issues

set -euo pipefail

LOG_ANALYSIS_FILE="__MONITORING_DATA_DIR__/log-analysis.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Log files to analyze
LOG_FILES=(
    "/var/log/auth.log:Authentication"
    "/var/log/syslog:System"
    "/usr/local/lsws/logs/error.log:OpenLiteSpeed Error"
    "/usr/local/lsws/logs/access.log:OpenLiteSpeed Access"
    "/var/log/mysql/error.log:MySQL Error"
    "/var/log/fail2ban.log:Fail2ban"
    "/var/log/ufw.log:UFW Firewall"
)

ANALYSIS_RESULTS="["
FIRST=true

for log_info in "${LOG_FILES[@]}"; do
    IFS=':' read -r log_file log_desc <<< "$log_info"
    
    if [[ "$FIRST" != true ]]; then
        ANALYSIS_RESULTS+=","
    fi
    FIRST=false
    
    if [[ -f "$log_file" ]]; then
        size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
        lines=$(wc -l < "$log_file" 2>/dev/null || echo 0)
        
        # Count errors in last hour
        errors=$(grep -c "$(date -d '1 hour ago' '+%Y-%m-%d %H')\|$(date '+%Y-%m-%d %H')" "$log_file" 2>/dev/null | grep -ci "error\|critical\|emergency\|alert" || echo 0)
        
        # Count warnings in last hour
        warnings=$(grep -c "$(date -d '1 hour ago' '+%Y-%m-%d %H')\|$(date '+%Y-%m-%d %H')" "$log_file" 2>/dev/null | grep -ci "warning\|warn" || echo 0)
        
        status="healthy"
        if [[ $errors -gt 10 ]]; then
            status="critical"
        elif [[ $errors -gt 5 ]] || [[ $warnings -gt 20 ]]; then
            status="warning"
        fi
        
    else
        size=0
        lines=0
        errors=0
        warnings=0
        status="missing"
    fi
    
    ANALYSIS_RESULTS+="{
        \"file\": \"$log_file\",
        \"description\": \"$log_desc\",
        \"size_bytes\": $size,
        \"total_lines\": $lines,
        \"errors_last_hour\": $errors,
        \"warnings_last_hour\": $warnings,
        \"status\": \"$status\"
    }"
done

ANALYSIS_RESULTS+="]"

# Create log analysis JSON
cat > "$LOG_ANALYSIS_FILE" <<EOJ
{
    "timestamp": "$TIMESTAMP",
    "hostname": "$(hostname)",
    "log_analysis": $ANALYSIS_RESULTS
}
EOJ
EOF

    # Replace placeholders
    sed -i "s|__MONITORING_DATA_DIR__|$MONITORING_DATA_DIR|g" "$MONITORING_SCRIPTS_DIR/analyze-logs.sh"
    
    chmod +x "$MONITORING_SCRIPTS_DIR/analyze-logs.sh"
    
    log_success "Log monitoring setup completed"
}

# Setup security monitoring
setup_security_monitoring() {
    log_info "Setting up security monitoring..."
    
    # Create security monitoring script
    cat > "$MONITORING_SCRIPTS_DIR/security-check.sh" <<'EOF'
#!/bin/bash

# Security Monitoring Script
# Monitors security events and potential threats

set -euo pipefail

SECURITY_FILE="__MONITORING_DATA_DIR__/security-status.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Check failed login attempts (last hour)
FAILED_LOGINS=$(grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')\|$(date '+%Y-%m-%d %H')" /var/log/auth.log 2>/dev/null | grep -c "Failed password" || echo 0)

# Check Fail2ban bans (last hour)
FAIL2BAN_BANS=$(grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')\|$(date '+%Y-%m-%d %H')" /var/log/fail2ban.log 2>/dev/null | grep -c "Ban " || echo 0)

# Check firewall blocks (last hour)  
UFW_BLOCKS=$(grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')\|$(date '+%Y-%m-%d %H')" /var/log/ufw.log 2>/dev/null | grep -c "BLOCK" || echo 0)

# Check unusual network connections
UNUSUAL_CONNECTIONS=$(netstat -ant | awk '$6 == "ESTABLISHED" {print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10)

# Check root logins (last hour)
ROOT_LOGINS=$(grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')\|$(date '+%Y-%m-%d %H')" /var/log/auth.log 2>/dev/null | grep -c "session opened for user root" || echo 0)

# Check WordPress brute force attempts (if log exists)
WP_ATTACKS=0
if [[ -f "/usr/local/lsws/logs/access.log" ]]; then
    WP_ATTACKS=$(grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')\|$(date '+%Y-%m-%d %H')" /usr/local/lsws/logs/access.log 2>/dev/null | grep -c "wp-login.php" || echo 0)
fi

# Determine security status
SECURITY_STATUS="normal"
if [[ $FAILED_LOGINS -gt 50 ]] || [[ $FAIL2BAN_BANS -gt 10 ]] || [[ $ROOT_LOGINS -gt 5 ]]; then
    SECURITY_STATUS="critical"
elif [[ $FAILED_LOGINS -gt 20 ]] || [[ $FAIL2BAN_BANS -gt 5 ]] || [[ $UFW_BLOCKS -gt 100 ]]; then
    SECURITY_STATUS="warning"
fi

# Create security JSON
cat > "$SECURITY_FILE" <<EOJ
{
    "timestamp": "$TIMESTAMP",
    "hostname": "$(hostname)",
    "security_status": "$SECURITY_STATUS",
    "metrics": {
        "failed_logins_last_hour": $FAILED_LOGINS,
        "fail2ban_bans_last_hour": $FAIL2BAN_BANS,
        "ufw_blocks_last_hour": $UFW_BLOCKS,
        "root_logins_last_hour": $ROOT_LOGINS,
        "wp_attacks_last_hour": $WP_ATTACKS
    },
    "active_connections": $(netstat -ant | grep ESTABLISHED | wc -l),
    "listening_ports": [$(netstat -tln | awk 'NR>2 {gsub(/.*:/, "", $4); print $4}' | sort -n | uniq | paste -sd "," -)]
}
EOJ
EOF

    # Replace placeholders
    sed -i "s|__MONITORING_DATA_DIR__|$MONITORING_DATA_DIR|g" "$MONITORING_SCRIPTS_DIR/security-check.sh"
    
    chmod +x "$MONITORING_SCRIPTS_DIR/security-check.sh"
    
    log_success "Security monitoring setup completed"
}

# Setup alert system
setup_alert_system() {
    log_info "Setting up alert system..."
    
    # Create alert processing script
    cat > "$MONITORING_SCRIPTS_DIR/process-alerts.sh" <<'EOF'
#!/bin/bash

# Alert Processing Script
# Processes monitoring data and sends alerts when thresholds are exceeded

set -euo pipefail

# Source configuration
CONFIG_FILE="__CONFIG_DIR__/notifications.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

ALERT_LOG="/var/log/monitoring-alerts.log"
LAST_ALERT_FILE="__MONITORING_DATA_DIR__/last-alert-times.txt"

# Initialize last alert file
touch "$LAST_ALERT_FILE"

log_alert() {
    local level=$1
    local message=$2
    echo "[$(date)] [$level] $message" >> "$ALERT_LOG"
}

send_email_alert() {
    local subject=$1
    local message=$2
    
    if [[ "$EMAIL_NOTIFICATIONS" == "true" && -n "${ADMIN_EMAIL:-}" ]]; then
        echo "$message" | mail -s "$subject" "$ADMIN_EMAIL" 2>/dev/null || log_alert "ERROR" "Failed to send email alert"
    fi
}

send_telegram_alert() {
    local message=$1
    
    if [[ "$TELEGRAM_NOTIFICATIONS" == "true" && -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="$message" \
            -d parse_mode="HTML" >/dev/null 2>&1 || log_alert "ERROR" "Failed to send Telegram alert"
    fi
}

should_send_alert() {
    local alert_type=$1
    local current_time=$(date +%s)
    local last_alert_time=$(grep "^$alert_type:" "$LAST_ALERT_FILE" 2>/dev/null | cut -d: -f2 || echo 0)
    local interval=${ALERT_INTERVAL:-15}
    
    if [[ $alert_type == *"CRITICAL"* ]]; then
        interval=${CRITICAL_ALERT_INTERVAL:-5}
    fi
    
    local time_diff=$((current_time - last_alert_time))
    local min_interval=$((interval * 60))
    
    if [[ $time_diff -gt $min_interval ]]; then
        # Update last alert time
        grep -v "^$alert_type:" "$LAST_ALERT_FILE" > "${LAST_ALERT_FILE}.tmp" 2>/dev/null || true
        echo "$alert_type:$current_time" >> "${LAST_ALERT_FILE}.tmp"
        mv "${LAST_ALERT_FILE}.tmp" "$LAST_ALERT_FILE"
        return 0
    fi
    
    return 1
}

# Process system metrics
METRICS_FILE="__MONITORING_DATA_DIR__/system-metrics.json"
if [[ -f "$METRICS_FILE" ]]; then
    CPU_USAGE=$(jq -r '.cpu.usage' "$METRICS_FILE" 2>/dev/null || echo 0)
    MEMORY_USAGE=$(jq -r '.memory.usage_percent' "$METRICS_FILE" 2>/dev/null || echo 0)
    DISK_USAGE=$(jq -r '.disk.root.usage_percent' "$METRICS_FILE" 2>/dev/null || echo 0)
    LOAD_1MIN=$(jq -r '.load."1min"' "$METRICS_FILE" 2>/dev/null || echo 0)
    
    # CPU Alert
    if (( $(echo "$CPU_USAGE > __CPU_THRESHOLD__" | bc -l) )) && should_send_alert "CPU_HIGH"; then
        ALERT_MSG="⚠️ <b>HIGH CPU USAGE ALERT</b>

🖥️ Server: $(hostname)
📊 CPU Usage: ${CPU_USAGE}%
🎯 Threshold: __CPU_THRESHOLD__%
⏰ Time: $(date)

Please check server performance immediately."
        
        send_email_alert "High CPU Usage Alert - $(hostname)" "$ALERT_MSG"
        send_telegram_alert "$ALERT_MSG"
        log_alert "WARNING" "High CPU usage: ${CPU_USAGE}%"
    fi
    
    # Memory Alert
    if (( $(echo "$MEMORY_USAGE > __MEMORY_THRESHOLD__" | bc -l) )) && should_send_alert "MEMORY_HIGH"; then
        ALERT_MSG="⚠️ <b>HIGH MEMORY USAGE ALERT</b>

🖥️ Server: $(hostname)
📊 Memory Usage: ${MEMORY_USAGE}%
🎯 Threshold: __MEMORY_THRESHOLD__%
⏰ Time: $(date)

Please check memory consumption immediately."
        
        send_email_alert "High Memory Usage Alert - $(hostname)" "$ALERT_MSG"
        send_telegram_alert "$ALERT_MSG"
        log_alert "WARNING" "High memory usage: ${MEMORY_USAGE}%"
    fi
    
    # Disk Alert
    if (( $(echo "$DISK_USAGE > __DISK_THRESHOLD__" | bc -l) )) && should_send_alert "DISK_HIGH"; then
        ALERT_MSG="🚨 <b>HIGH DISK USAGE ALERT</b>

🖥️ Server: $(hostname)
💾 Disk Usage: ${DISK_USAGE}%
🎯 Threshold: __DISK_THRESHOLD__%
⏰ Time: $(date)

⚠️ Critical: Please free up disk space immediately!"
        
        send_email_alert "CRITICAL: High Disk Usage Alert - $(hostname)" "$ALERT_MSG"
        send_telegram_alert "$ALERT_MSG"
        log_alert "CRITICAL" "High disk usage: ${DISK_USAGE}%"
    fi
fi

# Process security alerts
SECURITY_FILE="__MONITORING_DATA_DIR__/security-status.json"
if [[ -f "$SECURITY_FILE" ]]; then
    SECURITY_STATUS=$(jq -r '.security_status' "$SECURITY_FILE" 2>/dev/null || echo "unknown")
    FAILED_LOGINS=$(jq -r '.metrics.failed_logins_last_hour' "$SECURITY_FILE" 2>/dev/null || echo 0)
    
    if [[ "$SECURITY_STATUS" == "critical" ]] && should_send_alert "SECURITY_CRITICAL"; then
        ALERT_MSG="🚨 <b>CRITICAL SECURITY ALERT</b>

🖥️ Server: $(hostname)
🛡️ Status: CRITICAL
🚫 Failed Logins (1h): $FAILED_LOGINS
⏰ Time: $(date)

⚠️ Potential security breach detected!"
        
        send_email_alert "CRITICAL: Security Alert - $(hostname)" "$ALERT_MSG"
        send_telegram_alert "$ALERT_MSG"
        log_alert "CRITICAL" "Security status: $SECURITY_STATUS"
    fi
fi

# Process service alerts
SERVICES_FILE="__MONITORING_DATA_DIR__/services-status.json"
if [[ -f "$SERVICES_FILE" ]]; then
    STOPPED_SERVICES=$(jq -r '.services[] | select(.status == "stopped") | .name' "$SERVICES_FILE" 2>/dev/null || echo "")
    
    if [[ -n "$STOPPED_SERVICES" ]] && should_send_alert "SERVICES_DOWN"; then
        ALERT_MSG="🚨 <b>SERVICES DOWN ALERT</b>

🖥️ Server: $(hostname)
🔴 Stopped Services:
$(echo "$STOPPED_SERVICES" | sed 's/^/• /')
⏰ Time: $(date)

Please restart the services immediately!"
        
        send_email_alert "Services Down Alert - $(hostname)" "$ALERT_MSG"
        send_telegram_alert "$ALERT_MSG"
        log_alert "CRITICAL" "Services down: $STOPPED_SERVICES"
    fi
fi
EOF

    # Replace placeholders
    sed -i "s|__CONFIG_DIR__|$CONFIG_DIR|g" "$MONITORING_SCRIPTS_DIR/process-alerts.sh"
    sed -i "s|__MONITORING_DATA_DIR__|$MONITORING_DATA_DIR|g" "$MONITORING_SCRIPTS_DIR/process-alerts.sh"
    sed -i "s|__CPU_THRESHOLD__|$CPU_THRESHOLD|g" "$MONITORING_SCRIPTS_DIR/process-alerts.sh"
    sed -i "s|__MEMORY_THRESHOLD__|$MEMORY_THRESHOLD|g" "$MONITORING_SCRIPTS_DIR/process-alerts.sh"
    sed -i "s|__DISK_THRESHOLD__|$DISK_THRESHOLD|g" "$MONITORING_SCRIPTS_DIR/process-alerts.sh"
    
    chmod +x "$MONITORING_SCRIPTS_DIR/process-alerts.sh"
    
    log_success "Alert system setup completed"
}

# Setup monitoring dashboard
setup_monitoring_dashboard() {
    log_info "Setting up monitoring dashboard..."
    
    # Create dashboard script
    cat > "$MONITORING_SCRIPTS_DIR/dashboard.sh" <<'EOF'
#!/bin/bash

# Monitoring Dashboard Script
# Displays real-time system status in a formatted view

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

clear

show_header() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  WordPress Server Monitoring Dashboard${NC}"
    echo -e "${CYAN}  Server: $(hostname) | $(date)${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo
}

show_system_status() {
    echo -e "${WHITE}System Status:${NC}"
    
    # Load metrics if available
    METRICS_FILE="__MONITORING_DATA_DIR__/system-metrics.json"
    if [[ -f "$METRICS_FILE" ]]; then
        CPU_USAGE=$(jq -r '.cpu.usage' "$METRICS_FILE" 2>/dev/null || echo "N/A")
        MEMORY_USAGE=$(jq -r '.memory.usage_percent' "$METRICS_FILE" 2>/dev/null || echo "N/A")
        DISK_USAGE=$(jq -r '.disk.root.usage_percent' "$METRICS_FILE" 2>/dev/null || echo "N/A")
        LOAD_1MIN=$(jq -r '.load."1min"' "$METRICS_FILE" 2>/dev/null || echo "N/A")
        CONNECTIONS=$(jq -r '.network.connections' "$METRICS_FILE" 2>/dev/null || echo "N/A")
    else
        CPU_USAGE="N/A"
        MEMORY_USAGE="N/A" 
        DISK_USAGE="N/A"
        LOAD_1MIN="N/A"
        CONNECTIONS="N/A"
    fi
    
    # Color code based on thresholds
    if [[ "$CPU_USAGE" != "N/A" ]] && (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
        CPU_COLOR="$RED"
    elif [[ "$CPU_USAGE" != "N/A" ]] && (( $(echo "$CPU_USAGE > 60" | bc -l) )); then
        CPU_COLOR="$YELLOW"
    else
        CPU_COLOR="$GREEN"
    fi
    
    if [[ "$MEMORY_USAGE" != "N/A" ]] && (( $(echo "$MEMORY_USAGE > 85" | bc -l) )); then
        MEM_COLOR="$RED"
    elif [[ "$MEMORY_USAGE" != "N/A" ]] && (( $(echo "$MEMORY_USAGE > 70" | bc -l) )); then
        MEM_COLOR="$YELLOW"
    else
        MEM_COLOR="$GREEN"
    fi
    
    if [[ "$DISK_USAGE" != "N/A" ]] && (( $(echo "$DISK_USAGE > 90" | bc -l) )); then
        DISK_COLOR="$RED"
    elif [[ "$DISK_USAGE" != "N/A" ]] && (( $(echo "$DISK_USAGE > 75" | bc -l) )); then
        DISK_COLOR="$YELLOW"
    else
        DISK_COLOR="$GREEN"
    fi
    
    echo -e "  ${CPU_COLOR}CPU Usage: ${CPU_USAGE}%${NC}"
    echo -e "  ${MEM_COLOR}Memory Usage: ${MEMORY_USAGE}%${NC}"
    echo -e "  ${DISK_COLOR}Disk Usage: ${DISK_USAGE}%${NC}"
    echo -e "  ${BLUE}Load Average: ${LOAD_1MIN}${NC}"
    echo -e "  ${PURPLE}Active Connections: ${CONNECTIONS}${NC}"
    echo
}

show_service_status() {
    echo -e "${WHITE}Service Status:${NC}"
    
    SERVICES_FILE="__MONITORING_DATA_DIR__/services-status.json"
    if [[ -f "$SERVICES_FILE" ]]; then
        # Parse services status
        jq -r '.services[] | "\(.name):\(.status)"' "$SERVICES_FILE" 2>/dev/null | while IFS=: read -r service status; do
            if [[ "$status" == "running" ]]; then
                echo -e "  ${GREEN}✓${NC} $service: Running"
            else
                echo -e "  ${RED}✗${NC} $service: Stopped"
            fi
        done
    else
        echo -e "  ${YELLOW}Service status data not available${NC}"
    fi
    echo
}

show_security_status() {
    echo -e "${WHITE}Security Status:${NC}"
    
    SECURITY_FILE="__MONITORING_DATA_DIR__/security-status.json"
    if [[ -f "$SECURITY_FILE" ]]; then
        SECURITY_STATUS=$(jq -r '.security_status' "$SECURITY_FILE" 2>/dev/null || echo "unknown")
        FAILED_LOGINS=$(jq -r '.metrics.failed_logins_last_hour' "$SECURITY_FILE" 2>/dev/null || echo "0")
        FAIL2BAN_BANS=$(jq -r '.metrics.fail2ban_bans_last_hour' "$SECURITY_FILE" 2>/dev/null || echo "0")
        
        case "$SECURITY_STATUS" in
            "normal")
                echo -e "  ${GREEN}✓${NC} Security Status: Normal"
                ;;
            "warning")
                echo -e "  ${YELLOW}⚠${NC} Security Status: Warning"
                ;;
            "critical")
                echo -e "  ${RED}🚨${NC} Security Status: Critical"
                ;;
            *)
                echo -e "  ${YELLOW}?${NC} Security Status: Unknown"
                ;;
        esac
        
        echo -e "  Failed Logins (1h): $FAILED_LOGINS"
        echo -e "  Fail2ban Bans (1h): $FAIL2BAN_BANS"
    else
        echo -e "  ${YELLOW}Security data not available${NC}"
    fi
    echo
}

show_recent_alerts() {
    echo -e "${WHITE}Recent Alerts (Last 24h):${NC}"
    
    if [[ -f "/var/log/monitoring-alerts.log" ]]; then
        tail -n 20 "/var/log/monitoring-alerts.log" | head -n 10 | while read -r line; do
            if echo "$line" | grep -q "CRITICAL"; then
                echo -e "  ${RED}$line${NC}"
            elif echo "$line" | grep -q "WARNING"; then
                echo -e "  ${YELLOW}$line${NC}"
            else
                echo -e "  $line"
            fi
        done
    else
        echo -e "  ${GREEN}No recent alerts${NC}"
    fi
    echo
}

# Main dashboard display
show_header
show_system_status
show_service_status
show_security_status
show_recent_alerts

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}  Dashboard updated: $(date)${NC}"
echo -e "${CYAN}  Use 'watch -n 30 $0' for auto-refresh${NC}"
echo -e "${CYAN}================================================================${NC}"
EOF

    # Replace placeholders
    sed -i "s|__MONITORING_DATA_DIR__|$MONITORING_DATA_DIR|g" "$MONITORING_SCRIPTS_DIR/dashboard.sh"
    
    chmod +x "$MONITORING_SCRIPTS_DIR/dashboard.sh"
    
    # Create convenient alias
    cat > "/usr/local/bin/server-dashboard" <<EOF
#!/bin/bash
$MONITORING_SCRIPTS_DIR/dashboard.sh "\$@"
EOF
    
    chmod +x "/usr/local/bin/server-dashboard"
    
    log_success "Monitoring dashboard setup completed"
}

# Setup cron jobs for monitoring
setup_monitoring_cron() {
    log_info "Setting up monitoring cron jobs..."
    
    # Create main monitoring cron job
    cat > "/etc/cron.d/server-monitoring" <<EOF
# Server Monitoring Cron Jobs
# Collects metrics, checks services, and processes alerts

# Collect system metrics every minute
* * * * * root $MONITORING_SCRIPTS_DIR/collect-metrics.sh >/dev/null 2>&1

# Check services every 2 minutes  
*/2 * * * * root $MONITORING_SCRIPTS_DIR/check-services.sh >/dev/null 2>&1

# Analyze logs every 5 minutes
*/5 * * * * root $MONITORING_SCRIPTS_DIR/analyze-logs.sh >/dev/null 2>&1

# Security check every 5 minutes
*/5 * * * * root $MONITORING_SCRIPTS_DIR/security-check.sh >/dev/null 2>&1

# Process alerts every 5 minutes
*/5 * * * * root $MONITORING_SCRIPTS_DIR/process-alerts.sh >/dev/null 2>&1

# Cleanup old monitoring data daily at 3 AM
0 3 * * * root find $MONITORING_DATA_DIR -name "*.json" -mtime +7 -delete >/dev/null 2>&1
EOF
    
    log_success "Monitoring cron jobs configured"
}

# Create monitoring summary
create_monitoring_summary() {
    local summary_file="$LOG_DIR/monitoring_summary.txt"
    
    cat > "$summary_file" <<EOF
WordPress Server Automation - Monitoring Module Summary
=======================================================
Configuration Date: $(date)

Monitoring Configuration:
- Monitoring Directory: $MONITORING_DIR
- Scripts Directory: $MONITORING_SCRIPTS_DIR
- Data Directory: $MONITORING_DATA_DIR
- Log Directory: $MONITORING_LOG_DIR

Monitoring Components:
1. System Metrics Collection
   - CPU usage monitoring
   - Memory usage tracking
   - Disk space monitoring
   - Network connection tracking
   - Load average monitoring
   - Process monitoring

2. Service Health Monitoring
   - OpenLiteSpeed status
   - MySQL/MariaDB status
   - Redis status
   - Fail2ban status
   - UFW Firewall status
   - Critical system services

3. Log Analysis
   - Authentication logs
   - System logs
   - Web server logs
   - Database logs
   - Security logs
   - Error pattern detection

4. Security Monitoring
   - Failed login attempts
   - Brute force detection
   - Firewall blocks
   - Unusual connections
   - Root access monitoring
   - WordPress attack detection

5. Alert System
   - Email notifications: ${EMAIL_NOTIFICATIONS:-false}
   - Telegram notifications: ${TELEGRAM_NOTIFICATIONS:-false}
   - Webhook notifications: ${WEBHOOK_NOTIFICATIONS:-false}

Alert Thresholds:
- CPU Usage: ${CPU_THRESHOLD}%
- Memory Usage: ${MEMORY_THRESHOLD}%
- Disk Usage: ${DISK_THRESHOLD}%
- Load Average: ${LOAD_THRESHOLD}
- Active Connections: ${CONNECTION_THRESHOLD}

Monitoring Scripts:
- collect-metrics.sh: System metrics collection (every 1 minute)
- check-services.sh: Service health checks (every 2 minutes)
- analyze-logs.sh: Log analysis (every 5 minutes)
- security-check.sh: Security monitoring (every 5 minutes)
- process-alerts.sh: Alert processing (every 5 minutes)
- dashboard.sh: Real-time dashboard display

Management Commands:
- server-dashboard: View real-time monitoring dashboard
- watch -n 30 server-dashboard: Auto-refreshing dashboard
- tail -f /var/log/monitoring-alerts.log: View alerts log

Data Files:
- System Metrics: $MONITORING_DATA_DIR/system-metrics.json
- Service Status: $MONITORING_DATA_DIR/services-status.json
- Security Status: $MONITORING_DATA_DIR/security-status.json
- Log Analysis: $MONITORING_DATA_DIR/log-analysis.json
- Historical Data: $MONITORING_DATA_DIR/metrics-history.json

Log Files:
- Alert Log: /var/log/monitoring-alerts.log
- Module Logs: $LOG_DIR/monitoring/

Configuration:
- Edit notification settings: $CONFIG_DIR/notifications.conf
- Customize thresholds in monitoring scripts
- Add/remove services in check-services.sh

Next Steps:
1. Configure notification settings in $CONFIG_DIR/notifications.conf
2. Test alert system with: $MONITORING_SCRIPTS_DIR/process-alerts.sh
3. View dashboard with: server-dashboard
4. Setup dynamic tuning: ./master.sh dynamic-tuning

Installation Status: Completed Successfully
EOF

    log_info "Monitoring summary saved to: $summary_file"
}

# Main monitoring function
main() {
    log_info "=== Starting Monitoring & Logging Setup ==="
    
    # Load configuration
    load_monitoring_config
    
    # Install monitoring tools
    install_monitoring_tools
    
    # Setup monitoring components
    setup_system_monitoring
    setup_service_monitoring
    setup_log_monitoring
    setup_security_monitoring
    setup_alert_system
    setup_monitoring_dashboard
    
    # Setup cron jobs
    setup_monitoring_cron
    
    # Run initial data collection
    log_info "Running initial monitoring data collection..."
    execute_command "$MONITORING_SCRIPTS_DIR/collect-metrics.sh" "Collecting initial system metrics"
    execute_command "$MONITORING_SCRIPTS_DIR/check-services.sh" "Checking service status"
    execute_command "$MONITORING_SCRIPTS_DIR/analyze-logs.sh" "Analyzing logs"
    execute_command "$MONITORING_SCRIPTS_DIR/security-check.sh" "Running security check"
    
    # Create summary
    create_monitoring_summary
    
    log_success "=== Monitoring & Logging setup completed successfully! ==="
    log_info "Check $LOG_DIR/monitoring_summary.txt for configuration details"
    log_info "Run 'server-dashboard' to view the monitoring dashboard"
    
    # Show dashboard once
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        "$MONITORING_SCRIPTS_DIR/dashboard.sh"
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
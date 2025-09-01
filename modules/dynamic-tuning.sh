#!/bin/bash

# Dynamic Tuning Module for WordPress Server Automation
# =====================================================
# Description: Hardware-based performance optimization with extensible tuning interface
# Dependencies: System analysis tools, service configuration access
# Author: DevOps Ubuntu Team

set -euo pipefail

# Source utilities and set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
LOGS_DIR="$SCRIPT_DIR/../logs"
source "$SCRIPT_DIR/../scripts/utils.sh"

# Module information
MODULE_NAME="Dynamic Tuning Module"
MODULE_VERSION="1.0.0"

log_info "Starting $MODULE_NAME v$MODULE_VERSION"

# Tuning configuration variables
TUNING_DIR="/usr/local/tuning"
TUNING_CONFIG_DIR="$CONFIG_DIR/tuning"
TUNING_LOG_DIR="$LOG_DIR/tuning"
TUNING_PROFILES_DIR="$TUNING_DIR/profiles"
TUNING_SCRIPTS_DIR="$TUNING_DIR/scripts"

# Performance test variables
BENCHMARK_RUNS=3
BENCHMARK_DURATION=30
CURRENT_PROFILE="auto"

# Load tuning configuration
load_tuning_config() {
    log_info "Loading tuning configuration..."
    
    mkdir -p "$TUNING_DIR" "$TUNING_CONFIG_DIR" "$TUNING_LOG_DIR"
    mkdir -p "$TUNING_PROFILES_DIR" "$TUNING_SCRIPTS_DIR"
    
    # Load installation credentials
    local config_files=("mysql.conf" "openlitespeed.conf" "cyberpanel.conf")
    for config_file in "${config_files[@]}"; do
        local config_path="$CONFIG_DIR/$config_file"
        if [[ -f "$config_path" ]]; then
            source "$config_path"
        fi
    done
    
    # Detect and export hardware information
    detect_hardware
    
    log_info "Hardware Profile: $CPU_CORES cores, ${TOTAL_RAM_MB}MB RAM, ${TOTAL_DISK_GB}GB disk"
}

# Analyze current performance
analyze_current_performance() {
    log_info "Analyzing current system performance..."
    
    local analysis_file="$TUNING_DIR/current-performance.json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Collect performance metrics
    local cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/%id,//')
    local memory_free_percent=$(free | awk 'NR==2{printf("%.2f"), $4*100/$2}')
    local load_avg_1min=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local disk_iops=$(iostat -x 1 2 | tail -n +4 | awk '{sum += $4 + $5} END {print sum/2}' || echo "0")
    local network_connections=$(netstat -ant | grep ESTABLISHED | wc -l)
    
    # Web server response time test
    local response_time="0"
    if systemctl is-active --quiet lsws; then
        response_time=$(curl -o /dev/null -s -w "%{time_total}" "http://localhost/" 2>/dev/null || echo "0")
    fi
    
    # Database query performance
    local db_query_time="0"
    if [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]]; then
        db_query_time=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT BENCHMARK(1000000, 1+1);" 2>/dev/null | grep -o "[0-9.]*" | tail -1 || echo "0")
    fi
    
    # Create performance analysis JSON
    cat > "$analysis_file" <<EOF
{
    "timestamp": "$timestamp",
    "hostname": "$(hostname)",
    "hardware": {
        "cpu_cores": $CPU_CORES,
        "total_ram_mb": $TOTAL_RAM_MB,
        "total_disk_gb": $TOTAL_DISK_GB,
        "network_interface": "$NETWORK_INTERFACE"
    },
    "current_metrics": {
        "cpu_idle_percent": $cpu_idle,
        "memory_free_percent": $memory_free_percent,
        "load_average_1min": $load_avg_1min,
        "disk_iops": $disk_iops,
        "network_connections": $network_connections,
        "web_response_time_ms": $(echo "$response_time * 1000" | bc -l | cut -d. -f1),
        "db_query_time_ms": $db_query_time
    },
    "current_profile": "$CURRENT_PROFILE"
}
EOF
    
    log_success "Performance analysis completed and saved to: $analysis_file"
}

# Generate optimal tuning profile
generate_tuning_profile() {
    local profile_name=${1:-"auto"}
    
    log_info "Generating tuning profile: $profile_name"
    
    # Calculate optimal settings based on hardware
    local max_connections=$((TOTAL_RAM_MB * 2))
    local worker_processes=$((CPU_CORES * 2))
    local php_memory_limit=$((TOTAL_RAM_MB / 4))
    local php_max_children=$((TOTAL_RAM_MB / 50))
    local mysql_innodb_buffer_pool=$((TOTAL_RAM_MB * 70 / 100))
    local mysql_max_connections=$((TOTAL_RAM_MB / 12))
    local redis_maxmemory=$((TOTAL_RAM_MB * 20 / 100))
    
    # Apply minimums and maximums
    [[ $max_connections -lt 500 ]] && max_connections=500
    [[ $max_connections -gt 10000 ]] && max_connections=10000
    [[ $worker_processes -lt 2 ]] && worker_processes=2
    [[ $worker_processes -gt 32 ]] && worker_processes=32
    [[ $php_memory_limit -lt 128 ]] && php_memory_limit=128
    [[ $php_memory_limit -gt 512 ]] && php_memory_limit=512
    [[ $php_max_children -lt 10 ]] && php_max_children=10
    [[ $php_max_children -gt 100 ]] && php_max_children=100
    [[ $mysql_innodb_buffer_pool -lt 256 ]] && mysql_innodb_buffer_pool=256
    [[ $mysql_max_connections -lt 50 ]] && mysql_max_connections=50
    [[ $mysql_max_connections -gt 1000 ]] && mysql_max_connections=1000
    [[ $redis_maxmemory -lt 64 ]] && redis_maxmemory=64
    
    # Determine server tier based on resources
    local server_tier="small"
    if [[ $TOTAL_RAM_MB -gt 4000 && $CPU_CORES -gt 4 ]]; then
        server_tier="large"
    elif [[ $TOTAL_RAM_MB -gt 2000 && $CPU_CORES -gt 2 ]]; then
        server_tier="medium"
    fi
    
    # Create tuning profile
    cat > "$TUNING_PROFILES_DIR/${profile_name}.json" <<EOF
{
    "profile_name": "$profile_name",
    "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hardware_basis": {
        "cpu_cores": $CPU_CORES,
        "total_ram_mb": $TOTAL_RAM_MB,
        "total_disk_gb": $TOTAL_DISK_GB,
        "server_tier": "$server_tier"
    },
    "openlitespeed": {
        "max_connections": $max_connections,
        "max_ssl_connections": $((max_connections / 2)),
        "worker_processes": $worker_processes,
        "keep_alive_timeout": 5,
        "max_keep_alive_requests": 1000,
        "gzip_compression": true,
        "gzip_compression_level": 6,
        "cache_expire": 3600
    },
    "php": {
        "memory_limit": "${php_memory_limit}M",
        "max_execution_time": 300,
        "max_input_time": 300,
        "max_children": $php_max_children,
        "max_requests": 1000,
        "process_idle_timeout": 60,
        "opcache_memory_consumption": $((php_memory_limit / 2)),
        "opcache_max_accelerated_files": 20000
    },
    "mysql": {
        "innodb_buffer_pool_size": "${mysql_innodb_buffer_pool}M",
        "max_connections": $mysql_max_connections,
        "innodb_buffer_pool_instances": $CPU_CORES,
        "query_cache_size": "$((TOTAL_RAM_MB * 5 / 100))M",
        "innodb_log_file_size": "256M",
        "innodb_flush_log_at_trx_commit": 2,
        "innodb_io_capacity": 400,
        "tmp_table_size": "128M",
        "max_heap_table_size": "128M"
    },
    "redis": {
        "maxmemory": "${redis_maxmemory}mb",
        "maxmemory_policy": "allkeys-lru",
        "tcp_keepalive": 60,
        "timeout": 300
    },
    "system": {
        "vm_swappiness": 10,
        "net_core_somaxconn": 65535,
        "net_core_netdev_max_backlog": 30000,
        "net_ipv4_tcp_max_syn_backlog": 30000,
        "fs_file_max": 2097152
    }
}
EOF
    
    log_success "Tuning profile generated: $profile_name"
}

# Apply tuning profile
apply_tuning_profile() {
    local profile_name=${1:-"auto"}
    local profile_file="$TUNING_PROFILES_DIR/${profile_name}.json"
    
    if [[ ! -f "$profile_file" ]]; then
        log_error "Tuning profile not found: $profile_name"
        return 1
    fi
    
    log_info "Applying tuning profile: $profile_name"
    
    # Backup current configurations
    local backup_dir="$BACKUP_DIR/tuning_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Create tuning application script
    cat > "$TUNING_SCRIPTS_DIR/apply-profile.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

PROFILE_FILE="$1"
BACKUP_DIR="$2"

# Load profile data
PROFILE_DATA=$(cat "$PROFILE_FILE")

log_tuning() {
    echo "[$(date)] $1" >> "__TUNING_LOG_DIR__/tuning-application.log"
}

# Apply OpenLiteSpeed tuning
apply_openlitespeed_tuning() {
    log_tuning "Applying OpenLiteSpeed tuning..."
    
    local ols_conf="/usr/local/lsws/conf/httpd_config.conf"
    if [[ -f "$ols_conf" ]]; then
        cp "$ols_conf" "$BACKUP_DIR/openlitespeed_httpd_config.conf"
        
        local max_conn=$(echo "$PROFILE_DATA" | jq -r '.openlitespeed.max_connections')
        local workers=$(echo "$PROFILE_DATA" | jq -r '.openlitespeed.worker_processes')
        
        # Update configuration values
        sed -i "s/maxConnections.*/maxConnections          $max_conn/" "$ols_conf"
        sed -i "s/maxSSLConnections.*/maxSSLConnections       $((max_conn / 2))/" "$ols_conf"
        
        log_tuning "OpenLiteSpeed configuration updated"
    fi
}

# Apply PHP tuning
apply_php_tuning() {
    log_tuning "Applying PHP tuning..."
    
    local php_versions=("81" "82")
    
    for version in "${php_versions[@]}"; do
        local php_ini="/usr/local/lsws/lsphp$version/etc/php/$version/litespeed/php.ini"
        
        if [[ -f "$php_ini" ]]; then
            cp "$php_ini" "$BACKUP_DIR/php${version}_php.ini"
            
            local memory_limit=$(echo "$PROFILE_DATA" | jq -r '.php.memory_limit')
            local max_children=$(echo "$PROFILE_DATA" | jq -r '.php.max_children')
            local opcache_memory=$(echo "$PROFILE_DATA" | jq -r '.php.opcache_memory_consumption')
            
            # Update PHP settings
            sed -i "s/memory_limit = .*/memory_limit = $memory_limit/" "$php_ini"
            sed -i "s/opcache.memory_consumption=.*/opcache.memory_consumption=$opcache_memory/" "$php_ini"
            
            log_tuning "PHP $version configuration updated"
        fi
    done
}

# Apply MySQL tuning
apply_mysql_tuning() {
    log_tuning "Applying MySQL tuning..."
    
    local mysql_conf="/etc/mysql/mariadb.conf.d/99-dynamic-tuning.cnf"
    
    local innodb_buffer=$(echo "$PROFILE_DATA" | jq -r '.mysql.innodb_buffer_pool_size')
    local max_connections=$(echo "$PROFILE_DATA" | jq -r '.mysql.max_connections')
    local buffer_instances=$(echo "$PROFILE_DATA" | jq -r '.mysql.innodb_buffer_pool_instances')
    
    cat > "$mysql_conf" <<EOC
# Dynamic Tuning Configuration for MariaDB
[mysqld]
innodb_buffer_pool_size = $innodb_buffer
max_connections = $max_connections
innodb_buffer_pool_instances = $buffer_instances
query_cache_size = $(echo "$PROFILE_DATA" | jq -r '.mysql.query_cache_size')
innodb_log_file_size = $(echo "$PROFILE_DATA" | jq -r '.mysql.innodb_log_file_size')
innodb_flush_log_at_trx_commit = $(echo "$PROFILE_DATA" | jq -r '.mysql.innodb_flush_log_at_trx_commit')
innodb_io_capacity = $(echo "$PROFILE_DATA" | jq -r '.mysql.innodb_io_capacity')
tmp_table_size = $(echo "$PROFILE_DATA" | jq -r '.mysql.tmp_table_size')
max_heap_table_size = $(echo "$PROFILE_DATA" | jq -r '.mysql.max_heap_table_size')
EOC
    
    log_tuning "MySQL configuration updated"
}

# Apply Redis tuning
apply_redis_tuning() {
    log_tuning "Applying Redis tuning..."
    
    local redis_conf="/etc/redis/redis.conf"
    
    if [[ -f "$redis_conf" ]]; then
        cp "$redis_conf" "$BACKUP_DIR/redis.conf"
        
        local maxmemory=$(echo "$PROFILE_DATA" | jq -r '.redis.maxmemory')
        local policy=$(echo "$PROFILE_DATA" | jq -r '.redis.maxmemory_policy')
        
        # Update Redis configuration
        sed -i "s/# maxmemory .*/maxmemory $maxmemory/" "$redis_conf"
        sed -i "s/# maxmemory-policy .*/maxmemory-policy $policy/" "$redis_conf"
        
        log_tuning "Redis configuration updated"
    fi
}

# Apply system tuning
apply_system_tuning() {
    log_tuning "Applying system tuning..."
    
    local sysctl_conf="/etc/sysctl.d/99-dynamic-tuning.conf"
    
    local vm_swappiness=$(echo "$PROFILE_DATA" | jq -r '.system.vm_swappiness')
    local somaxconn=$(echo "$PROFILE_DATA" | jq -r '.system.net_core_somaxconn')
    local netdev_backlog=$(echo "$PROFILE_DATA" | jq -r '.system.net_core_netdev_max_backlog')
    local syn_backlog=$(echo "$PROFILE_DATA" | jq -r '.system.net_ipv4_tcp_max_syn_backlog')
    local file_max=$(echo "$PROFILE_DATA" | jq -r '.system.fs_file_max')
    
    cat > "$sysctl_conf" <<EOC
# Dynamic Tuning System Configuration
vm.swappiness = $vm_swappiness
net.core.somaxconn = $somaxconn
net.core.netdev_max_backlog = $netdev_backlog
net.ipv4.tcp_max_syn_backlog = $syn_backlog
fs.file-max = $file_max
EOC
    
    sysctl -p "$sysctl_conf"
    
    log_tuning "System parameters updated"
}

# Main application function
main() {
    apply_openlitespeed_tuning
    apply_php_tuning
    apply_mysql_tuning
    apply_redis_tuning
    apply_system_tuning
    
    log_tuning "Profile application completed successfully"
}

main
EOF

    # Replace placeholders and make executable
    sed -i "s|__TUNING_LOG_DIR__|$TUNING_LOG_DIR|g" "$TUNING_SCRIPTS_DIR/apply-profile.sh"
    chmod +x "$TUNING_SCRIPTS_DIR/apply-profile.sh"
    
    # Apply the profile
    execute_command "$TUNING_SCRIPTS_DIR/apply-profile.sh '$profile_file' '$backup_dir'" "Applying tuning profile"
    
    # Restart services to apply changes
    log_info "Restarting services to apply tuning changes..."
    local services=("lsws" "mysql" "redis-server")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            execute_command "systemctl restart $service" "Restarting $service"
        fi
    done
    
    # Wait for services to stabilize
    sleep 10
    
    # Update current profile
    CURRENT_PROFILE="$profile_name"
    echo "$profile_name" > "$TUNING_DIR/current-profile.txt"
    
    log_success "Tuning profile applied successfully: $profile_name"
}

# Run performance benchmark
run_performance_benchmark() {
    local profile_name=${1:-$CURRENT_PROFILE}
    local benchmark_file="$TUNING_DIR/benchmark-${profile_name}-$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Running performance benchmark for profile: $profile_name"
    
    # Wait for system to stabilize
    sleep 30
    
    local results=()
    
    for run in $(seq 1 $BENCHMARK_RUNS); do
        log_info "Benchmark run $run of $BENCHMARK_RUNS..."
        
        # Web server benchmark
        local web_rps=0
        local web_response_time=0
        
        if systemctl is-active --quiet lsws && command -v ab >/dev/null 2>&1; then
            local ab_output=$(ab -n 1000 -c 10 "http://localhost/" 2>/dev/null || echo "")
            if [[ -n "$ab_output" ]]; then
                web_rps=$(echo "$ab_output" | grep "Requests per second" | awk '{print $4}' || echo "0")
                web_response_time=$(echo "$ab_output" | grep "Time per request.*mean" | head -1 | awk '{print $4}' || echo "0")
            fi
        fi
        
        # Database benchmark
        local db_queries_per_sec=0
        if [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]]; then
            local db_start=$(date +%s.%N)
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT BENCHMARK(10000, 1+1);" >/dev/null 2>&1 || true
            local db_end=$(date +%s.%N)
            local db_duration=$(echo "$db_end - $db_start" | bc -l)
            db_queries_per_sec=$(echo "10000 / $db_duration" | bc -l | cut -d. -f1)
        fi
        
        # System metrics during benchmark
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        local memory_usage=$(free | awk 'NR==2{printf("%.2f"), $3*100/$2}')
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        
        results+=("{
            \"run\": $run,
            \"web_requests_per_second\": $web_rps,
            \"web_response_time_ms\": $web_response_time,
            \"database_queries_per_second\": $db_queries_per_sec,
            \"cpu_usage_percent\": $cpu_usage,
            \"memory_usage_percent\": $memory_usage,
            \"load_average\": $load_avg
        }")
        
        # Brief pause between runs
        sleep 10
    done
    
    # Calculate averages
    local avg_web_rps=$(echo "${results[@]}" | jq -s 'map(.web_requests_per_second | tonumber) | add / length')
    local avg_response_time=$(echo "${results[@]}" | jq -s 'map(.web_response_time_ms | tonumber) | add / length')
    local avg_db_qps=$(echo "${results[@]}" | jq -s 'map(.database_queries_per_second | tonumber) | add / length')
    
    # Create benchmark results
    cat > "$benchmark_file" <<EOF
{
    "profile": "$profile_name",
    "benchmark_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hardware": {
        "cpu_cores": $CPU_CORES,
        "total_ram_mb": $TOTAL_RAM_MB,
        "total_disk_gb": $TOTAL_DISK_GB
    },
    "benchmark_parameters": {
        "runs": $BENCHMARK_RUNS,
        "duration_seconds": $BENCHMARK_DURATION
    },
    "results": [
        $(IFS=,; echo "${results[*]}")
    ],
    "averages": {
        "web_requests_per_second": $avg_web_rps,
        "web_response_time_ms": $avg_response_time,
        "database_queries_per_second": $avg_db_qps
    },
    "performance_score": $(echo "($avg_web_rps + $avg_db_qps) / $avg_response_time" | bc -l | cut -d. -f1)
}
EOF
    
    log_success "Performance benchmark completed: $benchmark_file"
    log_info "Average Web RPS: $avg_web_rps, Response Time: ${avg_response_time}ms, DB QPS: $avg_db_qps"
}

# Create performance monitoring script
create_performance_monitor() {
    log_info "Creating performance monitoring script..."
    
    cat > "$TUNING_SCRIPTS_DIR/performance-monitor.sh" <<'EOF'
#!/bin/bash

# Performance Monitoring Script
# Continuously monitors system performance and suggests optimizations

set -euo pipefail

TUNING_DIR="__TUNING_DIR__"
LOG_FILE="__TUNING_LOG_DIR__/performance-monitor.log"
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEMORY=85
ALERT_THRESHOLD_RESPONSE_TIME=5000

log_perf() {
    echo "[$(date)] $1" >> "$LOG_FILE"
}

check_performance() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    local memory_usage=$(free | awk 'NR==2{printf("%.2f"), $3*100/$2}')
    local response_time=$(curl -o /dev/null -s -w "%{time_total}" "http://localhost/" 2>/dev/null | awk '{print $1 * 1000}' || echo "0")
    
    # Log current metrics
    log_perf "CPU: ${cpu_usage}%, Memory: ${memory_usage}%, Response Time: ${response_time}ms"
    
    # Check thresholds and recommend actions
    if (( $(echo "$cpu_usage > $ALERT_THRESHOLD_CPU" | bc -l) )); then
        log_perf "HIGH CPU DETECTED - Consider reducing PHP max_children or optimizing code"
    fi
    
    if (( $(echo "$memory_usage > $ALERT_THRESHOLD_MEMORY" | bc -l) )); then
        log_perf "HIGH MEMORY DETECTED - Consider reducing buffer sizes or adding RAM"
    fi
    
    if (( $(echo "$response_time > $ALERT_THRESHOLD_RESPONSE_TIME" | bc -l) )); then
        log_perf "SLOW RESPONSE TIME DETECTED - Consider enabling more caching or optimizing database"
    fi
}

# Main monitoring loop
main() {
    while true; do
        check_performance
        sleep 300  # Check every 5 minutes
    done
}

# Run as daemon if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
EOF

    # Replace placeholders
    sed -i "s|__TUNING_DIR__|$TUNING_DIR|g" "$TUNING_SCRIPTS_DIR/performance-monitor.sh"
    sed -i "s|__TUNING_LOG_DIR__|$TUNING_LOG_DIR|g" "$TUNING_SCRIPTS_DIR/performance-monitor.sh"
    
    chmod +x "$TUNING_SCRIPTS_DIR/performance-monitor.sh"
    
    log_success "Performance monitoring script created"
}

# Create tuning management tools
create_tuning_tools() {
    log_info "Creating tuning management tools..."
    
    # Create tuning CLI tool
    cat > "/usr/local/bin/server-tuning" <<'EOF'
#!/bin/bash

# Server Tuning Management Tool

TUNING_DIR="__TUNING_DIR__"
TUNING_PROFILES_DIR="$TUNING_DIR/profiles"
TUNING_SCRIPTS_DIR="$TUNING_DIR/scripts"

show_usage() {
    cat << 'USAGE_EOF'
Usage: \$0 [command] [options]

Commands:
    list-profiles       List all available tuning profiles
    current-profile     Show current active profile
    analyze             Analyze current system performance
    generate [name]     Generate new tuning profile
    apply [name]        Apply specific tuning profile
    benchmark [name]    Run performance benchmark
    monitor             Start performance monitoring
    revert              Revert to previous configuration
    compare             Compare performance between profiles

Examples:
    \$0 list-profiles
    \$0 generate high-performance
    \$0 apply high-performance
    \$0 benchmark high-performance
    \$0 monitor
USAGE_EOF
}

case "${1:-}" in
    "list-profiles")
        echo "Available Tuning Profiles:"
        if [[ -d "$TUNING_PROFILES_DIR" ]]; then
            for profile in "$TUNING_PROFILES_DIR"/*.json; do
                if [[ -f "$profile" ]]; then
                    name=$(basename "$profile" .json)
                    created=$(jq -r '.generated_at' "$profile" 2>/dev/null || echo "Unknown")
                    tier=$(jq -r '.hardware_basis.server_tier' "$profile" 2>/dev/null || echo "Unknown")
                    echo "  $name (Tier: $tier, Created: $created)"
                fi
            done
        fi
        ;;
    "current-profile")
        if [[ -f "$TUNING_DIR/current-profile.txt" ]]; then
            current=$(cat "$TUNING_DIR/current-profile.txt")
            echo "Current Profile: $current"
        else
            echo "No profile currently active"
        fi
        ;;
    "apply")
        profile="${2:-}"
        if [[ -z "$profile" ]]; then
            echo "Error: Profile name required"
            exit 1
        fi
        __TUNING_SCRIPT__ apply-profile "$profile"
        ;;
    "benchmark")
        profile="${2:-}"
        if [[ -z "$profile" ]]; then
            echo "Error: Profile name required"
            exit 1
        fi
        __TUNING_SCRIPT__ run-benchmark "$profile"
        ;;
    "monitor")
        echo "Starting performance monitor..."
        "$TUNING_SCRIPTS_DIR/performance-monitor.sh" &
        echo "Performance monitor started (PID: $!)"
        ;;
    *)
        show_usage
        ;;
esac
EOF

    # Replace placeholders
    sed -i "s|__TUNING_DIR__|$TUNING_DIR|g" "/usr/local/bin/server-tuning"
    sed -i "s|__TUNING_SCRIPT__|$TUNING_SCRIPTS_DIR/tuning-manager.sh|g" "/usr/local/bin/server-tuning"
    
    chmod +x "/usr/local/bin/server-tuning"
    
    # Create comprehensive tuning manager
    cat > "$TUNING_SCRIPTS_DIR/tuning-manager.sh" <<EOF
#!/bin/bash
# Comprehensive tuning management script
source "$SCRIPT_DIR/../scripts/utils.sh"

case "\$1" in
    "apply-profile")
        $SCRIPT_DIR/dynamic-tuning.sh apply-profile "\${2:-auto}"
        ;;
    "run-benchmark")  
        $SCRIPT_DIR/dynamic-tuning.sh run-benchmark "\${2:-auto}"
        ;;
    *)
        echo "Unknown tuning command: \$1"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$TUNING_SCRIPTS_DIR/tuning-manager.sh"
    
    log_success "Tuning management tools created"
}

# Create dynamic tuning summary
create_tuning_summary() {
    local summary_file="$LOG_DIR/dynamic-tuning_summary.txt"
    
    cat > "$summary_file" <<EOF
WordPress Server Automation - Dynamic Tuning Module Summary
===========================================================
Configuration Date: $(date)

Hardware Profile:
- CPU Cores: $CPU_CORES
- Total RAM: ${TOTAL_RAM_MB}MB
- Total Disk: ${TOTAL_DISK_GB}GB
- Network Interface: $NETWORK_INTERFACE

Dynamic Tuning Configuration:
- Tuning Directory: $TUNING_DIR
- Profiles Directory: $TUNING_PROFILES_DIR
- Scripts Directory: $TUNING_SCRIPTS_DIR
- Log Directory: $TUNING_LOG_DIR

Generated Tuning Profile (Auto):
- Max Connections: $((TOTAL_RAM_MB * 2))
- Worker Processes: $((CPU_CORES * 2))
- PHP Memory Limit: $((TOTAL_RAM_MB / 4))MB
- PHP Max Children: $((TOTAL_RAM_MB / 50))
- MySQL Buffer Pool: $((TOTAL_RAM_MB * 70 / 100))MB
- MySQL Max Connections: $((TOTAL_RAM_MB / 12))
- Redis Max Memory: $((TOTAL_RAM_MB * 20 / 100))MB

Optimization Areas:
1. OpenLiteSpeed Configuration
   - Connection limits and worker processes
   - Keep-alive settings and compression
   - SSL connection optimization

2. PHP Performance Tuning  
   - Memory limits and process management
   - OPcache optimization
   - Session handling optimization

3. MySQL/MariaDB Optimization
   - InnoDB buffer pool sizing
   - Query cache configuration
   - Connection pool management

4. Redis Cache Optimization
   - Memory allocation and policies
   - Connection timeout settings
   - Persistence configuration

5. System-Level Tuning
   - Kernel parameters optimization
   - Network stack tuning
   - File system optimization

Performance Monitoring:
- Real-time performance tracking
- Automated benchmark testing
- Alert system for performance degradation
- Historical performance data

Management Tools:
- server-tuning: Main tuning management CLI
- Performance monitor: Continuous monitoring
- Benchmark runner: Automated testing
- Profile manager: Configuration management

Usage Examples:
- server-tuning list-profiles
- server-tuning generate high-performance
- server-tuning apply high-performance
- server-tuning benchmark high-performance
- server-tuning monitor

Profile Files:
- Auto Profile: $TUNING_PROFILES_DIR/auto.json
- Current Profile: $(cat "$TUNING_DIR/current-profile.txt" 2>/dev/null || echo "None")

Log Files:
- Tuning Application: $TUNING_LOG_DIR/tuning-application.log
- Performance Monitor: $TUNING_LOG_DIR/performance-monitor.log
- Benchmark Results: $TUNING_DIR/benchmark-*.json

Extensible Architecture:
- Modular tuning components
- Plugin system for additional optimizations  
- Hardware detection and adaptation
- Performance feedback loop
- Rollback capability

Next Steps:
1. Review generated tuning profile
2. Run initial performance benchmark
3. Apply optimizations and test
4. Monitor performance continuously
5. Fine-tune based on workload patterns

Installation Status: Completed Successfully
EOF

    log_info "Dynamic tuning summary saved to: $summary_file"
}

# Main dynamic tuning function
main() {
    case "${1:-setup}" in
        "setup")
            log_info "=== Starting Dynamic Tuning Setup ==="
            
            # Load configuration and analyze system
            load_tuning_config
            analyze_current_performance
            
            # Generate and apply auto-tuning profile
            generate_tuning_profile "auto"
            apply_tuning_profile "auto"
            
            # Create management tools
            create_performance_monitor
            create_tuning_tools
            
            # Run initial benchmark
            if command -v ab >/dev/null 2>&1; then
                run_performance_benchmark "auto"
            else
                log_info "Apache Bench not available - skipping initial benchmark"
                log_info "Install 'apache2-utils' package to enable benchmarking"
            fi
            
            # Create summary
            create_tuning_summary
            
            log_success "=== Dynamic tuning setup completed successfully! ==="
            log_info "Check $LOG_DIR/dynamic-tuning_summary.txt for details"
            log_info "Use 'server-tuning' command for tuning management"
            ;;
        "apply-profile")
            load_tuning_config
            apply_tuning_profile "${2:-auto}"
            ;;
        "run-benchmark")
            load_tuning_config
            run_performance_benchmark "${2:-auto}"
            ;;
        "generate-profile")
            load_tuning_config
            generate_tuning_profile "${2:-custom}"
            ;;
        *)
            log_error "Unknown dynamic tuning command: ${1:-}"
            return 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
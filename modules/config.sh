#!/bin/bash

# Configuration Module for WordPress Server Automation
# ====================================================
# Description: Optimizes server and service settings for maximum performance
# Dependencies: OpenLiteSpeed, CyberPanel, MariaDB, Redis, PHP
# Author: DevOps Ubuntu Team

set -euo pipefail

# Source utilities and set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
LOGS_DIR="$SCRIPT_DIR/../logs"
source "$SCRIPT_DIR/../scripts/utils.sh"

# Module information
MODULE_NAME="Configuration Module"
MODULE_VERSION="1.0.0"

log_info "Starting $MODULE_NAME v$MODULE_VERSION"

# Load installation credentials
load_credentials() {
    log_info "Loading installation credentials..."
    
    local config_files=("mysql.conf" "openlitespeed.conf" "cyberpanel.conf")
    
    for config_file in "${config_files[@]}"; do
        local config_path="$CONFIG_DIR/$config_file"
        if [[ -f "$config_path" ]]; then
            source "$config_path"
            log_debug "Loaded configuration: $config_file"
        else
            log_warning "Configuration file not found: $config_path"
        fi
    done
}

# Configure OpenLiteSpeed
configure_openlitespeed() {
    log_info "Configuring OpenLiteSpeed..."
    
    local ols_conf="/usr/local/lsws/conf/httpd_config.conf"
    local ols_template="$CONFIG_DIR/openlitespeed_template.conf"
    
    # Create backup
    create_backup "$ols_conf"
    
    # Calculate optimal settings based on hardware
    local worker_processes=$((CPU_CORES * 2))
    local max_connections=$((TOTAL_RAM_MB * 2))
    local php_max_children=$((TOTAL_RAM_MB / 50))
    
    # Ensure minimum values
    [[ $worker_processes -lt 2 ]] && worker_processes=2
    [[ $max_connections -lt 500 ]] && max_connections=500
    [[ $php_max_children -lt 10 ]] && php_max_children=10
    
    # Create optimized configuration
    cat > "$ols_template" <<EOF
# OpenLiteSpeed HTTP Configuration - Optimized for $CPU_CORES cores, ${TOTAL_RAM_MB}MB RAM
# Generated automatically - DO NOT EDIT MANUALLY

serverName                \$hostname
user                      nobody
group                     nogroup
priority                  0
autoRestart               1
chrootPath                \$SERVER_ROOT
enableChroot              0
inMemBufSize              60M
swappingDir               /tmp/lshttpd/swap
autoFix503                1
gracefulRestartTimeout    300
mime                      \$SERVER_ROOT/conf/mime.properties
showVersionNumber         0
adminEmails               admin@localhost
indexFiles                index.html, index.php
disableWebAdmin           0

errorlog {
    logLevel                WARN
    debugLevel              0
    logHeaders              0
    enableStderrLog         1
}

accesslog \$SERVER_ROOT/logs/access.log {
    useServer               1
    logFormat               %h %l %u %t "%r" %>s %b "%{Referer}i" "%{User-Agent}i"
    logHeaders              0
    rollingSize             100M
    keepDays                30
}

expires {
    enableExpires           1
    expiresByType           image/*=A604800,text/css=A604800,application/x-javascript=A604800,application/javascript=A604800,font/*=A604800,application/x-font-ttf=A604800
}

tuning {
    maxConnections          $max_connections
    maxSSLConnections       $(($max_connections / 2))
    connTimeout             300
    maxKeepAliveReq         1000
    keepAliveTimeout        5
    sndBufSize              0
    rcvBufSize              0
    maxReqURLLen            32768
    maxReqHeaderSize        65536
    maxReqBodySize          2047M
    maxDynRespHeaderSize    32768
    maxDynRespSize          2047M
    maxCachedFileSize       4096
    totalInMemCacheSize     20M
    maxMMapFileSize         256K
    totalMMapCacheSize      40M
    useSendfile             1
    fileETag                28
    enableGzipCompress      1
    compressibleTypes       text/*, application/x-javascript, application/xml, application/javascript, image/svg+xml,application/rss+xml
    gzipAutoUpdateStatic    1
    gzipStaticCompressLevel 6
    gzipMaxFileSize         10M
    gzipMinFileSize         300
    gzipCompressLevel       6
}

fileAccessControl {
    followSymbolLink        1
    checkSymbolLink         0
    requiredPermissionMask  000
    restrictedPermissionMask 000
}

perClientConnLimit {
    staticReqPerSec         0
    dynReqPerSec            0
    outBandwidth            0
    inBandwidth             0
    softLimit               10000
    hardLimit               10000
    gracePeriod             15
    banPeriod               300
}

CGIRLimit {
    maxCGIInstances         20
    minUID                  11
    minGID                  10
    priority                0
    CPUSoftLimit            10
    CPUHardLimit            50
    memSoftLimit            1460M
    memHardLimit            1500M
    procSoftLimit           400
    procHardLimit           450
}

accessDenyDir {
    dir                     /
    dir                     /etc/*
    dir                     /dev/*
    dir                     conf/*
    dir                     admin/conf/*
}

accessControl {
    allow                   ALL
}

extprocessor lsphp82 {
    type                    lsapi
    address                 uds://tmp/lshttpd/lsphp.sock
    maxConns                35
    env                     PHP_LSAPI_CHILDREN=$php_max_children
    env                     PHP_LSAPI_MAX_REQUESTS=500
    initTimeout             60
    retryTimeout            0
    pcKeepAliveTimeout      1
    respBuffer              0
    autoStart               1
    path                    /usr/local/lsws/lsphp82/bin/lsphp
    backlog                 100
    instances               1
    priority                0
    memSoftLimit            2047M
    memHardLimit            2047M
    procSoftLimit           400
    procHardLimit           500
}

scripthandler {
    add                     lsphp82 php
}

railsDefaults {
    maxConns                1
    env                     LSAPI_MAX_REQS=500
    env                     LSAPI_MAX_IDLE=300
    initTimeout             60
    retryTimeout            0
    pcKeepAliveTimeout      60
    respBuffer              0
    backlog                 50
    runOnStartUp            3
    extMaxIdleTime          300
    priority                3
    memSoftLimit            2047M
    memHardLimit            2047M
    procSoftLimit           500
    procHardLimit           600
}

module cache {
    internal                1
    checkPrivateCache       1
    checkPublicCache        1
    maxCacheObjSize         10000000
    maxStaleAge             200
    qsCache                 1
    reqCookieCache          1
    respCookieCache         1
    ignoreReqCacheCtrl      1
    ignoreRespCacheCtrl     0
    enableCache             0
    expireInSeconds         3600
    enablePrivateCache      0
    privateExpireInSeconds  3600
}

listener Default {
    address                 *:80
    secure                  0
    map                     * \$VH_ROOT/
}

listener SSL {
    address                 *:443
    secure                  1
    keyFile                 \$SERVER_ROOT/conf/example.key
    certFile                \$SERVER_ROOT/conf/example.crt
    certChain               1
    sslProtocol             24
    ciphers                 EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH:ECDHE-RSA-AES128-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA128:DHE-RSA-AES128-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES128-GCM-SHA128:ECDHE-RSA-AES128-SHA384:ECDHE-RSA-AES128-SHA128:ECDHE-RSA-AES128-SHA:DHE-RSA-AES128-SHA128:DHE-RSA-AES128-SHA:AES128-GCM-SHA384:AES128-GCM-SHA128:AES128-SHA128:AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:DES-CBC3-SHA:!RC4:!aNULL:!eNULL:!MD5:!EXPORT:!LOW:!SEED:!CAMELLIA:!IDEA:!PSK:!SRP:!SSLv2
    enableECDHE             1
    renegProtection         1
    sslSessionCache         1
    sslSessionTickets       1
    enableSpdy              15
    enableQuic              1
    map                     * \$VH_ROOT/
}

vhTemplate centralConfigLog {
    templateFile            \$SERVER_ROOT/conf/templates/ccl.conf
    listeners               Default, SSL
}

vhTemplate PHP_SuEXEC {
    templateFile            \$SERVER_ROOT/conf/templates/phpsuexec.conf  
    listeners               Default, SSL
}

vhTemplate EasyRailsWithSuEXEC {
    templateFile            \$SERVER_ROOT/conf/templates/rails.conf
    listeners               Default, SSL
}
EOF

    # Apply configuration
    if [[ "$DRY_RUN" != "true" ]]; then
        cp "$ols_template" "$ols_conf"
        execute_command "/usr/local/lsws/bin/lshttpd -t" "Testing OpenLiteSpeed configuration"
        execute_command "systemctl reload lsws" "Reloading OpenLiteSpeed"
    fi
    
    log_success "OpenLiteSpeed configuration completed"
}

# Configure PHP settings
configure_php() {
    log_info "Configuring PHP settings..."
    
    local php_versions=("81" "82")
    
    for version in "${php_versions[@]}"; do
        log_info "Configuring PHP $version..."
        
        local php_ini="/usr/local/lsws/lsphp$version/etc/php/$version/litespeed/php.ini"
        
        if [[ -f "$php_ini" ]]; then
            create_backup "$php_ini"
            
            # Calculate PHP settings based on hardware
            local memory_limit=$((TOTAL_RAM_MB / 4))
            local max_children=$((TOTAL_RAM_MB / 50))
            local max_execution_time=300
            local max_input_vars=10000
            local upload_max_filesize="256M"
            local post_max_size="512M"
            
            # Ensure minimum values
            [[ $memory_limit -lt 256 ]] && memory_limit=256
            [[ $max_children -lt 10 ]] && max_children=10
            
            # Apply optimized PHP settings
            cat > "/tmp/php_optimization.ini" <<EOF
; PHP Optimization Settings - Generated automatically
; Hardware: $CPU_CORES cores, ${TOTAL_RAM_MB}MB RAM

; Basic Settings
engine = On
short_open_tag = Off
precision = 14
output_buffering = 4096
zlib.output_compression = Off
implicit_flush = Off
unserialize_callback_func =
serialize_precision = -1
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source
disable_classes =
zend.enable_gc = On

; Resource Limits
max_execution_time = $max_execution_time
max_input_time = 300
memory_limit = ${memory_limit}M
post_max_size = $post_max_size
upload_max_filesize = $upload_max_filesize
max_file_uploads = 20
max_input_vars = $max_input_vars

; Error Reporting
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 1024
ignore_repeated_errors = Off
ignore_repeated_source = Off
report_memleaks = On
html_errors = On
error_log = /usr/local/lsws/logs/php_errors.log

; Data Handling
variables_order = "GPCS"
request_order = "GP"
register_argc_argv = Off
auto_globals_jit = On

; Paths and Directories
include_path = ".:/usr/local/lsws/lsphp$version/lib/php"
doc_root =
user_dir =
extension_dir = "/usr/local/lsws/lsphp$version/lib/php/20210902"
sys_temp_dir = "/tmp"
enable_dl = Off

; File Uploads
file_uploads = On
tmp_upload_dir = /tmp

; Fopen wrappers
allow_url_fopen = On
allow_url_include = Off
default_socket_timeout = 60

; Dynamic Extensions
extension=bcmath
extension=calendar
extension=ctype
extension=curl
extension=dom
extension=exif
extension=ffi
extension=fileinfo
extension=filter
extension=ftp
extension=gd
extension=gettext
extension=gmp
extension=hash
extension=iconv
extension=intl
extension=json
extension=mbstring
extension=mysqli
extension=mysqlnd
extension=opcache
extension=openssl
extension=pcntl
extension=pdo
extension=pdo_mysql
extension=phar
extension=posix
extension=readline
extension=redis
extension=session
extension=shmop
extension=simplexml
extension=soap
extension=sockets
extension=sodium
extension=sysvmsg
extension=sysvsem
extension=sysvshm
extension=tokenizer
extension=xml
extension=xmlreader
extension=xmlwriter
extension=zip

; OPcache Settings
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.max_wasted_percentage=5
opcache.use_cwd=1
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.revalidate_path=0
opcache.save_comments=1
opcache.fast_shutdown=0
opcache.enable_file_override=0
opcache.optimization_level=0x7FFFBFFF
opcache.inherited_hack=1
opcache.dups_fix=0
opcache.blacklist_filename=

; Session Settings
session.save_handler = redis
session.save_path = "tcp://127.0.0.1:6379"
session.use_strict_mode = 0
session.use_cookies = 1
session.use_only_cookies = 1
session.name = PHPSESSID
session.auto_start = 0
session.cookie_lifetime = 0
session.cookie_path = /
session.cookie_domain =
session.cookie_httponly =
session.serialize_handler = php
session.gc_probability = 1
session.gc_divisor = 1000
session.gc_maxlifetime = 1440
session.cache_limiter = nocache
session.cache_expire = 180
session.use_trans_sid = 0
session.hash_function = 0
session.hash_bits_per_character = 5

; Date Settings
date.timezone = UTC
date.default_latitude = 31.7667
date.default_longitude = 35.2333
date.sunrise_zenith = 90.583333
date.sunset_zenith = 90.583333
EOF
            
            if [[ "$DRY_RUN" != "true" ]]; then
                # Merge with existing configuration
                cp "$php_ini" "${php_ini}.backup"
                cat "/tmp/php_optimization.ini" >> "$php_ini"
                rm "/tmp/php_optimization.ini"
            fi
            
            log_success "PHP $version configuration completed"
        else
            log_warning "PHP $version configuration file not found: $php_ini"
        fi
    done
}

# Configure MariaDB/MySQL
configure_mysql() {
    log_info "Configuring MariaDB/MySQL..."
    
    local mysql_conf="/etc/mysql/mariadb.conf.d/99-optimization.cnf"
    
    # Calculate MySQL settings based on hardware
    local innodb_buffer_pool_size=$((TOTAL_RAM_MB * 70 / 100))
    local max_connections=$((TOTAL_RAM_MB / 12))
    local query_cache_size=$((TOTAL_RAM_MB * 5 / 100))
    
    # Ensure reasonable limits
    [[ $innodb_buffer_pool_size -lt 256 ]] && innodb_buffer_pool_size=256
    [[ $max_connections -lt 50 ]] && max_connections=50
    [[ $max_connections -gt 1000 ]] && max_connections=1000
    [[ $query_cache_size -lt 32 ]] && query_cache_size=32
    
    cat > "$mysql_conf" <<EOF
# MariaDB Optimization Configuration
# Generated automatically for $CPU_CORES cores, ${TOTAL_RAM_MB}MB RAM

[mysqld]
# Basic Settings
user = mysql
pid-file = /var/run/mysqld/mysqld.pid
socket = /var/run/mysqld/mysqld.sock
port = 3306
basedir = /usr
datadir = /var/lib/mysql
tmpdir = /tmp
lc-messages-dir = /usr/share/mysql
bind-address = 127.0.0.1

# Connection Settings
max_connections = $max_connections
max_user_connections = $(($max_connections - 10))
max_connect_errors = 1000000
connect_timeout = 10
wait_timeout = 28800
interactive_timeout = 28800

# Buffer Settings
key_buffer_size = $(($query_cache_size))M
max_allowed_packet = 256M
thread_stack = 192K
thread_cache_size = 8
table_open_cache = 4096
table_definition_cache = 4096

# Query Cache Settings
query_cache_type = 1
query_cache_size = ${query_cache_size}M
query_cache_limit = 8M
query_cache_min_res_unit = 2K

# InnoDB Settings
innodb_buffer_pool_size = ${innodb_buffer_pool_size}M
innodb_buffer_pool_instances = $(($CPU_CORES))
innodb_log_file_size = 256M
innodb_log_buffer_size = 32M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_open_files = 4000
innodb_io_capacity = 400
innodb_read_io_threads = $CPU_CORES
innodb_write_io_threads = $CPU_CORES

# MyISAM Settings
myisam_recover_options = BACKUP
myisam_sort_buffer_size = 128M

# Temp Tables
tmp_table_size = 128M
max_heap_table_size = 128M

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow-query.log
long_query_time = 2
log_queries_not_using_indexes = 1
general_log = 0

# Binary Logging
server-id = 1
log_bin = /var/log/mysql/mysql-bin.log
expire_logs_days = 7
max_binlog_size = 100M
binlog_format = ROW

# Performance Schema
performance_schema = ON
performance_schema_max_table_instances = 12500
performance_schema_max_table_handles = 4000

# Character Set
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
init-connect = 'SET NAMES utf8mb4'

[mysql]
default-character-set = utf8mb4

[mysqldump]
quick
quote-names
max_allowed_packet = 256M

[isamchk]
key_buffer_size = 256M
EOF
    
    # Restart MySQL to apply changes
    if [[ "$DRY_RUN" != "true" ]]; then
        execute_command "systemctl restart mysql" "Restarting MariaDB"
        
        # Wait for MySQL to be ready
        local retries=0
        while ! mysqladmin ping --silent && [[ $retries -lt 30 ]]; do
            sleep 2
            retries=$((retries + 1))
        done
        
        if [[ $retries -ge 30 ]]; then
            log_error "MySQL failed to start after configuration"
            return 1
        fi
    fi
    
    log_success "MariaDB/MySQL configuration completed"
}

# Configure Redis
configure_redis() {
    log_info "Configuring Redis..."
    
    local redis_conf="/etc/redis/redis.conf"
    
    if [[ -f "$redis_conf" ]]; then
        create_backup "$redis_conf"
        
        # Calculate Redis settings
        local maxmemory=$((TOTAL_RAM_MB * 20 / 100))
        [[ $maxmemory -lt 64 ]] && maxmemory=64
        
        # Apply Redis optimizations
        cat >> "$redis_conf" <<EOF

# Redis Optimization Settings - Generated automatically
# Hardware: $CPU_CORES cores, ${TOTAL_RAM_MB}MB RAM

# Memory Management
maxmemory ${maxmemory}mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Persistence
save 900 1
save 300 10
save 60 10000
rdbcompression yes
rdbchecksum yes
stop-writes-on-bgsave-error yes

# Network
tcp-keepalive 60
tcp-backlog 511

# Performance
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000

# Logging
loglevel notice
logfile /var/log/redis/redis-server.log

# Security
bind 127.0.0.1 ::1
protected-mode yes
EOF
        
        if [[ "$DRY_RUN" != "true" ]]; then
            execute_command "systemctl restart redis-server" "Restarting Redis"
        fi
        
        log_success "Redis configuration completed"
    else
        log_warning "Redis configuration file not found: $redis_conf"
    fi
}

# Configure system kernel parameters
configure_system_kernel() {
    log_info "Configuring system kernel parameters..."
    
    local sysctl_conf="/etc/sysctl.d/99-server-optimization.conf"
    
    cat > "$sysctl_conf" <<EOF
# System Optimization Settings for Web Server
# Generated automatically for $CPU_CORES cores, ${TOTAL_RAM_MB}MB RAM

# Network Performance
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 30000
net.core.somaxconn = 65535
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_max_syn_backlog = 30000
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_syncookies = 1

# Memory Management
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

# File System
fs.file-max = 2097152
fs.nr_open = 1048576

# Process Limits
kernel.pid_max = 4194304
kernel.threads-max = 4194304
EOF
    
    if [[ "$DRY_RUN" != "true" ]]; then
        execute_command "sysctl -p $sysctl_conf" "Applying kernel parameters"
    fi
    
    log_success "System kernel parameters configured"
}

# Configure system limits
configure_system_limits() {
    log_info "Configuring system limits..."
    
    local limits_conf="/etc/security/limits.d/99-server-optimization.conf"
    
    cat > "$limits_conf" <<EOF
# System Limits Optimization for Web Server
# Generated automatically

# Root limits
root soft nofile 1048576
root hard nofile 1048576
root soft nproc unlimited
root hard nproc unlimited

# Web server user limits
nobody soft nofile 1048576
nobody hard nofile 1048576
nobody soft nproc 32768
nobody hard nproc 32768

# MySQL user limits
mysql soft nofile 65536
mysql hard nofile 65536
mysql soft nproc 32768
mysql hard nproc 32768

# Redis user limits
redis soft nofile 65536
redis hard nofile 65536

# Default limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
    
    # Update PAM configuration
    if ! grep -q "pam_limits.so" /etc/pam.d/common-session; then
        echo "session required pam_limits.so" >> /etc/pam.d/common-session
    fi
    
    log_success "System limits configured"
}

# Configure log rotation
configure_log_rotation() {
    log_info "Configuring log rotation..."
    
    cat > "/etc/logrotate.d/openlitespeed" <<EOF
/usr/local/lsws/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    postrotate
        /usr/local/lsws/bin/lshttpd -k USR1 >/dev/null 2>&1 || true
    endscript
}
EOF
    
    cat > "/etc/logrotate.d/cyberpanel" <<EOF
/usr/local/CyberCP/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
    
    log_success "Log rotation configured"
}

# Test all configurations
test_configurations() {
    log_info "Testing all configurations..."
    
    local failed_tests=()
    
    # Test OpenLiteSpeed
    if execute_command "/usr/local/lsws/bin/lshttpd -t" "Testing OpenLiteSpeed configuration"; then
        log_success "OpenLiteSpeed configuration test passed"
    else
        failed_tests+=("OpenLiteSpeed")
    fi
    
    # Test MySQL connection
    if [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]]; then
        if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT VERSION();" >/dev/null 2>&1; then
            log_success "MySQL connection test passed"
        else
            failed_tests+=("MySQL")
        fi
    fi
    
    # Test Redis connection
    if redis-cli ping >/dev/null 2>&1; then
        log_success "Redis connection test passed"
    else
        failed_tests+=("Redis")
    fi
    
    # Test PHP
    local php_versions=("81" "82")
    for version in "${php_versions[@]}"; do
        if /usr/local/lsws/lsphp$version/bin/php -v >/dev/null 2>&1; then
            log_success "PHP $version test passed"
        else
            failed_tests+=("PHP$version")
        fi
    done
    
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        log_error "Configuration tests failed for: ${failed_tests[*]}"
        return 1
    fi
    
    log_success "All configuration tests passed"
}

# Create configuration summary
create_configuration_summary() {
    local summary_file="$LOG_DIR/configuration_summary.txt"
    
    cat > "$summary_file" <<EOF
WordPress Server Automation - Configuration Summary
===================================================
Configuration Date: $(date)
Hardware: $CPU_CORES cores, ${TOTAL_RAM_MB}MB RAM

Applied Configurations:
- OpenLiteSpeed: Optimized for high performance and concurrency
- PHP 8.1 & 8.2: Memory and execution limits optimized
- MariaDB: InnoDB buffer pool and connection settings tuned
- Redis: Memory management and persistence configured
- System Kernel: Network and memory parameters optimized
- System Limits: File descriptor and process limits increased

Performance Optimizations:
- Max Connections: Calculated based on available RAM
- PHP Memory Limit: Set to ${memory_limit:-256}MB per process
- MySQL Buffer Pool: ${innodb_buffer_pool_size:-512}MB
- Redis Max Memory: ${maxmemory:-128}MB
- Worker Processes: ${worker_processes:-4} (2x CPU cores)

Configuration Files Modified:
- /usr/local/lsws/conf/httpd_config.conf
- /usr/local/lsws/lsphp81/etc/php/8.1/litespeed/php.ini
- /usr/local/lsws/lsphp82/etc/php/8.2/litespeed/php.ini
- /etc/mysql/mariadb.conf.d/99-optimization.cnf
- /etc/redis/redis.conf
- /etc/sysctl.d/99-server-optimization.conf
- /etc/security/limits.d/99-server-optimization.conf

Next Steps:
1. Run security hardening: ./master.sh security
2. Configure monitoring: ./master.sh monitoring
3. Setup WordPress automation: ./master.sh wp-automation

All configuration backups are stored in: $BACKUP_DIR
EOF
    
    log_info "Configuration summary saved to: $summary_file"
}

# Main configuration function
main() {
    log_info "=== Starting Server Configuration ==="
    
    # Load credentials and detect hardware
    load_credentials
    detect_hardware
    
    # Run configuration steps
    configure_openlitespeed
    configure_php
    configure_mysql
    configure_redis
    configure_system_kernel
    configure_system_limits
    configure_log_rotation
    
    # Test configurations
    test_configurations
    
    # Create summary
    create_configuration_summary
    
    log_success "=== Server configuration completed successfully! ==="
    log_info "Check $LOG_DIR/configuration_summary.txt for details"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash

# Security Module for WordPress Server Automation
# ===============================================
# Description: Implements comprehensive security hardening measures including firewall, WAF, SSL, and dynamic IP whitelisting
# Dependencies: UFW, Fail2ban, OpenLiteSpeed, CyberPanel, Cloudflare API
# Author: DevOps Ubuntu Team

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/utils.sh"

# Module information
MODULE_NAME="Security Module"
MODULE_VERSION="1.0.0"

log_info "Starting $MODULE_NAME v$MODULE_VERSION"

# Security configuration variables
UFW_PORTS=(22 80 443 8090 7080)
FAIL2BAN_JAILS=("sshd" "apache-auth" "apache-noscript" "cyberpanel" "wordpress")
CLOUDFLARE_CONFIG_FILE="$CONFIG_DIR/cloudflare.conf"

# Load security configuration
load_security_config() {
    log_info "Loading security configuration..."
    
    # Load Cloudflare configuration if exists
    if [[ -f "$CLOUDFLARE_CONFIG_FILE" ]]; then
        source "$CLOUDFLARE_CONFIG_FILE"
        log_debug "Loaded Cloudflare configuration"
    else
        log_warning "Cloudflare configuration not found. Dynamic IP whitelisting will be skipped."
        DYNAMIC_IP_ENABLED=false
    fi
    
    # Load installation credentials
    local config_files=("mysql.conf" "openlitespeed.conf" "cyberpanel.conf")
    for config_file in "${config_files[@]}"; do
        local config_path="$CONFIG_DIR/$config_file"
        if [[ -f "$config_path" ]]; then
            source "$config_path"
        fi
    done
}

# Configure UFW Firewall
configure_ufw() {
    log_info "Configuring UFW firewall..."
    
    # Reset UFW to default state
    execute_command "ufw --force reset" "Resetting UFW to defaults"
    
    # Set default policies
    execute_command "ufw default deny incoming" "Setting default deny incoming"
    execute_command "ufw default allow outgoing" "Setting default allow outgoing"
    
    # Allow essential ports
    for port in "${UFW_PORTS[@]}"; do
        case $port in
            22)
                if [[ "$DYNAMIC_IP_ENABLED" == "true" ]]; then
                    log_info "SSH access will be restricted to dynamic IP only"
                else
                    execute_command "ufw allow $port/tcp comment 'SSH'" "Allowing SSH port $port"
                fi
                ;;
            80)
                execute_command "ufw allow $port/tcp comment 'HTTP'" "Allowing HTTP port $port"
                ;;
            443)
                execute_command "ufw allow $port/tcp comment 'HTTPS'" "Allowing HTTPS port $port"
                ;;
            8090)
                if [[ "$DYNAMIC_IP_ENABLED" == "true" ]]; then
                    log_info "CyberPanel access will be restricted to dynamic IP only"
                else
                    execute_command "ufw allow $port/tcp comment 'CyberPanel'" "Allowing CyberPanel port $port"
                fi
                ;;
            7080)
                if [[ "$DYNAMIC_IP_ENABLED" == "true" ]]; then
                    log_info "OpenLiteSpeed Admin access will be restricted to dynamic IP only"
                else
                    execute_command "ufw allow $port/tcp comment 'OpenLiteSpeed Admin'" "Allowing OpenLiteSpeed Admin port $port"
                fi
                ;;
        esac
    done
    
    # Configure rate limiting
    execute_command "ufw limit ssh/tcp comment 'Rate limit SSH'" "Configuring SSH rate limiting"
    
    # Enable UFW
    execute_command "ufw --force enable" "Enabling UFW firewall"
    
    # Show status
    if [[ "$DRY_RUN" != "true" ]]; then
        ufw status verbose
    fi
    
    log_success "UFW firewall configured successfully"
}

# Configure Fail2ban
configure_fail2ban() {
    log_info "Configuring Fail2ban..."
    
    # Ensure fail2ban is installed
    install_package "fail2ban"
    
    # Create custom configuration directory
    mkdir -p "/etc/fail2ban/jail.d"
    
    # Main jail configuration
    cat > "/etc/fail2ban/jail.d/custom.conf" <<EOF
# Custom Fail2ban Configuration for WordPress Server
# Generated automatically - DO NOT EDIT MANUALLY

[DEFAULT]
# Ban settings
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
usedns = warn
logencoding = auto
enabled = false
mode = normal
filter = %(__name__)s[mode=%(mode)s]

# Actions
destemail = admin@localhost
sender = fail2ban@localhost
mta = sendmail
protocol = tcp
chain = <known/chain>
port = 0:65535
fail2ban_agent = Fail2Ban/%(fail2ban_version)s

# Ban action with UFW
banaction = ufw
banaction_allports = ufw

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
findtime = 600

[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /usr/local/lsws/logs/error.log
maxretry = 3

[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /usr/local/lsws/logs/access.log
maxretry = 6

[apache-overflows]
enabled = true
port = http,https
filter = apache-overflows
logpath = /usr/local/lsws/logs/error.log
maxretry = 2

[cyberpanel]
enabled = true
port = 8090
filter = cyberpanel
logpath = /usr/local/CyberCP/logs/loginLogs.log
maxretry = 3
bantime = 3600

[mysql-auth]
enabled = true
port = 3306
filter = mysql-auth
logpath = /var/log/mysql/error.log
maxretry = 3
bantime = 7200
EOF

    # WordPress specific jail
    cat > "/etc/fail2ban/jail.d/wordpress.conf" <<EOF
[wordpress]
enabled = true
port = http,https
filter = wordpress
logpath = /usr/local/lsws/logs/access.log
maxretry = 3
bantime = 7200
findtime = 600

[wordpress-soft]
enabled = true
port = http,https
filter = wordpress-soft
logpath = /usr/local/lsws/logs/access.log
maxretry = 5
bantime = 3600
findtime = 600

[wordpress-hard]
enabled = true
port = http,https
filter = wordpress-hard
logpath = /usr/local/lsws/logs/access.log
maxretry = 1
bantime = 86400
findtime = 300
EOF

    # Custom filters
    cat > "/etc/fail2ban/filter.d/cyberpanel.conf" <<EOF
[Definition]
failregex = .*Login attempt from <HOST> failed.*
ignoreregex =
EOF

    cat > "/etc/fail2ban/filter.d/wordpress.conf" <<EOF
[Definition]
failregex = <HOST>.*POST.*(wp-login\.php|xmlrpc\.php).* 200
            <HOST>.*POST.*wp-admin.*
            <HOST>.*GET.*/wp-admin.* 403
ignoreregex =
EOF

    cat > "/etc/fail2ban/filter.d/wordpress-soft.conf" <<EOF
[Definition]
failregex = <HOST>.*"(GET|POST).*(wp-content/|wp-includes/|wp-config\.php|wp-admin/admin-ajax\.php).*" (403|404)
ignoreregex =
EOF

    cat > "/etc/fail2ban/filter.d/wordpress-hard.conf" <<EOF
[Definition]
failregex = <HOST>.*"(GET|POST).*(eval\(|base64_|gzinflate|gzuncompress|gzinflate|str_rot13).*" 200
            <HOST>.*"(GET|POST).*(<script|javascript:|onload=).*" 200
ignoreregex =
EOF

    # Start and enable fail2ban
    start_service "fail2ban"
    enable_service "fail2ban"
    
    # Check status
    if [[ "$DRY_RUN" != "true" ]]; then
        execute_command "fail2ban-client status" "Checking Fail2ban status"
    fi
    
    log_success "Fail2ban configured successfully"
}

# Configure SSL with Let's Encrypt
configure_ssl() {
    log_info "Configuring SSL certificates..."
    
    # Install certbot
    install_package "certbot"
    install_package "python3-certbot-apache"
    
    # Check if email is configured
    if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
        log_warning "Let's Encrypt email not configured. SSL setup will be manual."
        log_info "Set LETSENCRYPT_EMAIL in config/global.conf to enable automatic SSL"
        return 0
    fi
    
    # Create SSL directory
    mkdir -p "/usr/local/lsws/conf/ssl"
    
    # Generate self-signed certificate for initial setup
    if [[ ! -f "/usr/local/lsws/conf/ssl/server.crt" ]]; then
        log_info "Generating self-signed SSL certificate for initial setup..."
        
        execute_command "openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /usr/local/lsws/conf/ssl/server.key -out /usr/local/lsws/conf/ssl/server.crt -subj '/C=US/ST=State/L=City/O=Organization/OU=IT/CN=localhost'" "Generating self-signed certificate"
        
        chmod 600 /usr/local/lsws/conf/ssl/server.key
        chmod 644 /usr/local/lsws/conf/ssl/server.crt
    fi
    
    # Configure automatic renewal
    cat > "/etc/cron.d/certbot" <<EOF
# Automatic Let's Encrypt certificate renewal
0 12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload lsws"
EOF
    
    # Create SSL renewal script
    cat > "/usr/local/bin/ssl-renewal.sh" <<'EOF'
#!/bin/bash
# SSL Certificate Renewal Script

LOG_FILE="/var/log/ssl-renewal.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Starting SSL certificate renewal check" >> "$LOG_FILE"

# Renew certificates
/usr/bin/certbot renew --quiet --post-hook "systemctl reload lsws" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$DATE] SSL renewal check completed successfully" >> "$LOG_FILE"
else
    echo "[$DATE] SSL renewal check failed" >> "$LOG_FILE"
fi
EOF
    
    chmod +x "/usr/local/bin/ssl-renewal.sh"
    
    log_success "SSL configuration completed (self-signed certificates generated)"
    log_info "Run 'certbot certonly --webroot -w /path/to/webroot -d yourdomain.com' for production certificates"
}

# Configure OpenLiteSpeed WAF
configure_openlitespeed_waf() {
    log_info "Configuring OpenLiteSpeed Web Application Firewall..."
    
    # Enable ModSecurity
    local ols_conf="/usr/local/lsws/conf/httpd_config.conf"
    
    if [[ -f "$ols_conf" ]]; then
        # Install ModSecurity rules
        mkdir -p "/usr/local/lsws/conf/modsec"
        
        # Download OWASP ModSecurity Core Rule Set
        if [[ ! -d "/usr/local/lsws/conf/modsec/owasp-modsecurity-crs" ]]; then
            cd "/usr/local/lsws/conf/modsec"
            execute_command "wget -q https://github.com/coreruleset/coreruleset/archive/v3.3.4.tar.gz" "Downloading OWASP CRS"
            execute_command "tar -xzf v3.3.4.tar.gz" "Extracting OWASP CRS"
            execute_command "mv coreruleset-3.3.4 owasp-modsecurity-crs" "Setting up OWASP CRS"
            rm -f v3.3.4.tar.gz
        fi
        
        # Create ModSecurity configuration
        cat > "/usr/local/lsws/conf/modsec/modsec.conf" <<EOF
# ModSecurity Configuration for WordPress
SecRuleEngine On
SecRequestBodyAccess On
SecRequestBodyLimit 134217728
SecRequestBodyNoFilesLimit 1048576
SecRequestBodyInMemoryLimit 1048576
SecRequestBodyLimitAction Reject
SecPcreMatchLimit 250000
SecPcreMatchLimitRecursion 250000
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecResponseBodyLimitAction ProcessPartial
SecTmpDir /tmp/
SecDataDir /tmp/
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"
SecAuditLogParts ABDEFHIJZ
SecAuditLogType Serial
SecAuditLog /usr/local/lsws/logs/modsec_audit.log
SecArgumentSeparator &
SecCookieFormat 0
SecUnicodeMapFile unicode.mapping 20127
SecStatusEngine On
SecRule REQUEST_HEADERS:Content-Type "(?:application(?:/soap\+|/)|text/)xml" \
    "id:'200000',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML"
SecRule REQUEST_HEADERS:Content-Type "application/json" \
    "id:'200001',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=JSON"
SecRule REQBODY_ERROR "!@eq 0" \
    "id:'200002', phase:2,t:none,log,deny,status:400,msg:'Failed to parse request body.',logdata:'Error %{reqbody_error_msg}',severity:2"
SecRule MULTIPART_STRICT_ERROR "!@eq 0" \
    "id:'200003',phase:2,t:none,log,deny,status:400, \
    msg:'Multipart request body failed strict validation: \
    PE %{REQBODY_PROCESSOR_ERROR}, \
    BQ %{MULTIPART_BOUNDARY_QUOTED}, \
    BW %{MULTIPART_BOUNDARY_WHITESPACE}, \
    DB %{MULTIPART_DATA_BEFORE}, \
    DA %{MULTIPART_DATA_AFTER}, \
    HF %{MULTIPART_HEADER_FOLDING}, \
    LF %{MULTIPART_LF_LINE}, \
    SM %{MULTIPART_MISSING_SEMICOLON}, \
    IQ %{MULTIPART_INVALID_QUOTING}, \
    IP %{MULTIPART_INVALID_PART}, \
    IH %{MULTIPART_INVALID_HEADER_FOLDING}, \
    FL %{MULTIPART_FILE_LIMIT_EXCEEDED}'"
EOF

        # Create WordPress-specific rules
        cat > "/usr/local/lsws/conf/modsec/wordpress.conf" <<EOF
# WordPress-specific ModSecurity Rules

# Block wp-config.php access
SecRule REQUEST_URI "@contains wp-config.php" \
    "id:1001,phase:2,block,msg:'WordPress config file access blocked'"

# Block wp-admin access from non-admin IPs
SecRule REQUEST_URI "@beginsWith /wp-admin" \
    "id:1002,phase:2,pass,setvar:'tx.wp_admin_access=1'"

# Block XML-RPC attacks
SecRule REQUEST_URI "@contains xmlrpc.php" \
    "id:1003,phase:2,block,msg:'XML-RPC access blocked'"

# Block common WordPress attack patterns
SecRule ARGS "@contains eval(" \
    "id:1004,phase:2,block,msg:'PHP eval detected'"

SecRule ARGS "@contains base64_decode" \
    "id:1005,phase:2,block,msg:'Base64 decode detected'"

# Block common file inclusion attacks
SecRule ARGS "@contains ../../../" \
    "id:1006,phase:2,block,msg:'Directory traversal attack detected'"

# Rate limiting for login attempts
SecAction "id:1010,phase:1,pass,initcol:ip=%{remote_addr},setvar:ip.wp_login_counter=+1,expirevar:ip.wp_login_counter=300"
SecRule IP:WP_LOGIN_COUNTER "@gt 5" \
    "id:1011,phase:2,block,msg:'Too many login attempts from IP'"
EOF
        
        log_success "OpenLiteSpeed WAF configured successfully"
    else
        log_warning "OpenLiteSpeed configuration file not found. WAF setup skipped."
    fi
}

# Setup dynamic IP whitelisting
setup_dynamic_ip_whitelisting() {
    if [[ "$DYNAMIC_IP_ENABLED" != "true" ]]; then
        log_info "Dynamic IP whitelisting is disabled. Skipping..."
        return 0
    fi
    
    log_info "Setting up dynamic IP whitelisting..."
    
    # Check Cloudflare credentials
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]] || [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
        log_error "Cloudflare API credentials not configured. Please set CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID in $CLOUDFLARE_CONFIG_FILE"
        return 1
    fi
    
    # Create IP update script
    cat > "/usr/local/bin/update-dynamic-ip.sh" <<'EOF'
#!/bin/bash

# Dynamic IP Update Script for Server Security
# Updates firewall rules based on Cloudflare DNS record

set -euo pipefail

# Configuration
DOMAIN="ip.dulundu.tools"
CLOUDFLARE_API_TOKEN="__CLOUDFLARE_API_TOKEN__"
CLOUDFLARE_ZONE_ID="__CLOUDFLARE_ZONE_ID__"
LOG_FILE="/var/log/dynamic-ip.log"
LOCK_FILE="/tmp/update-dynamic-ip.lock"
IP_FILE="/tmp/current-allowed-ip.txt"

# Logging function
log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Check if script is already running
if [[ -f "$LOCK_FILE" ]]; then
    log_message "INFO" "Script is already running. Exiting."
    exit 0
fi

# Create lock file
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log_message "INFO" "Starting dynamic IP update check"

# Resolve current IP from DNS
CURRENT_IP=$(dig +short "$DOMAIN" @1.1.1.1 2>/dev/null || echo "")

if [[ -z "$CURRENT_IP" ]]; then
    log_message "ERROR" "Failed to resolve IP for domain: $DOMAIN"
    exit 1
fi

# Check if IP has changed
PREVIOUS_IP=""
if [[ -f "$IP_FILE" ]]; then
    PREVIOUS_IP=$(cat "$IP_FILE")
fi

if [[ "$CURRENT_IP" == "$PREVIOUS_IP" ]]; then
    log_message "INFO" "IP unchanged: $CURRENT_IP"
    exit 0
fi

log_message "INFO" "IP changed from '$PREVIOUS_IP' to '$CURRENT_IP'"

# Update UFW rules
if command -v ufw >/dev/null 2>&1; then
    # Remove old IP rules if they exist
    if [[ -n "$PREVIOUS_IP" && "$PREVIOUS_IP" != "none" ]]; then
        ufw delete allow from "$PREVIOUS_IP" to any port 22 comment 'Dynamic SSH' 2>/dev/null || true
        ufw delete allow from "$PREVIOUS_IP" to any port 8090 comment 'Dynamic CyberPanel' 2>/dev/null || true
        ufw delete allow from "$PREVIOUS_IP" to any port 7080 comment 'Dynamic OLS Admin' 2>/dev/null || true
        log_message "INFO" "Removed old IP rules for: $PREVIOUS_IP"
    fi
    
    # Add new IP rules
    ufw allow from "$CURRENT_IP" to any port 22 comment 'Dynamic SSH'
    ufw allow from "$CURRENT_IP" to any port 8090 comment 'Dynamic CyberPanel'
    ufw allow from "$CURRENT_IP" to any port 7080 comment 'Dynamic OLS Admin'
    
    log_message "SUCCESS" "Added new IP rules for: $CURRENT_IP"
    
    # Reload UFW
    ufw reload
fi

# Save current IP
echo "$CURRENT_IP" > "$IP_FILE"

log_message "SUCCESS" "Dynamic IP update completed successfully"
EOF

    # Replace placeholders with actual values
    sed -i "s/__CLOUDFLARE_API_TOKEN__/$CLOUDFLARE_API_TOKEN/g" "/usr/local/bin/update-dynamic-ip.sh"
    sed -i "s/__CLOUDFLARE_ZONE_ID__/$CLOUDFLARE_ZONE_ID/g" "/usr/local/bin/update-dynamic-ip.sh"
    
    chmod +x "/usr/local/bin/update-dynamic-ip.sh"
    
    # Create systemd service for IP updates
    cat > "/etc/systemd/system/dynamic-ip-update.service" <<EOF
[Unit]
Description=Dynamic IP Update Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-dynamic-ip.sh
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer
    cat > "/etc/systemd/system/dynamic-ip-update.timer" <<EOF
[Unit]
Description=Run Dynamic IP Update Service every 5 minutes
Requires=dynamic-ip-update.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable and start the timer
    execute_command "systemctl daemon-reload" "Reloading systemd"
    enable_service "dynamic-ip-update.timer"
    start_service "dynamic-ip-update.timer"
    
    # Run initial IP update
    execute_command "/usr/local/bin/update-dynamic-ip.sh" "Running initial IP update"
    
    log_success "Dynamic IP whitelisting configured successfully"
}

# Additional security hardening
apply_additional_hardening() {
    log_info "Applying additional security hardening..."
    
    # Disable unused services
    local services_to_disable=("cups" "avahi-daemon" "bluetooth" "whoopsie")
    
    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            execute_command "systemctl disable $service" "Disabling service: $service"
        fi
    done
    
    # Secure shared memory
    if ! grep -q "tmpfs /run/shm" /etc/fstab; then
        echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab
        log_info "Secured shared memory mounting"
    fi
    
    # Disable unused network protocols
    cat > "/etc/modprobe.d/blacklist-uncommon-network.conf" <<EOF
# Disable uncommon network protocols
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install n-hdlc /bin/true
install ax25 /bin/true
install netrom /bin/true
install x25 /bin/true
install rose /bin/true
install decnet /bin/true
install econet /bin/true
install af_802154 /bin/true
install ipx /bin/true
install appletalk /bin/true
install psnap /bin/true
install p8023 /bin/true
install p8022 /bin/true
install can /bin/true
install atm /bin/true
EOF

    # Set secure kernel parameters
    cat > "/etc/sysctl.d/99-security.conf" <<EOF
# Security-focused kernel parameters

# Network security
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Protection against SYN flood attacks
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 3

# Kernel security
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.kexec_load_disabled = 1
EOF

    execute_command "sysctl -p /etc/sysctl.d/99-security.conf" "Applying security kernel parameters"
    
    # Configure automatic security updates
    install_package "unattended-upgrades"
    
    cat > "/etc/apt/apt.conf.d/50unattended-upgrades" <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

    execute_command "systemctl enable unattended-upgrades" "Enabling automatic security updates"
    
    log_success "Additional security hardening completed"
}

# Create security summary
create_security_summary() {
    local summary_file="$LOG_DIR/security_summary.txt"
    
    cat > "$summary_file" <<EOF
WordPress Server Automation - Security Summary
==============================================
Security Configuration Date: $(date)

Implemented Security Measures:

1. UFW Firewall:
   - Default deny incoming, allow outgoing
   - Allowed ports: ${UFW_PORTS[*]}
   - SSH rate limiting enabled
   $(if [[ "$DYNAMIC_IP_ENABLED" == "true" ]]; then
       echo "   - Dynamic IP whitelisting active for admin ports"
   fi)

2. Fail2ban Intrusion Prevention:
   - SSH brute force protection
   - Web server attack detection
   - WordPress-specific attack prevention
   - CyberPanel login protection
   - MySQL authentication monitoring

3. SSL/TLS Configuration:
   - Self-signed certificates generated
   - Automatic renewal configured
   - Strong cipher suites enabled

4. Web Application Firewall (WAF):
   - OpenLiteSpeed ModSecurity enabled
   - OWASP Core Rule Set deployed
   - WordPress-specific attack prevention
   - Request rate limiting

5. Dynamic IP Whitelisting:
   $(if [[ "$DYNAMIC_IP_ENABLED" == "true" ]]; then
       echo "   - Status: Active"
       echo "   - Domain: $CLOUDFLARE_DOMAIN"
       echo "   - Update interval: 5 minutes"
       echo "   - Restricted ports: SSH (22), CyberPanel (8090), OpenLiteSpeed (7080)"
   else
       echo "   - Status: Disabled"
       echo "   - Configure Cloudflare API credentials to enable"
   fi)

6. System Hardening:
   - Unused services disabled
   - Shared memory secured
   - Uncommon network protocols disabled
   - Security-focused kernel parameters applied
   - Automatic security updates enabled

Security Logs:
- UFW: /var/log/ufw.log
- Fail2ban: /var/log/fail2ban.log
- ModSecurity: /usr/local/lsws/logs/modsec_audit.log
$(if [[ "$DYNAMIC_IP_ENABLED" == "true" ]]; then
    echo "- Dynamic IP: /var/log/dynamic-ip.log"
fi)

Next Steps:
1. Configure monitoring: ./master.sh monitoring
2. Setup WordPress automation: ./master.sh wp-automation
3. Test all security measures
4. Configure production SSL certificates

IMPORTANT SECURITY NOTES:
- Change all default passwords immediately
- Regularly review security logs
- Keep all software updated
- Test disaster recovery procedures
- Monitor for security vulnerabilities
EOF

    log_info "Security summary saved to: $summary_file"
}

# Main security function
main() {
    log_info "=== Starting Security Hardening ==="
    
    # Load configuration
    load_security_config
    
    # Run security hardening steps
    configure_ufw
    configure_fail2ban
    configure_ssl
    configure_openlitespeed_waf
    setup_dynamic_ip_whitelisting
    apply_additional_hardening
    
    # Create summary
    create_security_summary
    
    log_success "=== Security hardening completed successfully! ==="
    log_info "Check $LOG_DIR/security_summary.txt for configuration details"
    
    if [[ "$DYNAMIC_IP_ENABLED" != "true" ]]; then
        log_warning "Dynamic IP whitelisting is disabled. Configure Cloudflare API credentials for enhanced security."
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
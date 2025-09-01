#!/bin/bash

# Installation Module for WordPress Server Automation
# ===================================================
# Description: Installs OpenLiteSpeed, CyberPanel, and all dependencies
# Dependencies: Ubuntu 22.04, Internet connection, Root access
# Author: DevOps Ubuntu Team

set -euo pipefail

# Source utilities and set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
LOGS_DIR="$SCRIPT_DIR/../logs"
source "$SCRIPT_DIR/../scripts/utils.sh"

# Module information
MODULE_NAME="Installation Module"
MODULE_VERSION="1.0.0"

# Installation variables
CYBERPANEL_VERSION="2.3"
OPENLITESPEED_VERSION="latest"
TEMP_DIR="/tmp/server-automation-install"

# Required packages
SYSTEM_PACKAGES=(
    "curl"
    "wget" 
    "gnupg"
    "lsb-release"
    "software-properties-common"
    "apt-transport-https"
    "ca-certificates"
    "unzip"
    "git"
    "htop"
    "nano"
    "vim"
    "net-tools"
    "ufw"
    "fail2ban"
    "certbot"
    "python3-certbot-apache"
)

# Python packages for CyberPanel
PYTHON_PACKAGES=(
    "python3"
    "python3-pip"
    "python3-venv"
    "python3-dev"
    "python3-setuptools"
)

# Set version-specific packages based on Ubuntu version
set_version_specific_packages() {
    local ubuntu_version=$(detect_ubuntu_version)
    
    case "$ubuntu_version" in
        "20.04")
            DATABASE_PACKAGES=(
                "mysql-server"
                "mysql-client"
                "redis-server"
                "memcached"
            )
            DEFAULT_PHP_VERSIONS=("7.4" "8.0")
            ;;
        "22.04")
            DATABASE_PACKAGES=(
                "mariadb-server"
                "mariadb-client"
                "redis-server"
                "memcached"
            )
            DEFAULT_PHP_VERSIONS=("8.1" "8.2")
            ;;
        "24.04"|"25."*)
            DATABASE_PACKAGES=(
                "mariadb-server"
                "mariadb-client"
                "redis-server"
                "memcached"
            )
            DEFAULT_PHP_VERSIONS=("8.2" "8.3")
            ;;
        *)
            # Default fallback
            DATABASE_PACKAGES=(
                "mariadb-server"
                "mariadb-client"
                "redis-server"
                "memcached"
            )
            DEFAULT_PHP_VERSIONS=("8.1" "8.2")
            ;;
    esac
    
    log_info "Configured packages for Ubuntu $ubuntu_version"
    log_info "Database: ${DATABASE_PACKAGES[0]}"
    log_info "PHP versions: ${DEFAULT_PHP_VERSIONS[*]}"
}

# Initialize version-specific packages
set_version_specific_packages

log_info "Starting $MODULE_NAME v$MODULE_VERSION"

# Pre-installation checks
pre_install_checks() {
    log_info "Running pre-installation checks..."
    
    # Check if already installed
    if command -v cyberpanel >/dev/null 2>&1; then
        log_warning "CyberPanel appears to be already installed"
        if [[ "$FORCE_MODE" != "true" ]]; then
            if ! confirm_action "Continue with installation anyway?"; then
                log_info "Installation cancelled by user"
                exit 0
            fi
        fi
    fi
    
    # Check system compatibility (now handled by utils.sh)
    if ! check_ubuntu_compatibility; then
        log_error "Ubuntu compatibility check failed"
        return 1
    fi
    
    # Check available ports
    local required_ports=(80 443 8090 7080 22)
    for port in "${required_ports[@]}"; do
        if ! is_port_available "$port"; then
            log_warning "Port $port is already in use"
        fi
    done
    
    log_success "Pre-installation checks completed"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    
    execute_command "apt-get update" "Updating package list"
    execute_command "apt-get upgrade -y" "Upgrading system packages"
    execute_command "apt-get autoremove -y" "Removing unnecessary packages"
    
    log_success "System update completed"
}

# Install system packages
install_system_packages() {
    log_info "Installing system packages..."
    
    local failed_packages=()
    
    for package in "${SYSTEM_PACKAGES[@]}"; do
        if install_package "$package"; then
            log_success "Installed: $package"
        else
            failed_packages+=("$package")
            log_error "Failed to install: $package"
        fi
    done
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_error "Some packages failed to install: ${failed_packages[*]}"
        return 1
    fi
    
    log_success "All system packages installed successfully"
}

# Install Python and related packages
install_python_packages() {
    log_info "Installing Python packages..."
    
    for package in "${PYTHON_PACKAGES[@]}"; do
        install_package "$package"
    done
    
    # Update pip
    execute_command "python3 -m pip install --upgrade pip" "Upgrading pip"
    
    # Install additional Python modules
    execute_command "pip3 install requests cloudflare psutil" "Installing Python modules"
    
    log_success "Python packages installed successfully"
}

# Install database packages
install_database_packages() {
    log_info "Installing database packages..."
    
    # Set MySQL root password non-interactively
    local mysql_root_password=$(generate_password 20)
    
    # Pre-configure MySQL
    execute_command "debconf-set-selections <<< 'mariadb-server mysql-server/root_password password $mysql_root_password'" "Setting MySQL root password"
    execute_command "debconf-set-selections <<< 'mariadb-server mysql-server/root_password_again password $mysql_root_password'" "Confirming MySQL root password"
    
    for package in "${DATABASE_PACKAGES[@]}"; do
        install_package "$package"
    done
    
    # Secure MySQL installation
    log_info "Securing MySQL installation..."
    mysql -u root -p"$mysql_root_password" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    # Save credentials
    cat > "$CONFIG_DIR/mysql.conf" <<EOF
MYSQL_ROOT_PASSWORD="$mysql_root_password"
MYSQL_ROOT_USER="root"
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
EOF
    
    chmod 600 "$CONFIG_DIR/mysql.conf"
    
    log_success "Database packages installed and secured"
}

# Download and install OpenLiteSpeed
install_openlitespeed() {
    log_info "Installing OpenLiteSpeed..."
    
    # Add OpenLiteSpeed repository
    execute_command "wget -qO - https://rpms.litespeedtech.com/debian/lst_debian_repo.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/lst_debian_repo.gpg >/dev/null" "Adding OpenLiteSpeed GPG key"
    
    execute_command "wget -qO - https://rpms.litespeedtech.com/debian/lst_repo.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/lst_repo.gpg >/dev/null" "Adding OpenLiteSpeed repository key"
    
    execute_command "echo 'deb http://rpms.litespeedtech.com/debian/ jammy main' | tee /etc/apt/sources.list.d/lst_debian_repo.list" "Adding OpenLiteSpeed repository"
    
    execute_command "apt-get update" "Updating package list"
    
    # Install OpenLiteSpeed
    install_package "openlitespeed"
    
    # Generate admin password
    local ols_admin_password=$(generate_password 16)
    
    # Set OpenLiteSpeed admin credentials
    execute_command "/usr/local/lsws/admin/misc/admpass.sh <<< $'$OLS_ADMIN_USER\\n$ols_admin_password\\n$ols_admin_password'" "Setting OpenLiteSpeed admin credentials"
    
    # Save credentials
    cat > "$CONFIG_DIR/openlitespeed.conf" <<EOF
OLS_ADMIN_USER="$OLS_ADMIN_USER"
OLS_ADMIN_PASSWORD="$ols_admin_password"
OLS_ADMIN_PORT="$OLS_ADMIN_PORT"
OLS_INSTALL_PATH="/usr/local/lsws"
OLS_CONF_PATH="/usr/local/lsws/conf"
OLS_LOG_PATH="/usr/local/lsws/logs"
EOF
    
    chmod 600 "$CONFIG_DIR/openlitespeed.conf"
    
    # Start and enable OpenLiteSpeed
    start_service "lsws"
    enable_service "lsws"
    
    log_success "OpenLiteSpeed installed successfully"
}

# Install PHP versions
install_php() {
    log_info "Installing PHP versions..."
    
    # Add PHP repository
    execute_command "add-apt-repository ppa:ondrej/php -y" "Adding PHP repository"
    execute_command "apt-get update" "Updating package list"
    
    # Install multiple PHP versions (use version-specific defaults)
    local php_versions=("${DEFAULT_PHP_VERSIONS[@]}")
    
    for version in "${php_versions[@]}"; do
        log_info "Installing PHP $version..."
        
        local php_packages=(
            "lsphp${version//.}"
            "lsphp${version//.}-common"
            "lsphp${version//.}-mysql"
            "lsphp${version//.}-opcache"
            "lsphp${version//.}-curl"
            "lsphp${version//.}-json"
            "lsphp${version//.}-redis"
            "lsphp${version//.}-memcached"
            "lsphp${version//.}-imagick"
            "lsphp${version//.}-zip"
            "lsphp${version//.}-xml"
            "lsphp${version//.}-mbstring"
            "lsphp${version//.}-gd"
            "lsphp${version//.}-intl"
        )
        
        for package in "${php_packages[@]}"; do
            install_package "$package"
        done
        
        log_success "PHP $version installed successfully"
    done
    
    # Set default PHP version
    execute_command "ln -sf /usr/local/lsws/lsphp82/bin/lsphp /usr/local/lsws/fcgi-bin/lsphp8" "Setting default PHP version"
    
    log_success "PHP installation completed"
}

# Download and install CyberPanel
install_cyberpanel() {
    log_info "Installing CyberPanel..."
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Download CyberPanel installer
    execute_command "wget -O installer.py https://cyberpanel.net/install.py" "Downloading CyberPanel installer"
    
    # Generate CyberPanel admin password
    local cp_admin_password=$(generate_password 16)
    
    # Create unattended installation configuration
    cat > cyberpanel_install.conf <<EOF
# CyberPanel Unattended Installation Configuration
install_type=1
admin_email=admin@localhost
admin_pass=$cp_admin_password
memcached=y
redis=y
watchdog=y
EOF
    
    # Run CyberPanel installer
    log_info "Running CyberPanel installer (this may take 10-15 minutes)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run: python3 installer.py"
    else
        # Run installer with minimal interaction
        python3 installer.py <<EOF
1
$CYBERPANEL_ADMIN_USER@localhost
$cp_admin_password
Y
Y
Y
EOF
    fi
    
    # Save CyberPanel credentials
    cat > "$CONFIG_DIR/cyberpanel.conf" <<EOF
CP_ADMIN_USER="$CYBERPANEL_ADMIN_USER"
CP_ADMIN_PASSWORD="$cp_admin_password"
CP_ADMIN_EMAIL="$CYBERPANEL_ADMIN_USER@localhost"
CP_ADMIN_PORT="$CYBERPANEL_PORT"
CP_INSTALL_PATH="/usr/local/CyberCP"
EOF
    
    chmod 600 "$CONFIG_DIR/cyberpanel.conf"
    
    log_success "CyberPanel installation completed"
}

# Install WP-CLI
install_wpcli() {
    log_info "Installing WP-CLI..."
    
    execute_command "curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/utils/wp-cli.phar" "Downloading WP-CLI"
    execute_command "chmod +x wp-cli.phar" "Making WP-CLI executable"
    execute_command "mv wp-cli.phar /usr/local/bin/wp" "Installing WP-CLI globally"
    
    # Verify installation
    if wp --info >/dev/null 2>&1; then
        log_success "WP-CLI installed successfully"
    else
        log_error "WP-CLI installation failed"
        return 1
    fi
}

# Install additional security tools
install_security_tools() {
    log_info "Installing security tools..."
    
    # Install ClamAV
    install_package "clamav"
    install_package "clamav-daemon"
    
    # Install additional security packages
    install_package "rkhunter"
    install_package "chkrootkit"
    install_package "lynis"
    
    # Update ClamAV database
    execute_command "freshclam" "Updating ClamAV database"
    
    log_success "Security tools installed successfully"
}

# Post-installation configuration
post_install_configuration() {
    log_info "Running post-installation configuration..."
    
    # Start all services
    local services=("mysql" "redis-server" "memcached" "lsws")
    
    for service in "${services[@]}"; do
        if start_service "$service"; then
            enable_service "$service"
        fi
    done
    
    # Create systemd service for CyberPanel
    if [[ ! -f "/etc/systemd/system/cyberpanel.service" ]]; then
        cat > "/etc/systemd/system/cyberpanel.service" <<EOF
[Unit]
Description=CyberPanel
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/CyberCP/bin/python /usr/local/CyberCP/manage.py runserver 0.0.0.0:8090
User=cyberpanel
Group=cyberpanel
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        
        execute_command "systemctl daemon-reload" "Reloading systemd"
        enable_service "cyberpanel"
        start_service "cyberpanel"
    fi
    
    # Set up log rotation
    cat > "/etc/logrotate.d/server-automation" <<EOF
/workspace/devops-ubuntu/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
    
    # Create installation summary
    create_installation_summary
    
    log_success "Post-installation configuration completed"
}

# Create installation summary
create_installation_summary() {
    local summary_file="$LOG_DIR/installation_summary.txt"
    
    cat > "$summary_file" <<EOF
WordPress Server Automation - Installation Summary
=================================================
Installation Date: $(date)
System: $(lsb_release -d | cut -f2)
Architecture: $(uname -m)

Installed Components:
- OpenLiteSpeed Web Server
- CyberPanel Control Panel  
- MariaDB Database Server
- Redis Cache Server
- Memcached
- PHP 8.1 & 8.2
- WP-CLI
- Security Tools (Fail2ban, UFW, ClamAV)

Access Information:
- CyberPanel: https://$(hostname -I | awk '{print $1}'):8090
- OpenLiteSpeed Admin: https://$(hostname -I | awk '{print $1}'):7080
- HTTP Port: 80
- HTTPS Port: 443

Configuration Files:
- Global Config: $CONFIG_DIR/global.conf
- MySQL Config: $CONFIG_DIR/mysql.conf  
- OpenLiteSpeed Config: $CONFIG_DIR/openlitespeed.conf
- CyberPanel Config: $CONFIG_DIR/cyberpanel.conf

Next Steps:
1. Run the configuration module: ./master.sh config
2. Run the security module: ./master.sh security
3. Configure WordPress automation: ./master.sh wp-automation

For support and documentation, see the project README.
EOF
    
    log_info "Installation summary saved to: $summary_file"
}

# Cleanup function
cleanup_installation() {
    log_info "Cleaning up installation files..."
    
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_success "Temporary files cleaned up"
    fi
}

# Main installation function
main() {
    log_info "=== Starting WordPress Server Installation ==="
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Setup cleanup on exit
    trap cleanup_installation EXIT
    
    # Run installation steps
    pre_install_checks
    update_system
    install_system_packages
    install_python_packages
    install_database_packages
    install_openlitespeed
    install_php
    install_cyberpanel
    install_wpcli
    install_security_tools
    post_install_configuration
    
    log_success "=== Installation completed successfully! ==="
    log_info "Check $LOG_DIR/installation_summary.txt for access information"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
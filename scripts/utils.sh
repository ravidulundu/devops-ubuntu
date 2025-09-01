#!/bin/bash

# Utility Functions for WordPress Server Automation
# =================================================

# Source global configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/global.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Error: Global configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure LOG_DIR is set, fallback to a default location
    if [[ -z "$LOG_DIR" ]]; then
        if [[ -n "$LOGS_DIR" ]]; then
            LOG_DIR="$LOGS_DIR"
        else
            # Fallback to script directory
            local fallback_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../logs"
            LOG_DIR="$fallback_dir"
        fi
    fi
    
    # Create log directory if it doesn't exist
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        # If we can't create the log directory, skip file logging
        echo "Warning: Cannot create log directory $LOG_DIR" >&2
    else
        # Log to file with error handling
        if ! echo "[$timestamp] [$level] $message" >> "$LOG_DIR/automation.log" 2>/dev/null; then
            echo "Warning: Cannot write to log file $LOG_DIR/automation.log" >&2
        fi
    fi
    
    # Log to console based on level
    case $level in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "DEBUG")
            if [[ "$DEBUG_MODE" == "true" ]]; then
                echo -e "${PURPLE}[DEBUG]${NC} $message"
            fi
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Convenience logging functions
log_error() { log "ERROR" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_info() { log "INFO" "$1"; }
log_debug() { log "DEBUG" "$1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Ubuntu version compatibility detection
detect_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS version - /etc/os-release not found"
        return 1
    fi
    
    local version_id=$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
    echo "$version_id"
}

# Check Ubuntu version compatibility
check_ubuntu_compatibility() {
    local detected_version=$(detect_ubuntu_version)
    
    if [[ -z "$detected_version" ]]; then
        log_error "Failed to detect Ubuntu version"
        return 1
    fi
    
    case "$detected_version" in
        "22.04")
            log_success "Running on Ubuntu 22.04 LTS - Fully supported and tested"
            return 0
            ;;
        "24.04")
            log_info "Running on Ubuntu 24.04 LTS - Supported with minor adjustments"
            log_warning "Some package versions may differ from tested configuration"
            return 0
            ;;
        "20.04")
            log_warning "Running on Ubuntu 20.04 LTS - Limited support"
            log_warning "Some features may require manual configuration"
            return 0
            ;;
        "25.04"|"25.10")
            log_info "Running on Ubuntu $detected_version - Experimental support"
            log_warning "This version is newer than tested configurations"
            return 0
            ;;
        *)
            if grep -q "Ubuntu" /etc/os-release; then
                log_warning "Running on Ubuntu $detected_version - Untested version"
                log_warning "Proceed with caution - compatibility not guaranteed"
                return 0
            else
                log_error "This script requires Ubuntu Linux (detected: non-Ubuntu system)"
                return 1
            fi
            ;;
    esac
}

# Get version-specific package names and configurations
get_version_specific_config() {
    local detected_version=$(detect_ubuntu_version)
    
    case "$detected_version" in
        "20.04")
            # Older PHP versions available
            export PREFERRED_PHP_VERSION="7.4"
            export MYSQL_PACKAGE="mysql-server"
            ;;
        "22.04")
            # Standard configuration
            export PREFERRED_PHP_VERSION="8.1"
            export MYSQL_PACKAGE="mariadb-server"
            ;;
        "24.04"|"25."*)
            # Newer versions with updated packages
            export PREFERRED_PHP_VERSION="8.2"
            export MYSQL_PACKAGE="mariadb-server"
            # Additional repositories may be needed for some packages
            ;;
        *)
            # Default fallback
            export PREFERRED_PHP_VERSION="8.1"
            export MYSQL_PACKAGE="mariadb-server"
            ;;
    esac
}

# Check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check Ubuntu version compatibility
    if ! check_ubuntu_compatibility; then
        log_error "Ubuntu version compatibility check failed"
        return 1
    fi
    
    # Load version-specific configuration
    get_version_specific_config
    log_info "Configured for PHP $PREFERRED_PHP_VERSION and $MYSQL_PACKAGE"
    
    # Check available memory
    local available_memory=$(free -m | awk 'NR==2{print $2}')
    if [[ $available_memory -lt $REQUIRED_MEMORY_MB ]]; then
        log_error "Insufficient memory. Required: ${REQUIRED_MEMORY_MB}MB, Available: ${available_memory}MB"
        return 1
    fi
    
    # Check available disk space
    local available_disk=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $available_disk -lt $REQUIRED_DISK_GB ]]; then
        log_error "Insufficient disk space. Required: ${REQUIRED_DISK_GB}GB, Available: ${available_disk}GB"
        return 1
    fi
    
    log_success "System requirements check passed"
    return 0
}

# Check if a service is running
is_service_running() {
    local service=$1
    systemctl is-active --quiet "$service"
    return $?
}

# Start a service
start_service() {
    local service=$1
    log_info "Starting service: $service"
    
    if systemctl start "$service"; then
        log_success "Service $service started successfully"
        return 0
    else
        log_error "Failed to start service: $service"
        return 1
    fi
}

# Enable a service
enable_service() {
    local service=$1
    log_info "Enabling service: $service"
    
    if systemctl enable "$service"; then
        log_success "Service $service enabled successfully"
        return 0
    else
        log_error "Failed to enable service: $service"
        return 1
    fi
}

# Check if package has available updates
check_package_updates() {
    local package=$1
    
    # Update package cache if older than 1 hour
    local cache_file="/var/cache/apt/pkgcache.bin"
    if [[ ! -f "$cache_file" ]] || [[ $(find "$cache_file" -mmin +60 2>/dev/null | wc -l) -gt 0 ]]; then
        log_debug "Updating package cache..."
        apt-get update -qq >/dev/null 2>&1
    fi
    
    # Check if package has updates available
    local upgradeable=$(apt list --upgradeable 2>/dev/null | grep "^$package/" | wc -l)
    return $([[ $upgradeable -eq 0 ]] && echo 1 || echo 0)
}

# Smart package installation - handles installation, updates, and version checking
install_package() {
    local package=$1
    local force_reinstall=${2:-false}
    
    # Check if package is installed
    if dpkg -l | grep -q "^ii  $package "; then
        local installed_version=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null)
        
        if [[ $force_reinstall == "true" ]]; then
            log_info "Force reinstalling package: $package"
            if apt-get install --reinstall -y "$package" >/dev/null 2>&1; then
                log_success "Package $package reinstalled successfully"
                return 0
            else
                log_error "Failed to reinstall package: $package"
                return 1
            fi
        elif check_package_updates "$package"; then
            log_info "Updating package: $package (current: $installed_version)"
            if apt-get install -y "$package" >/dev/null 2>&1; then
                local new_version=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null)
                log_success "Package $package updated successfully ($installed_version → $new_version)"
                return 0
            else
                log_error "Failed to update package: $package"
                return 1
            fi
        else
            log_debug "Package $package is already installed and up-to-date ($installed_version)"
            return 0
        fi
    else
        # Package not installed, install it
        log_info "Installing package: $package"
        if apt-get install -y "$package" >/dev/null 2>&1; then
            local new_version=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null)
            log_success "Package $package installed successfully ($new_version)"
            return 0
        else
            log_error "Failed to install package: $package"
            return 1
        fi
    fi
}

# Create backup of a file or directory
create_backup() {
    local source=$1
    local backup_name=${2:-$(basename "$source")_$(date +%Y%m%d_%H%M%S)}
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$BACKUP_DIR"
    
    if [[ -e "$source" ]]; then
        log_info "Creating backup of $source"
        if cp -r "$source" "$backup_path"; then
            log_success "Backup created: $backup_path"
            return 0
        else
            log_error "Failed to create backup of $source"
            return 1
        fi
    else
        log_warning "Source not found for backup: $source"
        return 1
    fi
}

# Validate configuration file
validate_config() {
    local config_file=$1
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Basic validation - check for required variables
    local required_vars=("PROJECT_NAME" "LOG_DIR" "BACKUP_DIR")
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" "$config_file"; then
            log_error "Required configuration variable missing: $var"
            return 1
        fi
    done
    
    log_success "Configuration validation passed"
    return 0
}

# Get current public IP
get_public_ip() {
    local ip
    ip=$(curl -s https://ipinfo.io/ip 2>/dev/null)
    
    if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    else
        log_error "Failed to retrieve public IP"
        return 1
    fi
}

# Check if port is available
is_port_available() {
    local port=$1
    
    # Use ss command (modern replacement for netstat)
    if ss -tuln | grep -q ":$port "; then
        return 1  # Port is in use
    else
        return 0  # Port is available
    fi
}

# Generate random password
generate_password() {
    local length=${1:-16}
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
}

# Check internet connectivity
check_internet() {
    log_info "Checking internet connectivity..."
    
    if ping -c 1 google.com >/dev/null 2>&1; then
        log_success "Internet connectivity confirmed"
        return 0
    else
        log_error "No internet connectivity"
        return 1
    fi
}

# Cleanup old log files
cleanup_logs() {
    if [[ -d "$LOG_DIR" ]]; then
        log_info "Cleaning up old log files..."
        find "$LOG_DIR" -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete
        log_success "Log cleanup completed"
    fi
}

# Cleanup old backups
cleanup_backups() {
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Cleaning up old backups..."
        find "$BACKUP_DIR" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete
        log_success "Backup cleanup completed"
    fi
}

# Display system information
show_system_info() {
    log_info "=== System Information ==="
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "CPU Cores: $(nproc)"
    echo "Total Memory: $(free -h | awk 'NR==2{print $2}')"
    echo "Available Disk: $(df -h / | awk 'NR==2{print $4}')"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo "==========================="
}

# Wait for user confirmation
confirm_action() {
    local message=${1:-"Do you want to continue?"}
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would prompt: $message"
        return 0
    fi
    
    echo -n "$message [y/N]: "
    read -r response
    
    case $response in
        [yY][eS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Execute command with logging
execute_command() {
    local command=$1
    local description=${2:-"Executing command"}
    
    log_info "$description: $command"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $command"
        return 0
    fi
    
    if eval "$command"; then
        log_success "Command executed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Command failed with exit code: $exit_code"
        return $exit_code
    fi
}

# Detect hardware specifications
detect_hardware() {
    log_info "Detecting hardware specifications..."
    
    # CPU information
    CPU_CORES=$(nproc)
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    
    # Memory information
    TOTAL_RAM_MB=$(free -m | awk 'NR==2{print $2}')
    AVAILABLE_RAM_MB=$(free -m | awk 'NR==2{print $7}')
    
    # Disk information
    TOTAL_DISK_GB=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
    AVAILABLE_DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    
    # Network information
    if command -v ip >/dev/null 2>&1; then
        NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    elif command -v route >/dev/null 2>&1; then
        NETWORK_INTERFACE=$(route -n | grep '^0.0.0.0' | awk '{print $8}' | head -n1)
    else
        NETWORK_INTERFACE="eth0"  # Default fallback
        log_warning "Neither 'ip' nor 'route' command available, using default interface: eth0"
    fi
    
    log_info "Hardware Detection Results:"
    log_info "CPU: $CPU_MODEL ($CPU_CORES cores)"
    log_info "RAM: ${TOTAL_RAM_MB}MB total, ${AVAILABLE_RAM_MB}MB available"
    log_info "Disk: ${TOTAL_DISK_GB}GB total, ${AVAILABLE_DISK_GB}GB available"
    log_info "Network Interface: $NETWORK_INTERFACE"
}

# Export detected hardware values
export CPU_CORES TOTAL_RAM_MB AVAILABLE_RAM_MB TOTAL_DISK_GB AVAILABLE_DISK_GB NETWORK_INTERFACE
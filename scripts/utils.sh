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
    
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/automation.log"
    
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

# Check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check OS version
    if ! grep -q "Ubuntu 22.04" /etc/os-release; then
        log_warning "This script is optimized for Ubuntu 22.04. Current OS may not be fully supported."
    fi
    
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

# Install package if not already installed
install_package() {
    local package=$1
    
    if dpkg -l | grep -q "^ii  $package "; then
        log_info "Package $package is already installed"
        return 0
    fi
    
    log_info "Installing package: $package"
    
    if apt-get update && apt-get install -y "$package"; then
        log_success "Package $package installed successfully"
        return 0
    else
        log_error "Failed to install package: $package"
        return 1
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
    
    if netstat -tuln | grep -q ":$port "; then
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
    NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    log_info "Hardware Detection Results:"
    log_info "CPU: $CPU_MODEL ($CPU_CORES cores)"
    log_info "RAM: ${TOTAL_RAM_MB}MB total, ${AVAILABLE_RAM_MB}MB available"
    log_info "Disk: ${TOTAL_DISK_GB}GB total, ${AVAILABLE_DISK_GB}GB available"
    log_info "Network Interface: $NETWORK_INTERFACE"
}

# Export detected hardware values
export CPU_CORES TOTAL_RAM_MB AVAILABLE_RAM_MB TOTAL_DISK_GB AVAILABLE_DISK_GB NETWORK_INTERFACE
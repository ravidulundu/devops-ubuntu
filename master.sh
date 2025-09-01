#!/bin/bash

# Master Management Script for WordPress Server Automation
# ========================================================
# This script orchestrates all modules for complete server setup and management
# Usage: ./master.sh [options] [modules]

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIG_DIR="$SCRIPT_DIR/config"

# Source utilities
source "$SCRIPTS_DIR/utils.sh"

# Script metadata
SCRIPT_NAME="WordPress Server Automation Master"
SCRIPT_VERSION="1.0.0"
SCRIPT_AUTHOR="DevOps Ubuntu Team"

# Available modules
AVAILABLE_MODULES=(
    "install"
    "config" 
    "security"
    "wp-automation"
    "monitoring"
    "dynamic-tuning"
)

# Default execution flags
FORCE_MODE=false
QUIET_MODE=false
SKIP_CHECKS=false
MODULES_TO_RUN=()

# Display script header
show_header() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  $SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo -e "${CYAN}  $SCRIPT_AUTHOR${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo
}

# Display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [MODULES]

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show version information
    -f, --force             Force execution without confirmations
    -q, --quiet             Quiet mode (minimal output)
    -d, --debug             Enable debug mode
    --dry-run              Show what would be done without executing
    --skip-checks          Skip system requirement checks
    --list-modules         List all available modules
    --status               Show system status

MODULES (run in order if multiple specified):
    install                Install OpenLiteSpeed, CyberPanel, and dependencies
    config                 Optimize server and service configurations
    security               Implement security hardening measures
    wp-automation          Deploy and configure WordPress automation
    monitoring             Setup monitoring and logging systems
    dynamic-tuning         Configure hardware-based performance tuning
    all                    Run all modules in recommended order

EXAMPLES:
    $0 --help
    $0 install config security
    $0 all --force
    $0 dynamic-tuning --debug
    $0 --status
    $0 --dry-run all

For detailed module documentation, see the modules/ directory.
EOF
}

# Display version information
show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
    echo "Author: $SCRIPT_AUTHOR"
    echo "Supported OS: Ubuntu 20.04, 22.04, 24.04, 25.04+"
    echo "Dependencies: OpenLiteSpeed, CyberPanel, WordPress"
}

# List available modules
list_modules() {
    log_info "Available modules:"
    for module in "${AVAILABLE_MODULES[@]}"; do
        local module_file="$MODULES_DIR/${module}.sh"
        if [[ -f "$module_file" ]]; then
            local description=$(grep "^# Description:" "$module_file" | cut -d: -f2 | xargs)
            echo -e "  ${GREEN}$module${NC}: $description"
        else
            echo -e "  ${RED}$module${NC}: Module file not found"
        fi
    done
}

# Show system status
show_status() {
    log_info "=== System Status ==="
    
    # System information
    show_system_info
    
    # Service status
    echo -e "\n${BLUE}Service Status:${NC}"
    for service in "lshttpd" "cyberpanel" "mysql" "redis-server"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $service: Running"
        else
            echo -e "  ${RED}✗${NC} $service: Not running"
        fi
    done
    
    # Port status
    echo -e "\n${BLUE}Port Status:${NC}"
    for port in "80:HTTP" "443:HTTPS" "8090:CyberPanel" "7080:OpenLiteSpeed Admin"; do
        local port_num=$(echo "$port" | cut -d: -f1)
        local port_desc=$(echo "$port" | cut -d: -f2)
        
        if netstat -tuln | grep -q ":$port_num "; then
            echo -e "  ${GREEN}✓${NC} Port $port_num ($port_desc): Open"
        else
            echo -e "  ${RED}✗${NC} Port $port_num ($port_desc): Closed"
        fi
    done
    
    # Firewall status
    echo -e "\n${BLUE}Security Status:${NC}"
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status | head -n1 | awk '{print $2}')
        echo -e "  UFW Firewall: $ufw_status"
    fi
    
    if command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "  Fail2ban: Installed"
    else
        echo -e "  Fail2ban: Not installed"
    fi
    
    echo "===================="
}

# Validate module name
is_valid_module() {
    local module=$1
    [[ " ${AVAILABLE_MODULES[*]} " =~ " $module " ]]
}

# Execute a module
execute_module() {
    local module=$1
    local module_file="$MODULES_DIR/${module}.sh"
    
    log_info "Starting module: $module"
    
    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi
    
    if [[ ! -x "$module_file" ]]; then
        log_info "Making module executable: $module_file"
        chmod +x "$module_file"
    fi
    
    # Execute module with current environment
    if "$module_file"; then
        log_success "Module completed successfully: $module"
        return 0
    else
        log_error "Module failed: $module"
        return 1
    fi
}

# Pre-execution checks
run_pre_checks() {
    if [[ "$SKIP_CHECKS" == "true" ]]; then
        log_info "Skipping pre-execution checks"
        return 0
    fi
    
    log_info "Running pre-execution checks..."
    
    # Check if running as root
    check_root
    
    # Check system requirements
    if ! check_system_requirements; then
        log_error "System requirements not met"
        return 1
    fi
    
    # Check internet connectivity
    if ! check_internet; then
        log_error "Internet connectivity required"
        return 1
    fi
    
    # Validate configuration
    if ! validate_config "$CONFIG_FILE"; then
        log_error "Configuration validation failed"
        return 1
    fi
    
    log_success "Pre-execution checks passed"
    return 0
}

# Main execution function
main() {
    local failed_modules=()
    local successful_modules=()
    
    # Run pre-checks
    if ! run_pre_checks; then
        log_error "Pre-execution checks failed"
        exit 1
    fi
    
    # Detect hardware if dynamic tuning is enabled
    if [[ "$AUTO_TUNE_ENABLED" == "true" ]] || [[ " ${MODULES_TO_RUN[*]} " =~ " dynamic-tuning " ]]; then
        detect_hardware
    fi
    
    # Execute modules
    for module in "${MODULES_TO_RUN[@]}"; do
        if [[ "$FORCE_MODE" == "false" ]]; then
            if ! confirm_action "Execute module '$module'?"; then
                log_info "Skipping module: $module"
                continue
            fi
        fi
        
        if execute_module "$module"; then
            successful_modules+=("$module")
        else
            failed_modules+=("$module")
            
            if [[ "$FORCE_MODE" == "false" ]]; then
                if ! confirm_action "Module '$module' failed. Continue with remaining modules?"; then
                    break
                fi
            fi
        fi
    done
    
    # Report results
    log_info "=== Execution Summary ==="
    
    if [[ ${#successful_modules[@]} -gt 0 ]]; then
        log_success "Successful modules: ${successful_modules[*]}"
    fi
    
    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        log_error "Failed modules: ${failed_modules[*]}"
        exit 1
    else
        log_success "All modules completed successfully!"
        
        # Show final status
        if [[ "$QUIET_MODE" == "false" ]]; then
            echo
            show_status
        fi
    fi
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -f|--force)
                FORCE_MODE=true
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -d|--debug)
                DEBUG_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-checks)
                SKIP_CHECKS=true
                shift
                ;;
            --list-modules)
                list_modules
                exit 0
                ;;
            --status)
                show_status
                exit 0
                ;;
            all)
                MODULES_TO_RUN=("${AVAILABLE_MODULES[@]}")
                shift
                ;;
            install|config|security|wp-automation|monitoring|dynamic-tuning)
                if is_valid_module "$1"; then
                    MODULES_TO_RUN+=("$1")
                else
                    log_error "Invalid module: $1"
                    exit 1
                fi
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Show header unless in quiet mode
    if [[ "$QUIET_MODE" == "false" ]]; then
        show_header
    fi
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check if any modules were specified
    if [[ ${#MODULES_TO_RUN[@]} -eq 0 ]]; then
        log_error "No modules specified"
        echo
        show_usage
        exit 1
    fi
    
    # Create required directories
    mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$MODULES_DIR/temp"
    
    # Setup cleanup on exit
    trap 'cleanup_logs; cleanup_backups' EXIT
    
    # Run main function
    main
fi
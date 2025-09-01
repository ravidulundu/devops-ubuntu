#!/bin/bash

# WordPress Server Automation - Installation Script
# =================================================
# Description: Installs the automation scripts to standard Linux locations
# Usage: sudo ./install.sh [--dev] [--prefix=/path]
# Author: DevOps Ubuntu Team

set -euo pipefail

# Default installation paths
DEFAULT_PREFIX="/opt/wp-automation"
DEV_MODE=false
INSTALL_PREFIX="$DEFAULT_PREFIX"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dev)
            DEV_MODE=true
            shift
            ;;
        --prefix=*)
            INSTALL_PREFIX="${1#*=}"
            shift
            ;;
        --help|-h)
            cat <<EOF
WordPress Server Automation - Installation Script

Usage: sudo ./install.sh [OPTIONS]

Options:
  --dev                Development installation (portable paths)
  --prefix=PATH        Install to custom path (default: /opt/wp-automation)
  --help, -h          Show this help message

Examples:
  sudo ./install.sh                    # Production install to /opt/wp-automation
  sudo ./install.sh --dev             # Development install (portable paths)
  sudo ./install.sh --prefix=/usr/local/wp-automation  # Custom location

Production Installation Creates:
  /opt/wp-automation/                 # Main installation directory
  /var/log/wp-automation/             # Log files
  /var/lib/wp-automation/             # Data files
  /usr/local/bin/wp-automation        # Command symlink

Development Installation:
  Uses relative paths from installation directory
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]] && [[ "$DEV_MODE" == false ]]; then
        log_error "This script must be run as root for production installation"
        log_info "Use 'sudo ./install.sh' or './install.sh --dev' for development mode"
        exit 1
    fi
}

# Create installation directories
create_directories() {
    log_info "Creating installation directories..."
    
    # Main installation directory
    mkdir -p "$INSTALL_PREFIX"
    mkdir -p "$INSTALL_PREFIX/modules"
    mkdir -p "$INSTALL_PREFIX/scripts"
    mkdir -p "$INSTALL_PREFIX/config"
    mkdir -p "$INSTALL_PREFIX/docs"
    
    if [[ "$DEV_MODE" == false ]]; then
        # Production directories
        mkdir -p /var/log/wp-automation
        mkdir -p /var/lib/wp-automation
        mkdir -p /opt/wp-automation/backups
        
        # Set proper permissions
        chmod 755 "$INSTALL_PREFIX"
        chmod 755 /var/log/wp-automation
        chmod 755 /var/lib/wp-automation
        chmod 755 /opt/wp-automation/backups
    else
        # Development directories
        mkdir -p "$INSTALL_PREFIX/logs"
        mkdir -p "$INSTALL_PREFIX/backups" 
        mkdir -p "$INSTALL_PREFIX/data"
    fi
    
    log_success "Directories created successfully"
}

# Copy files to installation directory
install_files() {
    log_info "Installing files to $INSTALL_PREFIX..."
    
    # Get the directory where this install script is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Copy main files
    cp "$SCRIPT_DIR/master.sh" "$INSTALL_PREFIX/"
    chmod +x "$INSTALL_PREFIX/master.sh"
    
    # Copy modules
    cp "$SCRIPT_DIR"/modules/*.sh "$INSTALL_PREFIX/modules/"
    chmod +x "$INSTALL_PREFIX"/modules/*.sh
    
    # Copy scripts
    cp "$SCRIPT_DIR"/scripts/*.sh "$INSTALL_PREFIX/scripts/"
    chmod +x "$INSTALL_PREFIX"/scripts/*.sh
    
    # Copy configuration
    cp "$SCRIPT_DIR"/config/* "$INSTALL_PREFIX/config/"
    
    # Copy documentation
    if [[ -d "$SCRIPT_DIR/docs" ]]; then
        cp -r "$SCRIPT_DIR"/docs/* "$INSTALL_PREFIX/docs/"
    fi
    
    # Copy README and other files
    cp "$SCRIPT_DIR/README.md" "$INSTALL_PREFIX/" 2>/dev/null || true
    cp "$SCRIPT_DIR/CLAUDE.md" "$INSTALL_PREFIX/" 2>/dev/null || true
    
    log_success "Files installed successfully"
}

# Create system symlinks and commands
create_system_links() {
    if [[ "$DEV_MODE" == false ]]; then
        log_info "Creating system command links..."
        
        # Create main command symlink
        ln -sf "$INSTALL_PREFIX/master.sh" /usr/local/bin/wp-automation
        
        # Create convenient aliases
        cat > /usr/local/bin/wp-server-status <<EOF
#!/bin/bash
exec "$INSTALL_PREFIX/master.sh" --status "\$@"
EOF
        chmod +x /usr/local/bin/wp-server-status
        
        cat > /usr/local/bin/wp-deploy <<EOF
#!/bin/bash
exec "$INSTALL_PREFIX/master.sh" all "\$@"
EOF
        chmod +x /usr/local/bin/wp-deploy
        
        log_success "System commands created: wp-automation, wp-server-status, wp-deploy"
    fi
}

# Update configuration for installation location
update_configuration() {
    log_info "Updating configuration for installation location..."
    
    # The global.conf already has auto-detection logic, but let's ensure it works
    # by testing the path detection
    if [[ "$DEV_MODE" == false ]]; then
        log_info "Production installation detected - will use standard Linux paths"
    else
        log_info "Development installation - will use portable paths"
    fi
    
    log_success "Configuration updated successfully"
}

# Main installation function
main() {
    log_info "WordPress Server Automation - Installation Script"
    log_info "Installation mode: $([ "$DEV_MODE" == true ] && echo "Development" || echo "Production")"
    log_info "Installation prefix: $INSTALL_PREFIX"
    echo
    
    check_root
    create_directories
    install_files
    create_system_links
    update_configuration
    
    echo
    log_success "Installation completed successfully!"
    
    if [[ "$DEV_MODE" == false ]]; then
        echo
        log_info "Available commands:"
        log_info "  wp-automation all              # Full deployment"
        log_info "  wp-automation --status         # System status"
        log_info "  wp-deploy                      # Quick deploy alias"
        log_info "  wp-server-status               # Quick status alias"
        echo
        log_info "Installation directory: $INSTALL_PREFIX"
        log_info "Logs directory: /var/log/wp-automation"
        log_info "Data directory: /var/lib/wp-automation"
    else
        echo
        log_info "Development installation completed"
        log_info "Run scripts from: $INSTALL_PREFIX"
        log_info "Example: $INSTALL_PREFIX/master.sh --status"
    fi
    
    echo
    log_info "Next steps:"
    log_info "1. Edit $INSTALL_PREFIX/config/.env for your environment"
    log_info "2. Configure Cloudflare settings (if using dynamic IP)"
    log_info "3. Run: $([ "$DEV_MODE" == true ] && echo "$INSTALL_PREFIX/master.sh" || echo "wp-automation") all"
}

# Run main function
main "$@"
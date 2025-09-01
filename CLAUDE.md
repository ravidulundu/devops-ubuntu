# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **production-ready WordPress Server Automation project** that provides modular Bash scripts for automated installation, configuration, and maintenance of WordPress hosting infrastructure using CyberPanel and OpenLiteSpeed on multiple Ubuntu versions (20.04, 22.04, 24.04, 25.04+). The project follows a security-first, performance-optimized approach with **Linux FHS compliance**, **comprehensive log management**, hardware-aware tuning, and dynamic IP whitelisting capabilities.

## Architecture

The system follows a modular architecture with 7 core bash script modules:

1. **Master Management Script (master.sh)** - Central controller orchestrating all modules
2. **Installation Module (install.sh)** - Handles OpenLiteSpeed, CyberPanel, and dependency installation
3. **Configuration Module (config.sh)** - Optimizes server and service settings
4. **Security Module (security.sh)** - Implements firewall, WAF, SSL, and server hardening
5. **WordPress Automation Module (wp-automation.sh)** - Manages WordPress deployment, caching, backups
6. **Monitoring & Logging Module (monitoring.sh)** - Resource monitoring, logging, and alerting
7. **Dynamic Tuning Module (dynamic-tuning.sh)** - Hardware-based performance optimization

## Key Design Principles

- **Modularity**: Each script handles specific functionality and can operate independently
- **Idempotency**: Scripts can be run multiple times without adverse effects
- **Hardware-aware optimization**: Dynamic tuning based on server resources (RAM, CPU, disk)
- **Security-first approach**: Dynamic IP whitelisting via Cloudflare API integration
- **Extensible architecture**: Base interfaces designed for future expansion
- **DevOps Best Practices**: Environment-driven configuration, externalized secrets, and configurable defaults
- **Configuration-as-Code**: Global configuration management with environment-specific overrides

## Special Features

### Dynamic IP Whitelisting
- Windows-based script updates "ip.dulundu.tools" A record via Cloudflare API when home IP changes
- Server-side automation resolves domain and updates firewall rules
- SSH, control panel, and custom ports restricted to dynamically updated IP only

### Performance Optimization
- Automatic detection and configuration of PHP/LSAPI parameters based on hardware
- OpenLiteSpeed tuning (gzip, caching, worker processes)
- Targets improvement of Lighthouse scores and TTFB metrics

## Development Status

Currently in planning phase with PRD completed. Implementation requires:
- Bash scripting expertise
- CyberPanel/OpenLiteSpeed configuration knowledge
- Cloudflare API integration
- Ubuntu 22.04 system administration
- WordPress deployment automation via WP-CLI

## DevOps Configuration

### Environment-Driven Configuration
All hardcoded values have been externalized to support DevOps best practices:

- **Configuration Files**: `config/global.conf` for system-wide settings
- **Environment Overrides**: `config/.env` for environment-specific values
- **Default Values**: Built-in fallbacks with sensible defaults
- **Secret Management**: Externalized passwords and sensitive data

### Configuration Hierarchy
```
1. Built-in defaults (fallback values)
2. global.conf settings 
3. .env file overrides (environment-specific)
4. Environment variables (runtime overrides)
```

### Example Environment Configuration
```bash
# Copy .env.example to .env and customize
cp config/.env.example config/.env

# Key configurable values:
DATABASE_HOST="mysql.internal"
WP_DEFAULT_ADMIN_EMAIL="admin@yourcompany.com"
REDIS_BIND_ADDRESS="redis.internal"
```

## Security Considerations

- All scripts implement defense-in-depth security
- Mandatory SSL via Let's Encrypt
- Fail2ban integration for brute force protection
- WAF implementation via OpenLiteSpeed or ModSecurity
- Automated backup and rollback capabilities
- UFW firewall with default deny policy
- Externalized secrets and credentials

## Current Implementation Status

### ✅ **Fully Implemented Features**

**Production Installation System:**
- Professional `install.sh` script with Linux FHS compliance
- Auto-detecting installation paths (development/production/system)
- System command creation (`wp-automation`, `wp-logs`, etc.)
- Proper directory permissions and ownership

**Log Management System:**
- Comprehensive log viewing with `scripts/logs.sh`
- Single command access (`wp-logs`, `wp-logs-follow`, `wp-logs-errors`)
- Real-time log following and search capabilities
- Integration with monitoring dashboard

**DevOps Configuration:**
- Environment-driven configuration with `.env` support
- Configuration hierarchy (defaults → global.conf → .env → env vars)
- Externalized all hardcoded values (no more `/workspace` paths)
- FHS-compliant path detection and management

**Syntax and Code Quality:**
- All bash scripts pass `bash -n` validation
- Fixed all syntax errors (QUIET_MODE, show_usage, arithmetic expressions)
- Proper error handling and logging throughout
- Idempotent script execution

### 🔧 **Architecture Improvements**

**Module Structure:**
1. **Master Management Script (master.sh)** - Central controller
2. **Installation Module (modules/install.sh)** - System installation
3. **Configuration Module (modules/config.sh)** - Performance optimization  
4. **Security Module (modules/security.sh)** - Security hardening
5. **WordPress Automation Module (modules/wp-automation.sh)** - WP management
6. **Monitoring & Logging Module (modules/monitoring.sh)** - System monitoring
7. **Dynamic Tuning Module (modules/dynamic-tuning.sh)** - Hardware tuning
8. **Log Management (scripts/logs.sh)** - Comprehensive log viewing
9. **Professional Installation (install.sh)** - Production deployment

**Path Management:**
- **Production**: `/opt/wp-automation` → `/etc`, `/var/log`, `/var/lib` directories
- **Development**: Portable relative paths within project directory
- **Auto-detection**: Based on installation location and FHS standards

## Essential Commands

### Production Installation Commands
```bash
# Professional installation to /opt/wp-automation
sudo ./install.sh

# Development installation (portable)
./install.sh --dev

# Custom installation location
sudo ./install.sh --prefix=/usr/local/wp-automation
```

### Primary Operation Commands
```bash
# Full system deployment
wp-automation all --force

# Individual modules
wp-automation install config security wp-automation monitoring dynamic-tuning

# System status and diagnostics
wp-automation --status
wp-automation --dry-run all

# Quick aliases
wp-deploy                    # Full deployment
wp-server-status            # System status
```

### Log Management Commands
```bash
# View all logs (last 50 lines)
wp-logs

# Real-time log following
wp-logs-follow

# Error-only filtering
wp-logs-errors

# Show last 100 lines
wp-logs-tail

# Specific log viewing
wp-logs automation
wp-logs mysql
wp-logs fail2ban

# Advanced options
wp-logs -s "error" all       # Search for "error" in all logs
wp-logs -n 200 mysql         # Show last 200 lines of MySQL log
wp-logs -f openlitespeed     # Follow OpenLiteSpeed log
wp-logs --list               # List all available logs
```

### Development and Testing Commands
```bash
# Validate script syntax
bash -n master.sh
bash -n modules/*.sh

# Test configuration without changes
./master.sh --dry-run [module]

# Debug mode with verbose output
./master.sh [module] --debug

# Check Ubuntu compatibility
source scripts/utils.sh && check_ubuntu_compatibility
```
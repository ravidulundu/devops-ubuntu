# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a DevOps project for creating an optimized WordPress server solution on Ubuntu 22.04. The project is based on a comprehensive PRD (devops-prd.md) that outlines the development of modular Bash scripts for automated installation, configuration, and maintenance of WordPress hosting infrastructure using CyberPanel and OpenLiteSpeed.

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
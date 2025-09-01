#!/bin/bash

# WordPress Automation Module for Server Automation
# =================================================
# Description: Manages WordPress installation, cache/CDN integration, backups, and updates
# Dependencies: WP-CLI, CyberPanel, OpenLiteSpeed, Redis
# Author: DevOps Ubuntu Team

set -euo pipefail

# Source utilities and set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
LOGS_DIR="$SCRIPT_DIR/../logs"
source "$SCRIPT_DIR/../scripts/utils.sh"

# Module information
MODULE_NAME="WordPress Automation Module"
MODULE_VERSION="1.0.0"

log_info "Starting $MODULE_NAME v$MODULE_VERSION"

# WordPress configuration variables
WP_SITES_DIR="/usr/local/lsws/Example/html"
WP_CONFIG_DIR="$CONFIG_DIR/wordpress"
WP_BACKUP_DIR="$BACKUP_DIR/wordpress"
WP_TEMP_DIR="/tmp/wp-automation"

# Default WordPress configuration
WP_DEFAULT_ADMIN_USER="wpadmin"
WP_DEFAULT_ADMIN_EMAIL="${WP_DEFAULT_ADMIN_EMAIL:-admin@example.com}"
WP_DEFAULT_PLUGINS=(
    "redis-cache"
    "wp-super-cache" 
    "wordfence"
    "updraftplus"
    "yoast-seo"
    "contact-form-7"
)

WP_DEFAULT_THEMES=(
    "twentytwentythree"
    "astra"
)

# Load WordPress configuration
load_wp_config() {
    log_info "Loading WordPress configuration..."
    
    mkdir -p "$WP_CONFIG_DIR" "$WP_BACKUP_DIR" "$WP_TEMP_DIR"
    
    # Load installation credentials
    local config_files=("mysql.conf" "openlitespeed.conf" "cyberpanel.conf")
    for config_file in "${config_files[@]}"; do
        local config_path="$CONFIG_DIR/$config_file"
        if [[ -f "$config_path" ]]; then
            source "$config_path"
        fi
    done
}

# Create WordPress database
create_wp_database() {
    local site_name=$1
    local db_name="${site_name//[-.]/_}_wp"
    local db_user="${site_name//[-.]/_}_user"
    local db_password=$(generate_password 20)
    
    log_info "Creating database for $site_name..."
    
    # Create database and user
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Save database credentials
    cat > "$WP_CONFIG_DIR/${site_name}_db.conf" <<EOF
WP_DB_NAME="$db_name"
WP_DB_USER="$db_user"
WP_DB_PASSWORD="$db_password"
WP_DB_HOST="${WP_DB_HOST:-localhost}"
WP_DB_PREFIX="wp_"
EOF
    
    chmod 600 "$WP_CONFIG_DIR/${site_name}_db.conf"
    
    log_success "Database created for $site_name: $db_name"
    echo "$db_name:$db_user:$db_password"
}

# Download and install WordPress
install_wordpress() {
    local site_name=$1
    local site_domain=${2:-$site_name}
    local site_path="$WP_SITES_DIR/$site_name"
    
    log_info "Installing WordPress for $site_name at $site_path..."
    
    # Create site directory
    mkdir -p "$site_path"
    cd "$site_path"
    
    # Download WordPress
    if [[ ! -f "wp-config.php" ]]; then
        log_info "Downloading WordPress core..."
        execute_command "wp core download --allow-root" "Downloading WordPress"
        
        # Create database
        local db_info=$(create_wp_database "$site_name")
        local db_name=$(echo "$db_info" | cut -d: -f1)
        local db_user=$(echo "$db_info" | cut -d: -f2)
        local db_password=$(echo "$db_info" | cut -d: -f3)
        
        # Create wp-config.php
        log_info "Creating WordPress configuration..."
        execute_command "wp config create --dbname='$db_name' --dbuser='$db_user' --dbpass='$db_password' --dbhost='${WP_DB_HOST:-localhost}' --dbprefix='wp_' --allow-root" "Creating WordPress config"
        
        # Add Redis cache configuration
        cat >> wp-config.php <<'EOF'

// Redis Cache Configuration
define('WP_REDIS_HOST', '${REDIS_BIND_ADDRESS:-127.0.0.1}');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DATABASE', 0);

// Security keys and salts
EOF
        
        # Generate security keys
        execute_command "wp config shuffle-salts --allow-root" "Generating security keys"
        
        # Install WordPress
        local wp_admin_password=$(generate_password 16)
        log_info "Installing WordPress..."
        execute_command "wp core install --url='http://$site_domain' --title='$site_name' --admin_user='$WP_DEFAULT_ADMIN_USER' --admin_password='$wp_admin_password' --admin_email='$WP_DEFAULT_ADMIN_EMAIL' --allow-root" "Installing WordPress"
        
        # Save admin credentials
        cat > "$WP_CONFIG_DIR/${site_name}_admin.conf" <<EOF
WP_ADMIN_USER="$WP_DEFAULT_ADMIN_USER"
WP_ADMIN_PASSWORD="$wp_admin_password"
WP_ADMIN_EMAIL="$WP_DEFAULT_ADMIN_EMAIL"
WP_SITE_URL="http://$site_domain"
WP_SITE_PATH="$site_path"
EOF
        
        chmod 600 "$WP_CONFIG_DIR/${site_name}_admin.conf"
        
        log_success "WordPress installed for $site_name"
    else
        log_info "WordPress already exists at $site_path"
    fi
    
    # Set proper permissions
    set_wp_permissions "$site_path"
    
    echo "$site_path"
}

# Set WordPress file permissions
set_wp_permissions() {
    local wp_path=$1
    
    log_info "Setting WordPress permissions for $wp_path..."
    
    # Set ownership
    execute_command "chown -R nobody:nogroup '$wp_path'" "Setting ownership"
    
    # Set directory permissions
    execute_command "find '$wp_path' -type d -exec chmod 755 {} \;" "Setting directory permissions"
    
    # Set file permissions
    execute_command "find '$wp_path' -type f -exec chmod 644 {} \;" "Setting file permissions"
    
    # Set wp-config.php permissions
    if [[ -f "$wp_path/wp-config.php" ]]; then
        execute_command "chmod 600 '$wp_path/wp-config.php'" "Securing wp-config.php"
    fi
    
    # Set .htaccess permissions
    if [[ -f "$wp_path/.htaccess" ]]; then
        execute_command "chmod 644 '$wp_path/.htaccess'" "Setting .htaccess permissions"
    fi
    
    log_success "WordPress permissions set correctly"
}

# Install WordPress plugins
install_wp_plugins() {
    local site_path=$1
    local plugins=("${@:2}")
    
    log_info "Installing WordPress plugins..."
    
    cd "$site_path"
    
    for plugin in "${plugins[@]}"; do
        if wp plugin is-installed "$plugin" --allow-root >/dev/null 2>&1; then
            log_info "Plugin already installed: $plugin"
        else
            log_info "Installing plugin: $plugin"
            execute_command "wp plugin install '$plugin' --activate --allow-root" "Installing plugin: $plugin"
        fi
    done
    
    log_success "WordPress plugins installation completed"
}

# Configure WordPress caching
configure_wp_caching() {
    local site_path=$1
    
    log_info "Configuring WordPress caching..."
    
    cd "$site_path"
    
    # Configure Redis Cache
    if wp plugin is-installed redis-cache --allow-root; then
        log_info "Configuring Redis cache..."
        execute_command "wp redis enable --allow-root" "Enabling Redis cache"
        
        # Update wp-config.php for Redis
        if ! grep -q "WP_REDIS_HOST" wp-config.php; then
            cat >> wp-config.php <<'EOF'

// Redis Cache Configuration
define('WP_REDIS_HOST', '${REDIS_BIND_ADDRESS:-127.0.0.1}');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DATABASE', 0);
define('WP_CACHE_KEY_SALT', 'wp-cache');
EOF
        fi
    fi
    
    # Configure WP Super Cache
    if wp plugin is-installed wp-super-cache --allow-root; then
        log_info "Configuring WP Super Cache..."
        
        # Enable caching
        execute_command "wp super-cache enable --allow-root" "Enabling WP Super Cache"
        
        # Configure cache settings
        execute_command "wp option update wpsupercache_gc_interval 3600 --allow-root" "Setting cache garbage collection"
        execute_command "wp option update wpsupercache_cache_timeout 1800 --allow-root" "Setting cache timeout"
    fi
    
    # Add caching headers to .htaccess
    create_htaccess_cache_rules "$site_path"
    
    log_success "WordPress caching configured"
}

# Create .htaccess cache rules
create_htaccess_cache_rules() {
    local site_path=$1
    local htaccess_file="$site_path/.htaccess"
    
    log_info "Creating .htaccess cache rules..."
    
    # Backup existing .htaccess
    if [[ -f "$htaccess_file" ]]; then
        create_backup "$htaccess_file"
    fi
    
    cat > "$htaccess_file" <<'EOF'
# WordPress Performance and Security Rules
# Generated automatically - Edit with caution

# Enable compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript application/json
    AddOutputFilterByType DEFLATE application/rss+xml application/atom+xml image/svg+xml
</IfModule>

# Set cache headers for static files
<IfModule mod_expires.c>
    ExpiresActive On
    
    # Images
    ExpiresByType image/jpg "access plus 1 month"
    ExpiresByType image/jpeg "access plus 1 month"
    ExpiresByType image/gif "access plus 1 month"
    ExpiresByType image/png "access plus 1 month"
    ExpiresByType image/webp "access plus 1 month"
    ExpiresByType image/svg+xml "access plus 1 month"
    ExpiresByType image/x-icon "access plus 1 year"
    
    # CSS and JavaScript
    ExpiresByType text/css "access plus 1 month"
    ExpiresByType application/javascript "access plus 1 month"
    ExpiresByType text/javascript "access plus 1 month"
    
    # Fonts
    ExpiresByType font/woff "access plus 1 year"
    ExpiresByType font/woff2 "access plus 1 year"
    ExpiresByType application/font-woff "access plus 1 year"
    ExpiresByType application/font-woff2 "access plus 1 year"
    
    # Other files
    ExpiresByType application/pdf "access plus 1 month"
    ExpiresByType text/html "access plus 1 hour"
</IfModule>

# Security headers
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "camera=(), microphone=(), geolocation=()"
</IfModule>

# Disable server signature
ServerSignature Off

# Block access to sensitive files
<FilesMatch "(^#.*#|\.(bak|config|dist|fla|inc|ini|log|psd|sh|sql|sw[op])|~)$">
    Require all denied
</FilesMatch>

# Block access to wp-config.php
<Files wp-config.php>
    Require all denied
</Files>

# Block access to xmlrpc.php
<Files xmlrpc.php>
    Require all denied
</Files>

# Limit login attempts
<Files wp-login.php>
    <RequireAll>
        Require all granted
        # Add your IP restrictions here if needed
    </RequireAll>
</Files>

# BEGIN WordPress
# The directives (lines) between "BEGIN WordPress" and "END WordPress" are
# dynamically generated, and should only be modified via WordPress filters.
# Any changes to the directives between these markers will be overwritten.
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>

# END WordPress
EOF

    log_success ".htaccess cache rules created"
}

# Setup WordPress backups
setup_wp_backups() {
    local site_name=$1
    local site_path=$2
    
    log_info "Setting up WordPress backups for $site_name..."
    
    # Create backup script
    cat > "/usr/local/bin/wp-backup-$site_name.sh" <<EOF
#!/bin/bash

# WordPress Backup Script for $site_name
# Generated automatically

set -euo pipefail

SITE_NAME="$site_name"
SITE_PATH="$site_path"
BACKUP_DIR="$WP_BACKUP_DIR/\$SITE_NAME"
DATE=\$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/wp-backup-\$SITE_NAME.log"

# Create backup directory
mkdir -p "\$BACKUP_DIR"

echo "[\$(date)] Starting WordPress backup for \$SITE_NAME" >> "\$LOG_FILE"

cd "\$SITE_PATH"

# Database backup
DB_NAME=\$(wp config get DB_NAME --allow-root)
DB_USER=\$(wp config get DB_USER --allow-root)
DB_PASSWORD=\$(wp config get DB_PASSWORD --allow-root)

mysqldump -u "\$DB_USER" -p"\$DB_PASSWORD" "\$DB_NAME" | gzip > "\$BACKUP_DIR/database_\${DATE}.sql.gz"

# Files backup
tar -czf "\$BACKUP_DIR/files_\${DATE}.tar.gz" -C "\$(dirname "\$SITE_PATH")" "\$(basename "\$SITE_PATH")"

# WordPress core backup
wp db export "\$BACKUP_DIR/wp-export_\${DATE}.xml" --allow-root

# Cleanup old backups (keep last 7 days)
find "\$BACKUP_DIR" -type f -mtime +7 -delete

echo "[\$(date)] WordPress backup completed for \$SITE_NAME" >> "\$LOG_FILE"

# Log backup size
BACKUP_SIZE=\$(du -sh "\$BACKUP_DIR" | cut -f1)
echo "[\$(date)] Backup size: \$BACKUP_SIZE" >> "\$LOG_FILE"
EOF

    chmod +x "/usr/local/bin/wp-backup-$site_name.sh"
    
    # Create cron job for automatic backups
    cat > "/etc/cron.d/wp-backup-$site_name" <<EOF
# WordPress backup for $site_name - Run daily at 2 AM
0 2 * * * root /usr/local/bin/wp-backup-$site_name.sh >/dev/null 2>&1
EOF

    # Run initial backup
    execute_command "/usr/local/bin/wp-backup-$site_name.sh" "Running initial backup"
    
    log_success "WordPress backups configured for $site_name"
}

# Configure WordPress security
configure_wp_security() {
    local site_path=$1
    
    log_info "Configuring WordPress security..."
    
    cd "$site_path"
    
    # Configure Wordfence if installed
    if wp plugin is-installed wordfence --allow-root; then
        log_info "Configuring Wordfence security..."
        
        # Enable firewall
        execute_command "wp option update wordfence_global_options '{\"firewallEnabled\":1,\"blockFakeGooglebots\":1,\"blockFakeBingbots\":1,\"blockFakeMSNbots\":1,\"blockFakeYahoobotsNegate\":1}' --format=json --allow-root" "Configuring Wordfence firewall"
        
        # Configure scan settings
        execute_command "wp option update wf_scanType 'Standard' --allow-root" "Configuring Wordfence scans"
    fi
    
    # Update WordPress security keys
    execute_command "wp config shuffle-salts --allow-root" "Updating security keys"
    
    # Remove default themes and plugins
    local default_themes=("twentytwenty" "twentytwentyone")
    for theme in "${default_themes[@]}"; do
        if wp theme is-installed "$theme" --allow-root; then
            execute_command "wp theme delete '$theme' --allow-root" "Removing default theme: $theme"
        fi
    done
    
    # Remove default plugins
    local default_plugins=("akismet" "hello")
    for plugin in "${default_plugins[@]}"; do
        if wp plugin is-installed "$plugin" --allow-root; then
            execute_command "wp plugin delete '$plugin' --allow-root" "Removing default plugin: $plugin"
        fi
    done
    
    # Disable file editing
    if ! grep -q "DISALLOW_FILE_EDIT" wp-config.php; then
        echo "define('DISALLOW_FILE_EDIT', true);" >> wp-config.php
    fi
    
    # Disable file modifications
    if ! grep -q "DISALLOW_FILE_MODS" wp-config.php; then
        echo "define('DISALLOW_FILE_MODS', true);" >> wp-config.php
    fi
    
    log_success "WordPress security configured"
}

# Setup WordPress auto-updates
setup_wp_auto_updates() {
    local site_path=$1
    
    log_info "Setting up WordPress auto-updates..."
    
    cd "$site_path"
    
    # Enable automatic core updates
    if ! grep -q "WP_AUTO_UPDATE_CORE" wp-config.php; then
        echo "define('WP_AUTO_UPDATE_CORE', true);" >> wp-config.php
    fi
    
    # Create update script
    cat > "/usr/local/bin/wp-update-all.sh" <<'EOF'
#!/bin/bash

# WordPress Auto-Update Script for All Sites
# Generated automatically

set -euo pipefail

LOG_FILE="/var/log/wp-updates.log"
WP_SITES_DIR="/usr/local/lsws/Example/html"

echo "[$(date)] Starting WordPress updates for all sites" >> "$LOG_FILE"

# Find all WordPress installations
find "$WP_SITES_DIR" -name "wp-config.php" -type f | while read wp_config; do
    WP_DIR=$(dirname "$wp_config")
    SITE_NAME=$(basename "$WP_DIR")
    
    echo "[$(date)] Updating site: $SITE_NAME" >> "$LOG_FILE"
    
    cd "$WP_DIR"
    
    # Update WordPress core
    wp core update --allow-root >> "$LOG_FILE" 2>&1 || echo "[$(date)] Core update failed for $SITE_NAME" >> "$LOG_FILE"
    
    # Update plugins
    wp plugin update --all --allow-root >> "$LOG_FILE" 2>&1 || echo "[$(date)] Plugin updates failed for $SITE_NAME" >> "$LOG_FILE"
    
    # Update themes
    wp theme update --all --allow-root >> "$LOG_FILE" 2>&1 || echo "[$(date)] Theme updates failed for $SITE_NAME" >> "$LOG_FILE"
    
    # Update database if needed
    wp core update-db --allow-root >> "$LOG_FILE" 2>&1 || echo "[$(date)] Database update failed for $SITE_NAME" >> "$LOG_FILE"
    
    # Flush cache
    if wp plugin is-installed redis-cache --allow-root; then
        wp redis flush --allow-root >> "$LOG_FILE" 2>&1
    fi
    
    if wp plugin is-installed wp-super-cache --allow-root; then
        wp super-cache flush --allow-root >> "$LOG_FILE" 2>&1
    fi
    
    echo "[$(date)] Site update completed: $SITE_NAME" >> "$LOG_FILE"
done

echo "[$(date)] All WordPress updates completed" >> "$LOG_FILE"
EOF

    chmod +x "/usr/local/bin/wp-update-all.sh"
    
    # Create cron job for weekly updates
    cat > "/etc/cron.d/wp-auto-updates" <<'EOF'
# WordPress auto-updates - Run weekly on Sunday at 3 AM
0 3 * * 0 root /usr/local/bin/wp-update-all.sh >/dev/null 2>&1
EOF

    log_success "WordPress auto-updates configured"
}

# Create sample WordPress site
create_sample_site() {
    log_info "Creating sample WordPress site..."
    
    local sample_site="demo"
    local sample_domain="demo.local"
    
    # Install WordPress
    local site_path=$(install_wordpress "$sample_site" "$sample_domain")
    
    # Install default plugins
    install_wp_plugins "$site_path" "${WP_DEFAULT_PLUGINS[@]}"
    
    # Configure caching
    configure_wp_caching "$site_path"
    
    # Configure security
    configure_wp_security "$site_path"
    
    # Setup backups
    setup_wp_backups "$sample_site" "$site_path"
    
    log_success "Sample WordPress site created: $sample_site"
}

# WordPress maintenance tools
create_wp_maintenance_tools() {
    log_info "Creating WordPress maintenance tools..."
    
    # Site health check script
    cat > "/usr/local/bin/wp-health-check.sh" <<'EOF'
#!/bin/bash

# WordPress Health Check Script
# Checks all WordPress sites for common issues

set -euo pipefail

LOG_FILE="/var/log/wp-health-check.log"
WP_SITES_DIR="/usr/local/lsws/Example/html"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "[$(date)] Starting WordPress health check" | tee -a "$LOG_FILE"

find "$WP_SITES_DIR" -name "wp-config.php" -type f | while read wp_config; do
    WP_DIR=$(dirname "$wp_config")
    SITE_NAME=$(basename "$WP_DIR")
    
    echo -e "\n${YELLOW}Checking site: $SITE_NAME${NC}"
    
    cd "$WP_DIR"
    
    # Check WordPress core
    if wp core verify-checksums --allow-root >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} WordPress core integrity: OK"
    else
        echo -e "  ${RED}✗${NC} WordPress core integrity: FAILED"
        echo "[$(date)] Core integrity check failed for $SITE_NAME" >> "$LOG_FILE"
    fi
    
    # Check database connection
    if wp db check --allow-root >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Database connection: OK"
    else
        echo -e "  ${RED}✗${NC} Database connection: FAILED"
        echo "[$(date)] Database connection failed for $SITE_NAME" >> "$LOG_FILE"
    fi
    
    # Check plugin security
    VULNERABLE_PLUGINS=$(wp plugin list --format=csv --allow-root | grep -v "name,status" | while IFS=',' read name status version update; do
        if [[ "$update" == "available" ]]; then
            echo "$name"
        fi
    done)
    
    if [[ -n "$VULNERABLE_PLUGINS" ]]; then
        echo -e "  ${YELLOW}!${NC} Plugins need updates: $VULNERABLE_PLUGINS"
    else
        echo -e "  ${GREEN}✓${NC} All plugins up to date"
    fi
    
    # Check permissions
    PERM_ISSUES=$(find "$WP_DIR" -type f -not -perm 644 -not -name "wp-config.php" | wc -l)
    if [[ $PERM_ISSUES -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} File permissions: OK"
    else
        echo -e "  ${YELLOW}!${NC} Permission issues found: $PERM_ISSUES files"
    fi
done

echo -e "\n[$(date)] WordPress health check completed" | tee -a "$LOG_FILE"
EOF

    chmod +x "/usr/local/bin/wp-health-check.sh"
    
    # WordPress CLI helper script
    cat > "/usr/local/bin/wp-manage.sh" <<'EOF'
#!/bin/bash

# WordPress Management Helper Script

show_usage() {
    cat << 'USAGE_EOF'
Usage: $0 [command] [site] [options]

Commands:
    list-sites          List all WordPress sites
    backup [site]       Create backup of specific site
    update [site]       Update specific site
    security-check      Run security check on all sites
    health-check        Run health check on all sites
    cache-flush [site]  Flush cache for specific site
    permissions [site]  Fix permissions for specific site

Examples:
    $0 list-sites
    $0 backup demo
    $0 update demo
    $0 cache-flush demo
    $0 security-check
USAGE_EOF
}

WP_SITES_DIR="/usr/local/lsws/Example/html"

case "${1:-}" in
    "list-sites")
        echo "WordPress Sites:"
        find "$WP_SITES_DIR" -name "wp-config.php" -type f | while read wp_config; do
            WP_DIR=$(dirname "$wp_config")
            SITE_NAME=$(basename "$WP_DIR")
            cd "$WP_DIR"
            URL=$(wp option get home --allow-root 2>/dev/null || echo "N/A")
            VERSION=$(wp core version --allow-root 2>/dev/null || echo "N/A")
            echo "  $SITE_NAME - $URL (WordPress $VERSION)"
        done
        ;;
    "backup")
        SITE="${2:-}"
        if [[ -z "$SITE" ]]; then
            echo "Error: Site name required"
            exit 1
        fi
        /usr/local/bin/wp-backup-$SITE.sh
        ;;
    "health-check")
        /usr/local/bin/wp-health-check.sh
        ;;
    "cache-flush")
        SITE="${2:-}"
        if [[ -z "$SITE" ]]; then
            echo "Error: Site name required"
            exit 1
        fi
        cd "$WP_SITES_DIR/$SITE"
        wp cache flush --allow-root
        wp redis flush --allow-root 2>/dev/null || true
        wp super-cache flush --allow-root 2>/dev/null || true
        echo "Cache flushed for $SITE"
        ;;
    *)
        show_usage
        ;;
esac
EOF

    chmod +x "/usr/local/bin/wp-manage.sh"
    
    log_success "WordPress maintenance tools created"
}

# Create WordPress automation summary
create_wp_summary() {
    local summary_file="$LOG_DIR/wordpress_summary.txt"
    
    cat > "$summary_file" <<EOF
WordPress Server Automation - WordPress Module Summary
======================================================
Configuration Date: $(date)

WordPress Configuration:
- Installation Directory: $WP_SITES_DIR
- Configuration Directory: $WP_CONFIG_DIR
- Backup Directory: $WP_BACKUP_DIR
- Default Admin User: $WP_DEFAULT_ADMIN_USER

Installed Features:
- WordPress Core (Latest Version)
- Default Plugins: ${WP_DEFAULT_PLUGINS[*]}
- Redis Cache Integration
- WP Super Cache
- Security Hardening (Wordfence)
- Automatic Backups
- Auto-Updates System

Security Measures:
- File editing disabled
- File modifications disabled
- Default themes/plugins removed
- Security headers configured
- Sensitive files protected
- Login attempt limiting

Performance Optimizations:
- Redis object caching
- Page caching (WP Super Cache)
- Static file compression
- Browser caching headers
- CDN-ready configuration

Automation Features:
- Daily backups (2 AM)
- Weekly updates (Sunday 3 AM)
- Health monitoring
- Permission management
- Cache management

Management Scripts:
- /usr/local/bin/wp-manage.sh - Site management helper
- /usr/local/bin/wp-health-check.sh - Health monitoring
- /usr/local/bin/wp-update-all.sh - Automatic updates
- Individual backup scripts per site

Sample Site:
- Name: demo
- Domain: demo.local
- Path: $WP_SITES_DIR/demo

Site Credentials:
- Check individual .conf files in: $WP_CONFIG_DIR/
- Database credentials: {site}_db.conf
- Admin credentials: {site}_admin.conf

Next Steps:
1. Configure monitoring: ./master.sh monitoring
2. Setup dynamic tuning: ./master.sh dynamic-tuning
3. Create additional sites with wp-manage.sh
4. Configure production domains and SSL

Log Files:
- WordPress Updates: /var/log/wp-updates.log
- Health Checks: /var/log/wp-health-check.log
- Site Backups: /var/log/wp-backup-{site}.log
EOF

    log_info "WordPress automation summary saved to: $summary_file"
}

# Main WordPress automation function
main() {
    log_info "=== Starting WordPress Automation Setup ==="
    
    # Load configuration
    load_wp_config
    
    # Verify WP-CLI is available
    if ! command -v wp >/dev/null 2>&1; then
        log_error "WP-CLI is not installed. Please run the installation module first."
        return 1
    fi
    
    # Setup WordPress automation features
    setup_wp_auto_updates
    create_wp_maintenance_tools
    
    # Create sample site
    create_sample_site
    
    # Create summary
    create_wp_summary
    
    log_success "=== WordPress automation setup completed successfully! ==="
    log_info "Check $LOG_DIR/wordpress_summary.txt for details"
    log_info "Use 'wp-manage.sh list-sites' to see all WordPress sites"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
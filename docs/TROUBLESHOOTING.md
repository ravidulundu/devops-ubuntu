# Troubleshooting Guide

Comprehensive troubleshooting guide for WordPress Server Automation system issues.

## 🚨 Quick Diagnostics

### System Health Check
```bash
# Run comprehensive system check
./master.sh --status

# Check all services
systemctl status lsws mysql redis-server fail2ban ufw

# View real-time dashboard
server-dashboard

# Check disk space and resources
df -h
free -h
top
```

### Log Analysis
```bash
# Main automation logs
tail -f logs/automation.log

# System logs
tail -f /var/log/syslog

# Service-specific logs
tail -f /usr/local/lsws/logs/error.log
tail -f /var/log/mysql/error.log
tail -f /var/log/fail2ban.log
```

---

## 🔧 Installation Issues

### Error: "CONFIG_DIR: unbound variable"

**Symptoms:**
```
/home/user/devops-ubuntu/modules/install.sh: line 173: CONFIG_DIR: unbound variable
[ERROR] Module failed: install
```

**Status:** ✅ **RESOLVED** in latest version

**Solutions:**
1. **Update to latest version** - This issue has been fixed
2. **Manual fix** - Ensure modules properly source utilities:
   ```bash
   # Each module should have:
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   CONFIG_DIR="$SCRIPT_DIR/../config"
   LOGS_DIR="$SCRIPT_DIR/../logs"
   source "$SCRIPT_DIR/../scripts/utils.sh"
   ```

### Error: "show_usage: command not found"

**Symptoms:**
```
/usr/local/bin/wp-manage.sh: line 719: show_usage: command not found
[ERROR] Module failed: wp-automation
```

**Status:** ✅ **RESOLVED** in latest version

**Solutions:**
1. **Update to latest version** - Heredoc syntax has been fixed
2. **Manual fix** - Check for proper function definitions in heredocs

### Error: OpenLiteSpeed PHP Configuration

**Symptoms:**
```
[ERROR] invalid path - /usr/local/lsws/lsphp82/bin/lsphp, it cannot be started by Web server!
[ERROR] Module failed: config
```

**Status:** ✅ **RESOLVED** in latest version

**Solutions:**
1. **Update to latest version** - Dynamic PHP detection implemented
2. **Manual check** - Verify PHP installation:
   ```bash
   ls -la /usr/local/lsws/lsphp*/bin/lsphp
   ```

### Error: "netstat: command not found"

**Symptoms:**
```
/scripts/utils.sh: line 224: netstat: command not found
```

**Status:** ✅ **RESOLVED** in latest version

**Solutions:**
1. **Update to latest version** - Replaced with `ss` command
2. **Manual install**:
   ```bash
   sudo apt-get update
   sudo apt-get install net-tools
   ```

### Error: "System requirements not met"

**Symptoms:**
```
[ERROR] System requirements check failed
[ERROR] Insufficient memory. Required: 1024MB, Available: 512MB
```

**Solutions:**
1. **Check actual requirements:**
   ```bash
   free -m
   nproc
   df -h
   ```

2. **Upgrade server resources:**
   - Minimum: 2 CPU cores, 2GB RAM, 20GB disk
   - Recommended: 4+ cores, 4GB+ RAM, 50GB+ SSD

3. **Clean up existing resources:**
   ```bash
   # Remove unnecessary packages
   sudo apt autoremove -y
   sudo apt autoclean
   
   # Clear temporary files
   sudo rm -rf /tmp/*
   sudo rm -rf /var/tmp/*
   ```

### Error: "Package installation failed"

**Symptoms:**
```
[ERROR] Failed to install package: mysql-server
E: Unable to locate package mysql-server
```

**Solutions:**
1. **Update package lists:**
   ```bash
   sudo apt update
   sudo apt upgrade -y
   ```

2. **Check Ubuntu version:**
   ```bash
   lsb_release -a
   # Must be Ubuntu 22.04 LTS
   ```

3. **Fix broken packages:**
   ```bash
   sudo apt --fix-broken install
   sudo dpkg --configure -a
   ```

4. **Reset package sources:**
   ```bash
   sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
   sudo sed -i 's/# deb-src/deb-src/g' /etc/apt/sources.list
   sudo apt update
   ```

### Error: "Port already in use"

**Symptoms:**
```
[WARNING] Port 80 is already in use
[ERROR] Failed to start OpenLiteSpeed
```

**Solutions:**
1. **Check what's using the port:**
   ```bash
   sudo netstat -tulpn | grep :80
   sudo lsof -i :80
   ```

2. **Stop conflicting services:**
   ```bash
   # Common conflicts
   sudo systemctl stop apache2 nginx
   sudo systemctl disable apache2 nginx
   ```

3. **Kill processes using ports:**
   ```bash
   # Find and kill process
   sudo fuser -k 80/tcp
   sudo fuser -k 443/tcp
   ```

---

## ⚡ Configuration Issues

### OpenLiteSpeed Won't Start

**Symptoms:**
```
[ERROR] Failed to start service: lsws
Job for lsws.service failed because the control process exited
```

**Diagnosis:**
```bash
# Check OpenLiteSpeed status
sudo systemctl status lsws

# Test configuration
sudo /usr/local/lsws/bin/lshttpd -t

# Check error logs
tail -f /usr/local/lsws/logs/error.log

# Check permissions
ls -la /usr/local/lsws/
```

**Solutions:**
1. **Fix configuration syntax:**
   ```bash
   # Backup and restore default config
   sudo cp /usr/local/lsws/conf/httpd_config.conf.backup /usr/local/lsws/conf/httpd_config.conf
   
   # Test configuration
   sudo /usr/local/lsws/bin/lshttpd -t
   ```

2. **Fix permissions:**
   ```bash
   sudo chown -R lsws:lsws /usr/local/lsws/
   sudo chmod -R 755 /usr/local/lsws/
   ```

3. **Reset to defaults:**
   ```bash
   # Reinstall OpenLiteSpeed
   sudo apt remove --purge openlitespeed
   ./master.sh install
   ```

### MySQL Connection Issues

**Symptoms:**
```
[ERROR] Can't connect to MySQL server on 'localhost'
ERROR 2002 (HY000): Can't connect to local MySQL server through socket
```

**Diagnosis:**
```bash
# Check MySQL status
sudo systemctl status mysql

# Check if MySQL is listening
sudo netstat -tlnp | grep mysql

# Check error logs
tail -f /var/log/mysql/error.log

# Test connection
mysql -u root -p
```

**Solutions:**
1. **Start MySQL service:**
   ```bash
   sudo systemctl start mysql
   sudo systemctl enable mysql
   ```

2. **Fix MySQL socket issues:**
   ```bash
   # Check socket location
   sudo find /var -name "mysqld.sock" 2>/dev/null
   
   # Create missing socket directory
   sudo mkdir -p /var/run/mysqld
   sudo chown mysql:mysql /var/run/mysqld
   ```

3. **Reset MySQL root password:**
   ```bash
   # Stop MySQL
   sudo systemctl stop mysql
   
   # Start in safe mode
   sudo mysqld_safe --skip-grant-tables --skip-networking &
   
   # Reset password
   mysql -u root
   mysql> USE mysql;
   mysql> UPDATE user SET password=PASSWORD("newpassword") WHERE User='root';
   mysql> FLUSH PRIVILEGES;
   mysql> EXIT;
   
   # Restart normally
   sudo systemctl restart mysql
   ```

### PHP Issues

**Symptoms:**
```
PHP Fatal error: Allowed memory size exhausted
PHP Warning: Module already loaded
```

**Diagnosis:**
```bash
# Check PHP version and modules
/usr/local/lsws/lsphp82/bin/php -v
/usr/local/lsws/lsphp82/bin/php -m

# Check PHP configuration
/usr/local/lsws/lsphp82/bin/php --ini

# Test PHP functionality
echo "<?php phpinfo(); ?>" | /usr/local/lsws/lsphp82/bin/php
```

**Solutions:**
1. **Fix memory issues:**
   ```bash
   # Edit PHP configuration
   sudo vim /usr/local/lsws/lsphp82/etc/php/8.2/litespeed/php.ini
   
   # Increase memory limit
   memory_limit = 512M
   max_execution_time = 300
   ```

2. **Fix module conflicts:**
   ```bash
   # Check for duplicate module loading
   grep -r "extension=" /usr/local/lsws/lsphp82/etc/php/8.2/
   
   # Remove duplicates from php.ini
   ```

3. **Rebuild PHP configuration:**
   ```bash
   # Re-run configuration module
   ./master.sh config --force
   ```

---

## 🔒 Security Issues

### Fail2ban Not Working

**Symptoms:**
```
[WARNING] High failed login attempts detected
Fail2ban service active but bans not working
```

**Diagnosis:**
```bash
# Check fail2ban status
sudo fail2ban-client status

# Check jail status
sudo fail2ban-client status sshd

# Check fail2ban logs
tail -f /var/log/fail2ban.log

# Test jail configuration
sudo fail2ban-client -d
```

**Solutions:**
1. **Fix jail configuration:**
   ```bash
   # Check jail configuration
   sudo fail2ban-client get sshd logpath
   
   # Restart fail2ban
   sudo systemctl restart fail2ban
   ```

2. **Update log paths:**
   ```bash
   # Edit jail configuration
   sudo vim /etc/fail2ban/jail.d/custom.conf
   
   # Ensure correct log paths
   logpath = /var/log/auth.log
   ```

3. **Test banning manually:**
   ```bash
   # Ban an IP manually
   sudo fail2ban-client set sshd banip 192.168.1.100
   
   # Check if ban worked
   sudo iptables -L -n
   ```

### UFW Firewall Issues

**Symptoms:**
```
[ERROR] UFW command failed
Status: inactive
Rules not being applied
```

**Diagnosis:**
```bash
# Check UFW status
sudo ufw status verbose

# Check UFW logs
tail -f /var/log/ufw.log

# List all rules
sudo ufw --dry-run show added
```

**Solutions:**
1. **Enable UFW:**
   ```bash
   sudo ufw --force reset
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow ssh
   sudo ufw --force enable
   ```

2. **Fix rule conflicts:**
   ```bash
   # Remove conflicting rules
   sudo ufw --force reset
   
   # Re-run security module
   ./master.sh security --force
   ```

### Dynamic IP Whitelisting Issues

**Symptoms:**
```
[ERROR] Failed to update Cloudflare DNS
[ERROR] Unable to resolve ip.dulundu.tools
```

**Diagnosis:**
```bash
# Test Cloudflare API
curl -X GET "https://api.cloudflare.com/v4/user/tokens/verify" \
     -H "Authorization: Bearer YOUR_API_TOKEN" \
     -H "Content-Type: application/json"

# Test DNS resolution
dig ip.dulundu.tools
nslookup ip.dulundu.tools
```

**Solutions:**
1. **Fix API credentials:**
   ```bash
   # Check configuration
   vim config/cloudflare.conf
   
   # Test API token
   curl -X GET "https://api.cloudflare.com/v4/zones" \
        -H "Authorization: Bearer YOUR_TOKEN"
   ```

2. **Update DNS manually:**
   ```bash
   # Get current IP
   curl -s https://ipinfo.io/ip
   
   # Update via API
   curl -X PUT "https://api.cloudflare.com/v4/zones/ZONE_ID/dns_records/RECORD_ID" \
        -H "Authorization: Bearer TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"type":"A","name":"ip.dulundu.tools","content":"YOUR_IP"}'
   ```

---

## 📊 Performance Issues

### High CPU Usage

**Symptoms:**
```
[WARNING] High CPU usage: 95%
Server response time degraded
```

**Diagnosis:**
```bash
# Check CPU usage
top
htop
iostat -x 1

# Check processes
ps aux --sort=-%cpu | head -20

# Check system load
uptime
cat /proc/loadavg
```

**Solutions:**
1. **Identify resource-heavy processes:**
   ```bash
   # Check top CPU consumers
   ps aux --sort=-%cpu | head -10
   
   # Kill problematic processes if needed
   sudo kill -9 PID
   ```

2. **Optimize PHP processes:**
   ```bash
   # Reduce PHP children
   vim /usr/local/lsws/lsphp82/etc/php/8.2/litespeed/php.ini
   
   # Adjust these values
   pm.max_children = 20
   pm.start_servers = 5
   pm.min_spare_servers = 2
   pm.max_spare_servers = 8
   ```

3. **Apply CPU-optimized tuning:**
   ```bash
   # Generate CPU-optimized profile
   ./master.sh dynamic-tuning generate-profile cpu-optimized
   ./master.sh dynamic-tuning apply-profile cpu-optimized
   ```

### High Memory Usage

**Symptoms:**
```
[CRITICAL] High memory usage: 95%
MySQL crashes with out of memory errors
```

**Diagnosis:**
```bash
# Check memory usage
free -h
cat /proc/meminfo

# Check memory consumers
ps aux --sort=-%mem | head -10

# Check for memory leaks
valgrind --tool=memcheck --leak-check=yes command
```

**Solutions:**
1. **Reduce MySQL memory usage:**
   ```bash
   # Edit MySQL configuration
   sudo vim /etc/mysql/mariadb.conf.d/99-optimization.cnf
   
   # Reduce buffer pool size
   innodb_buffer_pool_size = 1G  # Reduce from current value
   query_cache_size = 64M        # Reduce from current value
   
   sudo systemctl restart mysql
   ```

2. **Optimize PHP memory:**
   ```bash
   # Reduce PHP memory limit
   sed -i 's/memory_limit = 512M/memory_limit = 256M/g' /usr/local/lsws/lsphp82/etc/php/8.2/litespeed/php.ini
   
   # Restart web server
   sudo systemctl restart lsws
   ```

3. **Add swap if needed:**
   ```bash
   # Create swap file (temporary fix)
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   
   # Make permanent
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```

### Slow Database Queries

**Symptoms:**
```
WordPress loading slowly
Database connection timeouts
```

**Diagnosis:**
```bash
# Enable slow query log
mysql -u root -p -e "SET GLOBAL slow_query_log = 'ON';"
mysql -u root -p -e "SET GLOBAL long_query_time = 2;"

# Check slow queries
sudo tail -f /var/log/mysql/slow-query.log

# Check database status
mysql -u root -p -e "SHOW PROCESSLIST;"
mysql -u root -p -e "SHOW STATUS LIKE 'Threads%';"
```

**Solutions:**
1. **Optimize MySQL configuration:**
   ```bash
   # Tune MySQL settings
   sudo vim /etc/mysql/mariadb.conf.d/99-optimization.cnf
   
   # Add optimizations
   query_cache_size = 128M
   query_cache_type = 1
   tmp_table_size = 128M
   max_heap_table_size = 128M
   ```

2. **Optimize WordPress database:**
   ```bash
   cd /usr/local/lsws/Example/html/yoursite.com
   
   # Optimize database tables
   wp db optimize --allow-root
   
   # Clean up revisions and spam
   wp db query "DELETE FROM wp_posts WHERE post_type = 'revision';" --allow-root
   wp db query "DELETE FROM wp_comments WHERE comment_approved = 'spam';" --allow-root
   ```

---

## 🌐 WordPress Issues

### WordPress Site Not Loading

**Symptoms:**
```
403 Forbidden Error
500 Internal Server Error
White screen of death
```

**Diagnosis:**
```bash
# Check web server logs
tail -f /usr/local/lsws/logs/error.log
tail -f /usr/local/lsws/logs/access.log

# Check WordPress error log
tail -f /usr/local/lsws/Example/html/yoursite/wp-content/debug.log

# Test PHP functionality
echo "<?php phpinfo(); ?>" > /usr/local/lsws/Example/html/test.php
curl http://yoursite.com/test.php
```

**Solutions:**
1. **Fix file permissions:**
   ```bash
   # Set correct ownership
   sudo chown -R nobody:nogroup /usr/local/lsws/Example/html/yoursite/
   
   # Set correct permissions
   find /usr/local/lsws/Example/html/yoursite/ -type d -exec chmod 755 {} \;
   find /usr/local/lsws/Example/html/yoursite/ -type f -exec chmod 644 {} \;
   chmod 600 /usr/local/lsws/Example/html/yoursite/wp-config.php
   ```

2. **Check WordPress configuration:**
   ```bash
   cd /usr/local/lsws/Example/html/yoursite/
   
   # Test database connection
   wp db check --allow-root
   
   # Verify WordPress core
   wp core verify-checksums --allow-root
   ```

3. **Enable WordPress debugging:**
   ```bash
   # Edit wp-config.php
   vim /usr/local/lsws/Example/html/yoursite/wp-config.php
   
   # Add debugging
   define('WP_DEBUG', true);
   define('WP_DEBUG_LOG', true);
   define('WP_DEBUG_DISPLAY', false);
   ```

### Plugin/Theme Issues

**Symptoms:**
```
Fatal error after plugin activation
Theme causing white screen
Plugin conflicts
```

**Diagnosis:**
```bash
cd /usr/local/lsws/Example/html/yoursite/

# List active plugins
wp plugin list --status=active --allow-root

# Check for plugin errors
wp plugin status --allow-root

# Test with default theme
wp theme activate twentytwentythree --allow-root
```

**Solutions:**
1. **Deactivate problematic plugins:**
   ```bash
   # Deactivate all plugins
   wp plugin deactivate --all --allow-root
   
   # Activate one by one to find culprit
   wp plugin activate plugin-name --allow-root
   ```

2. **Reset theme:**
   ```bash
   # Switch to default theme
   wp theme activate twentytwentythree --allow-root
   
   # Remove problematic theme
   wp theme delete problematic-theme --allow-root
   ```

3. **Update everything:**
   ```bash
   # Update WordPress core
   wp core update --allow-root
   
   # Update plugins
   wp plugin update --all --allow-root
   
   # Update themes
   wp theme update --all --allow-root
   ```

---

## 🔍 Monitoring & Alerting Issues

### Monitoring Not Working

**Symptoms:**
```
Dashboard shows no data
Alerts not being sent
Monitoring scripts failing
```

**Diagnosis:**
```bash
# Check monitoring processes
ps aux | grep monitoring

# Check cron jobs
sudo crontab -l
sudo systemctl status cron

# Test monitoring scripts manually
/usr/local/monitoring/scripts/collect-metrics.sh
/usr/local/monitoring/scripts/check-services.sh
```

**Solutions:**
1. **Restart monitoring services:**
   ```bash
   # Restart cron
   sudo systemctl restart cron
   
   # Re-run monitoring setup
   ./master.sh monitoring --force
   ```

2. **Fix monitoring scripts:**
   ```bash
   # Check script permissions
   chmod +x /usr/local/monitoring/scripts/*.sh
   
   # Check script syntax
   bash -n /usr/local/monitoring/scripts/collect-metrics.sh
   ```

3. **Fix notification settings:**
   ```bash
   # Configure notifications
   vim config/notifications.conf
   
   # Test email notifications
   echo "Test" | mail -s "Test" admin@yourdomain.com
   ```

### Disk Space Issues

**Symptoms:**
```
[CRITICAL] High disk usage: 95%
No space left on device
```

**Quick Fix:**
```bash
# Emergency cleanup
sudo apt autoremove -y
sudo apt autoclean
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# Clean old logs
sudo journalctl --vacuum-time=7d
find /var/log -name "*.log" -type f -mtime +30 -delete

# Clean WordPress uploads (be careful!)
find /usr/local/lsws/Example/html/*/wp-content/uploads -name "*.tmp" -delete
```

**Permanent Solutions:**
```bash
# Increase disk space (cloud provider)
# Or add additional storage

# Set up log rotation
vim /etc/logrotate.conf
# Ensure proper rotation is configured

# Set up backup cleanup
vim config/global.conf
# Set BACKUP_RETENTION_DAYS to lower value
```

---

## 🆘 Emergency Procedures

### Complete System Recovery

If the system is completely broken:

```bash
# 1. Boot from rescue/recovery mode
# 2. Mount file system
# 3. Backup critical data
tar -czf /backup/wordpress-sites.tar.gz /usr/local/lsws/Example/html/

# 4. Backup databases
mysqldump --all-databases > /backup/all-databases.sql

# 5. Backup configurations
tar -czf /backup/configurations.tar.gz /workspace/devops-ubuntu/config/

# 6. Fresh installation
git clone <repository> /opt/wordpress-automation-new
cd /opt/wordpress-automation-new
./master.sh all --force

# 7. Restore data
# Restore databases, sites, and configurations
```

### Service Recovery

If specific services are down:

```bash
# Emergency service restart
sudo systemctl restart lsws mysql redis-server

# Force service reset
sudo systemctl stop lsws
sudo killall -9 lshttpd
sudo systemctl start lsws

# Database recovery
sudo systemctl stop mysql
sudo mysqld_safe --skip-grant-tables &
# Fix issues
sudo systemctl restart mysql
```

---

## 📞 Getting Help

### Information to Collect

Before seeking help, collect this information:

```bash
# System information
uname -a
lsb_release -a
free -h
df -h

# Service status
systemctl status lsws mysql redis-server

# Error logs (last 50 lines)
tail -50 /workspace/devops-ubuntu/logs/automation.log
tail -50 /usr/local/lsws/logs/error.log
tail -50 /var/log/mysql/error.log

# Configuration
cat /workspace/devops-ubuntu/config/global.conf
```

### Support Channels

1. **Check Documentation**: Review all files in `/docs/` directory
2. **Search Issues**: Look for similar problems in project repository
3. **Community Forums**: WordPress and OpenLiteSpeed communities
4. **Professional Support**: Consider professional DevOps assistance for critical systems

### Prevention

```bash
# Regular maintenance script
cat > /usr/local/bin/maintenance.sh <<'EOF'
#!/bin/bash
# Weekly maintenance tasks

# Update packages
apt update && apt upgrade -y

# Clean temporary files
rm -rf /tmp/* /var/tmp/*

# Optimize databases
wp db optimize --allow-root --all-sites

# Check disk space
df -h | grep -E '9[0-9]%' && echo "WARNING: Disk space critical"

# Test backups
wp-manage.sh backup test-site

# Health check
./master.sh --status
EOF

chmod +x /usr/local/bin/maintenance.sh

# Schedule weekly
echo "0 2 * * 0 /usr/local/bin/maintenance.sh" | sudo crontab -
```

Remember: Most issues can be prevented with regular monitoring, maintenance, and keeping systems updated. Always backup before making changes!
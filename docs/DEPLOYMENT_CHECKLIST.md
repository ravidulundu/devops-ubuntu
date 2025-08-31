# Deployment Checklist

Complete deployment checklist to ensure successful WordPress Server Automation installation and configuration.

## 📋 Pre-Deployment Checklist

### ✅ Server Requirements

- [ ] **Operating System**: Ubuntu 22.04 LTS installed and updated
- [ ] **Hardware Minimum**: 2 CPU cores, 2GB RAM, 20GB disk space
- [ ] **Hardware Recommended**: 4+ CPU cores, 4GB+ RAM, 50GB+ SSD
- [ ] **Network**: Stable internet connection with public IP (static or dynamic)
- [ ] **Access**: Root/sudo access to the server
- [ ] **Ports**: Ports 22, 80, 443, 7080, 8090 available
- [ ] **Domain**: Domain name configured (if using custom domain)

### 🔐 Access & Security

- [ ] SSH key-based authentication configured
- [ ] Server accessible via SSH
- [ ] Firewall rules documented for current access
- [ ] Backup of current server configuration (if existing)
- [ ] Root password known and secure
- [ ] Regular user account created (recommended)

### 🌐 DNS & Domain Setup

- [ ] Domain name purchased and configured
- [ ] DNS pointing to server IP address
- [ ] Cloudflare account created (for dynamic IP whitelisting)
- [ ] Cloudflare API token generated with Zone:Edit permissions
- [ ] Zone ID obtained from Cloudflare dashboard
- [ ] Subdomain for IP tracking created (e.g., ip.yourdomain.com)

---

## 🚀 Deployment Process

### Phase 1: Initial Setup

#### Step 1.1: System Preparation
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install git (if not already installed)
sudo apt install git -y

# Create deployment directory
sudo mkdir -p /opt/wordpress-automation
cd /opt/wordpress-automation
```

**Checklist:**
- [ ] System packages updated successfully
- [ ] Git installed and working
- [ ] Deployment directory created
- [ ] Current directory is `/opt/wordpress-automation`

#### Step 1.2: Download Project
```bash
# Clone the repository
git clone <repository-url> .

# Make scripts executable
chmod +x master.sh scripts/utils.sh modules/*.sh
```

**Checklist:**
- [ ] Repository cloned successfully
- [ ] All files present and accessible
- [ ] Scripts are executable
- [ ] No permission errors

#### Step 1.3: Pre-flight Check
```bash
# Run system status check
./master.sh --status

# Check available modules
./master.sh --list-modules
```

**Checklist:**
- [ ] System requirements check passes
- [ ] All 6 modules listed and available
- [ ] No critical errors in status check
- [ ] Sufficient disk space and memory

### Phase 2: Core Installation

#### Step 2.1: Basic Installation
```bash
# Run installation module
./master.sh install --debug
```

**Validation Checklist:**
- [ ] OpenLiteSpeed installed and running
- [ ] CyberPanel installed successfully
- [ ] MariaDB installed and secured
- [ ] Redis server installed and running
- [ ] PHP 8.1 & 8.2 installed with extensions
- [ ] WP-CLI installed and functional
- [ ] All services started automatically
- [ ] Installation summary created

**Service Status Check:**
```bash
# Verify all services are running
systemctl status lsws mysql redis-server fail2ban ufw

# Check listening ports
netstat -tulpn | grep -E ':80|:443|:3306|:6379|:8090|:7080'
```

#### Step 2.2: Performance Configuration
```bash
# Run configuration module
./master.sh config --debug
```

**Validation Checklist:**
- [ ] Hardware detection completed successfully
- [ ] OpenLiteSpeed configuration optimized
- [ ] PHP settings tuned for server specs
- [ ] MariaDB buffer pool sized correctly
- [ ] Redis memory allocation configured
- [ ] System kernel parameters optimized
- [ ] Log rotation configured
- [ ] Configuration tests passed
- [ ] Services restarted successfully

**Performance Validation:**
```bash
# Test OpenLiteSpeed configuration
/usr/local/lsws/bin/lshttpd -t

# Test database connection
mysql -u root -p"$(grep MYSQL_ROOT_PASSWORD config/mysql.conf | cut -d'=' -f2 | tr -d '"')" -e "SELECT VERSION();"

# Test Redis connection
redis-cli ping
```

### Phase 3: Security Hardening

#### Step 3.1: Security Configuration
```bash
# Configure Cloudflare credentials (if using dynamic IP)
cp config/cloudflare.conf.example config/cloudflare.conf
vim config/cloudflare.conf
# Add: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID

# Run security module
./master.sh security --debug
```

**Security Validation Checklist:**
- [ ] UFW firewall enabled and configured
- [ ] Fail2ban installed and active
- [ ] SSL certificates generated
- [ ] ModSecurity WAF enabled
- [ ] Dynamic IP whitelisting configured (if enabled)
- [ ] System hardening applied
- [ ] Security summary generated
- [ ] All security tests passed

**Security Status Check:**
```bash
# Check UFW status
sudo ufw status verbose

# Check Fail2ban jails
sudo fail2ban-client status

# Verify SSL certificates
ls -la /usr/local/lsws/conf/ssl/

# Test dynamic IP script (if configured)
/usr/local/bin/update-dynamic-ip.sh
```

### Phase 4: WordPress Setup

#### Step 4.1: WordPress Automation
```bash
# Run WordPress automation module
./master.sh wp-automation --debug
```

**WordPress Validation Checklist:**
- [ ] Sample WordPress site created
- [ ] Default plugins installed and activated
- [ ] Caching configured (Redis + WP Super Cache)
- [ ] Security hardening applied
- [ ] Backup system configured
- [ ] Auto-update system enabled
- [ ] Management tools created
- [ ] WordPress summary generated

**WordPress Testing:**
```bash
# List WordPress sites
wp-manage.sh list-sites

# Test site health
wp-manage.sh health-check

# Check cache functionality
wp-manage.sh cache-flush demo
redis-cli ping
```

### Phase 5: Monitoring & Tuning

#### Step 5.1: Monitoring Setup
```bash
# Run monitoring module
./master.sh monitoring --debug
```

**Monitoring Validation Checklist:**
- [ ] System metrics collection active
- [ ] Service monitoring configured
- [ ] Log analysis running
- [ ] Security monitoring enabled
- [ ] Alert system configured
- [ ] Dashboard accessible
- [ ] Cron jobs scheduled
- [ ] Monitoring summary created

**Monitoring Testing:**
```bash
# Test monitoring dashboard
server-dashboard

# Check monitoring data
ls -la /usr/local/monitoring/data/

# Verify cron jobs
sudo crontab -l | grep monitoring
```

#### Step 5.2: Dynamic Tuning
```bash
# Run dynamic tuning module
./master.sh dynamic-tuning --debug
```

**Tuning Validation Checklist:**
- [ ] Hardware analysis completed
- [ ] Performance profile generated
- [ ] Tuning profile applied
- [ ] Services restarted with new settings
- [ ] Benchmark test completed (if apache2-utils available)
- [ ] Performance monitoring enabled
- [ ] Tuning tools created
- [ ] Tuning summary generated

**Performance Testing:**
```bash
# Check current performance profile
server-tuning current-profile

# Run performance analysis
server-tuning analyze

# Test tuning tools
server-tuning list-profiles
```

---

## 🔧 Post-Deployment Configuration

### WordPress Site Setup

#### Create Production Site
```bash
# Create your main WordPress site
wp-manage.sh create-site yourdomain.com

# Configure SSL for production domain
certbot --webroot -w /usr/local/lsws/Example/html/yourdomain.com -d yourdomain.com

# Install production plugins
cd /usr/local/lsws/Example/html/yourdomain.com
wp plugin install wordfence yoast-seo contact-form-7 --activate --allow-root
```

**Production Site Checklist:**
- [ ] Production domain site created
- [ ] SSL certificate installed for domain
- [ ] Essential plugins installed
- [ ] Caching enabled and tested
- [ ] Security plugins configured
- [ ] Admin account created with strong password
- [ ] Site accessible via HTTPS

### Security Hardening

#### Additional Security Steps
```bash
# Change default admin passwords
# CyberPanel: https://your-ip:8090
# OpenLiteSpeed: https://your-ip:7080

# Update WordPress admin credentials
cd /usr/local/lsws/Example/html/yourdomain.com
wp user update admin --user_pass='NewSecurePassword123!' --allow-root

# Configure fail2ban email notifications
sudo vim /etc/fail2ban/jail.d/custom.conf
# Add: destemail = admin@yourdomain.com
```

**Security Hardening Checklist:**
- [ ] CyberPanel admin password changed
- [ ] OpenLiteSpeed admin password changed
- [ ] WordPress admin password updated
- [ ] SSH key authentication enabled
- [ ] Root login disabled (optional)
- [ ] Fail2ban email notifications configured
- [ ] Security monitoring alerts tested

### Monitoring & Alerting

#### Configure Notifications
```bash
# Configure email notifications
vim config/notifications.conf
# Set: EMAIL_NOTIFICATIONS=true
# Set: ADMIN_EMAIL=your-email@domain.com

# Configure Telegram notifications (optional)
# Set: TELEGRAM_NOTIFICATIONS=true
# Set: TELEGRAM_BOT_TOKEN=your-bot-token
# Set: TELEGRAM_CHAT_ID=your-chat-id

# Restart monitoring to apply changes
./master.sh monitoring --force
```

**Monitoring Configuration Checklist:**
- [ ] Email notifications configured and tested
- [ ] Telegram notifications configured (if desired)
- [ ] Alert thresholds reviewed and adjusted
- [ ] Test alerts sent and received
- [ ] Monitoring dashboard accessible
- [ ] Log rotation working correctly

---

## 🧪 Testing & Validation

### Comprehensive System Test

#### Performance Testing
```bash
# Install Apache Bench for testing
sudo apt install apache2-utils -y

# Run performance benchmark
ab -n 1000 -c 10 http://yourdomain.com/

# Run automated benchmark
server-tuning benchmark current
```

**Performance Testing Checklist:**
- [ ] Apache Bench installed
- [ ] Performance benchmark completed
- [ ] Results show adequate performance (>500 RPS)
- [ ] Response times acceptable (<200ms)
- [ ] No errors during load testing
- [ ] System resources stable under load

#### Security Testing
```bash
# Test firewall rules
nmap -sS localhost

# Test fail2ban functionality
# (From another IP) - attempt multiple failed SSH logins
# Check if IP gets banned

# Test SSL configuration
curl -I https://yourdomain.com
sslscan yourdomain.com
```

**Security Testing Checklist:**
- [ ] Only required ports open (22, 80, 443, 8090, 7080)
- [ ] Fail2ban successfully bans IPs after failed attempts
- [ ] SSL certificates valid and properly configured
- [ ] WordPress login protected against brute force
- [ ] Admin interfaces only accessible from allowed IPs
- [ ] No unnecessary services running

#### Backup & Recovery Testing
```bash
# Test backup functionality
wp-manage.sh backup yourdomain.com

# Verify backup files created
ls -la /workspace/devops-ubuntu/backups/wordpress/yourdomain.com/

# Test database backup
mysqldump -u root -p yourdomain_wp > test-backup.sql
```

**Backup Testing Checklist:**
- [ ] WordPress backup completes successfully
- [ ] Database backup created
- [ ] File backup includes all WordPress files
- [ ] Backup files are readable and valid
- [ ] Automated backup cron jobs scheduled
- [ ] Old backups cleaned up automatically

---

## 📋 Go-Live Checklist

### Pre-Launch Verification

- [ ] **DNS Configuration**
  - [ ] Domain points to server IP
  - [ ] WWW and non-WWW versions work
  - [ ] DNS propagation complete (use dig/nslookup)

- [ ] **SSL/TLS Setup**
  - [ ] SSL certificate installed and valid
  - [ ] HTTP redirects to HTTPS
  - [ ] SSL Labs test shows A+ rating
  - [ ] No mixed content warnings

- [ ] **Performance Optimization**
  - [ ] Caching enabled and working
  - [ ] Static files compressed (gzip)
  - [ ] Images optimized
  - [ ] CDN configured (if applicable)

- [ ] **Security Configuration**
  - [ ] Admin interfaces secured
  - [ ] Security plugins configured
  - [ ] Regular backups scheduled
  - [ ] Monitoring and alerts active

- [ ] **WordPress Configuration**
  - [ ] Site title and tagline set
  - [ ] Permalink structure configured
  - [ ] Default content removed
  - [ ] Essential plugins installed and configured
  - [ ] Theme customized (if applicable)

### Launch Day Tasks

```bash
# Final system status check
./master.sh --status
server-dashboard

# Clear all caches
wp-manage.sh cache-flush yourdomain.com

# Final security scan
wp plugin install wordfence --activate --allow-root
# Run Wordfence scan

# Monitor system during launch
watch -n 30 'server-dashboard'
```

### Post-Launch Monitoring

- [ ] **24-Hour Monitoring**
  - [ ] No critical alerts received
  - [ ] Site loading properly
  - [ ] SSL certificate working
  - [ ] No 404 or 500 errors
  - [ ] Performance metrics stable

- [ ] **Week 1 Tasks**
  - [ ] Review all log files for issues
  - [ ] Verify backups are running
  - [ ] Check security alerts
  - [ ] Monitor performance trends
  - [ ] Test disaster recovery procedure

---

## 📝 Maintenance Schedule

### Daily Tasks (Automated)
- [ ] System metrics collection
- [ ] Service health monitoring  
- [ ] Security event monitoring
- [ ] Log analysis
- [ ] Backup verification

### Weekly Tasks
- [ ] Review monitoring dashboards
- [ ] Check system performance trends
- [ ] Review security logs
- [ ] Update WordPress core/plugins (if auto-update disabled)
- [ ] Clean up temporary files

### Monthly Tasks
- [ ] Full system health review
- [ ] Performance benchmark testing
- [ ] Security audit
- [ ] Backup restoration test
- [ ] Review and update configurations
- [ ] Check disk space and clean up old files

### Quarterly Tasks
- [ ] System package updates
- [ ] Security penetration testing
- [ ] Performance optimization review
- [ ] Disaster recovery drill
- [ ] Documentation updates
- [ ] Staff training updates

---

## 🎯 Success Criteria

### Technical Metrics
- [ ] **Uptime**: >99.9%
- [ ] **Response Time**: <200ms average
- [ ] **Page Load Speed**: <3 seconds
- [ ] **Security Score**: A+ SSL Labs rating
- [ ] **Performance Score**: >90 Lighthouse score
- [ ] **Backup Success Rate**: 100%

### Operational Metrics
- [ ] **Incident Response**: <15 minutes
- [ ] **Mean Time to Recovery**: <30 minutes
- [ ] **Security Alerts**: Handled within 5 minutes
- [ ] **Maintenance Window**: <2 hours monthly
- [ ] **User Satisfaction**: >95%

### Business Metrics
- [ ] **Cost Optimization**: 30%+ reduction vs traditional hosting
- [ ] **Management Efficiency**: 80%+ time savings
- [ ] **Scalability**: Ready for 5x traffic growth
- [ ] **Security Compliance**: All requirements met
- [ ] **Business Continuity**: Zero data loss incidents

---

## 🚨 Emergency Contacts & Procedures

### Emergency Response Team
- **Primary Admin**: [Name] - [Email] - [Phone]
- **Secondary Admin**: [Name] - [Email] - [Phone]
- **Technical Support**: [Provider] - [Contact Info]
- **Hosting Provider**: [Provider] - [Support Number]

### Emergency Procedures
1. **Server Down**: Check status, restart services, escalate if needed
2. **Security Breach**: Isolate system, assess damage, implement fixes
3. **Data Loss**: Restore from backups, validate data integrity
4. **Performance Issues**: Check resources, apply optimizations
5. **Certificate Expiry**: Renew certificates immediately

### Recovery Contacts
- **Domain Registrar**: [Provider] - [Account Info]
- **DNS Provider**: [Cloudflare/Other] - [Account Info]
- **SSL Provider**: [Let's Encrypt/Other] - [Account Info]
- **Backup Storage**: [Location] - [Access Info]

---

✅ **Deployment Complete!** 

Your WordPress Server Automation system is now fully deployed and operational. Keep this checklist for future reference and maintenance activities.
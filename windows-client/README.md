# WordPress Server IP Updater for Windows

This Windows client automatically detects public IP address changes and updates the Cloudflare DNS record to maintain server access via dynamic IP whitelisting.

## 🎯 Overview

The WordPress Server automation system uses dynamic IP whitelisting for enhanced security. This Windows PowerShell script runs on your local machine and automatically updates the server's firewall rules whenever your home/office public IP address changes.

## 📋 Requirements

- **Windows 10/11** with PowerShell 5.0 or higher
- **Internet connectivity** for IP detection and Cloudflare API access
- **Cloudflare account** with API access
- **Administrative privileges** for scheduled task installation

## 🚀 Quick Start

### 1. Installation

1. Download the Windows client files:
   - `ip-updater.ps1` - Main PowerShell script
   - `install.bat` - Installation batch script
   - `README.md` - This documentation

2. Run the installer as Administrator:
   ```cmd
   Right-click install.bat → "Run as Administrator"
   ```

3. The installer will:
   - Create installation directory (`C:\Program Files\WordPress Server IP Updater`)
   - Copy PowerShell script
   - Create sample configuration
   - Set up desktop shortcuts
   - Configure PowerShell execution policy

### 2. Configuration

1. Edit the configuration file (`config.json`):
   ```json
   {
       "cloudflare_api_token": "YOUR_API_TOKEN_HERE",
       "cloudflare_zone_id": "YOUR_ZONE_ID_HERE", 
       "domain_name": "ip.dulundu.tools",
       "check_interval_minutes": 5,
       "log_retention_days": 30,
       "notification_email": "admin@yourdomain.com"
   }
   ```

2. **Get Cloudflare API Token:**
   - Log into [Cloudflare Dashboard](https://dash.cloudflare.com/)
   - Go to **My Profile** → **API Tokens**
   - Create token with **Zone:Edit** permissions
   - Copy the token to `cloudflare_api_token`

3. **Get Zone ID:**
   - Select your domain in Cloudflare Dashboard
   - Scroll down to **API** section on the right sidebar
   - Copy **Zone ID** to `cloudflare_zone_id`

### 3. Testing

Test the configuration:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\WordPress Server IP Updater\ip-updater.ps1" -Test -Verbose
```

Or use the desktop shortcut: **"Test IP Updater"**

### 4. Installation as Scheduled Task

Install as Windows scheduled task:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\WordPress Server IP Updater\ip-updater.ps1" -Install
```

This will:
- Create a scheduled task that runs every 5 minutes (or configured interval)
- Run automatically at startup
- Continue running even when not logged in

## 🔧 Usage

### Command Line Options

```powershell
.\ip-updater.ps1 [OPTIONS]

OPTIONS:
    -ConfigFile <path>    Path to configuration file (default: .\config.json)
    -Install             Install as Windows scheduled task
    -Uninstall           Remove Windows scheduled task  
    -Test                Test configuration and connectivity
    -Verbose             Enable verbose logging
    -Help                Show help message
```

### Examples

```powershell
# Run once with default configuration
.\ip-updater.ps1

# Test configuration with verbose output
.\ip-updater.ps1 -Test -Verbose

# Install as scheduled task
.\ip-updater.ps1 -Install

# Uninstall scheduled task
.\ip-updater.ps1 -Uninstall

# Use custom configuration file
.\ip-updater.ps1 -ConfigFile "C:\MyConfig\config.json"
```

### Desktop Shortcuts

The installer creates convenient desktop shortcuts:

- **IP Updater Config** - Opens configuration file in Notepad
- **Test IP Updater** - Tests configuration with verbose output

## 📊 Configuration Reference

### Required Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `cloudflare_api_token` | Cloudflare API token with Zone:Edit permissions | `abc123...` |
| `cloudflare_zone_id` | Cloudflare zone ID for your domain | `def456...` |
| `domain_name` | DNS record name to update | `ip.dulundu.tools` |

### Optional Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `check_interval_minutes` | How often to check for IP changes | `5` |
| `log_retention_days` | How long to keep log files | `30` |
| `notification_email` | Email for notifications (not implemented) | `""` |
| `ip_check_services` | Array of IP check services | See config |

### IP Check Services

The script uses multiple services for reliability:
- `https://ipinfo.io/ip`
- `https://icanhazip.com/`  
- `https://checkip.amazonaws.com/`
- `https://ipv4.icanhazip.com/`

If one service fails, it tries the next one automatically.

## 📁 File Locations

After installation:

```
C:\Program Files\WordPress Server IP Updater\
├── ip-updater.ps1          # Main PowerShell script
├── config.json             # Configuration file
├── last-ip.txt            # Last known IP address
└── logs\                   # Log files directory
    ├── ip-updater-2024-01.log
    ├── ip-updater-2024-02.log
    └── ...
```

Desktop shortcuts:
```
%USERPROFILE%\Desktop\
├── IP Updater Config.lnk   # Edit configuration
└── Test IP Updater.lnk     # Test configuration
```

## 📋 Logs and Monitoring

### Log Files

Log files are created monthly in the `logs` directory:
- **Location**: `C:\Program Files\WordPress Server IP Updater\logs`
- **Format**: `ip-updater-YYYY-MM.log`
- **Retention**: Configurable (default: 30 days)

### Log Levels

- **INFO**: General information and successful operations
- **SUCCESS**: Successful DNS updates and operations
- **WARNING**: Non-critical issues (service failures, etc.)
- **ERROR**: Critical errors that prevent operation
- **DEBUG**: Detailed information (only shown with -Verbose)

### Sample Log Entry

```
[2024-01-15 14:30:15] [INFO] WordPress Server IP Updater v1.0.0 starting...
[2024-01-15 14:30:15] [DEBUG] Loading configuration from: .\config.json
[2024-01-15 14:30:15] [SUCCESS] Configuration loaded successfully
[2024-01-15 14:30:16] [DEBUG] Current public IP: 203.0.113.45
[2024-01-15 14:30:16] [INFO] IP address changed from '203.0.113.44' to '203.0.113.45'
[2024-01-15 14:30:17] [INFO] Updating Cloudflare DNS record for ip.dulundu.tools to 203.0.113.45
[2024-01-15 14:30:18] [SUCCESS] DNS record updated successfully
[2024-01-15 14:30:18] [SUCCESS] IP address update completed successfully
```

## 🔒 Security Considerations

### API Token Security

- **Minimal Permissions**: Create API token with only **Zone:Edit** permissions
- **Specific Zone**: Limit token to specific zone if possible
- **Regular Rotation**: Rotate API tokens periodically
- **Secure Storage**: Keep configuration file in protected location

### Network Security

- **HTTPS Only**: All API communications use HTTPS
- **Multiple Services**: Uses multiple IP check services for reliability
- **Error Handling**: Graceful failure handling prevents exposure

### System Security

- **No Elevation**: Script runs with user privileges (except during installation)
- **Scheduled Task**: Runs as current user, not SYSTEM
- **Log Protection**: Logs stored in protected Program Files directory

## 🛠️ Troubleshooting

### Common Issues

#### 1. PowerShell Execution Policy Error

**Error**: `execution of scripts is disabled on this system`

**Solution**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

#### 2. Cloudflare API Authentication Failed

**Error**: `Cloudflare API authentication failed`

**Solutions**:
- Verify API token is correct
- Check token has **Zone:Edit** permissions
- Ensure zone ID is correct
- Test with [Cloudflare API documentation](https://developers.cloudflare.com/api/)

#### 3. Unable to Retrieve Public IP

**Error**: `Failed to retrieve public IP from any service`

**Solutions**:
- Check internet connectivity
- Verify DNS resolution is working
- Try running with `-Verbose` to see which services are failing
- Configure proxy settings if behind corporate firewall

#### 4. Scheduled Task Not Running

**Symptoms**: Task created but IP not updating

**Solutions**:
- Check Task Scheduler for error messages
- Verify task is set to run whether user is logged in or not
- Check PowerShell execution policy
- Review log files for errors

### Diagnostic Commands

```powershell
# Test connectivity to IP check services
Invoke-RestMethod -Uri "https://ipinfo.io/ip"

# Test Cloudflare API token
$headers = @{"Authorization" = "Bearer YOUR_TOKEN_HERE"}
Invoke-RestMethod -Uri "https://api.cloudflare.com/v4/user/tokens/verify" -Headers $headers

# Check scheduled task status
Get-ScheduledTask -TaskName "WordPress Server IP Updater"

# View recent log entries
Get-Content "C:\Program Files\WordPress Server IP Updater\logs\ip-updater-$(Get-Date -Format yyyy-MM).log" | Select-Object -Last 20
```

## 📞 Support

### Log Collection

When reporting issues, include:

1. **Configuration** (remove sensitive tokens):
   ```json
   {
       "cloudflare_api_token": "[REDACTED]",
       "cloudflare_zone_id": "[REDACTED]",
       "domain_name": "ip.dulundu.tools",
       "check_interval_minutes": 5
   }
   ```

2. **Error Output**:
   ```powershell
   .\ip-updater.ps1 -Test -Verbose
   ```

3. **Recent Log Entries**:
   ```powershell
   Get-Content "logs\ip-updater-$(Get-Date -Format yyyy-MM).log" | Select-Object -Last 50
   ```

4. **System Information**:
   ```powershell
   $PSVersionTable
   Get-WmiObject -Class Win32_OperatingSystem | Select-Object Caption, Version
   ```

### Additional Resources

- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [PowerShell Scheduled Tasks](https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/)
- [Windows PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)

## 🔄 Updates and Maintenance

### Updating the Script

1. Download new version
2. Stop scheduled task: `.\ip-updater.ps1 -Uninstall`
3. Replace script file
4. Reinstall scheduled task: `.\ip-updater.ps1 -Install`

### Regular Maintenance

- **Monitor Logs**: Review logs weekly for errors
- **Test Configuration**: Test monthly with `-Test` flag
- **Update API Tokens**: Rotate tokens every 6 months
- **Clean Logs**: Old logs are automatically cleaned up

## 📄 License

This script is part of the WordPress Server Automation project.
See the main project documentation for license information.

---

**WordPress Server Automation Project**  
*DevOps Ubuntu Team*
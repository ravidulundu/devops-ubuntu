# WordPress Server Dynamic IP Updater for Windows
# ================================================
# PowerShell script that detects public IP changes and updates Cloudflare DNS record
# This script runs on Windows 11 machine to maintain server access via dynamic IP whitelisting
# Author: DevOps Ubuntu Team

param(
    [string]$ConfigFile = ".\config.json",
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Test,
    [switch]$Verbose,
    [switch]$Help
)

# Script metadata
$ScriptName = "WordPress Server IP Updater"
$ScriptVersion = "1.0.0"
$ScriptAuthor = "DevOps Ubuntu Team"

# Global variables
$Global:Config = $null
$Global:LogFile = $null
$Global:LastIPFile = $null

# Show help information
function Show-Help {
    Write-Host @"
$ScriptName v$ScriptVersion
$ScriptAuthor

DESCRIPTION:
    Monitors public IP address changes and automatically updates Cloudflare DNS
    record to maintain server access via dynamic IP whitelisting.

USAGE:
    .\ip-updater.ps1 [-ConfigFile <path>] [-Install] [-Uninstall] [-Test] [-Verbose] [-Help]

PARAMETERS:
    -ConfigFile <path>  Path to configuration file (default: .\config.json)
    -Install            Install as Windows scheduled task
    -Uninstall          Remove Windows scheduled task
    -Test               Test configuration and connectivity
    -Verbose            Enable verbose logging
    -Help               Show this help message

EXAMPLES:
    .\ip-updater.ps1                          # Run once with default config
    .\ip-updater.ps1 -Install                 # Install as scheduled task
    .\ip-updater.ps1 -Test -Verbose           # Test configuration
    .\ip-updater.ps1 -ConfigFile ".\my.json"  # Use custom config file

CONFIGURATION:
    Create config.json file with your Cloudflare API credentials:
    {
        "cloudflare_api_token": "your-api-token",
        "cloudflare_zone_id": "your-zone-id",
        "domain_name": "ip.dulundu.tools",
        "check_interval_minutes": 5,
        "log_retention_days": 30,
        "notification_email": "admin@yourdomain.com"
    }

REQUIREMENTS:
    - Windows PowerShell 5.0 or higher
    - Internet connectivity
    - Cloudflare API token with Zone:Edit permissions
    - Administrative privileges (for scheduled task installation)
"@
}

# Logging functions
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "INFO" { Write-Host $logEntry -ForegroundColor Cyan }
        "DEBUG" { 
            if ($Verbose) { 
                Write-Host $logEntry -ForegroundColor Gray 
            }
        }
        default { Write-Host $logEntry }
    }
    
    # Write to log file if configured
    if ($Global:LogFile -and (Test-Path (Split-Path $Global:LogFile -Parent))) {
        Add-Content -Path $Global:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
}

# Load configuration from JSON file
function Load-Configuration {
    param([string]$ConfigPath)
    
    Write-Log "Loading configuration from: $ConfigPath" "DEBUG"
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Log "Configuration file not found: $ConfigPath" "ERROR"
        Write-Log "Creating sample configuration file..." "INFO"
        Create-SampleConfig -Path $ConfigPath
        return $false
    }
    
    try {
        $configContent = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
        $Global:Config = ConvertFrom-Json -InputObject $configContent -ErrorAction Stop
        
        # Validate required fields
        $requiredFields = @(
            'cloudflare_api_token',
            'cloudflare_zone_id', 
            'domain_name'
        )
        
        foreach ($field in $requiredFields) {
            if (-not $Global:Config.$field) {
                Write-Log "Missing required configuration field: $field" "ERROR"
                return $false
            }
        }
        
        # Set defaults for optional fields
        if (-not $Global:Config.check_interval_minutes) { 
            $Global:Config | Add-Member -MemberType NoteProperty -Name "check_interval_minutes" -Value 5 -Force
        }
        if (-not $Global:Config.log_retention_days) { 
            $Global:Config | Add-Member -MemberType NoteProperty -Name "log_retention_days" -Value 30 -Force
        }
        
        # Setup logging
        $logDir = Join-Path $PSScriptRoot "logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        $Global:LogFile = Join-Path $logDir "ip-updater-$(Get-Date -Format 'yyyy-MM').log"
        $Global:LastIPFile = Join-Path $PSScriptRoot "last-ip.txt"
        
        Write-Log "Configuration loaded successfully" "SUCCESS"
        Write-Log "Domain: $($Global:Config.domain_name)" "DEBUG"
        Write-Log "Check interval: $($Global:Config.check_interval_minutes) minutes" "DEBUG"
        
        return $true
    }
    catch {
        Write-Log "Failed to load configuration: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Create sample configuration file
function Create-SampleConfig {
    param([string]$Path)
    
    $sampleConfig = @{
        cloudflare_api_token = "YOUR_CLOUDFLARE_API_TOKEN_HERE"
        cloudflare_zone_id = "YOUR_CLOUDFLARE_ZONE_ID_HERE"
        domain_name = "ip.dulundu.tools"
        check_interval_minutes = 5
        log_retention_days = 30
        notification_email = "admin@yourdomain.com"
        ip_check_services = @(
            "https://ipinfo.io/ip",
            "https://icanhazip.com/",
            "https://checkip.amazonaws.com/",
            "https://ipv4.icanhazip.com/"
        )
    } | ConvertTo-Json -Depth 3
    
    try {
        $sampleConfig | Out-File -FilePath $Path -Encoding UTF8 -ErrorAction Stop
        Write-Log "Sample configuration created: $Path" "SUCCESS"
        Write-Log "Please edit the configuration file with your Cloudflare API credentials" "WARNING"
    }
    catch {
        Write-Log "Failed to create sample configuration: $($_.Exception.Message)" "ERROR"
    }
}

# Get current public IP address
function Get-PublicIP {
    $ipServices = $Global:Config.ip_check_services
    if (-not $ipServices) {
        $ipServices = @(
            "https://ipinfo.io/ip",
            "https://icanhazip.com/", 
            "https://checkip.amazonaws.com/",
            "https://ipv4.icanhazip.com/"
        )
    }
    
    foreach ($service in $ipServices) {
        try {
            Write-Log "Checking IP from: $service" "DEBUG"
            $response = Invoke-RestMethod -Uri $service -TimeoutSec 10 -ErrorAction Stop
            $ip = ($response -replace '\s', '').Trim()
            
            # Validate IP format
            if ($ip -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') {
                Write-Log "Current public IP: $ip" "DEBUG"
                return $ip
            }
            else {
                Write-Log "Invalid IP format from $service`: $ip" "WARNING"
            }
        }
        catch {
            Write-Log "Failed to get IP from $service`: $($_.Exception.Message)" "WARNING"
        }
    }
    
    Write-Log "Failed to retrieve public IP from any service" "ERROR"
    return $null
}

# Get last known IP address
function Get-LastIP {
    if (Test-Path $Global:LastIPFile) {
        try {
            $lastIP = Get-Content -Path $Global:LastIPFile -ErrorAction Stop
            Write-Log "Last known IP: $lastIP" "DEBUG"
            return $lastIP.Trim()
        }
        catch {
            Write-Log "Failed to read last IP file: $($_.Exception.Message)" "WARNING"
        }
    }
    
    return $null
}

# Save current IP address
function Set-LastIP {
    param([string]$IPAddress)
    
    try {
        $IPAddress | Out-File -FilePath $Global:LastIPFile -Encoding ASCII -ErrorAction Stop
        Write-Log "Saved current IP to file: $IPAddress" "DEBUG"
    }
    catch {
        Write-Log "Failed to save current IP: $($_.Exception.Message)" "WARNING"
    }
}

# Update Cloudflare DNS record
function Update-CloudflareDNS {
    param([string]$NewIP)
    
    Write-Log "Updating Cloudflare DNS record for $($Global:Config.domain_name) to $NewIP" "INFO"
    
    $headers = @{
        "Authorization" = "Bearer $($Global:Config.cloudflare_api_token)"
        "Content-Type" = "application/json"
    }
    
    try {
        # Get existing DNS record
        $recordsUrl = "https://api.cloudflare.com/v4/zones/$($Global:Config.cloudflare_zone_id)/dns_records?name=$($Global:Config.domain_name)&type=A"
        Write-Log "Fetching existing DNS records..." "DEBUG"
        
        $recordsResponse = Invoke-RestMethod -Uri $recordsUrl -Headers $headers -Method GET -ErrorAction Stop
        
        if (-not $recordsResponse.success) {
            Write-Log "Failed to fetch DNS records: $($recordsResponse.errors | ConvertTo-Json)" "ERROR"
            return $false
        }
        
        $existingRecord = $recordsResponse.result | Where-Object { $_.name -eq $Global:Config.domain_name -and $_.type -eq "A" } | Select-Object -First 1
        
        if ($existingRecord) {
            # Update existing record
            Write-Log "Updating existing DNS record (ID: $($existingRecord.id))" "DEBUG"
            
            $updateData = @{
                type = "A"
                name = $Global:Config.domain_name
                content = $NewIP
                ttl = 300
            } | ConvertTo-Json
            
            $updateUrl = "https://api.cloudflare.com/v4/zones/$($Global:Config.cloudflare_zone_id)/dns_records/$($existingRecord.id)"
            $updateResponse = Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PUT -Body $updateData -ErrorAction Stop
            
            if ($updateResponse.success) {
                Write-Log "DNS record updated successfully" "SUCCESS"
                return $true
            }
            else {
                Write-Log "Failed to update DNS record: $($updateResponse.errors | ConvertTo-Json)" "ERROR"
                return $false
            }
        }
        else {
            # Create new record
            Write-Log "Creating new DNS record" "DEBUG"
            
            $createData = @{
                type = "A"
                name = $Global:Config.domain_name
                content = $NewIP
                ttl = 300
            } | ConvertTo-Json
            
            $createUrl = "https://api.cloudflare.com/v4/zones/$($Global:Config.cloudflare_zone_id)/dns_records"
            $createResponse = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $createData -ErrorAction Stop
            
            if ($createResponse.success) {
                Write-Log "DNS record created successfully" "SUCCESS"
                return $true
            }
            else {
                Write-Log "Failed to create DNS record: $($createResponse.errors | ConvertTo-Json)" "ERROR"
                return $false
            }
        }
    }
    catch {
        Write-Log "Cloudflare API error: $($_.Exception.Message)" "ERROR"
        if ($_.Exception.Response) {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $responseBody = $reader.ReadToEnd()
            Write-Log "API Response: $responseBody" "DEBUG"
        }
        return $false
    }
}

# Send notification email
function Send-Notification {
    param(
        [string]$Subject,
        [string]$Body
    )
    
    if (-not $Global:Config.notification_email) {
        return
    }
    
    try {
        # This is a basic implementation - in production you might want to use SMTP
        Write-Log "Notification would be sent to: $($Global:Config.notification_email)" "DEBUG"
        Write-Log "Subject: $Subject" "DEBUG"
        Write-Log "Body: $Body" "DEBUG"
    }
    catch {
        Write-Log "Failed to send notification: $($_.Exception.Message)" "WARNING"
    }
}

# Test configuration and connectivity
function Test-Configuration {
    Write-Log "Testing configuration and connectivity..." "INFO"
    
    # Test public IP retrieval
    Write-Log "Testing public IP retrieval..." "INFO"
    $currentIP = Get-PublicIP
    if (-not $currentIP) {
        Write-Log "Failed to retrieve public IP address" "ERROR"
        return $false
    }
    Write-Log "✓ Public IP retrieval successful: $currentIP" "SUCCESS"
    
    # Test Cloudflare API connectivity
    Write-Log "Testing Cloudflare API connectivity..." "INFO"
    $headers = @{
        "Authorization" = "Bearer $($Global:Config.cloudflare_api_token)"
        "Content-Type" = "application/json"
    }
    
    try {
        $testUrl = "https://api.cloudflare.com/v4/user/tokens/verify"
        $response = Invoke-RestMethod -Uri $testUrl -Headers $headers -Method GET -ErrorAction Stop
        
        if ($response.success) {
            Write-Log "✓ Cloudflare API authentication successful" "SUCCESS"
        }
        else {
            Write-Log "Cloudflare API authentication failed" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Cloudflare API test failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
    
    # Test zone access
    Write-Log "Testing Cloudflare zone access..." "INFO"
    try {
        $zoneUrl = "https://api.cloudflare.com/v4/zones/$($Global:Config.cloudflare_zone_id)"
        $zoneResponse = Invoke-RestMethod -Uri $zoneUrl -Headers $headers -Method GET -ErrorAction Stop
        
        if ($zoneResponse.success) {
            Write-Log "✓ Zone access successful: $($zoneResponse.result.name)" "SUCCESS"
        }
        else {
            Write-Log "Zone access failed" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Zone access test failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
    
    Write-Log "✓ All configuration tests passed successfully" "SUCCESS"
    return $true
}

# Install as Windows scheduled task
function Install-ScheduledTask {
    Write-Log "Installing Windows scheduled task..." "INFO"
    
    try {
        $taskName = "WordPress Server IP Updater"
        $scriptPath = $MyInvocation.ScriptName
        $configPath = Resolve-Path $ConfigFile -ErrorAction Stop
        
        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Log "Removing existing scheduled task..." "INFO"
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
        
        # Create scheduled task action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -ConfigFile `"$configPath`""
        
        # Create trigger for specified interval
        $interval = [TimeSpan]::FromMinutes($Global:Config.check_interval_minutes)
        $trigger = New-ScheduledTaskTrigger -RepetitionInterval $interval -RepetitionDuration ([TimeSpan]::MaxValue) -At (Get-Date) -Once
        
        # Create task settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        
        # Create task principal (run as current user)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        
        # Register the task
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Automatically updates server IP address in Cloudflare DNS for dynamic IP whitelisting"
        
        Write-Log "✓ Scheduled task installed successfully" "SUCCESS"
        Write-Log "Task will run every $($Global:Config.check_interval_minutes) minutes" "INFO"
        
        # Start the task immediately
        Start-ScheduledTask -TaskName $taskName
        Write-Log "✓ Scheduled task started" "SUCCESS"
        
        return $true
    }
    catch {
        Write-Log "Failed to install scheduled task: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Uninstall Windows scheduled task
function Uninstall-ScheduledTask {
    Write-Log "Uninstalling Windows scheduled task..." "INFO"
    
    try {
        $taskName = "WordPress Server IP Updater"
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Log "✓ Scheduled task removed successfully" "SUCCESS"
        }
        else {
            Write-Log "Scheduled task not found" "WARNING"
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to uninstall scheduled task: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Cleanup old log files
function Cleanup-Logs {
    $logDir = Join-Path $PSScriptRoot "logs"
    if (Test-Path $logDir) {
        $cutoffDate = (Get-Date).AddDays(-$Global:Config.log_retention_days)
        Get-ChildItem -Path $logDir -Filter "*.log" | Where-Object { $_.LastWriteTime -lt $cutoffDate } | Remove-Item -Force
        Write-Log "Cleaned up old log files" "DEBUG"
    }
}

# Main execution function
function Main {
    Write-Log "$ScriptName v$ScriptVersion starting..." "INFO"
    
    # Load configuration
    if (-not (Load-Configuration -ConfigPath $ConfigFile)) {
        Write-Log "Failed to load configuration. Exiting." "ERROR"
        exit 1
    }
    
    # Cleanup old logs
    Cleanup-Logs
    
    # Get current public IP
    $currentIP = Get-PublicIP
    if (-not $currentIP) {
        Write-Log "Unable to determine current public IP address" "ERROR"
        exit 1
    }
    
    # Get last known IP
    $lastIP = Get-LastIP
    
    # Check if IP has changed
    if ($currentIP -eq $lastIP) {
        Write-Log "IP address unchanged: $currentIP" "INFO"
        exit 0
    }
    
    Write-Log "IP address changed from '$lastIP' to '$currentIP'" "INFO"
    
    # Update Cloudflare DNS
    if (Update-CloudflareDNS -NewIP $currentIP) {
        # Save new IP
        Set-LastIP -IPAddress $currentIP
        
        # Send notification
        $subject = "Server IP Updated: $currentIP"
        $body = @"
WordPress Server IP Address Updated

Previous IP: $lastIP
New IP: $currentIP
Domain: $($Global:Config.domain_name)
Updated: $(Get-Date)

Server access has been automatically updated for the new IP address.
"@
        Send-Notification -Subject $subject -Body $body
        
        Write-Log "IP address update completed successfully" "SUCCESS"
    }
    else {
        Write-Log "Failed to update IP address in Cloudflare DNS" "ERROR"
        exit 1
    }
}

# Script entry point
try {
    # Handle command line parameters
    if ($Help) {
        Show-Help
        exit 0
    }
    
    if ($Install) {
        if (-not (Load-Configuration -ConfigPath $ConfigFile)) {
            Write-Log "Configuration must be valid before installation" "ERROR"
            exit 1
        }
        if (Install-ScheduledTask) {
            exit 0
        } else {
            exit 1
        }
    }
    
    if ($Uninstall) {
        if (Uninstall-ScheduledTask) {
            exit 0
        } else {
            exit 1
        }
    }
    
    if ($Test) {
        if (-not (Load-Configuration -ConfigPath $ConfigFile)) {
            exit 1
        }
        if (Test-Configuration) {
            exit 0
        } else {
            exit 1
        }
    }
    
    # Main execution
    Main
}
catch {
    Write-Log "Unhandled exception: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "DEBUG"
    exit 1
}
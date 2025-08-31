@echo off
REM WordPress Server IP Updater Installation Script for Windows
REM ===========================================================
REM Batch script to install and configure the PowerShell IP updater
REM Author: DevOps Ubuntu Team

setlocal enabledelayedexpansion

REM Script metadata
set "SCRIPT_NAME=WordPress Server IP Updater Installer"
set "SCRIPT_VERSION=1.0.0"

echo ================================================================
echo %SCRIPT_NAME% v%SCRIPT_VERSION%
echo ================================================================
echo.

REM Check for administrative privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: This script requires administrative privileges.
    echo Please run as Administrator.
    echo.
    pause
    exit /b 1
)

REM Check PowerShell version
echo Checking PowerShell version...
for /f "tokens=*" %%i in ('powershell -command "$PSVersionTable.PSVersion.Major"') do set PS_VERSION=%%i
if !PS_VERSION! lss 5 (
    echo ERROR: PowerShell 5.0 or higher is required.
    echo Current version: !PS_VERSION!
    echo Please update PowerShell and try again.
    pause
    exit /b 1
)
echo ✓ PowerShell version !PS_VERSION! detected

REM Create installation directory
set "INSTALL_DIR=%PROGRAMFILES%\WordPress Server IP Updater"
echo.
echo Creating installation directory: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    if !errorlevel! neq 0 (
        echo ERROR: Failed to create installation directory
        pause
        exit /b 1
    )
)
echo ✓ Installation directory created

REM Copy PowerShell script
echo.
echo Copying PowerShell script...
copy /Y "ip-updater.ps1" "%INSTALL_DIR%\ip-updater.ps1" >nul
if !errorlevel! neq 0 (
    echo ERROR: Failed to copy PowerShell script
    pause
    exit /b 1
)
echo ✓ PowerShell script copied

REM Create sample configuration
echo.
echo Creating sample configuration...
if not exist "%INSTALL_DIR%\config.json" (
    powershell -ExecutionPolicy Bypass -Command "& '%INSTALL_DIR%\ip-updater.ps1' -ConfigFile '%INSTALL_DIR%\config.json'" >nul 2>&1
    echo ✓ Sample configuration created
) else (
    echo ! Configuration file already exists
)

REM Create logs directory
if not exist "%INSTALL_DIR%\logs" (
    mkdir "%INSTALL_DIR%\logs"
    echo ✓ Logs directory created
)

REM Create desktop shortcut
echo.
echo Creating desktop shortcuts...
set "DESKTOP=%USERPROFILE%\Desktop"

REM Configuration shortcut
powershell -Command "& {$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%DESKTOP%\IP Updater Config.lnk'); $s.TargetPath = 'notepad.exe'; $s.Arguments = '%INSTALL_DIR%\config.json'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Description = 'Edit IP Updater Configuration'; $s.Save()}" >nul 2>&1

REM Test shortcut  
powershell -Command "& {$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%DESKTOP%\Test IP Updater.lnk'); $s.TargetPath = 'powershell.exe'; $s.Arguments = '-ExecutionPolicy Bypass -File \"%INSTALL_DIR%\ip-updater.ps1\" -Test -Verbose'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Description = 'Test IP Updater Configuration'; $s.Save()}" >nul 2>&1

echo ✓ Desktop shortcuts created

REM Set PowerShell execution policy
echo.
echo Configuring PowerShell execution policy...
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" >nul 2>&1
echo ✓ PowerShell execution policy configured

REM Display final instructions
echo.
echo ================================================================
echo INSTALLATION COMPLETED SUCCESSFULLY!
echo ================================================================
echo.
echo NEXT STEPS:
echo.
echo 1. Edit the configuration file with your Cloudflare API credentials:
echo    "%INSTALL_DIR%\config.json"
echo.
echo    Required fields:
echo    - cloudflare_api_token: Your Cloudflare API token
echo    - cloudflare_zone_id: Your Cloudflare zone ID  
echo    - domain_name: DNS record name (e.g., ip.dulundu.tools)
echo.
echo 2. Test the configuration:
echo    powershell -ExecutionPolicy Bypass -File "%INSTALL_DIR%\ip-updater.ps1" -Test -Verbose
echo.
echo 3. Install as scheduled task:
echo    powershell -ExecutionPolicy Bypass -File "%INSTALL_DIR%\ip-updater.ps1" -Install
echo.
echo DESKTOP SHORTCUTS CREATED:
echo - "IP Updater Config" - Edit configuration
echo - "Test IP Updater" - Test configuration
echo.
echo LOG FILES LOCATION:
echo "%INSTALL_DIR%\logs"
echo.
echo MANUAL COMMANDS:
echo - Test: powershell -ExecutionPolicy Bypass -File "%INSTALL_DIR%\ip-updater.ps1" -Test
echo - Install: powershell -ExecutionPolicy Bypass -File "%INSTALL_DIR%\ip-updater.ps1" -Install  
echo - Uninstall: powershell -ExecutionPolicy Bypass -File "%INSTALL_DIR%\ip-updater.ps1" -Uninstall
echo - Help: powershell -ExecutionPolicy Bypass -File "%INSTALL_DIR%\ip-updater.ps1" -Help
echo.
echo For support, check the documentation or log files.
echo ================================================================
echo.
pause
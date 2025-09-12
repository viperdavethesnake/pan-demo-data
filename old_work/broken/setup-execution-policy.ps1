# setup-execution-policy.ps1
# --- PowerShell Execution Policy Setup for Script Deployment ---
# 
# PURPOSE:
#   Configures PowerShell execution policy on new file servers to allow
#   the Panzura Symphony test environment scripts to run properly.
#
# PROBLEM:
#   When copying scripts to new servers, PowerShell's security settings
#   prevent unsigned scripts from running with errors like:
#   - "execution of scripts is disabled on this system"
#   - "cannot be loaded because running scripts is disabled" 
#   - "digital signature" or "signing" errors
#
# SOLUTION:
#   Sets execution policy to RemoteSigned which allows:
#   - Local scripts to run (our test environment scripts)
#   - Downloaded scripts require digital signatures (maintains security)
#
# USAGE:
#   1. Copy this script to new file server
#   2. Run PowerShell as Administrator
#   3. Execute: .\setup-execution-policy.ps1
#   4. Then run other scripts normally:
#      - .\create-folders.ps1 -ThrottleLimit 16
#      - .\create-files.ps1 -FileCount 100000
#
# NOTES:
#   - This is a one-time setup per server
#   - RemoteSigned balances functionality with security
#   - Alternative: Use "Unrestricted" for maximum compatibility
#   - Use "Bypass -Scope Process" for temporary/single-session only
#
# AUTHOR: Panzura Symphony Test Environment Setup
# DATE: September 11, 2025
#

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "POWERSHELL EXECUTION POLICY SETUP" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Purpose: Enable Panzura Symphony test scripts on this server"
Write-Host ""

# Check current execution policy
Write-Host "Current Execution Policy Settings:" -ForegroundColor Yellow
Get-ExecutionPolicy -List | Format-Table -AutoSize

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "⚠️  WARNING: Not running as Administrator!" -ForegroundColor Red
    Write-Host "   This script should be run as Administrator to set machine-wide policy." -ForegroundColor Yellow
    Write-Host "   Alternative: Use temporary bypass for current session only." -ForegroundColor Yellow
    Write-Host ""
    
    $choice = Read-Host "Continue with temporary session policy? (y/n)"
    if ($choice -eq 'y' -or $choice -eq 'Y') {
        Write-Host "Setting temporary execution policy for current session..." -ForegroundColor Green
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        Write-Host "✅ Temporary policy set. Scripts will work in this PowerShell session." -ForegroundColor Green
        Write-Host "   Note: You'll need to run this again in new PowerShell sessions." -ForegroundColor Yellow
    } else {
        Write-Host "❌ Cancelled. Please run PowerShell as Administrator and try again." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✅ Running as Administrator - can set machine-wide policy." -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Setting execution policy to RemoteSigned..." -ForegroundColor Green
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
        Write-Host "✅ SUCCESS: Execution policy set to RemoteSigned" -ForegroundColor Green
        Write-Host ""
        Write-Host "Benefits:" -ForegroundColor Yellow
        Write-Host "  ✓ Local scripts (like our test environment scripts) will run" -ForegroundColor White
        Write-Host "  ✓ Downloaded scripts still require digital signatures (security)" -ForegroundColor White
        Write-Host "  ✓ One-time setup - no need to repeat on this server" -ForegroundColor White
    } catch {
        Write-Host "❌ ERROR: Failed to set execution policy: $_" -ForegroundColor Red
        Write-Host "   Try running the temporary session command instead:" -ForegroundColor Yellow
        Write-Host "   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process" -ForegroundColor Cyan
        exit 1
    }
}

Write-Host ""
Write-Host "Updated Execution Policy Settings:" -ForegroundColor Yellow
Get-ExecutionPolicy -List | Format-Table -AutoSize

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SETUP COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "You can now run the Panzura Symphony test environment scripts:" -ForegroundColor Green
Write-Host ""
Write-Host "For folder creation:" -ForegroundColor Yellow
Write-Host "  .\create-folders.ps1 -ThrottleLimit 16" -ForegroundColor Cyan
Write-Host ""
Write-Host "For file population:" -ForegroundColor Yellow  
Write-Host "  .\create-files.ps1 -FileCount 100000" -ForegroundColor Cyan
Write-Host ""
Write-Host "For preview mode (recommended first):" -ForegroundColor Yellow
Write-Host "  .\create-folders.ps1 -WhatIf" -ForegroundColor Cyan
Write-Host "  .\create-files.ps1 -WhatIf -FileCount 1000" -ForegroundColor Cyan
Write-Host ""
Write-Host "🚀 Ready for script deployment!" -ForegroundColor Green


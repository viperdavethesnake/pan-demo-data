# pre_flight.ps1 — Pre-flight checks for demo toolkit
<#
.SYNOPSIS
  Run pre-flight checks before executing the demo toolkit scripts.

.DESCRIPTION
  Validates environment prerequisites and provides helpful warnings.
#>

Write-Host "=== Pre-flight Checks ===" -ForegroundColor Cyan

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -lt 7) {
  Write-Warning "PowerShell 7.x or later recommended. Current version: $($psVersion)"
} else {
  Write-Host "✓ PowerShell version: $($psVersion)" -ForegroundColor Green
}

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Warning "Not running as Administrator. Some operations may fail."
} else {
  Write-Host "✓ Running as Administrator" -ForegroundColor Green
}

# Check ActiveDirectory module
try {
  Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
  Write-Host "✓ ActiveDirectory module available" -ForegroundColor Green
} catch {
  Write-Warning "ActiveDirectory module not available. Install RSAT."
}

# Check SmbShare module
try {
  Import-Module SmbShare -SkipEditionCheck -ErrorAction Stop
  Write-Host "✓ SmbShare module available" -ForegroundColor Green
} catch {
  Write-Warning "SmbShare module not available. Share creation will fail."
}

# Check S: drive
if (Get-PSDrive S -ErrorAction SilentlyContinue) {
  Write-Host "✓ S: drive found" -ForegroundColor Green
} else {
  Write-Warning "S: drive not found. Adjust -Root parameter if needed."
}

Write-Host "`n=== Pre-flight Complete ===" -ForegroundColor Cyan

# clean_shared.ps1 - Nuclear option to delete everything in S:\Shared
<#
.SYNOPSIS
  Completely deletes all files and folders in S:\Shared - NO RECYCLE BIN!

.DESCRIPTION
  This script will PERMANENTLY DELETE all content in S:\Shared.
  This action CANNOT be undone. Use with extreme caution.

.PARAMETER Confirm
  Skip confirmation prompt (for automation)

.EXAMPLE
  .\clean_shared.ps1
  .\clean_shared.ps1 -Confirm:$false
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [switch]$SkipConfirmation
)

$SharedPath = "S:\Shared"

Write-Host "=== NUCLEAR CLEANUP OF S:\Shared ===" -ForegroundColor Red
Write-Host "This will PERMANENTLY DELETE all files and folders!" -ForegroundColor Red
Write-Host "NO RECYCLE BIN - GONE FOREVER!" -ForegroundColor Red
Write-Host ""

if (-not $SkipConfirmation) {
    $response = Read-Host "Type 'DELETE' to confirm (case sensitive)"
    if ($response -ne "DELETE") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

if (Test-Path $SharedPath) {
    Write-Host "Deleting all content in $SharedPath..." -ForegroundColor Yellow
    
    try {
        # Get count before deletion
        $fileCount = (Get-ChildItem -Path $SharedPath -Recurse -File -ErrorAction SilentlyContinue).Count
        $folderCount = (Get-ChildItem -Path $SharedPath -Recurse -Directory -ErrorAction SilentlyContinue).Count
        
        Write-Host "Found $fileCount files and $folderCount folders to delete" -ForegroundColor Cyan
        
        # Delete everything recursively
        Get-ChildItem -Path $SharedPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "✅ S:\Shared is now completely empty!" -ForegroundColor Green
        Write-Host "Deleted $fileCount files and $folderCount folders" -ForegroundColor Green
        
    } catch {
        Write-Host "❌ Error during deletion: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "❌ S:\Shared does not exist!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== CLEANUP COMPLETE ===" -ForegroundColor Green

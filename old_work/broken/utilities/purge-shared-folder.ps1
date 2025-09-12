# purge-shared-folder.ps1
# Completely purges everything in S:\Shared - NO RECYCLE BIN

param(
    [string]$TargetPath = "S:\Shared",
    [switch]$WhatIf = $false,  # Safety switch to preview what would be deleted
    [switch]$Force = $false    # Required to actually run the deletion
)

if (-not $Force -and -not $WhatIf) {
    Write-Host "ERROR: This script will PERMANENTLY DELETE everything in $TargetPath"
    Write-Host "Use -WhatIf to preview what would be deleted"
    Write-Host "Use -Force to actually perform the deletion"
    Write-Host ""
    Write-Host "Example: .\purge-shared-folder.ps1 -WhatIf"
    Write-Host "Example: .\purge-shared-folder.ps1 -Force"
    exit 1
}

if (-not (Test-Path $TargetPath)) {
    Write-Host "Path does not exist: $TargetPath"
    exit 1
}

Write-Host "========================================="
Write-Host "PURGE SHARED FOLDER SCRIPT"
Write-Host "========================================="
Write-Host "Target: $TargetPath"
Write-Host "WhatIf: $WhatIf"
Write-Host "Force: $Force"
Write-Host ""

# Quick check if folder exists and has content
Write-Host "Checking if $TargetPath has content..."
$hasContent = (Get-ChildItem $TargetPath -Force -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null

if (-not $hasContent) {
    Write-Host "Nothing to delete - folder is already empty"
    exit 0
}

Write-Host "Folder contains data - proceeding with deletion..."
Write-Host "NOTE: Skipping full scan for 100TB performance - will delete as we go"

if ($WhatIf) {
    Write-Host ""
    Write-Host "WHATIF MODE - Would delete the following:"
    Write-Host ""
    
    Write-Host "SAMPLE OF WHAT WOULD BE DELETED:"
    Get-ChildItem $TargetPath -Force | Select-Object -First 20 | ForEach-Object { 
        if ($_.PSIsContainer) {
            Write-Host "  FOLDER: $($_.FullName)"
        } else {
            Write-Host "  FILE: $($_.FullName)"
        }
    }
    Write-Host "  ... and ALL other content in $TargetPath recursively"
    
    Write-Host ""
    Write-Host "Run with -Force to actually perform these deletions"
    Write-Host "WARNING: This will PERMANENTLY delete everything - NO RECYCLE BIN!"
    exit 0
}

# Actual deletion with -Force
Write-Host ""
Write-Host "WARNING: Starting PERMANENT deletion in 5 seconds..."
Write-Host "Press Ctrl+C to abort!"
for ($i = 5; $i -gt 0; $i--) {
    Write-Host "$i..."
    Start-Sleep 1
}

Write-Host ""
Write-Host "Starting FAST deletion process (no counting for 100TB performance)..."

# Use Get-ChildItem in batches and delete immediately
$batchCount = 0
do {
    $batchCount++
    Write-Host "Processing batch $batchCount..."
    
    # Get top-level items only (let Remove-Item handle recursion)
    $topLevelItems = Get-ChildItem $TargetPath -Force -ErrorAction SilentlyContinue
    
    if ($topLevelItems.Count -eq 0) {
        Write-Host "No more items to delete"
        break
    }
    
    Write-Host "  Deleting $($topLevelItems.Count) top-level items..."
    foreach ($item in $topLevelItems) {
        try {
            Remove-Item $item.FullName -Force -Recurse -ErrorAction Stop
        } catch {
            Write-Host "  ERROR deleting: $($item.FullName) - $_"
        }
    }
    
} while ($topLevelItems.Count -gt 0)

Write-Host "Fast deletion process completed!"

# Verify cleanup
Write-Host ""
Write-Host "Verifying cleanup..."
$remainingItems = Get-ChildItem $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
if ($remainingItems.Count -eq 0) {
    Write-Host "SUCCESS: $TargetPath is now completely empty"
} else {
    Write-Host "WARNING: $($remainingItems.Count) items remain:"
    $remainingItems | Select-Object -First 10 | ForEach-Object { Write-Host "  - $($_.FullName)" }
}

Write-Host ""
Write-Host "Purge complete!"
Write-Host "========================================="

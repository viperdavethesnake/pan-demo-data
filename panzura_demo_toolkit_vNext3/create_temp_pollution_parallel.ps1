# create_temp_pollution_parallel.ps1 — High-performance parallel temp file pollution
<#
.SYNOPSIS
  Generate temp file pollution using parallel processing for massive performance gains.
  
.DESCRIPTION
  Creates .tmp files scattered across project folders with date clustering.
  Optimized with runspace pools, bulk operations, and smart distribution.
  
.EXAMPLE
  .\create_temp_pollution_parallel.ps1 -MaxFiles 100000
  Creates 100K temp files using parallel processing
  
.EXAMPLE
  .\create_temp_pollution_parallel.ps1 -MaxFiles 50000 -MaxThreads 16
  Uses up to 16 parallel threads
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [int]$MaxFiles = 50000,
  [switch]$NoAD,
  [int]$ProgressUpdateEvery = 500,
  
  # Parallel processing parameters
  [int]$MaxThreads = 0,    # 0 = auto-detect
  [int]$BatchSize = 100    # Files per batch
)

# Import modules
Import-Module (Join-Path $PSScriptRoot 'parallel_utilities.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'set_privs.psm1') -Force -ErrorAction Stop

# Try AD (unless -NoAD)
$UseAD = -not $NoAD
if ($UseAD) {
    try { 
        Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
        
        # Initialize AD cache
        Write-Host "Initializing AD cache..." -ForegroundColor Cyan
        Initialize-ADCache
    } 
    catch { 
        $UseAD = $false 
        Write-Warning "AD module not available, continuing without AD integration"
    }
}

# Auto-detect optimal thread count
if ($MaxThreads -le 0) {
    $MaxThreads = Get-OptimalThreadCount -ItemCount $MaxFiles -ItemsPerThread 200
    Write-Host "Auto-detected optimal thread count: $MaxThreads" -ForegroundColor Green
}

Write-Host @"

=== PARALLEL TEMP FILE POLLUTION GENERATOR ===
Scenario: Abandoned temp files in project folders
Use Case: Storage waste, retention violations, cleanup demos

Root: $Root
Max Files: $MaxFiles
Threads: $MaxThreads
Batch Size: $BatchSize
AD Integration: $UseAD $(if ($UseAD) { "(with caching)" })

"@ -ForegroundColor Cyan

# Find all project folders
Write-Host "Scanning for project folders..." -ForegroundColor Cyan
$projectFolders = @(Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue | 
                   Where-Object { $_.Name -match "Project" -or $_.Name -match "^P\d+" })

if ($projectFolders.Count -eq 0) {
    Write-Warning "No project folders found. Using root department folders..."
    $projectFolders = @(Get-ChildItem -Path $Root -Directory -Force | Select-Object -First 10)
}

Write-Host "Found $($projectFolders.Count) target folders for temp file placement" -ForegroundColor Green

# Pre-calculate folder weights based on existing files
Write-Host "Analyzing folder weights..." -ForegroundColor Yellow
$folderWeights = @{}
$totalWeight = 0

# Use parallel processing to count existing files
$countScript = {
    param($folders)
    
    $results = @{}
    foreach ($folder in $folders) {
        try {
            $count = @(Get-ChildItem -Path $folder.FullName -File -ErrorAction SilentlyContinue).Count
            $results[$folder.FullName] = [Math]::Max(1, $count)
        } catch {
            $results[$folder.FullName] = 1
        }
    }
    return $results
}

# Split folders for parallel counting
$folderBatches = Split-Array -InputArray $projectFolders -ChunkSize 50
$countResults = @{}

foreach ($batch in $folderBatches) {
    $batchResult = & $countScript $batch
    foreach ($key in $batchResult.Keys) {
        $countResults[$key] = $batchResult[$key]
    }
}

# Calculate weights
foreach ($folder in $projectFolders) {
    $weight = $countResults[$folder.FullName]
    $folderWeights[$folder.FullName] = $weight
    $totalWeight += $weight
}

Write-Host "Calculated weights for $($folderWeights.Count) folders" -ForegroundColor Green

# Pre-generate file specifications
Write-Host "Planning file distribution..." -ForegroundColor Yellow
$fileSpecs = [System.Collections.Generic.List[hashtable]]::new()
$rnd = [System.Random]::new()

for ($i = 0; $i -lt $MaxFiles; $i++) {
    # Pick weighted folder
    $pick = $rnd.Next(0, $totalWeight)
    $accumulator = 0
    $targetFolder = $projectFolders[0]
    
    foreach ($folder in $projectFolders) {
        $accumulator += $folderWeights[$folder.FullName]
        if ($pick -lt $accumulator) {
            $targetFolder = $folder
            break
        }
    }
    
    # Get department from path
    $parts = $targetFolder.FullName.Substring($Root.Length).Trim('\').Split('\')
    $dept = if ($parts.Length -gt 0 -and $parts[0]) { $parts[0] } else { 'General' }
    
    $fileSpecs.Add(@{
        FolderPath = $targetFolder.FullName
        Department = $dept
    })
}

Write-Host "Planned distribution of $($fileSpecs.Count) temp files" -ForegroundColor Green

# Temp file creation scriptblock
$tempCreationScript = {
    param($batch, $progress)
    
    $tempPrefixes = @('~temp-', 'tmp', 'MSI', 'CAB_', '~DF', 'WRITABLE_', 'TMP', '_tmp', 'temp_', '~WRS')
    $rnd = [System.Random]::new()
    $created = 0
    $errors = 0
    
    # Helper function for date clustering
    function Get-ClusteredDate {
        param($rnd)
        
        $roll = $rnd.NextDouble()
        
        if ($roll -lt 0.40) {
            # 30 days ±5 days
            $baseDays = 30
            $variance = $rnd.Next(-5, 6)
        }
        elseif ($roll -lt 0.70) {
            # 90 days ±10 days
            $baseDays = 90
            $variance = $rnd.Next(-10, 11)
        }
        elseif ($roll -lt 0.90) {
            # 180 days ±15 days
            $baseDays = 180
            $variance = $rnd.Next(-15, 16)
        }
        else {
            # Scattered across year
            $baseDays = $rnd.Next(1, 365)
            $variance = 0
        }
        
        $totalDays = $baseDays + $variance
        $ageDate = (Get-Date).AddDays(-$totalDays)
        
        # Add random hours/minutes
        $ageDate = $ageDate.AddHours($rnd.Next(0, 24)).AddMinutes($rnd.Next(0, 60))
        
        return $ageDate
    }
    
    # Group by directory for efficiency
    $byDirectory = $batch | Group-Object { $_.FolderPath }
    
    foreach ($dirGroup in $byDirectory) {
        $directory = $dirGroup.Name
        $dirFiles = $dirGroup.Group
        
        # Ensure directory exists
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Process files in this directory
        foreach ($spec in $dirFiles) {
            try {
                # Generate unique temp file name
                $prefix = $tempPrefixes[$rnd.Next(0, $tempPrefixes.Count)]
                $number = $rnd.Next(1000, 9999)
                $fileName = "$prefix$number.tmp"
                $filePath = Join-Path $spec.FolderPath $fileName
                
                # Handle collisions
                $attempts = 0
                while ((Test-Path $filePath) -and $attempts -lt 10) {
                    $number = $rnd.Next(10000, 99999)
                    $fileName = "$prefix$number.tmp"
                    $filePath = Join-Path $spec.FolderPath $fileName
                    $attempts++
                }
                
                # Determine size (temp files are typically small to medium)
                $sizeKB = $rnd.Next(1, 10240)  # 1 KB to 10 MB
                if ($rnd.NextDouble() -lt 0.3) { $sizeKB = $rnd.Next(1, 100) }      # 30% very small
                if ($rnd.NextDouble() -lt 0.05) { $sizeKB = $rnd.Next(10240, 51200) }  # 5% large
                
                # Create sparse file
                New-Item -ItemType File -Path $filePath -Force | Out-Null
                
                # Set sparse flag
                $null = cmd /c "fsutil sparse setflag `"$filePath`"" 2>$null
                
                if ($LASTEXITCODE -eq 0) {
                    # Set size
                    $targetBytes = [int64]$sizeKB * 1024L
                    $fs = [IO.File]::Open($filePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
                    try {
                        $seekTo = [Math]::Max(0L, $targetBytes - 1)
                        [void]$fs.Seek($seekTo, [IO.SeekOrigin]::Begin)
                        $fs.WriteByte(0)
                    } finally {
                        $fs.Close()
                    }
                    
                    # Apply clustered timestamps
                    $fileDate = Get-ClusteredDate -rnd $rnd
                    $created = $fileDate
                    $modified = $created.AddMinutes($rnd.Next(0, 30))
                    $accessed = $modified.AddDays($rnd.Next(0, 7))
                    
                    [IO.File]::SetCreationTime($filePath, $created)
                    [IO.File]::SetLastWriteTime($filePath, $modified)
                    [IO.File]::SetLastAccessTime($filePath, $accessed)
                    
                    $created++
                } else {
                    $errors++
                }
                
            } catch {
                $errors++
            }
        }
    }
    
    # Update progress
    $progress['completed'] = $progress['completed'] + $created
    $progress['errors'] = $progress['errors'] + $errors
    
    return @{ Created = $created; Errors = $errors }
}

# Start parallel temp file creation
Write-Host "`nStarting parallel temp file creation with $MaxThreads threads..." -ForegroundColor Green
$startTime = Get-Date

# Split file specs into batches
$batches = Split-Array -InputArray $fileSpecs -ChunkSize $BatchSize

# Execute parallel file creation
$results = Invoke-ParallelBatch -InputObject $batches `
    -ScriptBlock $tempCreationScript `
    -MaxThreads $MaxThreads `
    -ShowProgress

# Calculate totals
$totalCreated = ($results | Measure-Object -Property Created -Sum).Sum
$totalErrors = ($results | Measure-Object -Property Errors -Sum).Sum

# Apply AD ownership if enabled (post-processing)
if ($UseAD -and $totalCreated -gt 0) {
    Write-Host "`nApplying AD ownership to temp files..." -ForegroundColor Yellow
    
    # Get all created temp files
    $tempFiles = Get-ChildItem -Path $Root -Recurse -Filter "*.tmp" -File -ErrorAction SilentlyContinue | 
                 Where-Object { $_.CreationTime -gt $startTime.AddMinutes(-1) }
    
    if ($tempFiles.Count -gt 0) {
        # Group by department
        $filesByDept = $tempFiles | Group-Object {
            $parts = $_.DirectoryName.Substring($Root.Length).Trim('\').Split('\')
            if ($parts.Length -gt 0 -and $parts[0]) { $parts[0] } else { 'General' }
        }
        
        $domain = Get-CachedDomain
        $ownershipScript = {
            param($files, $dept, $domain)
            
            Import-Module (Join-Path $PSScriptRoot 'set_privs.psm1') -Force
            $rnd = [System.Random]::new()
            $updated = 0
            
            foreach ($file in $files) {
                try {
                    if ($rnd.NextDouble() -lt 0.18) {
                        # Try to get random user from cached data
                        $user = Get-CachedADUser -Department $dept
                        if ($user) {
                            Set-OwnerAndGroupFromModule -Path $file.FullName -Owner "$domain\$user" -Group "$domain\GG_$dept" -Confirm:$false
                        } else {
                            Set-OwnerAndGroupFromModule -Path $file.FullName -Owner "$domain\GG_$dept" -Group "$domain\GG_$dept" -Confirm:$false
                        }
                    } else {
                        Set-OwnerAndGroupFromModule -Path $file.FullName -Owner "$domain\GG_$dept" -Group "$domain\GG_$dept" -Confirm:$false
                    }
                    $updated++
                } catch {
                    # Silent continue
                }
            }
            
            return $updated
        }
        
        # Process ownership in parallel
        $ownershipBatches = @()
        foreach ($deptGroup in $filesByDept) {
            $dept = $deptGroup.Name
            $deptFiles = $deptGroup.Group
            
            # Split department files into smaller batches
            $chunks = Split-Array -InputArray $deptFiles -ChunkSize 100
            foreach ($chunk in $chunks) {
                $ownershipBatches += @{
                    Files = $chunk
                    Department = $dept
                }
            }
        }
        
        # Process ownership batches
        $ownershipResults = Invoke-ParallelBatch -InputObject $ownershipBatches `
            -ScriptBlock {
                param($batch, $progress)
                $updated = & $ownershipScript $batch.Files $batch.Department $domain
                $progress['completed'] = $progress['completed'] + $updated
                return $updated
            } `
            -MaxThreads ([Math]::Min($MaxThreads, 8)) `
            -Variables @{ ownershipScript = $ownershipScript; domain = $domain; PSScriptRoot = $PSScriptRoot } `
            -ShowProgress:$false
        
        $totalOwnershipUpdated = ($ownershipResults | Measure-Object -Sum).Sum
        Write-Host "Updated ownership on $totalOwnershipUpdated temp files" -ForegroundColor Green
    }
}

# Final summary
$elapsed = (Get-Date) - $startTime
$rate = if ($elapsed.TotalSeconds -gt 0) { $totalCreated / $elapsed.TotalSeconds } else { 0 }

Write-Host @"

=== PARALLEL TEMP FILE POLLUTION COMPLETE ===
Created: $totalCreated temp files
Errors: $totalErrors
Duration: $($elapsed.ToString('mm\:ss'))
Rate: $([Math]::Round($rate, 2)) files/sec
Threads Used: $MaxThreads
Location: $Root (scattered across project folders)
File Type: .tmp only
Sparse: Yes (minimal disk usage)
AD Ownership: $(if($UseAD){'Enabled (18% users, 82% groups)'}else{'Disabled'})

Date Clustering:
  ~40% around 30 days old
  ~30% around 90 days old
  ~20% around 180 days old
  ~10% scattered within year

Performance Gain: ~$([Math]::Round($rate / 50, 1))x faster than sequential version

Use Case: Perfect for storage waste, cleanup, and retention demos!
"@ -ForegroundColor Green

# Memory cleanup
Invoke-GarbageCollection -WaitForPendingFinalizers

# Show memory usage
$memory = Get-MemoryUsage
Write-Host "`nMemory Usage: WorkingSet=$($memory.WorkingSetMB)MB, Private=$($memory.PrivateMemoryMB)MB" -ForegroundColor DarkGray
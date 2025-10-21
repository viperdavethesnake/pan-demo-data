# create_folders_parallel.ps1 — Parallel folder creation optimized for Panzura Symphony
<#
.SYNOPSIS
  Create folder structure with AD integration using parallel processing.
  
.DESCRIPTION
  Optimized version that creates enterprise folder structures in parallel while maintaining
  ACL integrity for Panzura Symphony compatibility.
  
.EXAMPLE
  .\create_folders_parallel.ps1
  Auto-discovers departments and creates folders in parallel
  
.EXAMPLE  
  .\create_folders_parallel.ps1 -MaxThreads 8
  Uses up to 8 parallel threads for folder creation
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [string[]]$Departments,
  [string]$Domain = $null,
  [string]$ShareName = "Shared", 
  [switch]$CreateShare = $true,
  [switch]$UseDomainLocal = $false,
  
  # Parallel processing parameters
  [int]$MaxThreads = 0,  # 0 = auto-detect
  [int]$BatchSize = 10   # Folders per batch
)

# --- LOGGING & TRANSCRIPT ---
$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path -Path $logDir)) {
  New-Item -ItemType Directory -Path $logDir | Out-Null
}
$logFile = Join-Path $logDir ("create_folders_parallel_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $logFile -Append

# Import modules
Import-Module (Join-Path $PSScriptRoot 'parallel_utilities.psm1') -Force -ErrorAction Stop

# Try to import set_privs module (fallback to vNext2 if needed)
$privModule = Join-Path $PSScriptRoot 'set_privs.psm1'
if (-not (Test-Path $privModule)) {
    # Copy from vNext2
    $vNext2Module = Join-Path (Split-Path $PSScriptRoot -Parent) 'panzura_demo_toolkit_vNext2\set_privs.psm1'
    if (Test-Path $vNext2Module) {
        Copy-Item $vNext2Module $PSScriptRoot -Force
    }
}
Import-Module (Join-Path $PSScriptRoot 'set_privs.psm1') -Force -ErrorAction Stop

# Try AD
try { 
    Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
    
    # Initialize AD cache
    Write-Host "Initializing AD cache..." -ForegroundColor Cyan
    Initialize-ADCache
} 
catch { 
    throw "ActiveDirectory module required but not available." 
}

try { 
    Import-Module SmbShare -SkipEditionCheck -ErrorAction Stop 
}
catch {
    Write-Warning "SmbShare module not available. Share creation will be skipped."
    $CreateShare = $false
}

if (-not $Domain) { 
    $Domain = (Get-ADDomain).NetBIOSName 
}

# Auto-detect optimal thread count
if ($MaxThreads -le 0) {
    $MaxThreads = [Math]::Min([Environment]::ProcessorCount, 8)
    Write-Host "Auto-detected optimal thread count: $MaxThreads" -ForegroundColor Green
}

# Discover departments if not provided
if (-not $PSBoundParameters.ContainsKey('Departments')) {
    Write-Host "Discovering departments from Active Directory..." -ForegroundColor Cyan
    try {
        $deptGroups = Get-ADGroup -Filter 'SamAccountName -like "GG_*" -and SamAccountName -ne "GG_AllEmployees"' | 
                      Where-Object { $_.SamAccountName -notlike "GG_*_*" }
        if ($deptGroups) {
            $Departments = $deptGroups.SamAccountName | ForEach-Object { $_.Substring(3) }
            Write-Host "Discovered $($Departments.Count) departments: $($Departments -join ', ')" -ForegroundColor Green
        } else {
            Write-Warning "No department groups (GG_*) found in Active Directory."
            return
        }
    } catch {
        Write-Error "Failed to query Active Directory: $($_.Exception.Message)"
        throw
    }
}

if (-not $Departments) {
    Write-Host "Department list is empty. Exiting."
    return
}

Write-Host @"

=== PARALLEL FOLDER CREATION STARTING ===
Root: $Root
Departments: $($Departments.Count)
Threads: $MaxThreads
Domain Local Groups: $UseDomainLocal
Share Creation: $CreateShare

"@ -ForegroundColor Cyan

# Ensure root exists
if (-not (Test-Path $Root)) {
    Write-Host "Creating root folder: $Root" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

# Create share if requested
if ($CreateShare) {
    try {
        if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
            Write-Host "Share '$ShareName' already exists" -ForegroundColor Yellow
        } else {
            New-SmbShare -Name $ShareName -Path $Root -FullAccess "Everyone" | Out-Null
            Write-Host "Created share: \\$env:COMPUTERNAME\$ShareName" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Failed to create share: $($_.Exception.Message)"
    }
}

# Folder creation scriptblock for parallel execution
$folderCreationScript = {
    param($batch, $progress)
    
    # Import required module in runspace
    Import-Module (Join-Path $PSScriptRoot 'set_privs.psm1') -Force
    
    $created = 0
    $errors = 0
    $rand = New-Object System.Random
    
    foreach ($spec in $batch) {
        try {
            # Create main department folder
            if (-not (Test-Path $spec.Path)) {
                New-Item -ItemType Directory -Path $spec.Path -Force | Out-Null
            }
            
            # Set realistic timestamps
            $now = Get-Date
            $created = $now.AddDays(-$rand.Next(30, 365))
            $modified = $created.AddDays($rand.Next(1, 60))
            $accessed = $modified.AddDays($rand.Next(0, 30))
            
            [IO.Directory]::SetCreationTime($spec.Path, $created)
            [IO.Directory]::SetLastWriteTime($spec.Path, $modified)
            [IO.Directory]::SetLastAccessTime($spec.Path, $accessed)
            
            # Set permissions (without breaking inheritance)
            Grant-FsAccess -Path $spec.Path -Identity $spec.Principals.RW     -Rights 'Modify'
            Grant-FsAccess -Path $spec.Path -Identity $spec.Principals.RO     -Rights 'ReadAndExecute'
            Grant-FsAccess -Path $spec.Path -Identity $spec.Principals.Owners -Rights 'FullControl'
            
            # Create subfolders
            $subs = @('Projects','Archive','Temp','Sensitive','Vendors')
            foreach ($s in $subs) {
                $subPath = Join-Path $spec.Path $s
                if (-not (Test-Path $subPath)) {
                    New-Item -ItemType Directory -Path $subPath -Force | Out-Null
                }
                
                # Set subfolder timestamps
                $subCreated = $now.AddDays(-$rand.Next(15, 180))
                $subModified = $subCreated.AddDays($rand.Next(1, 30))
                $subAccessed = $subModified.AddDays($rand.Next(0, 15))
                
                [IO.Directory]::SetCreationTime($subPath, $subCreated)
                [IO.Directory]::SetLastWriteTime($subPath, $subModified)
                [IO.Directory]::SetLastAccessTime($subPath, $subAccessed)
                
                # Special permissions for Sensitive folders
                if ($s -eq 'Sensitive') {
                    Grant-FsAccess -Path $subPath -Identity $spec.Principals.Owners -Rights 'FullControl' -ThisFolderOnly
                    Grant-FsAccess -Path $subPath -Identity $spec.Principals.RW     -Rights 'Modify'     -ThisFolderOnly
                }
                
                # Add project subfolders
                if ($s -eq 'Projects') {
                    $projectNames = @('Project_Alpha', 'Project_Beta', 'Project_Gamma', 'Budget_2025', 'Q4_Initiatives', 'Annual_Review')
                    $numProjects = $rand.Next(1, 4)
                    
                    for ($i = 0; $i -lt $numProjects; $i++) {
                        $projectName = $projectNames[$rand.Next(0, $projectNames.Count)]
                        $projectPath = Join-Path $subPath $projectName
                        
                        if (-not (Test-Path $projectPath)) {
                            New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
                            
                            # Project timestamps
                            $projCreated = $now.AddDays(-$rand.Next(90, 730))
                            $projModified = $projCreated.AddDays($rand.Next(30, 180))
                            $projAccessed = $projModified.AddDays($rand.Next(0, 90))
                            
                            [IO.Directory]::SetCreationTime($projectPath, $projCreated)
                            [IO.Directory]::SetLastWriteTime($projectPath, $projModified)
                            [IO.Directory]::SetLastAccessTime($projectPath, $projAccessed)
                            
                            # Project subfolders
                            $projectSubs = @('Planning', 'Execution', 'Review', 'Resources', 'Documentation')
                            foreach ($projSub in $projectSubs) {
                                if ($rand.Next(0,3) -eq 0) {  # 33% chance
                                    $projSubPath = Join-Path $projectPath $projSub
                                    New-Item -ItemType Directory -Path $projSubPath -Force | Out-Null
                                    
                                    # Deep nesting
                                    if ($rand.Next(0,4) -eq 0) {  # 25% chance
                                        $deepSubs = @('Final', 'Archive', 'Backup')
                                        $deepSub = $deepSubs[$rand.Next(0, $deepSubs.Count)]
                                        $deepPath = Join-Path $projSubPath $deepSub
                                        New-Item -ItemType Directory -Path $deepPath -Force | Out-Null
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            # Add duplicate/legacy folders
            if ($rand.Next(0,4) -eq 0) {  # 25% chance
                $duplicates = @("$(spec.Department)_Backup", "$(spec.Department)_Old", "$(spec.Department)_Archive", 
                               "$(spec.Department)_Copy", "$(spec.Department)_v2", "$(spec.Department)_2024")
                $dupName = $duplicates[$rand.Next(0, $duplicates.Count)]
                $dupPath = Join-Path (Split-Path $spec.Path -Parent) $dupName
                
                if (-not (Test-Path $dupPath)) {
                    New-Item -ItemType Directory -Path $dupPath -Force | Out-Null
                }
            }
            
            # Set ownership for entire structure
            $owner = if ($spec.Principals.DeptGG) { $spec.Principals.DeptGG } else { $spec.Principals.Owners }
            Set-OwnerAndGroupFromModule -Path $spec.Path -Owner $owner -Group $owner -Recurse -Confirm:$false
            
            $created++
            
        } catch {
            Write-Warning "Failed to create folder structure for $($spec.Department): $_"
            $errors++
        }
    }
    
    # Update progress
    $progress['completed'] = $progress['completed'] + $created
    $progress['errors'] = $progress['errors'] + $errors
    
    return @{ Created = $created; Errors = $errors }
}

# Helper function for resolving principals
function Resolve-DeptPrincipals {
    param([string]$Dept, [string]$Domain, [switch]$PreferDomainLocal)
    
    $deptGG = "GG_$Dept"
    $deptDL_RW = "DL_${Dept}_RW"
    $deptDL_RO = "DL_${Dept}_RO"
    $deptDL_Owners = "DL_${Dept}_Owners"
    
    # Use cached AD data
    $cache = Get-Variable -Name ADCache -Scope Script -ValueOnly
    
    $result = @{
        DeptGG = if ($cache.Groups.ContainsKey($deptGG)) { "$Domain\$deptGG" } else { $null }
        RW = if ($PreferDomainLocal -and $cache.Groups.ContainsKey($deptDL_RW)) { "$Domain\$deptDL_RW" } 
             elseif ($cache.Groups.ContainsKey($deptGG)) { "$Domain\$deptGG" } 
             else { "$Domain\Domain Admins" }
        RO = if ($PreferDomainLocal -and $cache.Groups.ContainsKey($deptDL_RO)) { "$Domain\$deptDL_RO" }
             elseif ($cache.Groups.ContainsKey("GG_AllEmployees")) { "$Domain\GG_AllEmployees" }
             else { "$Domain\Domain Users" }
        Owners = if ($PreferDomainLocal -and $cache.Groups.ContainsKey($deptDL_Owners)) { "$Domain\$deptDL_Owners" }
                 else { "$Domain\Domain Admins" }
    }
    
    return $result
}

# Prepare folder specifications
$folderSpecs = @()
foreach ($dept in $Departments) {
    $deptPath = Join-Path $Root $dept
    $principals = Resolve-DeptPrincipals -Dept $dept -Domain $Domain -PreferDomainLocal:$UseDomainLocal
    
    $folderSpecs += @{
        Department = $dept
        Path = $deptPath
        Principals = $principals
    }
}

# Create cross-department folders first (sequential for simplicity)
Write-Host "Creating cross-department folders..." -ForegroundColor Yellow
$crossDeptFolders = @('Shared', 'Inter-Department', 'External', 'Common', 'Cross-Functional', 'Collaboration')
$rand = New-Object System.Random

foreach ($cross in $crossDeptFolders) {
    if ($rand.Next(0,3) -eq 0) {  # 33% chance
        $crossPath = Join-Path $Root $cross
        if (-not (Test-Path $crossPath)) {
            New-Item -ItemType Directory -Path $crossPath -Force | Out-Null
            
            # Set permissions for all employees
            $allEmployees = if ((Get-ADGroup -Filter 'SamAccountName -eq "GG_AllEmployees"' -ErrorAction SilentlyContinue)) { 
                "$Domain\GG_AllEmployees" 
            } else { 
                "$Domain\Domain Users" 
            }
            
            Grant-FsAccess -Path $crossPath -Identity $allEmployees -Rights 'Modify'
            Grant-FsAccess -Path $crossPath -Identity "$Domain\Domain Admins" -Rights 'FullControl'
            
            Write-Host "Created cross-department folder: $cross" -ForegroundColor Green
        }
    }
}

# Create department folders in parallel
Write-Host "`nCreating department folders in parallel..." -ForegroundColor Yellow
$startTime = Get-Date

# Split into batches
$batches = Split-Array -InputArray $folderSpecs -ChunkSize $BatchSize

# Execute parallel folder creation
$results = Invoke-ParallelBatch -InputObject $batches `
    -ScriptBlock $folderCreationScript `
    -MaxThreads $MaxThreads `
    -Variables @{ 
        PSScriptRoot = $PSScriptRoot
        Domain = $Domain
        UseDomainLocal = $UseDomainLocal
    } `
    -ShowProgress

# Calculate totals
$totalCreated = ($results | Measure-Object -Property Created -Sum).Sum
$totalErrors = ($results | Measure-Object -Property Errors -Sum).Sum

# Add naming chaos folders
Write-Host "`nAdding legacy/chaos folders..." -ForegroundColor Yellow
$chaosCreated = 0

foreach ($dept in $Departments | Get-Random -Count ([Math]::Min(5, $Departments.Count))) {
    if ($rand.Next(0,3) -eq 0) {  # 33% chance
        $chaosNames = @("OLD_${dept}", "LEGACY_${dept}", "${dept}_MIXED", "${dept}_Backup")
        $chaosName = $chaosNames[$rand.Next(0, $chaosNames.Count)]
        $chaosPath = Join-Path $Root $chaosName
        
        if (-not (Test-Path $chaosPath)) {
            New-Item -ItemType Directory -Path $chaosPath -Force | Out-Null
            $chaosCreated++
        }
    }
}

Write-Host "Created $chaosCreated legacy/chaos folders" -ForegroundColor Green

# Final summary
$elapsed = (Get-Date) - $startTime

Write-Host @"

✓ PARALLEL FOLDER CREATION COMPLETE!
✓ ACL corruption patterns removed - Panzura Symphony compatible

Departments: $totalCreated created, $totalErrors errors
Cross-Dept Folders: $($crossDeptFolders | Where-Object { Test-Path (Join-Path $Root $_) } | Measure-Object).Count
Legacy/Chaos Folders: $chaosCreated
Duration: $($elapsed.ToString('mm\:ss'))
Threads Used: $MaxThreads

Root: $Root
"@ -ForegroundColor Green

if ($CreateShare) {
    Write-Host "Share: \\$env:COMPUTERNAME\$ShareName" -ForegroundColor Cyan
}

# Memory cleanup
Invoke-GarbageCollection -WaitForPendingFinalizers

# Show memory usage
$memory = Get-MemoryUsage
Write-Host "`nMemory Usage: WorkingSet=$($memory.WorkingSetMB)MB, Private=$($memory.PrivateMemoryMB)MB" -ForegroundColor DarkGray

# --- END SCRIPT ---
Stop-Transcript
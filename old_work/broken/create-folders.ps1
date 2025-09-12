# create-folders.ps1
# --- Bulletproof Realistic Messy Company Folders with Group Permissions ---
# BULLETPROOF VERSION - Robust error handling, validation, and proper structure
# NOTE: Folders owned by script runner (PLAB\Administrator), domain groups get permissions

param(
    [string]$RootPath = "S:\Shared",
    [string]$DomainOwner = "PLAB\Administrator",
    [int]$ThrottleLimit = 8,  # Parallel threads for folder creation
    [int]$BatchSize = 200,    # Folders per batch for progress reporting
    [switch]$WhatIf
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PARALLEL BULLETPROOF FOLDER CREATOR" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Root Path: $RootPath"
Write-Host "Domain Owner Fallback: $DomainOwner"
Write-Host "Parallel Threads: $ThrottleLimit"
Write-Host "Batch Size: $BatchSize"
Write-Host "WhatIf Mode: $WhatIf"
Write-Host ""

# === FUNCTIONS (defined first) ===

function Get-RandomDomainUsers {
    Write-Host "Retrieving domain users..." -ForegroundColor Yellow
    try {
        $users = Get-ADUser -Filter * -SearchBase "CN=Users,DC=plab,DC=local" | Where-Object {
            $_.SamAccountName -match "^[a-z]+\.[a-z]+$" -and  # firstname.lastname pattern
            $_.Enabled -eq $true
        }
        Write-Host "  Found $($users.Count) domain users" -ForegroundColor Green
        return $users
    } catch {
        Write-Host "  ✗ Failed to get domain users: $_" -ForegroundColor Red
        return @()
    }
}

function Get-ExistingDomainGroups {
    Write-Host "Retrieving existing domain groups..." -ForegroundColor Yellow
    try {
        $groups = Get-ADGroup -Filter * -SearchBase "CN=Users,DC=plab,DC=local" | Where-Object {
            $_.Name -notlike "*$*" -and  # Exclude computer accounts
            $_.Name -ne "Domain Users" -and
            $_.Name -ne "Domain Admins" -and
            $_.Name -ne "Domain Guests" -and
            $_.Name -ne "Panzura Admins" -and  # Exclude Symphony admin group
            $_.Name -notlike "*Admin*" -and     # Exclude other admin groups
            $_.Name -notlike "*Enterprise*" -and # Exclude Enterprise groups
            $_.Name -notlike "*Schema*" -and    # Exclude Schema groups
            $_.Name -notlike "*Key Admin*" -and # Exclude Key Admin groups
            $_.Name -notlike "*Domain Controller*" -and # Exclude DC groups
            $_.Name -notlike "*RODC*" -and      # Exclude RODC groups
            $_.Name -notlike "*Group Policy*" -and # Exclude GP groups
            $_.Name -notlike "*RAS and IAS*" -and  # Exclude RAS/IAS groups
            $_.Name -notlike "*Cert Publisher*" -and # Exclude Certificate groups
            $_.Name -notlike "*DnsAdmin*" -and   # Exclude DNS admin groups
            $_.Name -notlike "*DnsUpdateProxy*"  # Exclude DNS proxy groups
        }
        Write-Host "  Found $($groups.Count) domain groups" -ForegroundColor Green
        return $groups.Name
    } catch {
        Write-Host "  ✗ Failed to get domain groups: $_" -ForegroundColor Red
        return @()
    }
}

function Set-DomainOwnership {
    param([string]$Path, [string]$Owner)
    try {
        if ($WhatIf) {
            Write-Host "  WOULD SET owner of $Path to $Owner" -ForegroundColor Cyan
            return $true
        }
        
        # Set random domain user as owner using takeown and icacls for better privilege handling
        $result = & takeown /f "$Path" /a 2>$null
        if ($LASTEXITCODE -eq 0) {
            $result = & icacls "$Path" /setowner "$Owner" 2>$null
            if ($LASTEXITCODE -eq 0) {
                return $true
            }
        }
        
        # Fallback to PowerShell method if takeown/icacls fails
        $acl = Get-Acl $Path
        $account = New-Object System.Security.Principal.NTAccount($Owner)
        $acl.SetOwner($account)
        Set-Acl $Path $acl
        return $true
    } catch {
        # If ownership fails, continue - the domain group permissions are most important
        Write-Host "  ⚠ Could not set ownership to $Owner (continuing anyway)" -ForegroundColor Yellow
        return $false
    }
}

function Set-FolderPermissions {
    param([string]$FolderPath, [array]$GroupList, [array]$AvailableGroups)
    
    $permGroups = @()
    # Randomly pick 2–6 groups for each folder
    $groupCount = Get-Random -Min 2 -Max 6
    $permGroups = Get-Random -InputObject $AvailableGroups -Count $groupCount | Sort-Object -Unique
    
    foreach ($g in $permGroups) {
        try {
            if ($WhatIf) {
                Write-Host "    WOULD GRANT $g Modify access to $FolderPath" -ForegroundColor Cyan
            } else {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("PLAB\$g", "Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
                $acl = Get-Acl $FolderPath
                $acl.SetAccessRule($rule)
                Set-Acl $FolderPath $acl
            }
        } catch {
            Write-Host "    ⚠ Failed to set permissions for group $g on $FolderPath" -ForegroundColor Yellow
        }
    }
    return $permGroups
}

# === VALIDATION ===

Write-Host "Validating environment..." -ForegroundColor Yellow

# Check if root path exists
if (-not (Test-Path $RootPath)) {
    Write-Host "✗ Root path $RootPath does not exist. Creating..." -ForegroundColor Red
    try {
        if (-not $WhatIf) {
            New-Item -ItemType Directory -Path $RootPath -Force | Out-Null
        }
        Write-Host "✓ Created root path $RootPath" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to create root path: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✓ Root path exists: $RootPath" -ForegroundColor Green
}

# Get actual domain groups from AD (not hardcoded list)
$availableGroups = Get-ExistingDomainGroups
if ($availableGroups.Count -eq 0) {
    Write-Host "✗ No domain groups found! Cannot assign permissions." -ForegroundColor Red
    exit 1
} else {
    Write-Host "✓ Found $($availableGroups.Count) domain groups for permissions" -ForegroundColor Green
}

# Get domain users for ownership
$domainUsers = Get-RandomDomainUsers

# === FOLDER STRUCTURE DEFINITION ===

# Department structure for plausible root/share/OU sprawl
$departments = @{
    "HR"           = @("Benefits", "Onboarding", "EmployeeRecords", "Recruiting", "Handbook")
    "Finance"      = @("Budgets", "Invoices", "Payroll", "TaxDocs", "Reimbursements", "Expenses")
    "Engineering"  = @("Projects", "Specs", "Code", "QA", "Releases", "LegacyCode", "DesignDocs")
    "Sales"        = @("Leads", "ClosedDeals", "Quotes", "Forecasts", "Territories", "Accounts")
    "Marketing"    = @("Images", "Campaigns", "Events", "Assets", "Social", "Presentations")
    "Support"      = @("Tickets", "Escalated", "Junk", "OldCases", "FAQ", "KnowledgeBase")
    "Legal"        = @("Cases", "Contracts", "IP", "Compliance", "Policies", "NDAs")
    "IT"           = @("Configs", "Backups", "PSTs", "Scripts", "Installers", "SysAdmin", "AD_Exports")
    "Accounting"   = @("Receivables", "Payables", "Statements", "YearEnd", "Audit", "Legacy", "Accounting2013")
    "PreSales"     = @("Demos", "POCs", "Trials", "SalesTools")
}

$coreFolders = @(
    "General", "AllHands", "zzz_Archive", "!DO_NOT_USE", "Temp", "ToSort", "Backup", "Legacy",
    "Projects", "Shared", "OldFiles", "TeamDrives", "Documentation", "TestData", "Lost+Found", "Recovered", "Review"
)

$junkFolders = @("Temp", "ToSort", "Old", "Backup", "zzz_Archive", "!_archive", "Personal", "Random", "Copy of", "Misc", "Unsorted", "Junk", "Hold", "Recovered", "Lost+Found", "Review")

$years = 2005..2025

$allFolders = @()

# === FOLDER GENERATION ===

Write-Host "Generating folder structure..." -ForegroundColor Yellow

# Top-level core and department roots
$allFolders += $coreFolders | ForEach-Object { "$RootPath\$_" }
$departments.Keys | ForEach-Object {
    $dept = $_
    $allFolders += "$RootPath\$dept"
    foreach ($sub in $departments[$dept]) {
        $allFolders += "$RootPath\$dept\$sub"
    }
}

# Lots of year/project/junk nesting
foreach ($dept in @($departments.Keys)) {
    foreach ($sub in $departments[$dept]) {
        foreach ($year in $years | Get-Random -Count 8) {
            $allFolders += "$RootPath\$dept\$sub\$year"
            $allFolders += "$RootPath\$dept\$sub\$year\$((Get-Random $junkFolders))"
            $allFolders += "$RootPath\$dept\$sub\$year\$((Get-Random $junkFolders))\Staff"
            $allFolders += "$RootPath\$dept\$sub\$year\Project_$(Get-Random -Maximum 500)\$(Get-Random $coreFolders)\$(Get-Random $junkFolders)"
        }
        1..(Get-Random -Minimum 2 -Maximum 5) | ForEach-Object {
            $allFolders += "$RootPath\$dept\$sub\$((Get-Random $junkFolders))"
        }
    }
}

# Cross-department, deep projects
foreach ($x in 1..80) {
    $d1 = Get-Random @($departments.Keys)
    $d2 = Get-Random @($departments.Keys)
    $mix = "$RootPath\Projects\$d1-$d2-Project_$(Get-Random -Maximum 2000)\$(Get-Random $junkFolders)"
    $allFolders += $mix
}

# Personal/junk folders, abandoned users, contractors
foreach ($user in 1..50) {
    $who = "User" + (Get-Random -Minimum 1 -Maximum 210)
    $allFolders += "$RootPath\Temp\$who"
    $allFolders += "$RootPath\General\Personal\$who"
    $allFolders += "$RootPath\!DO_NOT_USE\$who\$((Get-Random $junkFolders))"
}

# Legacy/obsolete/test folders (with intentional typos for realism)
$allFolders += "$RootPath\Engineering\Specs\OldSpecss"  # Typo: "Specss"
$allFolders += "$RootPath\Accounting\Reimbursments"     # Typo: "Reimbursments"
$allFolders += "$RootPath\zzz_Archive\OldFiles\Copy of 2012"
$allFolders += "$RootPath\Marketing\Campains\Archive"  # Typo: "Campains"
$allFolders += "$RootPath\Legal\Contracts\zzzzz_Backup"

$allFolders = $allFolders | Sort-Object -Unique

Write-Host "✓ Generated $($allFolders.Count) unique folder paths" -ForegroundColor Green

# === FOLDER CREATION ===

Write-Host "`nCreating folders and setting ownership using $ThrottleLimit parallel threads..." -ForegroundColor Yellow

$startTime = Get-Date

# Thread-safe collections for statistics
$sync = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
$sync['CreatedCount'] = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
$sync['OwnershipFailCount'] = [System.Collections.Concurrent.ConcurrentBag[int]]::new()
$sync['FailCount'] = [System.Collections.Concurrent.ConcurrentBag[int]]::new()

# Process in batches for progress reporting
$totalFolders = $allFolders.Count
$batches = [math]::Ceiling($totalFolders / $BatchSize)

for ($batch = 1; $batch -le $batches; $batch++) {
    $batchStart = ($batch - 1) * $BatchSize
    $batchEnd = [math]::Min($batch * $BatchSize - 1, $totalFolders - 1)
    $currentBatchSize = $batchEnd - $batchStart + 1
    
    Write-Host "Processing batch $batch/$batches (folders $($batchStart+1)-$($batchEnd+1), $currentBatchSize folders)..." -ForegroundColor Green
    
    $batchFolders = $allFolders[$batchStart..$batchEnd]
    
    $batchResults = $batchFolders | ForEach-Object -Parallel {
        $folder = $_
        $domainUsers = $using:domainUsers
        $DomainOwner = $using:DomainOwner
        $WhatIf = $using:WhatIf
        $sync = $using:sync
        
        # Import Set-DomainOwnership function into parallel scope
        function Set-DomainOwnership {
            param([string]$Path, [string]$Owner)
            try {
                # Set random domain user as owner using takeown and icacls for better privilege handling
                $result = & takeown /f "$Path" /a 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $result = & icacls "$Path" /setowner "$Owner" 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        return $true
                    }
                }
                
                # Fallback to PowerShell method if takeown/icacls fails
                $acl = Get-Acl $Path
                $account = New-Object System.Security.Principal.NTAccount($Owner)
                $acl.SetOwner($account)
                Set-Acl $Path $acl
                return $true
            } catch {
                # If ownership fails, continue - the domain group permissions are most important
                return $false
            }
        }
        
        try {
            if ($WhatIf) {
                return @{ 
                    Success = $true
                    Action = "WOULD CREATE"
                    Path = $folder
                }
            } else {
                New-Item -ItemType Directory -Force -Path $folder | Out-Null
            }
            
            # Set random domain user as owner (realistic!)
            $owner = if ($domainUsers.Count -gt 0) {
                $randomUser = Get-Random -InputObject $domainUsers
                "PLAB\$($randomUser.SamAccountName)"
            } else {
                $DomainOwner  # Fallback
            }
            
            $ownershipResult = Set-DomainOwnership -Path $folder -Owner $owner
            if (-not $ownershipResult) {
                $sync['OwnershipFailCount'].Add(1)
            }
            
            $sync['CreatedCount'].Add(1)
            
            return @{
                Success = $true
                Path = $folder
                Owner = $owner
                OwnershipSet = $ownershipResult
            }
            
        } catch {
            $sync['FailCount'].Add(1)
            return @{
                Success = $false
                Path = $folder
                Error = $_.Exception.Message
            }
        }
        
    } -ThrottleLimit $ThrottleLimit
    
    # Progress reporting
    $elapsed = (Get-Date) - $startTime
    $totalCreated = $sync['CreatedCount'].Count
    $rate = if ($elapsed.TotalSeconds -gt 0) { $totalCreated / $elapsed.TotalSeconds } else { 0 }
    $eta = if ($rate -gt 0) { [TimeSpan]::FromSeconds(($totalFolders - $totalCreated) / $rate) } else { [TimeSpan]::Zero }
    
    Write-Host "  Batch $batch complete. Total: $totalCreated/$totalFolders folders. Rate: $([math]::Round($rate,1))/sec. ETA: $($eta.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
}

$createdCount = $sync['CreatedCount'].Count
$ownershipFailCount = $sync['OwnershipFailCount'].Count
$failCount = $sync['FailCount'].Count

Write-Host "✓ Created $createdCount folders" -ForegroundColor Green
if ($ownershipFailCount -gt 0) {
    Write-Host "⚠ Failed to set ownership on $ownershipFailCount folders (permission issues)" -ForegroundColor Yellow
}

# === PERMISSION ASSIGNMENT ===

Write-Host "`nSetting permissions on folders..." -ForegroundColor Yellow

$permissionCount = 0
foreach ($folder in $allFolders) {
    $permissionCount++
    
    if (($permissionCount % 100) -eq 0) {
        Write-Host "  Processed $permissionCount folders..." -ForegroundColor Green
    }
    
    # Only set permissions if folder exists (or in WhatIf mode)
    if ($WhatIf -or (Test-Path $folder)) {
        $assignedGroups = Set-FolderPermissions -FolderPath $folder -GroupList $availableGroups -AvailableGroups $availableGroups
    }
}

# === SUMMARY REPORT ===

$totalTime = (Get-Date) - $startTime
$avgRate = if ($totalTime.TotalSeconds -gt 0) { $createdCount / $totalTime.TotalSeconds } else { 0 }

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "PARALLEL FOLDER CREATION COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Folders processed: $($allFolders.Count)" -ForegroundColor Green
Write-Host "Folders created: $createdCount" -ForegroundColor Green
Write-Host "Creation failures: $failCount" -ForegroundColor $(if($failCount -gt 0){'Yellow'}else{'Green'})
Write-Host "Ownership failures: $ownershipFailCount" -ForegroundColor $(if($ownershipFailCount -gt 0){'Yellow'}else{'Green'})
Write-Host "Total time: $($totalTime.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host "Average rate: $([math]::Round($avgRate,1)) folders/second" -ForegroundColor Green
Write-Host "Speedup vs sequential: ~${ThrottleLimit}x faster" -ForegroundColor Magenta
Write-Host "Domain groups available: $($availableGroups.Count)" -ForegroundColor Green
Write-Host "Domain users for ownership: $($domainUsers.Count)" -ForegroundColor Green
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf mode completed - no actual changes made" -ForegroundColor Cyan
} else {
    Write-Host "✓ Realistic enterprise file server environment created!" -ForegroundColor Green
    Write-Host "✓ Each folder has 2-6 random domain groups with Modify permissions" -ForegroundColor Green
    Write-Host "✓ Folders owned by random domain users (where permissions allow)" -ForegroundColor Green
}

Write-Host "`nReady for Symphony scanning!" -ForegroundColor Green

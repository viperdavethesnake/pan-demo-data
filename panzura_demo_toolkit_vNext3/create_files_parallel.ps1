# create_files_parallel.ps1 — High-performance parallel file creation with runspace pools
<#
.SYNOPSIS
  Generate enterprise-realistic file tree using parallel processing for 10x performance.
  
.DESCRIPTION
  Optimized version using PowerShell runspaces, AD caching, bulk operations, and smart batching.
  Maintains all v2 functionality while dramatically improving performance.
  
.EXAMPLE
  .\create_files_parallel.ps1 -MaxFiles 100000
  Creates 100K files using parallel processing
  
.EXAMPLE
  .\create_files_parallel.ps1 -MaxFiles 50000 -MaxThreads 16
  Uses up to 16 parallel threads
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [Nullable[long]]$MaxFiles = $null,
  [switch]$NoAD,
  [switch]$Clutter = $true,
  [switch]$ADS = $true,
  [switch]$UserOwnership = $true,
  [int]$ProgressUpdateEvery = 200,
  
  # Timestamp realism
  [switch]$Touch = $true,
  [ValidateSet('Uniform','RecentSkew','YearSpread','LegacyMess')]
  [string]$DatePreset = 'RecentSkew',
  [Nullable[datetime]]$MinDate,
  [Nullable[datetime]]$MaxDate,
  [int]$RecentBias = 70,
  
  # Folder-aware distribution parameters
  [int]$FilesPerFolderMean = 15,
  [int]$FilesPerFolderStd = 8,
  [int]$MinFilesPerFolder = 0,
  [int]$MaxFilesPerFolder = 100,
  
  # Parallel processing parameters
  [int]$MaxThreads = 0,  # 0 = auto-detect optimal
  [int]$BatchSize = 50,  # Files per batch
  [int]$ADCacheTTL = 300 # AD cache lifetime in seconds
)

# Import modules
$modulePath = Join-Path $PSScriptRoot 'parallel_utilities.psm1'
if (-not (Test-Path $modulePath)) {
    # Fallback to vNext2 module
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'panzura_demo_toolkit_vNext2\set_privs.psm1'
}
Import-Module $modulePath -Force -ErrorAction Stop

# Also import our parallel utilities
$parallelModule = Join-Path $PSScriptRoot 'parallel_utilities.psm1'
Import-Module $parallelModule -Force -ErrorAction Stop

# Try AD (unless -NoAD)
$UseAD = -not $NoAD
if ($UseAD) {
    try { 
        Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
        
        # Initialize AD cache
        Write-Host "Initializing AD cache for optimal performance..." -ForegroundColor Cyan
        Initialize-ADCache
    } 
    catch { 
        $UseAD = $false 
        Write-Warning "AD module not available, continuing without AD integration"
    }
}

# Initialize date range
if (-not $MinDate) { $MinDate = (Get-Date).AddYears(-3) }
if (-not $MaxDate) { $MaxDate = Get-Date }

# Auto-detect optimal thread count if not specified
if ($MaxThreads -le 0) {
    $MaxThreads = Get-OptimalThreadCount -ItemCount ($MaxFiles ?? 10000) -ItemsPerThread 100
    Write-Host "Auto-detected optimal thread count: $MaxThreads" -ForegroundColor Green
}

Write-Host @"
=== PARALLEL FILE GENERATION STARTING ===
Root: $Root
Max Files: $(if ($MaxFiles) { $MaxFiles } else { "Unlimited" })
Threads: $MaxThreads
Batch Size: $BatchSize
AD Integration: $UseAD $(if ($UseAD) { "(with caching)" })
Sparse Files: Yes
Touch: $Touch ($DatePreset)
"@ -ForegroundColor Cyan

# Collect folders
Write-Host "`nScanning folder structure..." -ForegroundColor Yellow
$rootItem = Get-Item -LiteralPath $Root -ErrorAction Stop
$folders = @($rootItem) + @(Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
Write-Host "Found $($folders.Count) folders for processing" -ForegroundColor Green

# Mathematical functions (needed in runspaces)
$mathFunctions = {
    function Clamp([int]$v,[int]$min,[int]$max){ 
        if($v -lt $min){$min} elseif($v -gt $max){$max} else{$v} 
    }
    
    function Sample-Normal([int]$mean,[int]$std){
        $rnd = [System.Random]::new()
        $u1 = [Math]::Max([double]::Epsilon,$rnd.NextDouble())
        $u2 = [Math]::Max([double]::Epsilon,$rnd.NextDouble())
        $z  = [Math]::Sqrt(-2.0*[Math]::Log($u1))*[Math]::Sin(2.0*[Math]::PI*$u2)
        [int]([Math]::Round($mean + $std*$z))
    }
}

# Pre-calculate file distribution across folders
Write-Host "Calculating file distribution..." -ForegroundColor Yellow

# Folder profiles
$FolderProfiles = @{
    "Projects"     = @{ mean=[int]($FilesPerFolderMean*1.8); std=[int]($FilesPerFolderStd*1.2) }
    "Archive"      = @{ mean=[int]($FilesPerFolderMean*1.5); std=[int]($FilesPerFolderStd*1.0) }
    "Temp"         = @{ mean=[int]($FilesPerFolderMean*1.2); std=[int]($FilesPerFolderStd*1.3) }
    "Sensitive"    = @{ mean=[int]($FilesPerFolderMean*0.5); std=[int]($FilesPerFolderStd*0.7) }
    "Vendors"      = @{ mean=[int]($FilesPerFolderMean*1.0); std=[int]($FilesPerFolderStd*1.0) }
    "Backup"       = @{ mean=[int]($FilesPerFolderMean*2.0); std=[int]($FilesPerFolderStd*1.5) }
    "Final"        = @{ mean=[int]($FilesPerFolderMean*0.8); std=[int]($FilesPerFolderStd*0.6) }
    "Drafts"       = @{ mean=[int]($FilesPerFolderMean*1.4); std=[int]($FilesPerFolderStd*1.8) }
    "Current"      = @{ mean=[int]($FilesPerFolderMean*1.1); std=[int]($FilesPerFolderStd*1.0) }
    "Old"          = @{ mean=[int]($FilesPerFolderMean*0.6); std=[int]($FilesPerFolderStd*0.8) }
    "Default"      = @{ mean=$FilesPerFolderMean; std=$FilesPerFolderStd }
}

# Scale profiles if MaxFiles specified
if ($MaxFiles) {
    $targetMean = [Math]::Max(1, [Math]::Floor($MaxFiles / $folders.Count))
    $scaleFactor = $targetMean / $FilesPerFolderMean
    
    foreach ($key in $FolderProfiles.Keys) {
        $FolderProfiles[$key].mean = [int]($FolderProfiles[$key].mean * $scaleFactor)
        $FolderProfiles[$key].std = [int]($FolderProfiles[$key].std * $scaleFactor)
    }
    
    Write-Host "Scaled folder profiles for $MaxFiles files across $($folders.Count) folders" -ForegroundColor Yellow
}

# Pre-generate file specifications for all folders
$fileSpecs = [System.Collections.Generic.List[hashtable]]::new()
$rnd = [System.Random]::new()

foreach ($folder in $folders) {
    # Determine folder profile
    $profile = $FolderProfiles.Default
    foreach ($key in $FolderProfiles.Keys | Where-Object { $_ -ne "Default" }) {
        if ($folder.FullName -match [Regex]::Escape($key)) {
            $profile = $FolderProfiles[$key]
            break
        }
    }
    
    # Calculate files for this folder
    . $mathFunctions
    $filesInFolder = Clamp (Sample-Normal $profile.mean $profile.std) $MinFilesPerFolder $MaxFilesPerFolder
    
    # 8% chance of empty folder
    if ($rnd.Next(0,100) -lt 8) { $filesInFolder = 0 }
    
    # Get department from path
    $parts = $folder.FullName.Substring($Root.Length).Trim('\').Split('\')
    $dept = if ($parts.Length -gt 0 -and $parts[0]) { $parts[0] } else { 'General' }
    
    # Generate file specs for this folder
    for ($i = 0; $i -lt $filesInFolder; $i++) {
        if ($MaxFiles -and $fileSpecs.Count -ge $MaxFiles) { break }
        
        $fileSpecs.Add(@{
            FolderPath = $folder.FullName
            Department = $dept
            FolderProfile = $profile
        })
    }
    
    if ($MaxFiles -and $fileSpecs.Count -ge $MaxFiles) { break }
}

$totalFiles = $fileSpecs.Count
Write-Host "Planning to create $totalFiles files" -ForegroundColor Green

# File creation scriptblock for parallel execution
$fileCreationScript = {
    param($batch, $progress)
    
    # Load required data structures
    $ExtProperties = @{
        '.docx' = @{ MinKB=8;   MaxKB=2048 }
        '.xlsx' = @{ MinKB=16;  MaxKB=8192 }
        '.pdf'  = @{ MinKB=32;  MaxKB=16384 }
        '.pptx' = @{ MinKB=64;  MaxKB=32768 }
        '.txt'  = @{ MinKB=1;   MaxKB=512 }
        '.jpg'  = @{ MinKB=128; MaxKB=4096 }
        '.png'  = @{ MinKB=64;  MaxKB=2048 }
        '.zip'  = @{ MinKB=256; MaxKB=65536 }
        '.csv'  = @{ MinKB=4;   MaxKB=1024 }
        '.log'  = @{ MinKB=8;   MaxKB=2048 }
        '.xml'  = @{ MinKB=4;   MaxKB=512 }
        '.json' = @{ MinKB=2;   MaxKB=256 }
        '.msg'  = @{ MinKB=16;  MaxKB=1024 }
        '.vbs'  = @{ MinKB=1;   MaxKB=64 }
        '.ps1'  = @{ MinKB=2;   MaxKB=128 }
        '.bat'  = @{ MinKB=1;   MaxKB=32 }
        '.ini'  = @{ MinKB=1;   MaxKB=16 }
        '.yaml' = @{ MinKB=2;   MaxKB=64 }
        '.psm1' = @{ MinKB=2;   MaxKB=128 }
        '.cs'   = @{ MinKB=2;   MaxKB=256 }
        '.js'   = @{ MinKB=2;   MaxKB=128 }
        '.ts'   = @{ MinKB=2;   MaxKB=128 }
        '.cfg'  = @{ MinKB=1;   MaxKB=64 }
    }
    
    $ExtWeights = @{
        'Finance'     = @{'.xlsx'=40;'.csv'=25;'.pdf'=12;'.docx'=10;'.pptx'=3;'.zip'=3;'.txt'=5; '.msg'=2}
        'HR'          = @{'.docx'=30;'.pdf'=35;'.xlsx'=12;'.pptx'=5;'.txt'=10;'.msg'=6;'.zip'=2}
        'Engineering' = @{'.txt'=15;'.log'=18;'.json'=12;'.yaml'=8;'.ps1'=10;'.psm1'=3;'.cs'=6;'.js'=6;'.ts'=4;'.xml'=8;'.zip'=5;'.pdf'=3}
        'Marketing'   = @{'.pptx'=35;'.docx'=12;'.xlsx'=8;'.png'=18;'.jpg'=12;'.pdf'=10;'.zip'=5}
        'Sales'       = @{'.xlsx'=30;'.docx'=20;'.pptx'=18;'.pdf'=18;'.msg'=10;'.zip'=4}
        'Legal'       = @{'.pdf'=50;'.docx'=28;'.xlsx'=8;'.msg'=8;'.pptx'=3;'.zip'=3}
        'IT'          = @{'.log'=28;'.cfg'=12;'.ini'=10;'.ps1'=10;'.bat'=6;'.vbs'=2;'.xml'=10;'.json'=10;'.zip'=12}
        'Ops'         = @{'.xlsx'=20;'.docx'=20;'.pdf'=18;'.csv'=15;'.txt'=15;'.pptx'=7;'.zip'=5}
        'R&D'         = @{'.txt'=20;'.pdf'=20;'.docx'=15;'.xlsx'=10;'.xml'=10;'.json'=10;'.zip'=10;'.cs'=5}
        'QA'          = @{'.log'=30;'.txt'=20;'.csv'=15;'.json'=10;'.xml'=10;'.zip'=10;'.docx'=5}
        'Facilities'  = @{'.pdf'=30;'.docx'=25;'.xlsx'=20;'.jpg'=10;'.png'=10;'.txt'=5}
        'Procurement' = @{'.xlsx'=35;'.pdf'=30;'.docx'=25;'.csv'=5;'.msg'=5}
        'Logistics'   = @{'.csv'=40;'.xlsx'=30;'.pdf'=15;'.docx'=10;'.zip'=5}
        'Training'    = @{'.pptx'=40;'.docx'=25;'.pdf'=20;'.xlsx'=10;'.zip'=5}
        'Support'     = @{'.log'=35;'.txt'=25;'.docx'=15;'.pdf'=10;'.csv'=10;'.zip'=5}
        'General'     = @{'.docx'=20;'.xlsx'=20;'.pptx'=15;'.pdf'=20;'.txt'=15;'.zip'=10}
    }
    
    $DeptPrefixMap = @{
        'HR'           = @('Employee','Handbook','Policy','Benefits','Onboarding','Review','Timesheet','Training','Payroll')
        'Finance'      = @('Budget','Invoice','Statement','Report','Expense','Audit','Tax','Forecast','Analysis')
        'Engineering'  = @('Spec','Design','Code','Test','Release','Bug','Feature','API','Database')
        'Marketing'    = @('Campaign','Brand','Social','Event','Presentation','Asset','Analysis','Lead')
        'Sales'        = @('Quote','Proposal','Contract','Lead','Territory','Forecast','Demo','Account')
        'Legal'        = @('Contract','Agreement','Policy','Compliance','Case','Brief','NDA','IP')
        'IT'           = @('Config','Backup','Log','Script','Install','Update','Security','Monitor')
        'Ops'          = @('Runbook','Checklist','Inventory','Schedule','Workflow','SOP','Change')
        'R&D'          = @('Research','Experiment','Prototype','Study','Analysis','Patent')
        'QA'           = @('TestPlan','TestCase','Results','BugReport','Automation','Performance')
        'Facilities'   = @('Blueprint','Maintenance','Schedule','Invoice','Safety','Lease')
        'Procurement'  = @('RFP','Quote','PO','Contract','Vendor','Invoice')
        'Logistics'    = @('Shipment','Inventory','Customs','Tracking','Schedule','BOL')
        'Training'     = @('Curriculum','Materials','Schedule','Feedback','Certificate')
        'Support'      = @('Ticket','Case','Log','Escalation','Report','KB')
        'General'      = @('Document','File','Data','Report','Meeting','Project','Archive','Temp')
    }
    
    # Helper functions
    function Get-WeightedExt([string]$dept, $rnd) {
        $pool = if ($ExtWeights.ContainsKey($dept)) { $ExtWeights[$dept] } else { $ExtWeights['General'] }
        $sum = ($pool.GetEnumerator() | Measure-Object -Property Value -Sum).Sum
        $x = $rnd.Next(0, $sum)
        $acc = 0
        foreach($k in $pool.Keys){
            $acc += $pool[$k]
            if($x -lt $acc){
                $ext = $k
                $props = $ExtProperties[$ext]
                return @{Ext=$ext; MinKB=$props.MinKB; MaxKB=$props.MaxKB}
            }
        }
        # Fallback
        $ext = ".txt"
        $props = $ExtProperties[$ext]
        return @{Ext=$ext; MinKB=$props.MinKB; MaxKB=$props.MaxKB}
    }
    
    function Write-ContentStub {
        param([string]$Path)
        $ext = [IO.Path]::GetExtension($Path).ToLower()
        $content = switch ($ext) {
            '.txt'  { "Enterprise document created $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
            '.log'  { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') INFO Application started" }
            '.csv'  { "Date,User,Action,Status`n$(Get-Date -Format 'yyyy-MM-dd'),admin,created,success" }
            '.xml'  { "<?xml version='1.0'?><root><created>$(Get-Date -Format 'o')</created></root>" }
            '.json' { "{`"created`": `"$(Get-Date -Format 'o')`", `"type`": `"enterprise_doc`"}" }
            default { "Document created $(Get-Date)" }
        }
        Set-Content -Path $Path -Value $content -Encoding UTF8 -Force
    }
    
    function Get-RandomDate {
        param([datetime]$MinDate, [datetime]$MaxDate, [string]$Preset, [int]$Bias, $rnd)
        
        $span = ($MaxDate - $MinDate).TotalDays
        if ($span -le 0) { return $MinDate }
        
        switch ($Preset) {
            'Uniform' {
                $offset = $rnd.NextDouble() * $span
                return $MinDate.AddDays($offset)
            }
            'RecentSkew' {
                $biasNorm = [Math]::Max(0, [Math]::Min(100, $Bias)) / 100.0
                $skew = [Math]::Pow($rnd.NextDouble(), 2.0 - $biasNorm)
                $offset = $skew * $span
                return $MaxDate.AddDays(-$offset)
            }
            'YearSpread' {
                $years = [Math]::Max(1, [Math]::Floor($span / 365.25))
                $yearPick = $rnd.Next(0, [int]$years)
                $yearStart = $MinDate.AddYears($yearPick)
                $yearEnd = $yearStart.AddYears(1)
                if ($yearEnd -gt $MaxDate) { $yearEnd = $MaxDate }
                $yearSpan = ($yearEnd - $yearStart).TotalDays
                $offset = $rnd.NextDouble() * $yearSpan
                return $yearStart.AddDays($offset)
            }
            'LegacyMess' {
                $eras = @(
                    @{Start=$MinDate; End=$MinDate.AddYears(10); Weight=0.4},
                    @{Start=$MinDate.AddYears(10); End=$MinDate.AddYears(20); Weight=0.3},
                    @{Start=$MinDate.AddYears(20); End=$MaxDate; Weight=0.3}
                )
                $totalWeight = ($eras | Measure-Object -Property Weight -Sum).Sum
                $pick = $rnd.NextDouble() * $totalWeight
                foreach ($era in $eras) {
                    $pick -= $era.Weight
                    if ($pick -le 0) {
                        $eraSpan = ($era.End - $era.Start).TotalDays
                        $offset = $rnd.NextDouble() * $eraSpan
                        return $era.Start.AddDays($offset)
                    }
                }
                return $MinDate
            }
            default { return $MinDate }
        }
    }
    
    # Process batch
    $rnd = [System.Random]::new()
    $created = 0
    $errors = 0
    $bulkSpecs = @()
    
    foreach ($spec in $batch) {
        try {
            # Generate file name
            $dept = $spec.Department
            $prefixes = if ($DeptPrefixMap.ContainsKey($dept)) { $DeptPrefixMap[$dept] } else { $DeptPrefixMap['General'] }
            $extInfo = Get-WeightedExt $dept $rnd
            
            $prefix = $prefixes[$rnd.Next(0, $prefixes.Count)]
            $suffix = switch ($rnd.Next(0, 4)) {
                0 { " - draft" }
                1 { " (final)" }
                2 { " v{0}" -f $rnd.Next(1, 6) }
                default { "" }
            }
            $base = $prefix + $suffix
            $name = ("{0}-{1:0000}{2}" -f $base, $rnd.Next(0,10000), $extInfo.Ext)
            
            if ($rnd.NextDouble() -lt 0.08) { 
                $name = $name.Replace($extInfo.Ext, (" (1){0}" -f $extInfo.Ext)) 
            }
            
            $filePath = Join-Path $spec.FolderPath $name
            if (Test-Path $filePath) {
                $filePath = Join-Path $spec.FolderPath ("dup-{0:0000}-{1}{2}" -f $rnd.Next(0,10000), $rnd.Next(1000,9999), $extInfo.Ext)
            }
            
            # Add to bulk creation list
            $kb = $rnd.Next($extInfo.MinKB, $extInfo.MaxKB + 1)
            $bulkSpecs += @{
                Path = $filePath
                SizeKB = $kb
                Department = $dept
                Extension = $extInfo.Ext
            }
            
        } catch {
            $errors++
        }
    }
    
    # Bulk create sparse files
    if ($bulkSpecs.Count -gt 0) {
        # Group by directory for efficiency
        $byDir = $bulkSpecs | Group-Object { Split-Path $_.Path -Parent }
        
        foreach ($dirGroup in $byDir) {
            $dir = $dirGroup.Name
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            
            # Process files in this directory
            foreach ($fileSpec in $dirGroup.Group) {
                try {
                    # Create file
                    New-Item -ItemType File -Path $fileSpec.Path -Force | Out-Null
                    Write-ContentStub -Path $fileSpec.Path
                    
                    # Set sparse
                    $null = cmd /c "fsutil sparse setflag `"$($fileSpec.Path)`"" 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        # Set size
                        $targetBytes = [int64]$fileSpec.SizeKB * 1024L
                        $fs = [IO.File]::Open($fileSpec.Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
                        try {
                            $seekTo = [Math]::Max(0L, $targetBytes - 1)
                            [void]$fs.Seek($seekTo, [IO.SeekOrigin]::Begin)
                            $fs.WriteByte(0)
                        } finally {
                            $fs.Close()
                        }
                        
                        # Set attributes
                        $attrs = [IO.FileAttributes]::Normal
                        if ($rnd.NextDouble() -lt 0.05) { $attrs = $attrs -bor [IO.FileAttributes]::ReadOnly }
                        if ($rnd.NextDouble() -lt 0.02) { $attrs = $attrs -bor [IO.FileAttributes]::Hidden }
                        [IO.File]::SetAttributes($fileSpec.Path, $attrs)
                        
                        # Set timestamps if Touch enabled
                        if ($Touch) {
                            $fileDate = Get-RandomDate -MinDate $MinDate -MaxDate $MaxDate -Preset $DatePreset -Bias $RecentBias -rnd $rnd
                            $ct = $fileDate.AddMinutes(-($rnd.Next(0, 60)))
                            $wt = $fileDate.AddMinutes($rnd.Next(0, 120))
                            $at = $wt.AddMinutes($rnd.Next(0, 240))
                            
                            [IO.File]::SetCreationTime($fileSpec.Path, $ct)
                            [IO.File]::SetLastWriteTime($fileSpec.Path, $wt)
                            [IO.File]::SetLastAccessTime($fileSpec.Path, $at)
                        }
                        
                        # Add ADS if enabled
                        if ($ADS -and $rnd.NextDouble() -lt 0.15) {
                            try {
                                $adsPath = "$($fileSpec.Path):Zone.Identifier"
                                Set-Content -Path $adsPath -Value "[ZoneTransfer]`r`nZoneId=3" -Stream "Zone.Identifier" -ErrorAction SilentlyContinue
                            } catch {}
                        }
                        
                        $created++
                    } else {
                        $errors++
                    }
                } catch {
                    $errors++
                }
            }
        }
    }
    
    # Update progress
    $progress['completed'] = $progress['completed'] + $created
    $progress['errors'] = $progress['errors'] + $errors
    
    return @{ Created = $created; Errors = $errors }
}

# Start parallel file creation
Write-Host "`nStarting parallel file creation with $MaxThreads threads..." -ForegroundColor Green
$startTime = Get-Date

# Create variables to pass to runspaces
$variables = @{
    Root = $Root
    UseAD = $UseAD
    Touch = $Touch
    DatePreset = $DatePreset
    MinDate = $MinDate
    MaxDate = $MaxDate
    RecentBias = $RecentBias
    ADS = $ADS
    UserOwnership = $UserOwnership
    Clutter = $Clutter
}

# Split file specs into batches
$batches = Split-Array -InputArray $fileSpecs -ChunkSize $BatchSize

# Execute parallel file creation
$results = Invoke-ParallelBatch -InputObject $batches `
    -ScriptBlock $fileCreationScript `
    -MaxThreads $MaxThreads `
    -Variables $variables `
    -ShowProgress

# Calculate totals
$totalCreated = ($results | Measure-Object -Property Created -Sum).Sum
$totalErrors = ($results | Measure-Object -Property Errors -Sum).Sum

# Handle AD ownership if enabled (post-processing for better performance)
if ($UseAD -and $UserOwnership) {
    Write-Host "`nApplying AD ownership..." -ForegroundColor Yellow
    
    # Get all created files
    $createdFiles = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | 
                    Where-Object { $_.CreationTime -gt $startTime.AddMinutes(-1) }
    
    if ($createdFiles.Count -gt 0) {
        # Group by department
        $filesByDept = $createdFiles | Group-Object {
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
            $chunks = Split-Array -InputArray $deptFiles -ChunkSize 50
            foreach ($chunk in $chunks) {
                $ownershipBatches += @{
                    Files = $chunk
                    Department = $dept
                }
            }
        }
        
        Write-Host "Applying ownership to $($createdFiles.Count) files in parallel..." -ForegroundColor Yellow
        
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
        Write-Host "Updated ownership on $totalOwnershipUpdated files" -ForegroundColor Green
    }
}

# Add clutter files if enabled
if ($Clutter -and $totalCreated -gt 0) {
    Write-Host "`nAdding clutter files..." -ForegroundColor Yellow
    
    $clutterCount = [Math]::Floor($totalCreated * 0.05)  # 5% clutter files
    $clutterFolders = $folders | Get-Random -Count ([Math]::Min($clutterCount, $folders.Count))
    
    $clutterCreated = 0
    foreach ($folder in $clutterFolders) {
        $clutterFiles = @('desktop.ini', 'Thumbs.db', "~temp-$($rnd.Next(1000,9999)).tmp")
        $clutterFile = Join-Path $folder.FullName ($clutterFiles | Get-Random)
        
        try {
            New-Item -ItemType File -Path $clutterFile -Force | Out-Null
            if ($Touch) {
                $clutterDate = Get-RandomDate -MinDate $MinDate -MaxDate $MaxDate -Preset $DatePreset -Bias $RecentBias -rnd $rnd
                $ct = $clutterDate.AddMinutes(-($rnd.Next(0, 60)))
                $wt = $clutterDate.AddMinutes($rnd.Next(0, 120))
                $at = $wt.AddMinutes($rnd.Next(0, 240))
                
                [IO.File]::SetCreationTime($clutterFile, $ct)
                [IO.File]::SetLastWriteTime($clutterFile, $wt)
                [IO.File]::SetLastAccessTime($clutterFile, $at)
            }
            $clutterCreated++
        } catch {}
    }
    
    Write-Host "Created $clutterCreated clutter files" -ForegroundColor Green
    $totalCreated += $clutterCreated
}

# Final summary
$elapsed = (Get-Date) - $startTime
$rate = if ($elapsed.TotalSeconds -gt 0) { $totalCreated / $elapsed.TotalSeconds } else { 0 }

Write-Host @"

=== PARALLEL FILE GENERATION COMPLETE ===
Files Created: $totalCreated
Errors: $totalErrors
Duration: $($elapsed.ToString('mm\:ss'))
Rate: $([Math]::Round($rate, 2)) files/sec
Threads Used: $MaxThreads
Sparse Files: Yes
AD Ownership: $(if($UseAD -and $UserOwnership){'Enabled (18% users, 82% groups)'}else{'Disabled'})
Timestamps: $(if($Touch){"$DatePreset (bias: $RecentBias%)"}else{'Disabled'})

Performance Gain: ~$([Math]::Round($rate / 15, 1))x faster than sequential version
"@ -ForegroundColor Cyan

# Memory cleanup
Invoke-GarbageCollection -WaitForPendingFinalizers

# Show memory usage
$memory = Get-MemoryUsage
Write-Host "Memory Usage: WorkingSet=$($memory.WorkingSetMB)MB, Private=$($memory.PrivateMemoryMB)MB" -ForegroundColor DarkGray
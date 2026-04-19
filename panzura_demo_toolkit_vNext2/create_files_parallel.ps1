# create_files_simple_parallel.ps1 — Simple parallel file creation using ForEach-Object -Parallel
<#
.SYNOPSIS
  Generate enterprise-realistic file tree using PowerShell 7+ parallel processing.
  
.DESCRIPTION
  Based on proven vNext2 logic with ForEach-Object -Parallel for true parallel execution.
  Much simpler and more reliable than runspace pools.
  
.EXAMPLE
  .\create_files_simple_parallel.ps1 -MaxFiles 10000 -DatePreset RecentSkew -RecentBias 20
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
  [int]$ThrottleLimit = 0  # 0 = auto-detect (CPU count * 2)
)

# Detect PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "This script requires PowerShell 7 or later for parallel processing. Current version: $($PSVersionTable.PSVersion)"
}

# Auto-detect throttle limit
if ($ThrottleLimit -le 0) {
    $ThrottleLimit = [Environment]::ProcessorCount * 2
}

Write-Host "=== PARALLEL FILE GENERATION (PowerShell 7+ ForEach-Object -Parallel) ===" -ForegroundColor Cyan
Write-Host "Throttle Limit: $ThrottleLimit threads" -ForegroundColor Green

# Import helper module from vNext2
$vNext2ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'panzura_demo_toolkit_vNext2\set_privs.psm1'
if (-not (Test-Path $vNext2ModulePath)) {
    throw "Cannot find set_privs.psm1 from vNext2. Please ensure panzura_demo_toolkit_vNext2 exists."
}
Import-Module $vNext2ModulePath -Force -ErrorAction Stop

# Try AD (unless -NoAD)
$UseAD = -not $NoAD
if ($UseAD) {
    try { 
        Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
        $Domain = (Get-ADDomain).NetBIOSName
    } catch { 
        $UseAD = $false 
        Write-Warning "AD module not available, continuing without AD integration"
    }
}

# Initialize date range
if (-not $MinDate) { $MinDate = (Get-Date).AddYears(-3) }
if (-not $MaxDate) { $MaxDate = Get-Date }

Write-Host "Scanning folder structure..." -ForegroundColor Yellow
$rootItem = Get-Item -LiteralPath $Root -ErrorAction Stop
$folders = @($rootItem) + (Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
Write-Host "Found $($folders.Count) folders" -ForegroundColor Green

# Calculate file distribution per folder
$totalFolders = $folders.Count
if ($MaxFiles) {
    $globalMean = [Math]::Max(1, [Math]::Floor($MaxFiles / $totalFolders))
    $globalStd = [Math]::Max(1, [Math]::Floor($globalMean * 0.6))
    Write-Host "Target: $MaxFiles files across $totalFolders folders (mean: $globalMean, std: $globalStd)" -ForegroundColor Yellow
} else {
    $globalMean = $FilesPerFolderMean
    $globalStd = $FilesPerFolderStd
}

# Build folder work items
Write-Host "Planning file distribution..." -ForegroundColor Yellow
$folderWorkItems = $folders | ForEach-Object {
    $folder = $_
    $folderName = $folder.FullName
    
    # Determine folder type for distribution
    $folderType = "Default"
    if ($folderName -match "Projects") { $folderType = "Projects"; $mult = 1.8 }
    elseif ($folderName -match "Archive") { $folderType = "Archive"; $mult = 1.5 }
    elseif ($folderName -match "Temp") { $folderType = "Temp"; $mult = 1.2 }
    elseif ($folderName -match "Sensitive") { $folderType = "Sensitive"; $mult = 0.5 }
    elseif ($folderName -match "Backup") { $folderType = "Backup"; $mult = 2.0 }
    else { $mult = 1.0 }
    
    # Calculate file count using normal distribution
    $mean = [int]($globalMean * $mult)
    $std = [int]($globalStd * $mult)
    
    # Box-Muller transform for normal distribution
    $rnd = [System.Random]::new()
    $u1 = [Math]::Max([double]::Epsilon, $rnd.NextDouble())
    $u2 = [Math]::Max([double]::Epsilon, $rnd.NextDouble())
    $z = [Math]::Sqrt(-2.0 * [Math]::Log($u1)) * [Math]::Sin(2.0 * [Math]::PI * $u2)
    $fileCount = [int]([Math]::Round($mean + $std * $z))
    
    # Clamp to min/max
    $fileCount = [Math]::Max($MinFilesPerFolder, [Math]::Min($MaxFilesPerFolder, $fileCount))
    
    # 8% chance of empty folder
    if ($rnd.Next(0, 100) -lt 8) { $fileCount = 0 }
    
    # Determine department from path
    $parts = $folderName.Substring($Root.Length).Trim('\').Split('\')
    $dept = if ($parts.Length -gt 0 -and $parts[0]) { $parts[0] } else { "General" }
    
    [PSCustomObject]@{
        Path = $folderName
        Department = $dept
        FileCount = $fileCount
        FolderType = $folderType
    }
}

# Limit total files if MaxFiles specified
if ($MaxFiles) {
    $totalPlanned = ($folderWorkItems | Measure-Object -Property FileCount -Sum).Sum
    if ($totalPlanned -gt $MaxFiles) {
        Write-Host "Adjusting from $totalPlanned planned files to $MaxFiles target..." -ForegroundColor Yellow
        $scaleFactor = $MaxFiles / $totalPlanned
        $folderWorkItems | ForEach-Object { $_.FileCount = [Math]::Floor($_.FileCount * $scaleFactor) }
    }
}

$totalFiles = ($folderWorkItems | Measure-Object -Property FileCount -Sum).Sum
Write-Host "Will create $totalFiles files" -ForegroundColor Green

# Department prefixes and extension weights (from vNext2)
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

$ExtWeights = @{
  'Finance'     = @{'.xlsx'=40;'.csv'=25;'.pdf'=12;'.docx'=10;'.pptx'=3;'.zip'=3;'.txt'=5;'.msg'=2}
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

$ExtProperties = @{
  '.docx' = @{ MinKB=8; MaxKB=2048 };   '.xlsx' = @{ MinKB=16; MaxKB=8192 }
  '.pdf'  = @{ MinKB=32; MaxKB=16384 };  '.pptx' = @{ MinKB=64; MaxKB=32768 }
  '.txt'  = @{ MinKB=1; MaxKB=512 };     '.jpg'  = @{ MinKB=128; MaxKB=4096 }
  '.png'  = @{ MinKB=64; MaxKB=2048 };   '.zip'  = @{ MinKB=256; MaxKB=65536 }
  '.csv'  = @{ MinKB=4; MaxKB=1024 };    '.log'  = @{ MinKB=8; MaxKB=2048 }
  '.xml'  = @{ MinKB=4; MaxKB=512 };     '.json' = @{ MinKB=2; MaxKB=256 }
  '.msg'  = @{ MinKB=16; MaxKB=1024 };   '.vbs'  = @{ MinKB=1; MaxKB=64 }
  '.ps1'  = @{ MinKB=2; MaxKB=128 };     '.bat'  = @{ MinKB=1; MaxKB=32 }
  '.ini'  = @{ MinKB=1; MaxKB=16 };      '.yaml' = @{ MinKB=2; MaxKB=64 }
  '.psm1' = @{ MinKB=2; MaxKB=128 };     '.cs'   = @{ MinKB=2; MaxKB=256 }
  '.js'   = @{ MinKB=2; MaxKB=128 };     '.ts'   = @{ MinKB=2; MaxKB=128 }
  '.cfg'  = @{ MinKB=1; MaxKB=64 }
}

# Expand folder work items into individual file work items
Write-Host "Generating file specifications..." -ForegroundColor Yellow
$fileWorkItems = $folderWorkItems | ForEach-Object {
    $folderPath = $_.Path
    $dept = $_.Department
    $count = $_.FileCount
    
    1..$count | ForEach-Object {
        [PSCustomObject]@{
            FolderPath = $folderPath
            Department = $dept
            FileIndex = $_
        }
    }
}

Write-Host "Created $($fileWorkItems.Count) file work items" -ForegroundColor Green
Write-Host "Starting parallel file creation with throttle limit of $ThrottleLimit..." -ForegroundColor Cyan

$startTime = Get-Date
$syncHash = [hashtable]::Synchronized(@{ Created = 0; Errors = 0 })

# Process files in parallel
$results = $fileWorkItems | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $workItem = $_
    $syncHash = $using:syncHash
    $Root = $using:Root
    $UseAD = $using:UseAD
    $Domain = $using:Domain
    $UserOwnership = $using:UserOwnership
    $Touch = $using:Touch
    $MinDate = $using:MinDate
    $MaxDate = $using:MaxDate
    $DatePreset = $using:DatePreset
    $RecentBias = $using:RecentBias
    $ADS = $using:ADS
    $DeptPrefixMap = $using:DeptPrefixMap
    $ExtWeights = $using:ExtWeights
    $ExtProperties = $using:ExtProperties
    $vNext2ModulePath = $using:vNext2ModulePath
    
    # Import module in parallel thread
    Import-Module $vNext2ModulePath -Force -ErrorAction SilentlyContinue
    
    # Helper functions
    function Get-WeightedExt([string]$dept, [System.Random]$rnd) {
      $pool = if ($ExtWeights.ContainsKey($dept)) { $ExtWeights[$dept] } else { $ExtWeights['General'] }
      $sum = ($pool.Values | Measure-Object -Sum).Sum
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
      $ext = ".txt"
      $props = $ExtProperties[$ext]
      return @{Ext=$ext; MinKB=$props.MinKB; MaxKB=$props.MaxKB}
    }
    
    function Get-RandomDate {
      param([datetime]$MinDate, [datetime]$MaxDate, [string]$Preset, [int]$Bias, [System.Random]$rnd)
      
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
    
    try {
        $rnd = [System.Random]::new()
        $dept = $workItem.Department
        $folderPath = $workItem.FolderPath
        
        # Get extension info
        $extInfo = Get-WeightedExt $dept $rnd
        
        # Generate file name
        $prefixes = if ($DeptPrefixMap.ContainsKey($dept)) { $DeptPrefixMap[$dept] } else { $DeptPrefixMap['General'] }
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
        
        $filePath = Join-Path $folderPath $name
        if (Test-Path $filePath) {
            $filePath = Join-Path $folderPath ("dup-{0:0000}-{1}{2}" -f $rnd.Next(0,10000), $rnd.Next(1000,9999), $extInfo.Ext)
        }
        
        # Create sparse file
        $kb = $rnd.Next($extInfo.MinKB, $extInfo.MaxKB + 1)
        if ($kb -lt 1) { $kb = 1 }
        $targetBytes = [int64]$kb * 1024L
        
        New-Item -ItemType File -Path $filePath -Force | Out-Null
        
        # Mark sparse
        $null = cmd /c ("fsutil sparse setflag ""{0}""" -f $filePath) 2>$null
        if ($LASTEXITCODE -eq 0) {
            # Seek and write
            $fs = [IO.File]::Open($filePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $seekTo = [Math]::Max([int64]0, $targetBytes - 1)
                $null = $fs.Seek($seekTo, [IO.SeekOrigin]::Begin)
                $fs.WriteByte(0) | Out-Null
            } finally {
                $fs.Close()
            }
            
            # Set attributes
            $attrs = [IO.FileAttributes]::Normal
            if ($rnd.NextDouble() -lt 0.05) { $attrs = $attrs -bor [IO.FileAttributes]::ReadOnly }
            if ($rnd.NextDouble() -lt 0.02) { $attrs = $attrs -bor [IO.FileAttributes]::Hidden }
            [IO.File]::SetAttributes($filePath, $attrs)
            
            # Apply timestamps
            if ($Touch) {
                $fileDate = Get-RandomDate -MinDate $MinDate -MaxDate $MaxDate -Preset $DatePreset -Bias $RecentBias -rnd $rnd
                $ct = $fileDate.AddMinutes(-($rnd.Next(0, 60)))
                $wt = $fileDate.AddMinutes($rnd.Next(0, 120))
                $at = $wt.AddMinutes($rnd.Next(0, 240))
                
                [IO.File]::SetCreationTime($filePath, $ct)
                [IO.File]::SetLastWriteTime($filePath, $wt)
                [IO.File]::SetLastAccessTime($filePath, $at)
            }
            
            # Add ADS
            if ($ADS -and $rnd.NextDouble() -lt 0.15) {
                try {
                    $adsPath = "${filePath}:Zone.Identifier"
                    Set-Content -Path $adsPath -Value "[ZoneTransfer]`r`nZoneId=3" -Stream "Zone.Identifier" -ErrorAction SilentlyContinue
                } catch {}
            }
            
            # Set ownership (if AD enabled) - match vNext2 logic
            if ($UseAD -and $UserOwnership) {
                try {
                    # Determine actual department from path (match vNext2 logic)
                    $deptName = $null
                    $pathParts = $filePath.Split([IO.Path]::DirectorySeparatorChar)
                    # Assuming structure is S:\Shared\<Dept>...
                    if ($pathParts.Length -ge 4) {
                        $deptCandidate = $pathParts[2]
                        # Check if this is a valid department by checking if GG_<dept> exists
                        if ($DeptPrefixMap.ContainsKey($deptCandidate)) {
                            $deptName = $deptCandidate
                        }
                    }
                    
                    if ($deptName) {
                        $rng = $rnd.NextDouble()
                        if ($rng -lt 0.18) {
                            # 18% owned by random user
                            $groupName = "GG_$deptName"
                            try {
                                $users = Get-ADGroupMember -Identity $groupName -ErrorAction Stop | Get-ADUser -ErrorAction SilentlyContinue
                                if ($users) {
                                    $sam = ($users | Get-Random).SamAccountName
                                    Set-OwnerAndGroupFromModule -Path $filePath -Owner "$Domain\$sam" -Group "$Domain\$groupName" -Confirm:$false
                                } else {
                                    Set-OwnerAndGroupFromModule -Path $filePath -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
                                }
                            } catch {
                                Set-OwnerAndGroupFromModule -Path $filePath -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
                            }
                        } else {
                            # 82% owned by department group
                            $groupName = "GG_$deptName"
                            Set-OwnerAndGroupFromModule -Path $filePath -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
                        }
                    }
                    # Else: Leave ownership as default (BUILTIN\Administrators) for non-departmental folders
                } catch {}
            }
            
            $syncHash.Created++
            return @{ Success = $true; Path = $filePath }
        } else {
            $syncHash.Errors++
            return @{ Success = $false; Error = "fsutil failed" }
        }
    } catch {
        $syncHash.Errors++
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

$elapsed = (Get-Date) - $startTime
$rate = if ($elapsed.TotalSeconds -gt 0) { $syncHash.Created / $elapsed.TotalSeconds } else { 0 }

Write-Host @"

=== PARALLEL FILE GENERATION COMPLETE ===
Files Created: $($syncHash.Created)
Errors: $($syncHash.Errors)
Duration: $($elapsed.ToString('mm\:ss'))
Rate: $([Math]::Round($rate, 2)) files/sec
Throttle Limit: $ThrottleLimit threads
Sparse Files: Yes
AD Ownership: $(if($UseAD -and $UserOwnership){'Enabled (18% users, 82% groups)'}else{'Disabled'})
Timestamps: $(if($Touch){"$DatePreset (bias: $RecentBias%)"}else{'Disabled'})

Performance vs Sequential: ~$([Math]::Round($rate / 13.5, 1))x faster
"@ -ForegroundColor Cyan

# Memory cleanup
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

$currentMemory = (Get-Process -Id $PID).WorkingSet
Write-Host "Memory Usage: $([Math]::Round($currentMemory/1MB, 2))MB" -ForegroundColor DarkGray


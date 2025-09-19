# create_files_hybrid.ps1 — Sophisticated folder-aware distribution with modern AD integration
<#
.SYNOPSIS
  Generate messy, enterprise-realistic file tree using folder-type aware distribution.
  Combines sophisticated normal distribution logic from old script with enhanced AD integration.

.DESCRIPTION
  Uses folder-type profiles (Projects busier than Sensitive) with normal distribution
  for realistic file counts, while keeping modern AD integration, enhanced ownership,
  and perfect timestamp realism from the new script.
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [Nullable[long]]$MaxFiles = $null,
  [switch]$NoAD,                      # skip AD lookups / owner setting
  [switch]$Clutter = $true,           # drop desktop.ini, Thumbs.db, temp files occasionally
  [switch]$ADS = $true,               # add Alternate Data Streams for a subset
  [switch]$UserOwnership = $true,     # some files owned by random users (rest by GG_<Dept>)
  [int]$ProgressUpdateEvery = 200,

  # Timestamp realism
  [switch]$Touch = $true,
  [ValidateSet('Uniform','RecentSkew','YearSpread','LegacyMess')]
  [string]$DatePreset = 'RecentSkew',
  [Nullable[datetime]]$MinDate,
  [Nullable[datetime]]$MaxDate,
  [int]$RecentBias = 70,               # 0-100; higher = more recent (for RecentSkew)

  # Folder-aware distribution parameters (will be calculated based on MaxFiles)
  [int]$FilesPerFolderMean = 15,       # Base mean files per folder (overridden if MaxFiles specified)
  [int]$FilesPerFolderStd = 8,         # Standard deviation (overridden if MaxFiles specified)
  [int]$MinFilesPerFolder = 0,         # Minimum files per folder
  [int]$MaxFilesPerFolder = 100        # Maximum files per folder
)

# Optional helper for ownership/ACLs
Import-Module (Join-Path $PSScriptRoot 'set_privs.psm1') -Force -ErrorAction Stop

# Try AD (unless -NoAD)
$UseAD = -not $NoAD
if ($UseAD) {
  try { Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop } catch { $UseAD = $false }
}

# Random number generator
$rnd = [System.Random]::new()

# Mathematical functions from old script
function Clamp([int]$v,[int]$min,[int]$max){ if($v -lt $min){$min} elseif($v -gt $max){$max} else{$v} }
function Sample-Normal([int]$mean,[int]$std){
  $u1 = [Math]::Max([double]::Epsilon,$rnd.NextDouble())
  $u2 = [Math]::Max([double]::Epsilon,$rnd.NextDouble())
  $z  = [Math]::Sqrt(-2.0*[Math]::Log($u1))*[Math]::Sin(2.0*[Math]::PI*$u2)
  [int]([Math]::Round($mean + $std*$z))
}

# Folder-type profiles (sophisticated distribution from old script)
$FolderProfiles = @{
  "Projects"     = @{ mean=[int]($FilesPerFolderMean*1.8); std=[int]($FilesPerFolderStd*1.2) }  # Busiest
  "Archive"      = @{ mean=[int]($FilesPerFolderMean*1.5); std=[int]($FilesPerFolderStd*1.0) }  # Lots of old files
  "Temp"         = @{ mean=[int]($FilesPerFolderMean*1.2); std=[int]($FilesPerFolderStd*1.3) }  # Variable
  "Sensitive"    = @{ mean=[int]($FilesPerFolderMean*0.5); std=[int]($FilesPerFolderStd*0.7) }  # Fewer files
  "Vendors"      = @{ mean=[int]($FilesPerFolderMean*1.0); std=[int]($FilesPerFolderStd*1.0) }  # Normal
  "Backup"       = @{ mean=[int]($FilesPerFolderMean*2.0); std=[int]($FilesPerFolderStd*1.5) }  # Packed
  "Final"        = @{ mean=[int]($FilesPerFolderMean*0.8); std=[int]($FilesPerFolderStd*0.6) }  # Curated
  "Drafts"       = @{ mean=[int]($FilesPerFolderMean*1.4); std=[int]($FilesPerFolderStd*1.8) }  # Messy
  "Current"      = @{ mean=[int]($FilesPerFolderMean*1.1); std=[int]($FilesPerFolderStd*1.0) }  # Active
  "Old"          = @{ mean=[int]($FilesPerFolderMean*0.6); std=[int]($FilesPerFolderStd*0.8) }  # Sparse
  "Default"      = @{ mean=$FilesPerFolderMean;             std=$FilesPerFolderStd }              # Base
}

function Get-FolderProfile([string]$FullName){
  foreach($k in $FolderProfiles.Keys | Where-Object { $_ -ne "Default" }) {
    if ($FullName -match [Regex]::Escape($k)) { return $FolderProfiles[$k] }
  }
  return $FolderProfiles.Default
}

# --- FILE TYPE & NAME GENERATION ---

# Master lookup for file extension properties
$ExtProperties = @{
  '.docx' = @{ MinKB=8;   MaxKB=2048 };
  '.xlsx' = @{ MinKB=16;  MaxKB=8192 };
  '.pdf'  = @{ MinKB=32;  MaxKB=16384 };
  '.pptx' = @{ MinKB=64;  MaxKB=32768 };
  '.txt'  = @{ MinKB=1;   MaxKB=512 };
  '.jpg'  = @{ MinKB=128; MaxKB=4096 };
  '.png'  = @{ MinKB=64;  MaxKB=2048 };
  '.zip'  = @{ MinKB=256; MaxKB=65536 };
  '.csv'  = @{ MinKB=4;   MaxKB=1024 };
  '.log'  = @{ MinKB=8;   MaxKB=2048 };
  '.xml'  = @{ MinKB=4;   MaxKB=512 };
  '.json' = @{ MinKB=2;   MaxKB=256 };
  '.msg'  = @{ MinKB=16;  MaxKB=1024 };
  '.vbs'  = @{ MinKB=1;   MaxKB=64 };
  '.ps1'  = @{ MinKB=2;   MaxKB=128 };
  '.bat'  = @{ MinKB=1;   MaxKB=32 };
  '.ini'  = @{ MinKB=1;   MaxKB=16 };
  '.yaml' = @{ MinKB=2;   MaxKB=64 };
  '.psm1' = @{ MinKB=2;   MaxKB=128 };
  '.cs'   = @{ MinKB=2;   MaxKB=256 };
  '.js'   = @{ MinKB=2;   MaxKB=128 };
  '.ts'   = @{ MinKB=2;   MaxKB=128 };
  '.cfg'  = @{ MinKB=1;   MaxKB=64 };
}

# Per-department EXTENSION WEIGHTS (from original script)
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

# Department prefixes (enhanced from new script)
[hashtable]$DeptPrefixMap = @{
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

# Department SAmAccountName prefixes (for user ownership)
[hashtable]$DeptSamPrefixMap = @{
  'HR'           = 'GG_HR'
  'Finance'      = 'GG_Finance'
  'Engineering'  = 'GG_Engineering'
  'Marketing'    = 'GG_Marketing'
  'Sales'        = 'GG_Sales'
  'Legal'        = 'GG_Legal'
  'IT'           = 'GG_IT'
  'Ops'          = 'GG_Ops'
  'R&D'          = 'GG_R&D'
  'QA'           = 'GG_QA'
  'Facilities'   = 'GG_Facilities'
  'Procurement'  = 'GG_Procurement'
  'Logistics'    = 'GG_Logistics'
  'Training'     = 'GG_Training'
  'Support'      = 'GG_Support'
  'General'      = 'GG_General'
}

function Get-WeightedExt([string]$dept) {
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

function Get-RealisticKB([string]$dept) {
  $extInfo = Get-WeightedExt $dept
  return $rnd.Next($extInfo.MinKB, $extInfo.MaxKB + 1)
}

function Get-RealisticBaseName([string]$dept, [array]$prefixes) {
  $prefix = $prefixes[$rnd.Next(0, $prefixes.Count)]
  $suffix = switch ($rnd.Next(0, 4)) {
    0 { " - draft" }
    1 { " (final)" }
    2 { " v{0}" -f $rnd.Next(1, 6) }
    default { "" }
  }
  return $prefix + $suffix
}

# Date generation functions (from new script)
function Get-RandomDate {
  param([datetime]$MinDate, [datetime]$MaxDate, [string]$Preset, [int]$Bias)
  
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

# Initialize date range
if (-not $MinDate) { $MinDate = (Get-Date).AddYears(-3) }
if (-not $MaxDate) { $MaxDate = Get-Date }

# Timestamp application (from new script)
function Apply-Timestamps {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][datetime]$BaseTime)
  try {
    $baseDateTime = $BaseTime
    if (-not $baseDateTime -or $baseDateTime -eq [datetime]::MinValue) {
      $baseDateTime = Get-Date
    }
    $ct = $baseDateTime.AddMinutes(-($rnd.Next(0, 60)))   # created up to 1h earlier
    $wt = $baseDateTime.AddMinutes($rnd.Next(0, 120))     # modified up to 2h later
    $at = $wt.AddMinutes($rnd.Next(0, 240))               # accessed up to 4h after modification

    [IO.File]::SetCreationTime($Path, $ct)
    [IO.File]::SetLastWriteTime($Path, $wt)
    [IO.File]::SetLastAccessTime($Path, $at)
  } catch {
    Write-Verbose ("Timestamp set failed on {0}: {1}" -f $Path, $_.Exception.Message)
  }
}

# File creation functions (from new script)
function Write-ContentStub {
  param([Parameter(Mandatory)][string]$Path)
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

function New-RealisticFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][long]$KB)
  if ($KB -lt 1) { $KB = 1 }
  $targetBytes = [int64]$KB * 1024L

  # Ensure file exists, write content stub
  New-Item -ItemType File -Path $Path -Force | Out-Null
  Write-ContentStub -Path $Path

  # Mark sparse (must succeed)
  $null = cmd /c ("fsutil sparse setflag ""{0}""" -f $Path)
  if ($LASTEXITCODE -ne 0) { throw ("fsutil sparse setflag failed for {0} (exit {1})." -f $Path, $LASTEXITCODE) }

  # Seek to target-1 then write 1 byte
  $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $seekTo = [Math]::Max([int64]0, $targetBytes - 1)
    $null = $fs.Seek($seekTo, [IO.SeekOrigin]::Begin)
    $fs.WriteByte(0) | Out-Null
  } finally {
    $fs.Close()
  }
}

# Additional file functions (from new script)
function Set-RandomAttributes {
  param([Parameter(Mandatory)][string]$Path)
  try {
    $attrs = [IO.FileAttributes]::Normal
    if ($rnd.NextDouble() -lt 0.05) { $attrs = $attrs -bor [IO.FileAttributes]::ReadOnly }
    if ($rnd.NextDouble() -lt 0.02) { $attrs = $attrs -bor [IO.FileAttributes]::Hidden }
    [IO.File]::SetAttributes($Path, $attrs)
  } catch {}
}

function Add-ADS {
  param([Parameter(Mandatory)][string]$Path)
  if (-not $ADS) { return }
  try {
    if ($rnd.NextDouble() -lt 0.15) {
      $adsPath = "${Path}:Zone.Identifier"
      Set-Content -Path $adsPath -Value "[ZoneTransfer]`r`nZoneId=3" -Stream "Zone.Identifier" -ErrorAction SilentlyContinue
    }
  } catch {}
}

# --- Main execution ---
Write-Host "Starting hybrid file generation with folder-aware distribution..." -ForegroundColor Green

# Collect folders
$rootItem = Get-Item -LiteralPath $Root -ErrorAction Stop
$folders = @($rootItem) + (Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
Write-Host "Found $($folders.Count) folders for processing" -ForegroundColor Cyan

# Scale folder profiles based on MaxFiles if specified
if ($MaxFiles) {
  $targetMean = [Math]::Max(1, [Math]::Floor($MaxFiles / $folders.Count))
  $targetStd = [Math]::Max(1, [Math]::Floor($targetMean * 0.6))
  Write-Host "Scaling folder profiles: Mean=$targetMean, Std=$targetStd (Target: $MaxFiles files across $($folders.Count) folders)" -ForegroundColor Yellow
  
  # Update all folder profiles proportionally
  $scaleFactor = $targetMean / $FilesPerFolderMean
  $FolderProfiles["Projects"].mean = [int]($FolderProfiles["Projects"].mean * $scaleFactor)
  $FolderProfiles["Projects"].std = [int]($FolderProfiles["Projects"].std * $scaleFactor)
  $FolderProfiles["Archive"].mean = [int]($FolderProfiles["Archive"].mean * $scaleFactor)
  $FolderProfiles["Archive"].std = [int]($FolderProfiles["Archive"].std * $scaleFactor)
  $FolderProfiles["Temp"].mean = [int]($FolderProfiles["Temp"].mean * $scaleFactor)
  $FolderProfiles["Temp"].std = [int]($FolderProfiles["Temp"].std * $scaleFactor)
  $FolderProfiles["Sensitive"].mean = [int]($FolderProfiles["Sensitive"].mean * $scaleFactor)
  $FolderProfiles["Sensitive"].std = [int]($FolderProfiles["Sensitive"].std * $scaleFactor)
  $FolderProfiles["Vendors"].mean = [int]($FolderProfiles["Vendors"].mean * $scaleFactor)
  $FolderProfiles["Vendors"].std = [int]($FolderProfiles["Vendors"].std * $scaleFactor)
  $FolderProfiles["Backup"].mean = [int]($FolderProfiles["Backup"].mean * $scaleFactor)
  $FolderProfiles["Backup"].std = [int]($FolderProfiles["Backup"].std * $scaleFactor)
  $FolderProfiles["Final"].mean = [int]($FolderProfiles["Final"].mean * $scaleFactor)
  $FolderProfiles["Final"].std = [int]($FolderProfiles["Final"].std * $scaleFactor)
  $FolderProfiles["Drafts"].mean = [int]($FolderProfiles["Drafts"].mean * $scaleFactor)
  $FolderProfiles["Drafts"].std = [int]($FolderProfiles["Drafts"].std * $scaleFactor)
  $FolderProfiles["Current"].mean = [int]($FolderProfiles["Current"].mean * $scaleFactor)
  $FolderProfiles["Current"].std = [int]($FolderProfiles["Current"].std * $scaleFactor)
  $FolderProfiles["Old"].mean = [int]($FolderProfiles["Old"].mean * $scaleFactor)
  $FolderProfiles["Old"].std = [int]($FolderProfiles["Old"].std * $scaleFactor)
  $FolderProfiles["Default"].mean = $targetMean
  $FolderProfiles["Default"].std = $targetStd
}

$created = 0L
$start = Get-Date
$folderIdx = 0

foreach ($dir in $folders) {
  $folderIdx++
  
  # Get folder profile and calculate files using normal distribution
  $profile = Get-FolderProfile -FullName $dir.FullName
  $filesPerFolder = Clamp (Sample-Normal $profile.mean $profile.std) $MinFilesPerFolder $MaxFilesPerFolder
  
  # 8% chance of empty folder (from old script)
  if ($rnd.Next(0,100) -lt 8) { $filesPerFolder = 0 }
  
  # Department context
  $parts = $dir.FullName.Substring($Root.Length).Trim('\').Split('\')
  $dept = if ($parts.Length -gt 0 -and $parts[0]) { $parts[0] } else { $null }
  $prefixes = if ($dept -and $DeptPrefixMap.ContainsKey($dept)) { $DeptPrefixMap[$dept] } else { $DeptPrefixMap['General'] }
  
  Write-Verbose "Processing folder: $($dir.FullName) (Profile: $($profile.mean)±$($profile.std), Files: $filesPerFolder)"
  
  for ($i = 0; $i -lt $filesPerFolder; $i++) {
    
    # Check if we've hit the MaxFiles limit
    if ($MaxFiles -and $created -ge $MaxFiles) { break }
    
    # Generate file
    $extInfo = Get-WeightedExt $dept
    $base = Get-RealisticBaseName $dept $prefixes
    $name = ("{0}-{1:0000}{2}" -f $base, $rnd.Next(0,10000), $extInfo.Ext)
    if ($rnd.NextDouble() -lt 0.08) { $name = $name.Replace($extInfo.Ext, (" (1){0}" -f $extInfo.Ext)) }
    $file = Join-Path $dir.FullName $name
    if (Test-Path $file) {
      $file = Join-Path $dir.FullName ("dup-{0:0000}-{1}{2}" -f $rnd.Next(0,10000), $rnd.Next(1000,9999), $extInfo.Ext)
    }
    
    try {
      $kb = $rnd.Next($extInfo.MinKB, $extInfo.MaxKB + 1)
      New-RealisticFile -Path $file -KB $kb
      
      # Set file attributes BEFORE timestamps
      Set-RandomAttributes -Path $file
      
      # Ownership (enhanced from new script) - CORRECTED
      if ($UseAD -and $UserOwnership) {
        try {
          $Domain = (Get-ADDomain).NetBIOSName
          
          # Correctly determine the department from the file's full path.
          $deptName = $null
          $pathParts = $file.Split([IO.Path]::DirectorySeparatorChar)
          # Assuming the structure is always S:\Shared\<Dept>...
          if ($pathParts.Length -ge 4) {
              $deptCandidate = $pathParts[2]
              if ($DeptPrefixMap.ContainsKey($deptCandidate)) {
                  $deptName = $deptCandidate
              }
          }

          if ($deptName) {
            $rng = $rnd.NextDouble()
            if ($rng -lt 0.18) { # ~18% of files owned by a random user from the dept
              $groupName = "GG_$deptName"
              try {
                $users = Get-ADGroupMember -Identity $groupName -ErrorAction Stop | Get-ADUser -ErrorAction SilentlyContinue
                if ($users) {
                  $sam = ($users | Get-Random).SamAccountName
                  Set-OwnerAndGroupFromModule -Path $file -Owner "$Domain\$sam" -Group "$Domain\$groupName" -Confirm:$false
                } else { # Fallback to group if no users found
                  Set-OwnerAndGroupFromModule -Path $file -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
                }
              } catch {
                # Group not found or other AD error, fallback to group ownership by name
                Set-OwnerAndGroupFromModule -Path $file -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
              }
            } else { # Rest owned by the department group
              $groupName = "GG_$deptName"
              Set-OwnerAndGroupFromModule -Path $file -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
            }
          } else {
             # Fallback for non-departmental folders (e.g., S:\Shared\Common)
             # Let these files be owned by BUILTIN\Administrators as is the default
          }
        } catch {
          Write-Verbose "AD ownership failed for $file."
        }
      }
      
      # Add ADS
      Add-ADS -Path $file
      
      # Clutter files
      if ($Clutter -and $rnd.NextDouble() -lt 0.05) {
        $clutterFiles = @('desktop.ini', 'Thumbs.db', "~temp-$($rnd.Next(1000,9999)).tmp")
        $clutterFile = Join-Path $dir.FullName ($clutterFiles | Get-Random)
        try {
          New-Item -ItemType File -Path $clutterFile -Force | Out-Null
          if ($Touch) {
            $clutterDate = Get-RandomDate -MinDate $MinDate -MaxDate $MaxDate -Preset $DatePreset -Bias $RecentBias
            Apply-Timestamps -Path $clutterFile -BaseTime $clutterDate
          }
        } catch {}
      }
      
      # Apply timestamps LAST
      if ($Touch) {
        try {
          $fileDate = Get-RandomDate -MinDate $MinDate -MaxDate $MaxDate -Preset $DatePreset -Bias $RecentBias
          Apply-Timestamps -Path $file -BaseTime $fileDate
        } catch {
          Write-Verbose ("Timestamp generation failed for {0}: {1}" -f $file, $_.Exception.Message)
          $fallbackDate = (Get-Date).AddDays(-$rnd.Next(365, 1095))
          Apply-Timestamps -Path $file -BaseTime $fallbackDate
        }
      }
      
      $created++
      if (($created % $ProgressUpdateEvery) -eq 0) {
        $elapsed = ((Get-Date) - $start).TotalSeconds
        $rate = if ($elapsed -gt 0) { $created / $elapsed } else { 0 }
        $etaSec = if ($MaxFiles) { [math]::Max(0, ($MaxFiles - $created) / ($rate + 0.0001)) } else { 0 }
        $pct = if ($MaxFiles) { [Math]::Min(100, [int](100 * $created / [double]$MaxFiles)) } else { [int](100 * ($folderIdx / [double]$folders.Count)) }
        $status = if ($MaxFiles) { ("Files: {0} / {1} (~{2:N1}/s)" -f $created, $MaxFiles, $rate) } else { ("Folder {0} / {1} — Files: {2} (~{3:N1}/s)" -f $folderIdx, $folders.Count, $created, $rate) }
        $detail = if ($MaxFiles) { ("ETA: ~{0:N0}s" -f $etaSec) } else { "ETA: estimating…" }
        Write-Progress -Activity ("Generating files (sparse: True; AD used: {0}; folder-aware: True)" -f $UseAD) -Status $status -CurrentOperation $detail -PercentComplete $pct
      }
    } catch {
      Write-Warning ("File create failed for {0}: {1}" -f $file, $_.Exception.Message)
      continue
    }
  }
  
  # Check if we've hit the MaxFiles limit at folder level
  if ($MaxFiles -and $created -ge $MaxFiles) { break }
}

Write-Progress -Activity "Generating files" -Completed
$elapsed = ((Get-Date) - $start)
if ($created -eq 0) {
  Write-Warning "No files were created. Check -Root, permissions, and sparse support on the backend."
}
Write-Host ("Created {0} files under {1} in {2:mm\:ss} (sparse: True; AD used: {3}; touch: {4}, preset: {5}; folder-aware: True)" -f $created,$Root,$elapsed,$UseAD,$Touch,$DatePreset) -ForegroundColor Cyan

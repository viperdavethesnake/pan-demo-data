# create_temp_pollution.ps1 — Specialized temp file pollution scenario
<#
.SYNOPSIS
  Generate temp file pollution in project folders - the "nobody cleaned up" scenario.

.DESCRIPTION
  Creates .tmp files scattered across project folders with date clustering at 30/90/180 days old.
  Perfect for demonstrating storage waste, retention violations, and data hygiene issues.

.EXAMPLE
  .\create_temp_pollution.ps1 -MaxFiles 50000
  
.EXAMPLE
  .\create_temp_pollution.ps1 -MaxFiles 25000 -NoAD
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [int]$MaxFiles = 50000,
  [switch]$NoAD,
  [int]$ProgressUpdateEvery = 500
)

# Import helper module
Import-Module (Join-Path $PSScriptRoot 'set_privs.psm1') -Force -ErrorAction Stop

# Try AD (unless -NoAD)
$UseAD = -not $NoAD
if ($UseAD) {
  try { Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop } catch { $UseAD = $false }
}

# Random number generator
$rnd = [System.Random]::new()

Write-Host "`n=== TEMP FILE POLLUTION GENERATOR ===" -ForegroundColor Cyan
Write-Host "Scenario: Abandoned temp files in project folders" -ForegroundColor Yellow
Write-Host "Use Case: Storage waste, retention violations, cleanup demos`n" -ForegroundColor Yellow

# Find all project folders in the structure
Write-Host "Scanning for project folders..." -ForegroundColor Cyan
$projectFolders = Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue | 
                  Where-Object { $_.Name -match "Project" -or $_.Name -match "^P\d+" }

if ($projectFolders.Count -eq 0) {
  Write-Warning "No project folders found. Creating temp folders in root departments..."
  $projectFolders = Get-ChildItem -Path $Root -Directory -Force | Select-Object -First 10
}

Write-Host "Found $($projectFolders.Count) project/work folders for temp file placement" -ForegroundColor Green

# Temp file name patterns (realistic Windows temp file names)
$tempPrefixes = @(
  '~temp-',
  'tmp',
  'MSI',
  'CAB_',
  '~DF',
  'WRITABLE_',
  'TMP',
  '_tmp',
  'temp_',
  '~WRS'
)

function Get-TempFileName {
  $prefix = $tempPrefixes[$rnd.Next(0, $tempPrefixes.Count)]
  $number = $rnd.Next(1000, 9999)
  return "$prefix$number.tmp"
}

function Get-ClusteredDate {
  # 40% around 30 days, 30% around 90 days, 20% around 180 days, 10% scattered
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
  
  # Add random hours/minutes for realism
  $ageDate = $ageDate.AddHours($rnd.Next(0, 24)).AddMinutes($rnd.Next(0, 60))
  
  return $ageDate
}

function New-SparseTempFile {
  param([string]$Path, [long]$KB)
  
  if ($KB -lt 1) { $KB = 1 }
  $targetBytes = [int64]$KB * 1024L
  
  # Create file
  New-Item -ItemType File -Path $Path -Force | Out-Null
  
  # Mark sparse
  $null = cmd /c ("fsutil sparse setflag ""{0}""" -f $Path) 2>$null
  if ($LASTEXITCODE -ne 0) { 
    Write-Warning "fsutil sparse setflag failed for $Path"
    return
  }
  
  # Seek to target-1 then write 1 byte
  $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $seekTo = [Math]::Max([int64]0, $targetBytes - 1)
    $null = $fs.Seek($seekTo, [IO.SeekOrigin]::Begin)
    $fs.WriteByte(0) | Out-Null
  } 
  finally {
    $fs.Close()
  }
}

function Apply-Timestamps {
  param([string]$Path, [datetime]$BaseTime)
  
  try {
    # For temp files, all three timestamps are usually the same (created and abandoned)
    $created = $BaseTime
    $modified = $created.AddMinutes($rnd.Next(0, 30))  # Modified within 30 min
    $accessed = $modified.AddDays($rnd.Next(0, 7))     # Maybe accessed within a week
    
    [IO.File]::SetCreationTime($Path, $created)
    [IO.File]::SetLastWriteTime($Path, $modified)
    [IO.File]::SetLastAccessTime($Path, $accessed)
  } 
  catch {
    Write-Verbose "Timestamp set failed on $Path"
  }
}

# Main generation loop
Write-Host "`nGenerating $MaxFiles temp files with date clustering..." -ForegroundColor Green
Write-Host "Distribution: 40% ~30d, 30% ~90d, 20% ~180d, 10% scattered" -ForegroundColor Yellow

$created = 0
$start = Get-Date

# Pre-calculate folder weights (folders with more existing files get more temp files)
$folderWeights = @{}
$totalExisting = 0
foreach ($folder in $projectFolders) {
  $existingCount = (Get-ChildItem -Path $folder.FullName -File -ErrorAction SilentlyContinue).Count
  $weight = [Math]::Max(1, $existingCount)  # Minimum weight of 1
  $folderWeights[$folder.FullName] = $weight
  $totalExisting += $weight
}

# Create temp files
for ($i = 0; $i -lt $MaxFiles; $i++) {
  
  # Pick a folder weighted by existing file count
  $pick = $rnd.Next(0, $totalExisting)
  $accumulator = 0
  $targetFolder = $projectFolders[0]
  
  foreach ($folder in $projectFolders) {
    $accumulator += $folderWeights[$folder.FullName]
    if ($pick -lt $accumulator) {
      $targetFolder = $folder
      break
    }
  }
  
  # Generate temp file name (check for collision)
  $fileName = Get-TempFileName
  $filePath = Join-Path $targetFolder.FullName $fileName
  $attempts = 0
  while ((Test-Path $filePath) -and $attempts -lt 10) {
    $fileName = Get-TempFileName
    $filePath = Join-Path $targetFolder.FullName $fileName
    $attempts++
  }
  
  try {
    # Temp files are typically small to medium
    $sizeKB = $rnd.Next(1, 10240)  # 1 KB to 10 MB (some temp files can be large)
    
    # Occasional very small or very large
    if ($rnd.NextDouble() -lt 0.3) { $sizeKB = $rnd.Next(1, 100) }      # 30% very small
    if ($rnd.NextDouble() -lt 0.05) { $sizeKB = $rnd.Next(10240, 51200) }  # 5% large (10-50 MB)
    
    # Create sparse temp file
    New-SparseTempFile -Path $filePath -KB $sizeKB
    
    # Set ownership (if AD enabled)
    if ($UseAD) {
      try {
        $Domain = (Get-ADDomain).NetBIOSName
        
        # Determine department from path
        $deptName = $null
        $pathParts = $filePath.Split([IO.Path]::DirectorySeparatorChar)
        if ($pathParts.Length -ge 3) {
          $deptCandidate = $pathParts[2]
          # Check if this looks like a department
          $deptGroups = @('Finance','HR','Engineering','Marketing','Sales','Legal','IT','Ops','R&D','QA','Facilities','Procurement','Logistics','Training','Support')
          if ($deptGroups -contains $deptCandidate) {
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
              }
              else {
                Set-OwnerAndGroupFromModule -Path $filePath -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
              }
            }
            catch {
              Set-OwnerAndGroupFromModule -Path $filePath -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
            }
          }
          else {
            # 82% owned by department group
            $groupName = "GG_$deptName"
            Set-OwnerAndGroupFromModule -Path $filePath -Owner "$Domain\$groupName" -Group "$Domain\$groupName" -Confirm:$false
          }
        }
      }
      catch {
        Write-Verbose "AD ownership failed for $filePath"
      }
    }
    
    # Apply clustered timestamps
    $fileDate = Get-ClusteredDate
    Apply-Timestamps -Path $filePath -BaseTime $fileDate
    
    $created++
    
    # Progress reporting
    if (($created % $ProgressUpdateEvery) -eq 0) {
      $elapsed = ((Get-Date) - $start).TotalSeconds
      $rate = if ($elapsed -gt 0) { $created / $elapsed } else { 0 }
      $etaSec = [math]::Max(0, ($MaxFiles - $created) / ($rate + 0.0001))
      $pct = [Math]::Min(100, [int](100 * $created / [double]$MaxFiles))
      Write-Progress -Activity "Generating temp file pollution" -Status ("Files: {0} / {1} (~{2:N1}/s)" -f $created, $MaxFiles, $rate) -CurrentOperation ("ETA: ~{0:N0}s" -f $etaSec) -PercentComplete $pct
    }
  }
  catch {
    Write-Warning "Failed to create $filePath : $($_.Exception.Message)"
    continue
  }
}

Write-Progress -Activity "Generating temp file pollution" -Completed

# Summary
$elapsed = ((Get-Date) - $start)
Write-Host "`n=== TEMP FILE POLLUTION COMPLETE ===" -ForegroundColor Green
Write-Host "Created: $created temp files" -ForegroundColor Cyan
Write-Host "Time: $($elapsed.ToString('mm\:ss'))" -ForegroundColor Cyan
Write-Host "Location: $Root (scattered across project folders)" -ForegroundColor Cyan
Write-Host "File Type: .tmp only" -ForegroundColor Cyan
Write-Host "Sparse: Yes (minimal disk usage)" -ForegroundColor Cyan
Write-Host "AD Ownership: $(if($UseAD){'Enabled (18% users, 82% groups)'}else{'Disabled'})" -ForegroundColor Cyan
Write-Host "`nDate Clustering:" -ForegroundColor Yellow
Write-Host "  ~40% around 30 days old" -ForegroundColor White
Write-Host "  ~30% around 90 days old" -ForegroundColor White
Write-Host "  ~20% around 180 days old" -ForegroundColor White
Write-Host "  ~10% scattered within year" -ForegroundColor White
Write-Host "`nUse Case: Perfect for storage waste, cleanup, and retention demos!" -ForegroundColor Green
Write-Host ""



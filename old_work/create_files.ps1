# create-files_v4.ps1 (fixed)
<#
.SYNOPSIS
  Generate a realistic, messy file corpus under S:\Shared (or custom root):
  - Sparse files by default (NTFS). Use -Physical to write real bytes.
  - Department-aware filenames and extension choices
  - Folder-type profiles (Projects/Archive/Temp/Sensitive/Vendors)
  - Era-weighted timestamps and formats (legacy earlier; modern later)
  - Random ownership: ~20% user-owned when AD available; else Domain Admins
  - Optional CSV log

.PREREQS
  - Run create-folders_v2.ps1 first
  - Import set-privs.psm1 (Enable-Privilege, Set-OwnerAndGroup, Grant-FsAccess)
  - If using AD features, ActiveDirectory module available & groups present
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [string]$Domain = (Get-ADDomain).NetBIOSName,

  # Era for timestamp spread and format weighting
  [datetime]$StartDate = (Get-Date).AddYears(-12),
  [datetime]$EndDate   = (Get-Date),

  # Distribution knobs
  [int]$FilesPerFolderMean = 40,
  [int]$FilesPerFolderStd  = 25,
  [int]$MinFilesPerFolder  = 0,
  [int]$MaxFilesPerFolder  = 150,

  [int]$ExtraSubfolderChancePct = 35,
  [int]$MaxExtraSubfolders      = 5,

  # Total cap (null = unlimited)
  [Nullable[int]]$MaxFiles = $null,

  # Behavior: sparse is default; pass -Physical to write real bytes
  [switch]$Physical,

  # Skip all AD lookups and use Domain Admins for ownership, skip AD ACE noise
  [switch]$NoAD,

  # Optional logging
  [string]$LogCsv
)

# Load helpers
. (Join-Path $PSScriptRoot 'set-privs.psm1')

# Try AD unless explicitly disabled
$UseAD = $true
if ($NoAD) { $UseAD = $false }
elseif (-not (Get-Module ActiveDirectory -ListAvailable)) { $UseAD = $false }
elseif (-not (Get-Module ActiveDirectory)) {
  try { Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop } catch { $UseAD = $false }
}

$rand = [System.Random]::new()
function Clamp([int]$v,[int]$min,[int]$max){ if($v -lt $min){$min} elseif($v -gt $max){$max} else{$v} }
function Sample-Normal([int]$mean,[int]$std){
  $u1 = [Math]::Max([double]::Epsilon,$rand.NextDouble())
  $u2 = [Math]::Max([double]::Epsilon,$rand.NextDouble())
  $z  = [Math]::Sqrt(-2.0*[Math]::Log($u1))*[Math]::Sin(2.0*[Math]::PI*$u2)
  [int]([Math]::Round($mean + $std*$z))
}

# --- Department-aware prefixes (cast as hashtable; unique name to avoid collisions) ---
[hashtable]$DeptPrefixMap = @{
  'HR'           = @('Employee','Handbook','Policy','Benefits','Onboarding','Review','Timesheet','Training','Payroll')
  'Finance'      = @('Budget','Invoice','Statement','Report','Expense','Audit','Tax','Forecast','Analysis')
  'Engineering'  = @('Spec','Design','Code','Test','Release','Bug','Feature','API','Database')
  'Marketing'    = @('Campaign','Brand','Social','Event','Presentation','Asset','Analysis','Lead')
  'Sales'        = @('Quote','Proposal','Contract','Lead','Territory','Forecast','Demo','Account')
  'Legal'        = @('Contract','Agreement','Policy','Compliance','Case','Brief','NDA','IP')
  'IT'           = @('Config','Backup','Log','Script','Install','Update','Security','Monitor')
  'Ops'          = @('Runbook','Checklist','Inventory','Schedule','Workflow','SOP','Change')
  'General'      = @('Document','File','Data','Report','Meeting','Project','Archive','Temp')
}

# Era-profiled extension pools
$FormatsModern = @(
  @{Ext=".docx"; Weight=18; MinKB=32; MaxKB=4096},
  @{Ext=".xlsx"; Weight=18; MinKB=16; MaxKB=8192},
  @{Ext=".pptx"; Weight=12; MinKB=128; MaxKB=16384},
  @{Ext=".pdf" ; Weight=16; MinKB=64; MaxKB=8192},
  @{Ext=".csv" ; Weight=10; MinKB=4 ; MaxKB=2048},
  @{Ext=".txt" ; Weight=6 ; MinKB=1 ; MaxKB=256},
  @{Ext=".zip" ; Weight=8 ; MinKB=32; MaxKB=32768},
  @{Ext=".msg" ; Weight=6 ; MinKB=8 ; MaxKB=4096},
  @{Ext=".png" ; Weight=6 ; MinKB=16; MaxKB=4096}
)
$FormatsLegacy = @(
  @{Ext=".doc" ; Weight=18; MinKB=16; MaxKB=2048},
  @{Ext=".xls" ; Weight=18; MinKB=16; MaxKB=4096},
  @{Ext=".ppt" ; Weight=12; MinKB=128; MaxKB=8192},
  @{Ext=".pdf" ; Weight=12; MinKB=64 ; MaxKB=4096},
  @{Ext=".txt" ; Weight=10; MinKB=1  ; MaxKB=256},
  @{Ext=".csv" ; Weight=8 ; MinKB=4  ; MaxKB=2048},
  @{Ext=".zip" ; Weight=10; MinKB=16 ; MaxKB=16384},
  @{Ext=".msg" ; Weight=6 ; MinKB=8  ; MaxKB=4096},
  @{Ext=".png" ; Weight=6 ; MinKB=16 ; MaxKB=2048}
)

# Folder-type profiles
$FolderProfiles = @{
  "Projects"  = @{ mean=[int]($FilesPerFolderMean*1.8); std=[int]($FilesPerFolderStd*1.2) }
  "Archive"   = @{ mean=[int]($FilesPerFolderMean*1.5); std=[int]($FilesPerFolderStd*1.0) }
  "Temp"      = @{ mean=[int]($FilesPerFolderMean*1.2); std=[int]($FilesPerFolderStd*1.3) }
  "Sensitive" = @{ mean=[int]($FilesPerFolderMean*0.5); std=[int]($FilesPerFolderStd*0.7) }
  "Vendors"   = @{ mean=[int]($FilesPerFolderMean*1.0); std=[int]($FilesPerFolderStd*1.0) }
  "Default"   = @{ mean=$FilesPerFolderMean;             std=$FilesPerFolderStd }
}
function Get-FolderProfile([string]$FullName){
  foreach($k in $FolderProfiles.Keys | Where-Object { $_ -ne "Default" }) {
    if ($FullName -match [Regex]::Escape($k)) { return $FolderProfiles[$k] }
  }
  return $FolderProfiles.Default
}

# Era blending
function Choose-FormatPool([datetime]$dt){
  $span = [Math]::Max(1.0, ($EndDate - $StartDate).TotalDays)
  $pos  = [Math]::Min(1.0,[Math]::Max(0.0, ($dt - $StartDate).TotalDays / $span))
  if ($pos -le 0.35) { return @($FormatsLegacy, 0.8, $FormatsModern, 0.2) }
  if ($pos -ge 0.55) { return @($FormatsModern, 0.85, $FormatsLegacy, 0.15) }
  return @($FormatsModern, 0.6, $FormatsLegacy, 0.4)
}
function Choose-Weighted($items){
  $total = ($items | Measure-Object -Property Weight -Sum).Sum
  if ($total -le 0) { return $items[0] }
  $pick = $rand.NextDouble() * $total
  foreach ($it in $items) {
    $pick -= $it.Weight
    if ($pick -le 0) { return $it }
  }
  return $items[-1]
}

# AD helpers (only if $UseAD)
function Test-AdGroupSam {
  param([Parameter(Mandatory)][string]$Sam)
  if (-not $UseAD) { return $false }
  try {
    $dn = (Get-ADDomain).DistinguishedName
    return [bool](Get-ADGroup -LDAPFilter "(sAMAccountName=$Sam)" -SearchBase $dn -ErrorAction SilentlyContinue)
  } catch { return $false }
}
function Resolve-DeptPrincipals {
  param([string]$Dept,[string]$Domain = (Get-ADDomain).NetBIOSName)
  if (-not $UseAD) { return [pscustomobject]@{ DeptGG=$null; RO=$null } }
  $ggDeptSam = "GG_${Dept}"
  $ggROSam   = "GG_${Dept}_RO"
  $dlROSam   = "DL_Share_${Dept}_RO"
  $deptGGQualified = if (Test-AdGroupSam $ggDeptSam) { "$Domain\$ggDeptSam" } else { $null }
  $roQualified     = if (Test-AdGroupSam $dlROSam)   { "$Domain\$dlROSam" }
                     elseif (Test-AdGroupSam $ggROSam){ "$Domain\$ggROSam" } else { $null }
  [pscustomobject]@{ DeptGG = $deptGGQualified; RO = $roQualified }
}

# File creation (sparse default)
function New-RealisticFile {
  param([string]$Path,[int]$SizeKB,[switch]$Physical)
  if ($Physical) {
    $bytes = New-Object byte[] ($SizeKB*1024)
    (New-Object System.Random).NextBytes($bytes)
    [IO.File]::WriteAllBytes($Path,$bytes); return
  }
  New-Item -ItemType File -Path $Path -Force | Out-Null
  cmd /c "fsutil sparse setflag `"$Path`"" | Out-Null
  $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  try { $fs.SetLength([int64]$SizeKB*1024) } finally { $fs.Close() }
}

# Extra subfolders
function Maybe-Create-ExtraSubfolders([string]$Parent){
  if ($rand.Next(0,100) -ge $ExtraSubfolderChancePct) { return @() }
  $count = $rand.Next(1, [Math]::Max(2, $MaxExtraSubfolders+1))
  $made = @()
  1..$count | ForEach-Object {
    $name = ("{0}-{1:000}" -f @("Q1","Q2","Q3","Q4","Backlog","InFlight","Hold","ToReview","Legacy","Audit")[$rand.Next(0,10)], $rand.Next(0,1000))
    $p = Join-Path $Parent $name
    try { New-Item -ItemType Directory -Path $p -Force | Out-Null; $made += $p } catch {}
  }
  return $made
}

# Gather folders
$allFolders = Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue
$allFolders = ,(Get-Item -LiteralPath $Root) + $allFolders

# Optional CSV
if ($LogCsv) { "FullPath,SizeBytes,Created,Modified,Owner" | Out-File -FilePath $LogCsv -Encoding UTF8 }

# Main
$totalCreated = 0
foreach ($dir in $allFolders) {
  $extra = Maybe-Create-ExtraSubfolders -Parent $dir.FullName
  if ($extra.Count -gt 0) { $extra | ForEach-Object { $allFolders += (Get-Item $_) } }

  $profile = Get-FolderProfile -FullName $dir.FullName
  $n = Clamp (Sample-Normal $profile.mean $profile.std) $MinFilesPerFolder $MaxFilesPerFolder
  if ($rand.Next(0,100) -lt 8) { $n = 0 }  # ~8% empty

  # Dept context
  $parts = $dir.FullName.Substring($Root.Length).Trim('\').Split('\')
  $dept  = if ($parts.Length -gt 0 -and $parts[0]) { $parts[0] } else { $null }
  $deptPrefixes = if ($dept -and $DeptPrefixMap.ContainsKey($dept)) { $DeptPrefixMap[$dept] } else { $DeptPrefixMap['General'] }

  for($i=1; $i -le $n; $i++){
    if ($MaxFiles -and $totalCreated -ge $MaxFiles) { Write-Warning "Reached MaxFiles cap ($MaxFiles). Stopping."; break }

    # Era-weighted timestamp
    $spanDays = [Math]::Max(1.0, ($EndDate - $StartDate).TotalDays)
    $offset   = $rand.NextDouble() * $spanDays
    $when     = $StartDate.AddDays($offset)

    # Pick format + size
    $pools = Choose-FormatPool -dt $when
    $modern, $mw, $legacy, $lw = $pools[0], $pools[1], $pools[2], $pools[3]
    $pool  = if ($rand.NextDouble() -lt $mw) { $modern } else { $legacy }
    $fmt   = Choose-Weighted $pool
    $sizeKB = $rand.Next([int]$fmt.MinKB, [int]$fmt.MaxKB + 1)

    # Dept-aware name
    $prefix = $deptPrefixes[ $rand.Next(0, $deptPrefixes.Count) ]
    $stem   = @("doc","spec","report","export","invoice","note","img","mail","data")[$rand.Next(0,9)]
    $name   = ("{0}-{1}-{2:0000}{3}" -f $prefix, $stem, $rand.Next(0,10000), $fmt.Ext)
    $file   = Join-Path $dir.FullName $name
    if (Test-Path $file) { $file = Join-Path $dir.FullName ("dup-{0:0000}-{1}{2}" -f $rand.Next(0,10000),$rand.Next(1000,9999),$fmt.Ext) }

    # Create file (sparse default)
    try { New-RealisticFile -Path $file -SizeKB $sizeKB -Physical:$Physical }
    catch { Write-Warning ("Failed to create {0}: {1}" -f $file, $_.Exception.Message); continue }

    # Timestamps
    try {
      (Get-Item $file).CreationTime  = $when
      (Get-Item $file).LastWriteTime = $when.AddDays($rand.Next(0,120))
    } catch {}

    # Ownership / ACE noise
    $ownerUsed = "$Domain\Domain Admins"
    if ($dept -and $UseAD) {
      $resolved  = Resolve-DeptPrincipals -Dept $dept -Domain $Domain
      $deptGroup = if ($resolved.DeptGG) { $resolved.DeptGG } else { "$Domain\Domain Admins" }
      $ownerUsed = $deptGroup

      $useUserOwner = ($rand.Next(0,5) -eq 0)  # 20% user owner
      try {
        if ($useUserOwner) {
          $users = Get-ADGroupMember -Identity $deptGroup -Recursive -ErrorAction SilentlyContinue | Where-Object {$_.objectClass -eq 'user'}
          if ($users -and $users.Count -gt 0) {
            $u = $users[ $rand.Next(0,$users.Count) ].SamAccountName
            Set-OwnerAndGroup -Path $file -Owner "$Domain\$u"
            $ownerUsed = "$Domain\$u"
          } else {
            Set-OwnerAndGroup -Path $file -Owner $deptGroup
          }
        } else {
          Set-OwnerAndGroup -Path $file -Owner $deptGroup
        }
      } catch {
        Write-Warning ("Owner set failed on {0}: {1}" -f $file, $_.Exception.Message)
        try { Set-OwnerAndGroup -Path $file -Owner "$Domain\Domain Admins" } catch {}
        $ownerUsed = "$Domain\Domain Admins"
      }

      # Light ACE noise only when AD is available
      if ($resolved.RO) {
        $choice = $rand.Next(0,10)
        if ($choice -le 2) {
          Grant-FsAccess -Path $file -Identity $resolved.RO -Rights 'ReadAndExecute' -ThisFolderOnly
        } elseif ($choice -eq 9) {
          Grant-FsAccess -Path $file -Identity $resolved.RO -Rights 'Write' -Type 'Deny' -ThisFolderOnly
        }
      }
    } else {
      # No AD: just ensure we own the file with something safe
      try { Set-OwnerAndGroup -Path $file -Owner "$Domain\Domain Admins" } catch {}
    }

    # CSV log
    if ($LogCsv) {
      try {
        $len = (Get-Item $file).Length
        ('"{0}",{1},"{2}","{3}","{4}"' -f $file.Replace('"','""'), $len, (Get-Item $file).CreationTime, (Get-Item $file).LastWriteTime, $ownerUsed.Replace('"','""')) |
          Add-Content -Path $LogCsv -Encoding UTF8
      } catch {}
    }

    $totalCreated++
  }

  if ($MaxFiles -and $totalCreated -ge $MaxFiles) { break }
}

Write-Host "Created $totalCreated files under $Root (sparse default: $(-not $Physical); AD used: $UseAD)." -ForegroundColor Cyan

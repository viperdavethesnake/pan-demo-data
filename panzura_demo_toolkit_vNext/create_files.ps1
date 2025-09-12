# create_files.ps1 — ultra-realistic, sparse-only generator (PS 7.5.x)
<#
.SYNOPSIS
  Generate a messy, enterprise-realistic file tree (sparse-only). Randomized sizes,
  realistic names, per-department extension mix, content stubs, timestamps, ownership.

.DESIGNED FOR
  PowerShell 7.x. Run with rights to write S:\Shared (and set file attributes).
  Sparse is REQUIRED. If sparse/seek fail on the backend, the script throws.

.NOTES
  - Sets CreationTime, LastWriteTime, LastAccessTime per file (NTFS “ChangeTime” is internal).
  - Uses seek-and-poke (size-1 + write 1 byte) to grow sparse files (more compatible than SetLength()).
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
  [int]$RecentBias = 70               # 0-100; higher = more recent (for RecentSkew)
)

# Optional helper for ownership/ACLs
try { Import-Module (Join-Path $PSScriptRoot 'set_privs.psm1') -Force -ErrorAction Stop } catch {}

# Try AD (unless -NoAD)
$UseAD = -not $NoAD
if ($UseAD) {
  try { Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop } catch { $UseAD = $false }
}

# Dept prefixes (for base names)
[hashtable]$DeptPrefixMap = @{
  'HR'          = @('Employee','Handbook','Policy','Benefits','Onboarding','Review','Timesheet','Training','Payroll')
  'Finance'     = @('Budget','Invoice','Statement','Report','Expense','Audit','Tax','Forecast','Analysis')
  'Engineering' = @('Spec','Design','Code','Test','Release','Bug','Feature','API','Database')
  'Marketing'   = @('Campaign','Brand','Social','Event','Presentation','Asset','Analysis','Lead')
  'Sales'       = @('Quote','Proposal','Contract','Lead','Territory','Forecast','Demo','Account')
  'Legal'       = @('Contract','Agreement','Policy','Compliance','Case','Brief','NDA','IP')
  'IT'          = @('Config','Backup','Log','Script','Install','Update','Security','Monitor')
  'Ops'         = @('Runbook','Checklist','Inventory','Schedule','Workflow','SOP','Change')
  'General'     = @('Document','File','Data','Report','Meeting','Project','Archive','Temp')
}

# Per-department EXTENSION WEIGHTS
$ExtWeights = @{
  'Finance'     = @{'xlsx'=40;'csv'=25;'pdf'=12;'docx'=10;'pptx'=3;'zip'=3;'txt'=5; 'msg'=2}
  'HR'          = @{'docx'=30;'pdf'=35;'xlsx'=12;'pptx'=5;'txt'=10;'msg'=6;'zip'=2}
  'Engineering' = @{'txt'=15;'log'=18;'json'=12;'yaml'=8;'ps1'=10;'psm1'=3;'cs'=6;'js'=6;'ts'=4;'xml'=8;'zip'=5;'pdf'=3}
  'Marketing'   = @{'pptx'=35;'docx'=12;'xlsx'=8;'png'=18;'jpg'=12;'pdf'=10;'zip'=5}
  'Sales'       = @{'xlsx'=30;'docx'=20;'pptx'=18;'pdf'=18;'msg'=10;'zip'=4}
  'Legal'       = @{'pdf'=50;'docx'=28;'xlsx'=8;'msg'=8;'pptx'=3;'zip'=3}
  'IT'          = @{'log'=28;'cfg'=12;'ini'=10;'ps1'=10;'bat'=6;'vbs'=2;'xml'=10;'json'=10;'zip'=12}
  'Ops'         = @{'xlsx'=20;'docx'=20;'pdf'=18;'csv'=15;'txt'=15;'pptx'=7;'zip'=5}
  'General'     = @{'docx'=20;'xlsx'=20;'pptx'=15;'pdf'=20;'txt'=15;'zip'=10}
}

$rnd = [Random]::new()

function Get-WeightedExt([string]$Dept){
  $pool = if ($ExtWeights.ContainsKey($Dept)) { $ExtWeights[$Dept] } else { $ExtWeights['General'] }
  $sum = ($pool.GetEnumerator() | Measure-Object -Property Value -Sum).Sum
  $x = Get-Random -Maximum $sum
  $acc = 0; foreach($k in $pool.Keys){ $acc += $pool[$k]; if($x -lt $acc){ return ".$k" } }
  return ".txt"
}

function Get-RealisticBaseName([string]$Dept,[string[]]$Prefixes){
  $p = $Prefixes[$rnd.Next(0,$Prefixes.Count)]
  $suffix = @(
    "",
    (" v{0}" -f (1 + $rnd.Next(5))),
    " (final)",
    (" (final v{0})" -f (1 + $rnd.Next(3))),
    " - draft",
    (" ({0})" -f (Get-Date).AddDays(-$rnd.Next(0,365)).ToString('yyyy-MM-dd'))
  )[$rnd.Next(0,6)]
  return "$p$suffix"
}

function Set-RandomAttributes([string]$Path){
  $attr = [IO.FileAttributes]::Normal
  if ($rnd.NextDouble() -lt 0.06) { $attr = $attr -bor [IO.FileAttributes]::ReadOnly }
  if ($rnd.NextDouble() -lt 0.03) { $attr = $attr -bor [IO.FileAttributes]::Hidden }
  if ($rnd.NextDouble() -lt 0.01) { $attr = $attr -bor [IO.FileAttributes]::System }
  try { (Get-Item $Path -Force).Attributes = $attr } catch {}
}

function Add-ADS([string]$Path,[string]$Name,[string]$Content){
  try { Set-Content -Path ("{0}:{1}" -f $Path,$Name) -Value $Content -Encoding UTF8 -Force } catch {}
}

function Get-RealisticKB([string]$Dept){
  # All returns are Int64 (KB)
  $small = @(4L,8L,12L,16L,32L,64L,128L,256L)
  $med   = @(512L,1024L,2048L,4096L,8192L,16384L)
  $large = @(32768L,65536L,131072L)         # 32MB, 64MB, 128MB
  $hugeGB = @(2L,4L,8L,12L,20L)             # GB
  $roll = Get-Random -Maximum 100
  if     ($roll -lt 65) { return ($small + $med) | Get-Random }
  elseif ($roll -lt 95) { return $large | Get-Random }
  else                  { return ( ($hugeGB | Get-Random) * 1024L * 1024L ) }  # GB -> KB (Int64)
}

function Write-ContentStub([string]$Path){
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  $ascii = [System.Text.Encoding]::ASCII
  switch ($ext) {
    '.pdf'  { [IO.File]::WriteAllBytes($Path, $ascii.GetBytes("%PDF-1.5`n")); return }
    '.png'  { [IO.File]::WriteAllBytes($Path, [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A)); return }
    '.jpg'  { [IO.File]::WriteAllBytes($Path, [byte[]](0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01)); return }
    '.docx' { [IO.File]::WriteAllBytes($Path, [byte[]](0x50,0x4B,0x03,0x04)); return } # PK..
    '.xlsx' { [IO.File]::WriteAllBytes($Path, [byte[]](0x50,0x4B,0x03,0x04)); return }
    '.pptx' { [IO.File]::WriteAllBytes($Path, [byte[]](0x50,0x4B,0x03,0x04)); return }
    '.zip'  { [IO.File]::WriteAllBytes($Path, [byte[]](0x50,0x4B,0x03,0x04)); return }
    '.msg'  { Set-Content -Path $Path -Value "From: someone@example.com`nTo: you@example.com`nSubject: FYI`n`nHello." -Encoding UTF8; return }
    '.csv'  { Set-Content -Path $Path -Value "id,name,amount`n1,Alpha,123.45`n2,Beta,67.89" -Encoding UTF8; return }
    default { Set-Content -Path $Path -Value ("Lorem ipsum {0}" -f (Get-Date -Format o)) -Encoding UTF8; return }
  }
}

function Get-RandomDate {
  param([Nullable[datetime]]$Min,[Nullable[datetime]]$Max,[string]$Mode,[int]$Bias)
  
  try {
    # Ensure we always have valid dates
    if (-not $Min -or -not $Min.HasValue) { $Min = [datetime]::UtcNow.AddYears(-3) }
    if (-not $Max -or -not $Max.HasValue) { $Max = [datetime]::UtcNow }
    if ($Max.Value -lt $Min.Value) { $Max = $Min.Value.AddMinutes(1) }

    $localMin = $Min.Value; $localMax = $Max.Value; $t = 0.0
    switch ($Mode) {
      'Uniform'     { $t = [double]$rnd.NextDouble() }
      'RecentSkew'  { $alpha = [math]::Max(0.01, [double]$Bias / 100.0 * 4.0); $t = [math]::Pow($rnd.NextDouble(), 1.0 / (1.0 + $alpha)) }
      'YearSpread'  { $t = [double]$rnd.NextDouble(); if ($rnd.NextDouble() -lt 0.4) { $t = $t * 0.5 } }
      'LegacyMess'  {
        $r = $rnd.NextDouble()
        if     ($r -lt 0.10) { $localMin = (Get-Date '2000-01-01'); $localMax = (Get-Date '2009-12-31') }
        elseif ($r -lt 0.40) { $localMin = (Get-Date '2010-01-01'); $localMax = (Get-Date '2019-12-31') }
        else                 { $localMin = [datetime]::UtcNow.AddYears(-5); $localMax = [datetime]::UtcNow }
        $t = [double]$rnd.NextDouble()
      }
      default       { $t = [double]$rnd.NextDouble() }
    }
    if ($localMax -lt $localMin) { $localMax = $localMin.AddMinutes(1) }
    $span = ($localMax - $localMin).TotalSeconds
    if ($span -le 1) { return $localMax }
    
    # Calculate result and ensure it's valid
    $result = $localMin.AddSeconds($t * $span)
    if (-not $result -or $result -eq [datetime]::MinValue) { 
      $result = [datetime]::UtcNow 
    }
    return $result
  } catch {
    # Fallback to current time if anything goes wrong
    return [datetime]::UtcNow
  }
}

function Apply-Timestamps([string]$Path,[Nullable[datetime]]$BaseTime){
  try {
    # Ensure we have a valid BaseTime - convert to regular datetime
    $baseDateTime = if ($BaseTime -and $BaseTime.HasValue) { $BaseTime.Value } else { Get-Date }
    
    # Ensure baseDateTime is valid
    if (-not $baseDateTime -or $baseDateTime -eq [datetime]::MinValue) {
      $baseDateTime = Get-Date
    }

    $ct = $baseDateTime.AddMinutes(-($rnd.Next(0, 4320)))  # up to 3 days earlier
    $wt = $baseDateTime.AddMinutes($rnd.Next(0, 1440))     # within next 24h
    $at = $wt.AddMinutes($rnd.Next(0, 2880))               # up to 2 days after

    [IO.File]::SetCreationTime($Path, $ct)
    [IO.File]::SetLastWriteTime($Path, $wt)
    [IO.File]::SetLastAccessTime($Path, $at)
  } catch {
    Write-Verbose ("Timestamp set failed on {0}: {1}" -f $Path, $_.Exception.Message)
  }
}


# STRICT SPARSE CREATION — seek & poke (no SetLength())
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

# --- Collect folders
$rootItem = Get-Item -LiteralPath $Root -ErrorAction Stop
$folders = @($rootItem) + (Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
$totalTarget = if ($MaxFiles) { [int]$MaxFiles } else { ($folders.Count * 40) }
if ($totalTarget -lt 1) { $totalTarget = 1 }

$created = 0L
$start   = Get-Date
$folderIdx = 0

foreach ($dir in $folders) {
  $createdThisFolder = 0L
  $folderIdx++

  # Folder clutter (optional)
  if ($Clutter) {
    if ($rnd.NextDouble() -lt 0.25) { Set-Content -Path (Join-Path $dir.FullName 'desktop.ini') -Value "[.ShellClassInfo]" -Encoding ASCII -Force }
    if ($rnd.NextDouble() -lt 0.15) { New-Item -ItemType File -Path (Join-Path $dir.FullName 'Thumbs.db') -Force | Out-Null }
    if ($rnd.NextDouble() -lt 0.12) { New-Item -ItemType File -Path (Join-Path $dir.FullName ("~$temp{0:000}.tmp" -f $rnd.Next(0,999))) -Force | Out-Null }
    if ($rnd.NextDouble() -lt 0.05) { Set-Content -Path (Join-Path $dir.FullName ("link-{0}.url" -f $rnd.Next(1000,9999))) -Value "[InternetShortcut]`nURL=file://\\server\missing\doc.pdf" -Encoding ASCII }
  }

  $parts = $dir.FullName.Substring($Root.Length).Trim('\').Split('\')
  $dept  = if ($parts.Length -gt 0 -and $parts[0]) { $parts[0] } else { $null }
  $prefixes = if ($dept -and $DeptPrefixMap.ContainsKey($dept)) { $DeptPrefixMap[$dept] } else { $DeptPrefixMap['General'] }

  $n = $rnd.Next(8,90)  # messy count per folder
  for ($i=0; $i -lt $n; $i++) {
    if ($MaxFiles -and $created -ge $MaxFiles) { break }

    $ext  = Get-WeightedExt $dept
    $base = Get-RealisticBaseName $dept $prefixes
    $name = ("{0}-{1:0000}{2}" -f $base, $rnd.Next(0,10000), $ext)
    if ($rnd.NextDouble() -lt 0.08) { $name = $name.Replace($ext, (" (1){0}" -f $ext)) }  # dup flavor
    $file = Join-Path $dir.FullName $name
    if (Test-Path $file) {
      $file = Join-Path $dir.FullName ("dup-{0:0000}-{1}{2}" -f $rnd.Next(0,10000), $rnd.Next(1000,9999), $ext)
    }

    try {
      $kb = Get-RealisticKB $dept
      New-RealisticFile -Path $file -KB $kb

      if ($Touch) {
        try {
          # Build param splat only when bounds are present (avoid null->datetime conversion)
          $randParams = @{ Mode = $DatePreset; Bias = $RecentBias }
          if ($PSBoundParameters.ContainsKey('MinDate')) { $randParams.Min = $MinDate }
          if ($PSBoundParameters.ContainsKey('MaxDate')) { $randParams.Max = $MaxDate }
          $baseTime = Get-RandomDate @randParams
          Apply-Timestamps -Path $file -BaseTime $baseTime
        } catch {
          Write-Verbose ("Timestamp generation failed for {0}: {1}" -f $file, $_.Exception.Message)
          # Fallback to current time
          Apply-Timestamps -Path $file -BaseTime (Get-Date)
        }
      }

      # Ownership realism (optional)
      if ($UseAD -and $dept -and $UserOwnership) {
        try {
          $Domain = (Get-ADDomain).NetBIOSName
          $rng = $rnd.NextDouble()
          if ($rng -lt 0.18) {
            # ~18% owned by random dept user
            $prefix = $dept.Substring(0, [Math]::Min(4,$dept.Length)).ToLower()
            $users = Get-ADUser -LDAPFilter ("(sAMAccountName={0}*)" -f $prefix) -SearchBase (Get-ADDomain).DistinguishedName -ErrorAction SilentlyContinue
            if ($users) {
              $sam = ($users | Get-Random).SamAccountName
              try { Set-OwnerAndGroup -Path $file -Owner ("{0}\{1}" -f $Domain, $sam) } catch {}
            }
          } else {
            # rest owned by GG_<Dept>
            try { Set-OwnerAndGroup -Path $file -Owner ("{0}\GG_{1}" -f $Domain, $dept) } catch {}
          }
        } catch {}
      }

      Set-RandomAttributes -Path $file
      if ($ADS -and ($rnd.NextDouble() -lt 0.05)) {
        Add-ADS -Path $file -Name "meta.tag" -Content ("dept={0};created={1:o}" -f $dept,(Get-Date))
      }

      $created++
      if (($created % $ProgressUpdateEvery) -eq 0) {
        $elapsed = ((Get-Date) - $start).TotalSeconds
        $rate    = if ($elapsed -gt 0) { $created / $elapsed } else { 0 }
        $etaSec  = if ($MaxFiles) { [math]::Max(0, ($MaxFiles - $created) / ($rate + 0.0001)) } else { 0 }
        $pct     = if ($MaxFiles) { [int](100 * $created / [double]$MaxFiles) } else { [int](100 * ($folderIdx / [double]$folders.Count)) }
        $status  = if ($MaxFiles) { ("Files: {0} / {1} (~{2:N1}/s)" -f $created, $MaxFiles, $rate) } else { ("Folder {0} / {1} — Files: {2} (~{3:N1}/s)" -f $folderIdx, $folders.Count, $created, $rate) }
        $detail  = if ($MaxFiles) { ("ETA: ~{0:N0}s" -f $etaSec) } else { "ETA: estimating…" }
        Write-Progress -Activity ("Generating files (sparse: True; AD used: {0})" -f $UseAD) -Status $status -CurrentOperation $detail -PercentComplete $pct
      }
    } catch {
      Write-Warning ("File create failed for {0}: {1}" -f $file, $_.Exception.Message)
      continue
    }
  }

  if ($PSBoundParameters.ContainsKey('Verbose')) {
    Write-Verbose ("Folder '{0}' processed." -f $dir.FullName)
  }

  if ($MaxFiles -and $created -ge $MaxFiles) { break }
}

Write-Progress -Activity "Generating files" -Completed
$elapsed = ((Get-Date) - $start)
if ($created -eq 0) {
  Write-Warning "No files were created. Check -Root, permissions, and sparse support on the backend."
}
Write-Host ("Created {0} files under {1} in {2:mm\:ss} (sparse: True; AD used: {3}; touch: {4}, preset: {5})" -f $created,$Root,$elapsed,$UseAD,$Touch,$DatePreset) -ForegroundColor Cyan

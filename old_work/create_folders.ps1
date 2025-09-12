# create-folders_v2.ps1
<#
.SYNOPSIS
  Build an enterprise-like departmental folder tree under S:\Shared (or custom Root),
  create/update the SMB share, and apply NTFS ACLs. Prefers AGDLP (DL_Share_*) if present,
  falls back to GG_* groups. PowerShell 5.1+ and 7.x safe.

.PREREQS
  - Run the AD populator first (ad-populator.ps1 recommended).
  - Run PowerShell as Domain Admin.
  - set_privs.psm1 in same folder (for SeRestore/SeTakeOwnership + ACL helpers).
  - In PowerShell 7.x, import Windows modules via the compatibility shim:
      Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
      Import-Module SmbShare -SkipEditionCheck -ErrorAction Stop

.EXAMPLE
  .\create_folders.ps1 -UseDomainLocal
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [string[]]$Departments = @("Finance","HR","Engineering","Sales","Legal","IT","Ops"),
  [string]$Domain = (Get-ADDomain).NetBIOSName,
  [string]$ShareName = "Shared",
  [switch]$CreateShare = $true,
  [switch]$UseDomainLocal
)

Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
# Dot-source the privilege/ACL helpers
. (Join-Path $PSScriptRoot 'set_privs.psm1')

# ---------- Helpers ----------
function Ensure-Folder {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    $drive = (Split-Path -Path $Path -Qualifier)
    if ($drive -and -not (Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction SilentlyContinue)) {
      throw "Drive $drive not found. Attach/mount it or change -Root."
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Ensure-SmbShare {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Path,
    [string]$Domain = (Get-ADDomain).NetBIOSName
  )
  $existing = Get-SmbShare -Name $Name -ErrorAction SilentlyContinue
  if (-not $existing) {
    New-SmbShare -Name $Name -Path $Path -CachingMode Documents -Description "Demo enterprise share" `
      -FullAccess "$Domain\Domain Admins" `
      -ReadAccess "$Domain\GG_AllEmployees" | Out-Null
  } else {
    try { Grant-SmbShareAccess -Name $Name -AccountName "$Domain\Domain Admins" -AccessRight Full -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Grant-SmbShareAccess -Name $Name -AccountName "$Domain\GG_AllEmployees" -AccessRight Read -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Revoke-SmbShareAccess -Name $Name -AccountName "Everyone" -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
  }
}

# PS-safe AD group lookup by sAMAccountName
function Test-AdGroupBySam {
  param([Parameter(Mandatory)][string]$Sam)
  try { return [bool](Get-ADGroup -LDAPFilter "(sAMAccountName=$Sam)" -ErrorAction SilentlyContinue) }
  catch { return $false }
}

# Resolve dept principals (DL_Share_* preferred when -UseDomainLocal and DLs exist; safe fallbacks)
function Resolve-DeptPrincipals {
  param(
    [Parameter(Mandatory)][string]$Dept,
    [string]$Domain = (Get-ADDomain).NetBIOSName,
    [switch]$PreferDomainLocal
  )

  # Candidate SamAccountNames
  $ggDeptSam = "GG_${Dept}"
  $ggROSam   = "GG_${Dept}_RO"
  $ggRWSam   = "GG_${Dept}_RW"
  $ggOwnSam  = "GG_${Dept}_Owners"

  $dlROSam   = "DL_Share_${Dept}_RO"
  $dlRWSam   = "DL_Share_${Dept}_RW"
  $dlOwnSam  = "DL_Share_${Dept}_Owners"

  function Test-Group { param($Sam) try { Get-ADGroup -LDAPFilter "(sAMAccountName=$Sam)" -ErrorAction SilentlyContinue } catch {} }

  $hasDL = (Test-Group $dlROSam) -and (Test-Group $dlRWSam) -and (Test-Group $dlOwnSam)
  $useDL = ($PreferDomainLocal -and $hasDL)

  # Start building resolved identities
  $ggDept = if (Test-Group $ggDeptSam) { "$Domain\$ggDeptSam" } else { $null }

  $RO = $null
  $RW = $null
  $Owners = $null

  if ($useDL) {
    $RO     = "$Domain\$dlROSam"
    $RW     = "$Domain\$dlRWSam"
    $Owners = "$Domain\$dlOwnSam"
  } else {
    if (Test-Group $ggROSam)  { $RO = "$Domain\$ggROSam" }
    if (Test-Group $ggRWSam)  { $RW = "$Domain\$ggRWSam" }
    if (Test-Group $ggOwnSam) { $Owners = "$Domain\$ggOwnSam" }
  }

  # Fallbacks: make sure none are empty
  if (-not $RW)     { $RW = $ggDept }                    # at minimum, dept group gets Modify
  if (-not $RO)     { $RO = "$Domain\GG_AllEmployees" }  # baseline read
  if (-not $Owners) { $Owners = "$Domain\Domain Admins" }

  return [pscustomobject]@{
    UseDL  = $useDL
    DeptGG = $ggDept
    RO     = $RO
    RW     = $RW
    Owners = $Owners
  }
}

# ---------- Build root + share ----------
Ensure-Folder -Path $Root

if ($CreateShare) {
  Ensure-SmbShare -Name $ShareName -Path $Root -Domain $Domain
}

# Baseline NTFS: AllEmployees read at root (simulate broad read), inherited to children
$allEmployees = "$Domain\GG_AllEmployees"
Grant-FsAccess -Path $Root -Identity $allEmployees -Rights 'ReadAndExecute' -InheritToChildren

# ---------- Department trees ----------
$rand = New-Object System.Random

foreach ($d in $Departments) {
  $deptPath = Join-Path $Root $d
  Ensure-Folder -Path $deptPath

  $principals = Resolve-DeptPrincipals -Dept $d -Domain $Domain -PreferDomainLocal:$UseDomainLocal

  # Owner: GG_<Dept> if it exists, else Owners principal; SD.Group = Domain Admins (mostly unused)
  $owner = if ($principals.DeptGG) { $principals.DeptGG } else { $principals.Owners }
  Set-OwnerAndGroup -Path $deptPath -Owner $owner -Group "$Domain\Domain Admins"

  # Block inheritance at dept root; grant RW/RO/Owners
  Grant-FsAccess -Path $deptPath -Identity $principals.RW     -Rights 'Modify'        -BreakInheritance -CopyInheritance
  Grant-FsAccess -Path $deptPath -Identity $principals.RO     -Rights 'ReadAndExecute'
  Grant-FsAccess -Path $deptPath -Identity $principals.Owners -Rights 'FullControl'

  # Standard substructure
  $subs = @('Projects','Archive','Temp','Sensitive','Vendors')
  foreach ($s in $subs) {
    $p = Join-Path $deptPath $s
    Ensure-Folder -Path $p

    # Randomly break inheritance to create "messy" areas
    if ($rand.Next(0,2) -eq 1) {
      Grant-FsAccess -Path $p -Identity $principals.RW -Rights 'Modify' -BreakInheritance -CopyInheritance
    } else {
      Grant-FsAccess -Path $p -Identity $principals.RW -Rights 'Modify'
    }

    if ($s -eq 'Sensitive') {
      # Remove broad read at NTFS on Sensitive (if it slipped in), then ThisFolderOnly scoped rights
      $acl = Get-Acl $p
      $acl.Access | Where-Object {
        $_.IdentityReference -like '*Everyone' -or $_.IdentityReference -eq $allEmployees
      } | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
      Set-Acl $p $acl

      foreach ($tuple in @(
        @{id=$principals.Owners; rights='FullControl'},
        @{id=$principals.RW;     rights='Modify'},
        @{id=$principals.RO;     rights='ReadAndExecute'}
      )) {
        if ($tuple.id) { Grant-FsAccess -Path $p -Identity $tuple.id -Rights $tuple.rights -ThisFolderOnly }
      }
    }
  }

  # Sprinkle a Deny to simulate trouble tickets (on Temp)
  $temp = Join-Path $deptPath "Temp"
  if (Test-Path $temp) {
    Grant-FsAccess -Path $temp -Identity $principals.RO -Rights 'Write' -Type 'Deny' -ThisFolderOnly
  }
}

Write-Host "Folder tree created & ACLed at $Root" -ForegroundColor Green
if ($CreateShare) {
  try {
    $sh = Get-SmbShare | Where-Object { $_.Path -eq $Root } | Select-Object -First 1
    if ($sh) {
      Write-Host ("Share: \\$env:COMPUTERNAME\{0}" -f $sh.Name) -ForegroundColor Cyan
      Get-SmbShareAccess -Name $sh.Name | Format-Table -Auto
    }
  } catch {}
}

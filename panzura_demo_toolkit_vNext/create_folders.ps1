# create_folders.ps1
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
  [string[]]$Departments = @("Finance","HR","Engineering","Sales","Legal","IT","Ops","Marketing"),
  [string]$Domain = (Get-ADDomain).NetBIOSName,
  [string]$ShareName = "Shared",
  [switch]$CreateShare = $true,
  [switch]$UseDomainLocal
)

Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
# Dot-source the privilege/ACL helpers
. (Join-Path $PSScriptRoot 'set_privs.psm1')

# ---------- Helper Functions ----------
function Set-RealisticFolderTimestamps {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$FolderType = "Standard"
  )
  
  $rand = New-Object System.Random
  $now = Get-Date
  
  # Different timestamp patterns based on folder type
  switch ($FolderType) {
    "Year" {
      # Year folders: created at start of year, modified throughout
      $year = [int](Split-Path $Path -Leaf)
      $created = Get-Date "$year-01-01"
      $modified = $created.AddDays($rand.Next(0, 365))
      $accessed = $modified.AddDays($rand.Next(0, 30))
    }
    "Project" {
      # Project folders: created 1-3 years ago, modified recently
      $created = $now.AddDays(-$rand.Next(365, 1095))
      $modified = $now.AddDays(-$rand.Next(0, 90))
      $accessed = $modified.AddDays($rand.Next(0, [Math]::Min(7, ($now - $modified).Days)))
    }
    "Archive" {
      # Archive folders: old creation, infrequent access
      $created = $now.AddDays(-$rand.Next(1095, 2190))
      $modified = $created.AddDays($rand.Next(0, [Math]::Min(365, ($now - $created).Days)))
      $accessed = $modified.AddDays($rand.Next(0, [Math]::Min(180, ($now - $modified).Days)))
    }
    "Duplicate" {
      # Duplicate folders: created when original was copied
      $created = $now.AddDays(-$rand.Next(30, 365))
      $modified = $created.AddDays($rand.Next(0, [Math]::Min(30, ($now - $created).Days)))
      $accessed = $modified.AddDays($rand.Next(0, [Math]::Min(14, ($now - $modified).Days)))
    }
    default {
      # Standard folders: mixed ages (ensure no future dates)
      $created = $now.AddDays(-$rand.Next(365, 1095))  # 1-3 years ago
      $modified = $created.AddDays($rand.Next(0, [Math]::Min(365, ($now - $created).Days)))
      $accessed = $modified.AddDays($rand.Next(0, [Math]::Min(30, ($now - $modified).Days)))
    }
  }
  
  try {
    [IO.Directory]::SetCreationTime($Path, $created)
    [IO.Directory]::SetLastWriteTime($Path, $modified)
    [IO.Directory]::SetLastAccessTime($Path, $accessed)
  } catch {
    # Silently continue if timestamp setting fails
  }
}

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

# ---------- Cross-department folders ----------
$crossDeptFolders = @('Shared','Inter-Department','External','Common','Cross-Functional','Collaboration')
foreach ($crossDept in $crossDeptFolders) {
  if ($rand.Next(0,3) -eq 0) {  # 33% chance per cross-dept folder
    $crossPath = Join-Path $Root $crossDept
    Ensure-Folder -Path $crossPath
    Grant-FsAccess -Path $crossPath -Identity $allEmployees -Rights 'Modify' -BreakInheritance -CopyInheritance
    Grant-FsAccess -Path $crossPath -Identity "$Domain\Domain Admins" -Rights 'FullControl'
    Set-RealisticFolderTimestamps -Path $crossPath -FolderType "Standard"
  }
}

foreach ($d in $Departments) {
  $deptPath = Join-Path $Root $d
  Ensure-Folder -Path $deptPath
  Set-RealisticFolderTimestamps -Path $deptPath -FolderType "Standard"

  $principals = Resolve-DeptPrincipals -Dept $d -Domain $Domain -PreferDomainLocal:$UseDomainLocal

  # Owner: GG_<Dept> if it exists, else Owners principal; SD.Group = Domain Admins (mostly unused)
  $owner = if ($principals.DeptGG) { $principals.DeptGG } else { $principals.Owners }
  Set-OwnerAndGroup -Path $deptPath -Owner $owner -Group "$Domain\Domain Admins"

  # Block inheritance at dept root; grant RW/RO/Owners
  Grant-FsAccess -Path $deptPath -Identity $principals.RW     -Rights 'Modify'        -BreakInheritance -CopyInheritance
  Grant-FsAccess -Path $deptPath -Identity $principals.RO     -Rights 'ReadAndExecute'
  Grant-FsAccess -Path $deptPath -Identity $principals.Owners -Rights 'FullControl'

  # Enhanced realistic substructure
  $subs = @('Current','Drafts','Final','Backup','Old','Projects','Archive','Temp','Sensitive','Vendors')
  foreach ($s in $subs) {
    $p = Join-Path $deptPath $s
    Ensure-Folder -Path $p

    # Randomly break inheritance to create "messy" areas
    if ($rand.Next(0,2) -eq 1) {
      Grant-FsAccess -Path $p -Identity $principals.RW -Rights 'Modify' -BreakInheritance -CopyInheritance
    } else {
      Grant-FsAccess -Path $p -Identity $principals.RW -Rights 'Modify'
    }
    
    # Set realistic timestamps based on folder type
    $folderType = if ($s -eq 'Archive') { "Archive" } else { "Standard" }
    Set-RealisticFolderTimestamps -Path $p -FolderType $folderType

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

  # Add year-based organization (2020-2025)
  $years = @('2020','2021','2022','2023','2024','2025')
  foreach ($year in $years) {
    if ($rand.Next(0,3) -eq 0) {  # 33% chance per year
      $yearPath = Join-Path $deptPath $year
      Ensure-Folder -Path $yearPath
      Grant-FsAccess -Path $yearPath -Identity $principals.RW -Rights 'Modify'
      Set-RealisticFolderTimestamps -Path $yearPath -FolderType "Year"
    }
  }

  # Add project-specific folders with realistic names
  $projectNames = @('Project_Alpha','Project_Beta','Project_Gamma','Project_Delta','Project_Echo',
                   'Q4_2024_Initiatives','Annual_Review_2024','Budget_Planning_2025','Compliance_Audit_2024',
                   'Digital_Transformation','Infrastructure_Upgrade','Security_Assessment','Process_Improvement')
  
  foreach ($proj in $projectNames) {
    if ($rand.Next(0,4) -eq 0) {  # 25% chance per project
      $projPath = Join-Path $deptPath $proj
      Ensure-Folder -Path $projPath
      Grant-FsAccess -Path $projPath -Identity $principals.RW -Rights 'Modify'
      Set-RealisticFolderTimestamps -Path $projPath -FolderType "Project"
      
      # Add subfolders to some projects (deep nesting)
      if ($rand.Next(0,3) -eq 0) {
        $projSubs = @('Planning','Execution','Review','Documentation','Resources')
        foreach ($projSub in $projSubs) {
          if ($rand.Next(0,2) -eq 0) {  # 50% chance per subfolder
            $projSubPath = Join-Path $projPath $projSub
            Ensure-Folder -Path $projSubPath
            Grant-FsAccess -Path $projSubPath -Identity $principals.RW -Rights 'Modify'
            Set-RealisticFolderTimestamps -Path $projSubPath -FolderType "Standard"
            
            # Even deeper nesting for some folders
            if ($rand.Next(0,4) -eq 0) {  # 25% chance for deeper nesting
              $deepSubs = @('Draft','Final','Archive','Backup')
              foreach ($deepSub in $deepSubs) {
                if ($rand.Next(0,2) -eq 0) {
                  $deepPath = Join-Path $projSubPath $deepSub
                  Ensure-Folder -Path $deepPath
                  Grant-FsAccess -Path $deepPath -Identity $principals.RW -Rights 'Modify'
                  Set-RealisticFolderTimestamps -Path $deepPath -FolderType "Standard"
                }
              }
            }
          }
        }
      }
    }
  }

  # Add duplicate structures (multiple versions)
  if ($rand.Next(0,3) -eq 0) {  # 33% chance for duplicates
    $duplicateNames = @('_Backup','_Old','_Archive','_Copy','_v2','_2024','_Legacy')
    foreach ($dup in $duplicateNames) {
      if ($rand.Next(0,2) -eq 0) {  # 50% chance per duplicate type
        $dupPath = Join-Path $deptPath "${d}${dup}"
        Ensure-Folder -Path $dupPath
        Grant-FsAccess -Path $dupPath -Identity $principals.RW -Rights 'Modify'
        Set-RealisticFolderTimestamps -Path $dupPath -FolderType "Duplicate"
      }
    }
  }

  # Add naming convention chaos (useful for Panzura scanning)
  if ($rand.Next(0,4) -eq 0) {  # 25% chance for naming chaos
    $namingChaos = @(
      # Legacy naming conventions
      "OLD_${d}", "LEGACY_${d}", "DEPRECATED_${d}",
      # Mixed case variations
      "${d}_MIXED", "${d}_lower", "${d}_UPPER",
      # Special character variations
      "${d}-Dept", "${d}_Dept", "${d}.Dept", "${d} Dept"
    )
    
    # Add department-specific abbreviation variations
    switch ($d) {
      "HR" { $namingChaos += @("HumanResources", "H.R.", "Human_Resources") }
      "IT" { $namingChaos += @("InformationTechnology", "I.T.", "InfoTech") }
      "Marketing" { $namingChaos += @("MKT", "MKTG", "Marketing_Dept") }
      "Finance" { $namingChaos += @("FIN", "FINANCE", "Financial") }
      "Engineering" { $namingChaos += @("ENG", "ENGINEERING", "Engineering_Dept") }
      "Sales" { $namingChaos += @("SALES", "Sales_Dept", "Sales_Team") }
      "Ops" { $namingChaos += @("OPS", "OPERATIONS", "Ops_Dept") }
      "Legal" { $namingChaos += @("LEGAL", "Legal_Dept", "Legal_Team") }
    }
    
    foreach ($chaos in $namingChaos) {
      if ($chaos -and $rand.Next(0,3) -eq 0) {  # 33% chance per chaos type
        $chaosPath = Join-Path $Root $chaos
        Ensure-Folder -Path $chaosPath
        Grant-FsAccess -Path $chaosPath -Identity $principals.RW -Rights 'Modify'
        Set-RealisticFolderTimestamps -Path $chaosPath -FolderType "Standard"
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

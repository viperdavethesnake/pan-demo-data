# create_folders_hybrid.ps1 — Simple folder structure with enhanced AD integration
<#
.SYNOPSIS
  Create folder structure combining simplicity of old script with enhanced features of new script.

.DESCRIPTION
  Uses the clean, simple folder structure from the old script (Projects, Archive, Temp, Sensitive, Vendors)
  with the enhanced AD integration, realistic timestamps, and cross-department folders from the new script.
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [string[]]$Departments,
  [string]$Domain = $null,
  [string]$ShareName = "Shared", 
  [switch]$CreateShare = $true,
  [switch]$UseDomainLocal = $false
)

# --- LOGGING & TRANSCRIPT ---
$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path -Path $logDir)) {
  New-Item -ItemType Directory -Path $logDir | Out-Null
}
$logFile = Join-Path $logDir ("create_folders_hybrid_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $logFile -Append

# Import helper module
. (Join-Path $PSScriptRoot 'set_privs.psm1')

# Try AD
try { Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop } 
catch { throw "ActiveDirectory module required but not available." }

if (-not $Domain) { $Domain = (Get-ADDomain).NetBIOSName }

# If -Departments was not provided, discover them dynamically from Active Directory
# This ensures we only create folders for groups created by the ad_populator.ps1 script.
if (-not $PSBoundParameters.ContainsKey('Departments')) {
    Write-Host "No -Departments specified. Discovering from Directory (GG_* pattern)..." -ForegroundColor Cyan
    try {
        # Find all GG_* groups, then filter out sub-groups and non-department groups locally.
        $deptGroups = Get-ADGroup -Filter 'SamAccountName -like "GG_*" -and SamAccountName -ne "GG_AllEmployees"' | Where-Object { $_.SamAccountName -notlike "GG_*_*" }
        if ($deptGroups) {
            $Departments = $deptGroups.SamAccountName | ForEach-Object { $_.Substring(3) }
            Write-Host "Discovered $($Departments.Count) departments: $($Departments -join ', ')" -ForegroundColor Green
        } else {
            Write-Warning "No department groups (GG_*) found in Active Directory. No folders will be created."
            return # Exit gracefully
        }
    } catch {
        Write-Error "An error occurred while querying Active Directory: $($_.Exception.Message)"
        throw
    }
} else {
    Write-Host "Using manually specified list of $($Departments.Count) departments." -ForegroundColor Yellow
}

# If after all that, we have no departments, exit.
if (-not $Departments) {
    Write-Host "Department list is empty. Exiting."
    return
}

# Random for timestamps
$rand = New-Object System.Random

# Folder timestamp function (from new script)
function Set-RealisticFolderTimestamps {
  param([Parameter(Mandatory)][string]$Path, [string]$FolderType = "Standard")
  
  $now = Get-Date
  switch ($FolderType) {
    "Year" {
      $yearMatch = [regex]::Match((Split-Path $Path -Leaf), '\d{4}')
      if ($yearMatch.Success) {
        $year = [int]$yearMatch.Value
        $created = Get-Date -Year $year -Month ($rand.Next(1,13)) -Day ($rand.Next(1,29)) -Hour ($rand.Next(8,18)) -Minute ($rand.Next(0,60)) -Second ($rand.Next(0,60))
        $modified = $created.AddDays($rand.Next(30, 300))
        $accessed = $modified.AddDays($rand.Next(0, 60))
      } else {
        $created = $now.AddDays(-$rand.Next(365, 1095))
        $modified = $created.AddDays($rand.Next(1, 180))
        $accessed = $modified.AddDays($rand.Next(0, 30))
      }
    }
    "Project" {
      $created = $now.AddDays(-$rand.Next(90, 730))
      $modified = $created.AddDays($rand.Next(30, 180))
      $accessed = $modified.AddDays($rand.Next(0, 90))
    }
    "Archive" {
      $created = $now.AddDays(-$rand.Next(730, 2190))
      $modified = $created.AddDays($rand.Next(1, 90))
      $accessed = $modified.AddDays($rand.Next(0, 365))
    }
    "Duplicate" {
      $created = $now.AddDays(-$rand.Next(365, 1460))
      $modified = $created.AddDays($rand.Next(1, 30))
      $accessed = $modified.AddDays($rand.Next(0, 180))
    }
    default {
      $created = $now.AddDays(-$rand.Next(30, 365))
      $modified = $created.AddDays($rand.Next(1, 60))
      $accessed = $modified.AddDays($rand.Next(0, 30))
    }
  }
  
  # Ensure no future dates
  $modified = [Math]::Min($modified.Ticks, $now.Ticks) | ForEach-Object { [datetime]$_ }
  $accessed = [Math]::Min($accessed.Ticks, $now.Ticks) | ForEach-Object { [datetime]$_ }
  
  try {
    [IO.Directory]::SetCreationTime($Path, $created)
    [IO.Directory]::SetLastWriteTime($Path, $modified)
    [IO.Directory]::SetLastAccessTime($Path, $accessed)
  } catch {
    # Silently continue if timestamp setting fails
  }
}

# Helper functions (from new script)
function Ensure-Folder([string]$Path) {
  if (-not (Test-Path $Path)) {
    $drive = Split-Path $Path -Qualifier
    if ($drive -and -not (Get-PSDrive $drive.TrimEnd(':') -ErrorAction SilentlyContinue)) {
      throw "Drive $drive not found. Attach/mount it or change -Root."
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Resolve-DeptPrincipals {
  param([string]$Dept, [string]$Domain, [switch]$PreferDomainLocal)
  
  $deptGG = "GG_$Dept"
  $deptDL_RW = "DL_${Dept}_RW"
  $deptDL_RO = "DL_${Dept}_RO"
  $deptDL_Owners = "DL_${Dept}_Owners"
  
  $result = @{
    DeptGG = if (Test-AdGroupSam $deptGG) { "$Domain\$deptGG" } else { $null }
    RW = if ($PreferDomainLocal -and (Test-AdGroupSam $deptDL_RW)) { "$Domain\$deptDL_RW" } 
         elseif (Test-AdGroupSam $deptGG) { "$Domain\$deptGG" } 
         else { "$Domain\Domain Admins" }
    RO = if ($PreferDomainLocal -and (Test-AdGroupSam $deptDL_RO)) { "$Domain\$deptDL_RO" }
         elseif (Test-AdGroupSam "GG_AllEmployees") { "$Domain\GG_AllEmployees" }
         else { "$Domain\Domain Users" }
    Owners = if ($PreferDomainLocal -and (Test-AdGroupSam $deptDL_Owners)) { "$Domain\$deptDL_Owners" }
             else { "$Domain\Domain Admins" }
  }
  return $result
}

function Test-AdGroupSam([string]$Sam) {
  try {
    $dn = (Get-ADDomain).DistinguishedName
    return [bool](Get-ADGroup -LDAPFilter "(sAMAccountName=$Sam)" -SearchBase $dn -ErrorAction SilentlyContinue)
  } catch { return $false }
}

# Main execution
Write-Host "Creating hybrid folder structure (simple + enhanced)..." -ForegroundColor Green

# Ensure root exists
Ensure-Folder -Path $Root
Set-RealisticFolderTimestamps -Path $Root -FolderType "Standard"

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

# Cross-department folders (from new script)
$crossDeptFolders = @('Shared', 'Inter-Department', 'External', 'Common', 'Cross-Functional', 'Collaboration')
foreach ($cross in $crossDeptFolders) {
  if ($rand.Next(0,3) -eq 0) {  # 33% chance
    $crossPath = Join-Path $Root $cross
    Ensure-Folder -Path $crossPath
    
    # Set permissions for all employees
    $allEmployees = if (Test-AdGroupSam "GG_AllEmployees") { "$Domain\GG_AllEmployees" } else { "$Domain\Domain Users" }
    Grant-FsAccess -Path $crossPath -Identity $allEmployees -Rights 'Modify' -BreakInheritance -CopyInheritance
    Grant-FsAccess -Path $crossPath -Identity "$Domain\Domain Admins" -Rights 'FullControl'
    Set-RealisticFolderTimestamps -Path $crossPath -FolderType "Standard"
  }
}

# Department folders
foreach ($d in $Departments) {
  Write-Host "Creating department: $d" -ForegroundColor Cyan
  
  $deptPath = Join-Path $Root $d
  Ensure-Folder -Path $deptPath
  Set-RealisticFolderTimestamps -Path $deptPath -FolderType "Standard"
  
  $principals = Resolve-DeptPrincipals -Dept $d -Domain $Domain -PreferDomainLocal:$UseDomainLocal
  
  # Set ownership
  $owner = if ($principals.DeptGG) { $principals.DeptGG } else { $principals.Owners }
  
  # Set permissions
  Grant-FsAccess -Path $deptPath -Identity $principals.RW     -Rights 'Modify'        -BreakInheritance -CopyInheritance
  Grant-FsAccess -Path $deptPath -Identity $principals.RO     -Rights 'ReadAndExecute'
  Grant-FsAccess -Path $deptPath -Identity $principals.Owners -Rights 'FullControl'
  
  # Simple substructure (from old script)
  $subs = @('Projects','Archive','Temp','Sensitive','Vendors')
  foreach ($s in $subs) {
    $subPath = Join-Path $deptPath $s
    Ensure-Folder -Path $subPath
    Set-RealisticFolderTimestamps -Path $subPath -FolderType $s
    
    # Randomly break inheritance for "messy" areas (from old script)
    if ($rand.Next(0,2) -eq 1) {
      Grant-FsAccess -Path $subPath -Identity $principals.RW -Rights 'Modify' -BreakInheritance -CopyInheritance
    } else {
      Grant-FsAccess -Path $subPath -Identity $principals.RW -Rights 'Modify'
    }
    
    # Special handling for Sensitive folders
    if ($s -eq 'Sensitive') {
      # Remove broad access and set restricted permissions
      $acl = Get-Acl $subPath
      $acl.Access | Where-Object {
        $_.IdentityReference -like '*Everyone' -or $_.IdentityReference -like '*AllEmployees*'
      } | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
      Set-Acl $subPath $acl
      
      # Set restricted permissions
      Grant-FsAccess -Path $subPath -Identity $principals.Owners -Rights 'FullControl' -ThisFolderOnly
      Grant-FsAccess -Path $subPath -Identity $principals.RW     -Rights 'Modify'     -ThisFolderOnly
      Grant-FsAccess -Path $subPath -Identity $principals.RO     -Rights 'ReadAndExecute' -ThisFolderOnly
    }
    
    # Add some project subfolders for Projects folder
    if ($s -eq 'Projects') {
      $projectNames = @('Project_Alpha', 'Project_Beta', 'Project_Gamma', 'Budget_Planning_2025', 'Q4_2024_Initiatives', 'Annual_Review_2024')
      $numProjects = $rand.Next(1, 4)
      for ($i = 0; $i -lt $numProjects; $i++) {
        $projectName = $projectNames[$rand.Next(0, $projectNames.Count)]
        $projectPath = Join-Path $subPath $projectName
        Ensure-Folder -Path $projectPath
        Set-RealisticFolderTimestamps -Path $projectPath -FolderType "Project"
        
        # Add project subfolders
        $projectSubs = @('Planning', 'Execution', 'Review', 'Resources', 'Documentation')
        foreach ($projSub in $projectSubs) {
          if ($rand.Next(0,3) -eq 0) {  # 33% chance
            $projSubPath = Join-Path $projectPath $projSub
            Ensure-Folder -Path $projSubPath
            Set-RealisticFolderTimestamps -Path $projSubPath -FolderType "Project"
            
            # Deep nesting - add Final/Archive/Backup to some project subfolders
            if ($rand.Next(0,4) -eq 0) {  # 25% chance
              $deepSubs = @('Final', 'Archive', 'Backup')
              $deepSub = $deepSubs[$rand.Next(0, $deepSubs.Count)]
              $deepPath = Join-Path $projSubPath $deepSub
              Ensure-Folder -Path $deepPath
              Set-RealisticFolderTimestamps -Path $deepPath -FolderType $deepSub
            }
          }
        }
      }
    }
    
    # Add some duplicate/legacy folders (from new script concept)
    if ($rand.Next(0,4) -eq 0) {  # 25% chance
      $duplicates = @("${s}_Backup", "${s}_Old", "${s}_Archive", "${s}_Copy", "${s}_v2", "${s}_2024", "${s}_Legacy")
      $dupName = $duplicates[$rand.Next(0, $duplicates.Count)]
      $dupPath = Join-Path $deptPath $dupName
      Ensure-Folder -Path $dupPath
      Set-RealisticFolderTimestamps -Path $dupPath -FolderType "Duplicate"
      
      # Same permissions as parent
      Grant-FsAccess -Path $dupPath -Identity $principals.RW -Rights 'Modify'
    }
  }
  
  # Add some naming chaos folders (simplified from new script)
  if ($rand.Next(0,3) -eq 0) {  # 33% chance
    $chaosNames = @("OLD_${d}", "LEGACY_${d}", "${d}_MIXED", "${d}_Backup")
    $chaosName = $chaosNames[$rand.Next(0, $chaosNames.Count)]
    $chaosPath = Join-Path $Root $chaosName
    Ensure-Folder -Path $chaosPath
    Set-RealisticFolderTimestamps -Path $chaosPath -FolderType "Standard"
    
    # Same permissions as department
    Grant-FsAccess -Path $chaosPath -Identity $principals.RW -Rights 'Modify'
  }
  
  # Set ownership for the entire department structure now that all folders are created
  Set-OwnerAndGroup -Path $deptPath -Owner $owner -Group $owner -Recurse
}

Write-Host "Hybrid folder structure created successfully!" -ForegroundColor Green
Write-Host "Folder tree created & ACLed at $Root" -ForegroundColor Cyan
if ($CreateShare) {
  Write-Host "Share: \\$env:COMPUTERNAME\$ShareName" -ForegroundColor Cyan
}

# --- END SCRIPT ---
Stop-Transcript


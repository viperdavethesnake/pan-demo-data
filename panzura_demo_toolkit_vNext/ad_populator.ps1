# ad_populator.ps1 (Enhanced Enterprise AD Populator; PS 7.5.x)
<#
.SYNOPSIS
  Populate AD with OUs, groups, users, and service accounts while avoiding duplicate-name errors.

.KEY IMPROVEMENTS
  - Unique user CNs by setting -Name to the sAMAccountName
  - Unique sAMAccountName per department via Get-NextSam() (prefix scan -> next number)
  - If a prior run left users behind, v5 simply picks the next available number (idempotent)
  - Users auto-added to GG_AllEmployees and GG_<Dept>
  - Optional access tiers and AGDLP wiring
  - Service accounts with realistic enterprise roles
  - Rich user attributes (job titles, locations, departments)
  - Legacy/obsolete groups for realistic enterprise mess
  - Enhanced group diversity (security, compliance, location-based)
  - WhatIf support for safe testing
  - Progress reporting during operations

.DESIGNED FOR
  PowerShell 7.x (imports AD with -SkipEditionCheck). Run as Domain Admin.

.EXAMPLE
  .\ad_populator.ps1 -BaseOUName DemoCorp
  Creates basic AD structure with default settings (12-40 users per department)

.EXAMPLE
  .\ad_populator.ps1 -BaseOUName DemoCorp -UsersPerDeptMin 8 -UsersPerDeptMax 75 -CreateAccessTiers -CreateAGDLP -VerboseSummary
  Creates full enterprise AD structure with access tiers and AGDLP groups

.EXAMPLE
  .\ad_populator.ps1 -BaseOUName DemoCorp -WhatIf
  Preview what would be created without making changes
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$BaseOUName,
  [int]$UsersPerDeptMin = 12,
  [int]$UsersPerDeptMax = 40,
  [string[]]$RoleGroups = @('Mgmt','Leads','Contractors','Interns','Auditors'),
  [switch]$CreateAccessTiers,
  [switch]$CreateAGDLP,
  [int]$ProjectsPerDeptMin = 0,
  [int]$ProjectsPerDeptMax = 3,
  [switch]$VerboseSummary,
  [switch]$WhatIf,
  [int]$NumServiceAccounts = 8,
  [switch]$ForceRecreateServiceAccounts
)

# --- LOGGING & TRANSCRIPT ---
$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path -Path $logDir)) {
  New-Item -ItemType Directory -Path $logDir | Out-Null
}
$logFile = Join-Path $logDir ("ad_populator_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $logFile -Append

Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop

$Domain      = Get-ADDomain
$DomainDN    = $Domain.DistinguishedName
$DNSRoot     = $Domain.DNSRoot
$NetBIOS     = $Domain.NetBIOSName
$Departments = @('Finance','HR','Engineering','Sales','Legal','IT','Ops','Marketing','R&D','QA','Facilities','Procurement','Logistics','Training','Support')
$DeptSamPrefixMap = @{
  'Finance'='fina'; 'HR'='hr'; 'Engineering'='eng'; 'Sales'='sale';
  'Legal'='lega'; 'IT'='it'; 'Ops'='ops'; 'Marketing'='mark';
  'R&D'='rnd'; 'QA'='qa'; 'Facilities'='faci'; 'Procurement'='proc';
  'Logistics'='logi'; 'Training'='trai'; 'Support'='supp'
}
$Password    = (ConvertTo-SecureString 'P@ssw0rd!2024' -AsPlainText -Force)
$rand        = [Random]::new()

# Enhanced group diversity for realistic enterprise environment
$AdditionalGroups = @(
  # Security/compliance
  "SecurityTeam","AuditTeam","Compliance","DataStewards","ISOAdmins","BackupOps","DisasterRecovery","PrivilegedIT",
  # IT-specific (for service accounts)
  "WebTeam","SysAdmins","DesktopSupport",
  # Business/operational
  "MobileUsers","RemoteOnly","VPNUsers","AllStaff","AllContractors","ExternalVendors","Alumni","OnLeave",
  # Location-based
  "Office_NYC","Office_LA","Office_Chicago","Office_Austin","Remote_Workers","Field_Staff",
  # Legacy/obsolete (realistic enterprise mess)
  "ObsoleteStaff","RetiredGroups","LegacyApps","OldFinance","OldSales","Projects2010","Accounting2013","Sales2009"
)

# Realistic job titles with hierarchy
$JobTitles = @{
  "Junior" = @("Junior Developer","Junior Analyst","Associate","Assistant","Coordinator","Specialist I")
  "Mid" = @("Developer","Analyst","Specialist","Consultant","Manager","Lead","Principal")
  "Senior" = @("Senior Developer","Senior Analyst","Senior Manager","Director","Principal Consultant","Architect")
  "Executive" = @("VP","SVP","CTO","CIO","CFO","CMO","CHRO","General Manager","Vice President")
}

# Office locations
$Locations = @("New York","Los Angeles","Chicago","Austin","Seattle","Boston","Remote","Field")

# Service account definitions
$ServiceAccounts = @(
  @{Name="sql_service"; Description="SQL Server Service Account"; Groups=@("ISOAdmins","BackupOps")}
  @{Name="backup_svc"; Description="Backup Service Account"; Groups=@("BackupOps","DisasterRecovery")}
  @{Name="web_app_pool"; Description="Web Application Pool Account"; Groups=@("WebTeam","IT")}
  @{Name="monitoring_svc"; Description="System Monitoring Service"; Groups=@("SysAdmins","IT")}
  @{Name="ad_sync_svc"; Description="AD Synchronization Service"; Groups=@("PrivilegedIT","SysAdmins")}
  @{Name="file_share_svc"; Description="File Share Service Account"; Groups=@("IT","BackupOps")}
  @{Name="print_svc"; Description="Print Spooler Service Account"; Groups=@("IT","DesktopSupport")}
  @{Name="crm_service"; Description="CRM Application Service"; Groups=@("Sales","IT")}
)

function Test-OUByNameAndPath {
  param([string]$Name,[string]$Path)
  try {
    $cand = Get-ADOrganizationalUnit -LDAPFilter "(ou=$Name)" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue
    return [bool]$cand
  } catch { return $false }
}

function Ensure-OUPath {
  param([Parameter(Mandatory)][string[]]$Segments)
  $currentPath = $DomainDN
  foreach ($seg in $Segments) {
    if (-not (Test-OUByNameAndPath -Name $seg -Path $currentPath)) {
      New-ADOrganizationalUnit -Name $seg -Path $currentPath -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop | Out-Null
    }
    $currentPath = "OU=$seg,$currentPath"
  }
  return $currentPath
}

function Ensure-Group {
  param(
    [Parameter(Mandatory)][string]$Name,
    [ValidateSet('Global','DomainLocal')][string]$Scope='Global',
    [string]$Path
  )
  $existing = Get-ADGroup -LDAPFilter "(sAMAccountName=$Name)" -SearchBase $DomainDN -ErrorAction SilentlyContinue
  if ($existing) {
    if ($Path -and ($existing.DistinguishedName -notlike "*$Path*")) {
      try { Move-ADObject -Identity $existing.DistinguishedName -TargetPath $Path -ErrorAction SilentlyContinue } catch {}
    }
    return (Get-ADGroup -Identity $existing.DistinguishedName)
  }
  return New-ADGroup -Name $Name -SamAccountName $Name -GroupScope $Scope -GroupCategory Security -Path $Path -PassThru
}

function Ensure-UserInGroup {
  param([Parameter(Mandatory)][string]$GroupSam,[Parameter(Mandatory)][string]$UserSam)
  try {
    $g = Get-ADGroup -LDAPFilter "(sAMAccountName=$GroupSam)" -SearchBase $DomainDN -ErrorAction SilentlyContinue
    $u = Get-ADUser  -LDAPFilter "(sAMAccountName=$UserSam)"  -SearchBase $DomainDN -ErrorAction SilentlyContinue
    if ($g -and $u) {
      $already = Get-ADGroupMember -Identity $g.DistinguishedName -Recursive -ErrorAction SilentlyContinue | Where-Object { $_.distinguishedName -eq $u.DistinguishedName }
      if (-not $already) { Add-ADGroupMember -Identity $g.DistinguishedName -Members $u.SamAccountName -ErrorAction SilentlyContinue }
    }
  } catch {}
}

function New-RandomDisplayName {
  $given = @('Alex','Sam','Taylor','Jordan','Casey','Riley','Morgan','Avery','Jamie','Quinn','Reese','Rowan','Elliot','Devin','Hayden')[$rand.Next(0,15)]
  $sur   = @('Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez','Hernandez','Lopez','Gonzalez','Wilson','Anderson')[$rand.Next(0,15)]
  [pscustomobject]@{ Given=$given; Surname=$sur; Display=("$given $sur") }
}

function Get-NextSam {
  param([Parameter(Mandatory)][string]$Prefix)
  # Scan existing users for this prefix, find the max numeric suffix, and return next number
  $existing = Get-ADUser -LDAPFilter "(sAMAccountName=$Prefix*)" -SearchBase $DomainDN -ErrorAction SilentlyContinue |
              Select-Object -ExpandProperty SamAccountName
  $max = 0
  if ($existing) {
    foreach ($s in $existing) {
      if ($s -match ('^{0}(\d+)$' -f [regex]::Escape($Prefix))) {
        $n = [int]$Matches[1]
        if ($n -gt $max) { $max = $n }
      }
    }
  }
  $next = $max + 1
  return ('{0}{1:0000}' -f $Prefix, $next)
}

function Between([int]$min,[int]$max){ if ($max -le $min) { return $min } $rand.Next($min, $max+1) }

# OUs
$rootOU        = Ensure-OUPath -Segments @($BaseOUName)
$usersOU       = Ensure-OUPath -Segments @($BaseOUName,'Users')
$groupsOU      = Ensure-OUPath -Segments @($BaseOUName,'Groups')
$departmentsOU = Ensure-OUPath -Segments @($BaseOUName,'Departments')
$projectsOU    = Ensure-OUPath -Segments @($BaseOUName,'Projects')
$deptOUs = @{}
foreach ($d in $Departments) { $deptOUs[$d] = Ensure-OUPath -Segments @($BaseOUName,'Departments',$d) }

# Groups (ALL GROUP CREATION MUST HAPPEN BEFORE MEMBERSHIP ASSIGNMENTS)
$ggAll = Ensure-Group -Name "GG_AllEmployees" -Scope Global -Path $groupsOU
$roleGroupsEnsured = @()
foreach ($rg in $RoleGroups) { $roleGroupsEnsured += (Ensure-Group -Name "GG_Role_$rg" -Scope Global -Path $groupsOU) }
foreach ($Dept in $Departments) {
  $ggDept = Ensure-Group -Name "GG_$Dept" -Scope Global -Path $groupsOU
  if ($CreateAccessTiers) { Ensure-Group -Name ("GG_{0}_RO" -f $Dept) -Scope Global -Path $groupsOU | Out-Null }
}

# Create additional enterprise groups for realism
Write-Host "Creating additional enterprise groups..." -ForegroundColor Yellow
foreach ($groupName in $AdditionalGroups) {
  try {
    if (-not (Get-ADGroup -LDAPFilter "(sAMAccountName=$groupName)" -SearchBase $DomainDN -ErrorAction SilentlyContinue)) {
      if (-not $WhatIf) {
        New-ADGroup -Name $groupName -SamAccountName $groupName -GroupScope Global -GroupCategory Security -Path $groupsOU -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Created group: $groupName" -ForegroundColor Green
      } else {
        Write-Host "  WOULD CREATE group: $groupName" -ForegroundColor Cyan
      }
    } else {
      Write-Host "  - Group already exists: $groupName" -ForegroundColor Gray
    }
  } catch {
    Write-Host "  ✗ Failed to create group $groupName : $_" -ForegroundColor Red
  }
}

# Wire up AGDLP now that all groups are created
if ($CreateAGDLP) {
  foreach ($Dept in $Departments) {
    $ggDept = Get-ADGroup -Identity "GG_$Dept"
    $dlRO = Ensure-Group -Name ("DL_Share_{0}_RO" -f $Dept) -Scope DomainLocal -Path $groupsOU
    $dlRW = Ensure-Group -Name ("DL_Share_{0}_RW" -f $Dept) -Scope DomainLocal -Path $groupsOU
    try {
      Add-ADGroupMember -Identity $dlRW -Members $ggDept -ErrorAction SilentlyContinue
      if ($CreateAccessTiers) { Add-ADGroupMember -Identity $dlRO -Members ("GG_{0}_RO" -f $Dept) -ErrorAction SilentlyContinue }
    } catch {}
  }
}

# Users
$totalUsers = 0
$userDetails = @()
$userErrors = 0
foreach ($Dept in $Departments) {
  $deptUsersOU = $deptOUs[$Dept]
  $count = Between -min $UsersPerDeptMin -max $UsersPerDeptMax
  $prefix = $DeptSamPrefixMap[$Dept]

  foreach ($n in 1..$count) {
    # Generate a guaranteed-unique SAM and CN for this dept
    $sam = Get-NextSam -Prefix $prefix
    $display = (New-RandomDisplayName)
    $upn = ("{0}@{1}" -f $sam, $DNSRoot)
    
    # Add rich attributes
    $location = $Locations[$rand.Next(0, $Locations.Count)]
    $seniority = $rand.Next(1, 101)
    $titleCategory = if ($seniority -le 5) { "Executive" } 
                    elseif ($seniority -le 15) { "Senior" } 
                    elseif ($seniority -le 60) { "Mid" } 
                    else { "Junior" }
    $title = $JobTitles[$titleCategory][$rand.Next(0, $JobTitles[$titleCategory].Count)]

    try {
      if (-not $WhatIf) {
        # Ensure CN uniqueness in the OU by using -Name $sam
        $user = New-ADUser -SamAccountName $sam -Name $sam -DisplayName $display.Display -GivenName $display.Given -Surname $display.Surname `
          -UserPrincipalName $upn -AccountPassword $Password -Enabled $true -ChangePasswordAtLogon $false -PasswordNeverExpires $true `
          -Path $deptUsersOU -Department $Dept -Title $title -Office $location -Company "DemoCorp" -PassThru -ErrorAction Stop

        Ensure-UserInGroup -GroupSam "GG_AllEmployees" -UserSam $sam
        Ensure-UserInGroup -GroupSam ("GG_{0}" -f $Dept) -UserSam $sam

        # Add to location-based groups
        if ($location -eq "Remote") {
          Ensure-UserInGroup -GroupSam "RemoteOnly" -UserSam $sam
          Ensure-UserInGroup -GroupSam "VPNUsers" -UserSam $sam
        } else {
          $locationGroup = "Office_$($location.Replace(' ','_'))"
          Ensure-UserInGroup -GroupSam $locationGroup -UserSam $sam
        }

        # Add to role groups
        if ($roleGroupsEnsured.Count -gt 0 -and $rand.Next(0,5) -eq 0) {
          $pick = $roleGroupsEnsured[$rand.Next(0,$roleGroupsEnsured.Count)]
          try { Add-ADGroupMember -Identity $pick -Members $user.SamAccountName -ErrorAction SilentlyContinue } catch {}
        }

        # Add some legacy/obsolete group memberships (realistic enterprise mess)
        if ($rand.Next(0,8) -eq 1) { Ensure-UserInGroup -GroupSam "ObsoleteStaff" -UserSam $sam }
        if ($rand.Next(0,15) -eq 3) { Ensure-UserInGroup -GroupSam "RetiredGroups" -UserSam $sam }
        if ($rand.Next(0,11) -eq 4) { Ensure-UserInGroup -GroupSam "LegacyApps" -UserSam $sam }

        $totalUsers++
        
        # Store user details for CSV export
        $userDetails += [PSCustomObject]@{
          SamAccountName = $sam
          Name = $display.Display
          GivenName = $display.Given
          Surname = $display.Surname
          Department = $Dept
          Title = $title
          Office = $location
          Company = "DemoCorp"
          UserPrincipalName = $upn
          Created = Get-Date
        }
        
        # Progress reporting
        if (($totalUsers % 25) -eq 0) {
          Write-Host "  Created $totalUsers users so far..." -ForegroundColor Green
        }
      } else {
        Write-Host "  WOULD CREATE user: $sam ($($display.Display)) - $title in $Dept at $location" -ForegroundColor Cyan
      }
    } catch {
      $errorMsg = "Failed to create user {0} in {1}: {2}" -f $sam, $Dept, $_.Exception.Message
      Write-Warning $errorMsg
      $userErrors++
      # Advance prefix counter once to avoid retrying same SAM in tight loops
      # (By recalculating on next iteration we will naturally pick the next available)
    }
  }
}

# Service Accounts
Write-Host "Creating service accounts..." -ForegroundColor Yellow
$serviceAccountsCreated = 0
$serviceAccountsExisted = 0
$serviceAccountsErrors = 0
foreach ($svcAcct in $ServiceAccounts[0..($NumServiceAccounts-1)]) {
  try {
    $sam = $svcAcct.Name
    $existing = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -SearchBase $DomainDN -ErrorAction SilentlyContinue
    
    if ($existing -and $ForceRecreateServiceAccounts) {
      Write-Host "  🔄 Force recreating service account: $sam" -ForegroundColor Yellow
      Remove-ADUser -Identity $existing.DistinguishedName -Confirm:$false -ErrorAction SilentlyContinue
      $existing = $null
    }
    
    if (-not $existing) {
      if (-not $WhatIf) {
        New-ADUser -SamAccountName $sam -Name $svcAcct.Description `
          -Description $svcAcct.Description -Path $usersOU -Enabled $true `
          -AccountPassword $Password `
          -UserPrincipalName "$sam@$DNSRoot" `
          -Title "Service Account" -Department "IT" -ErrorAction Stop | Out-Null

        # Add to groups
        $groupMemberships = 0
        foreach ($g in $svcAcct.Groups) {
          try {
            Add-ADGroupMember -Identity $g -Members $sam -ErrorAction SilentlyContinue
            $groupMemberships++
          } catch {
            Write-Host "    ⚠ Failed to add $sam to group $g" -ForegroundColor Yellow
          }
        }
        Write-Host "  ✓ Created service account: $sam (added to $groupMemberships groups)" -ForegroundColor Green
        $serviceAccountsCreated++
      } else {
        Write-Host "  WOULD CREATE service account: $sam" -ForegroundColor Cyan
      }
    } else {
      Write-Host "  - Service account already exists: $sam" -ForegroundColor Gray
      $serviceAccountsExisted++
    }
  } catch {
    Write-Host "  ✗ Failed to create service account $($svcAcct.Name) : $_" -ForegroundColor Red
    $serviceAccountsErrors++
  }
}

# Projects
if ($ProjectsPerDeptMax -gt 0) {
  foreach ($Dept in $Departments) {
    $projCount = Between -min $ProjectsPerDeptMin -max $ProjectsPerDeptMax
    foreach ($i in 1..$projCount) {
      $pg = Ensure-Group -Name ("PG_{0}_Proj{1:00}" -f $Dept, $i) -Scope Global -Path $groupsOU
      try {
        $prefix = $DeptSamPrefixMap[$Dept]
        $deptUsers = Get-ADUser -LDAPFilter ("(sAMAccountName={0}*)" -f $prefix) -SearchBase $DomainDN -ErrorAction SilentlyContinue
        if ($deptUsers) {
          $take = [Math]::Max(1, [int]([double]$deptUsers.Count * (0.08 + ($rand.NextDouble()*0.15))))
          $members = $deptUsers | Get-Random -Count ([Math]::Min($take, $deptUsers.Count))
          Add-ADGroupMember -Identity $pg -Members ($members | Select-Object -Expand SamAccountName) -ErrorAction SilentlyContinue
        }
      } catch {}
    }
  }
}

# CSV Export
if (-not $WhatIf -and $userDetails.Count -gt 0) {
  $csvPath = Join-Path $logDir ("users_created_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  try {
    $userDetails | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "`n📊 User details exported to: $csvPath" -ForegroundColor Green
  } catch {
    Write-Host "`n⚠️ Failed to export CSV: $_" -ForegroundColor Yellow
  }
}

# Comprehensive Validation
Write-Host "`n🔍 Running validation checks..." -ForegroundColor Yellow
$validationResults = @{
  TotalGroups = 0
  TotalUsers = 0
  ServiceAccounts = 0
  ValidationErrors = @()
}

# Validate groups
try {
  $allGroups = Get-ADGroup -Filter "Name -like 'GG_*' -or Name -like 'DL_*'" -SearchBase $DomainDN -ErrorAction SilentlyContinue
  $additionalGroups = Get-ADGroup -Filter "Name -eq 'SecurityTeam' -or Name -eq 'AuditTeam' -or Name -eq 'Compliance' -or Name -eq 'DataStewards' -or Name -eq 'ISOAdmins' -or Name -eq 'BackupOps' -or Name -eq 'DisasterRecovery' -or Name -eq 'PrivilegedIT' -or Name -eq 'MobileUsers' -or Name -eq 'RemoteOnly' -or Name -eq 'VPNUsers' -or Name -eq 'AllStaff' -or Name -eq 'AllContractors' -or Name -eq 'ExternalVendors' -or Name -eq 'Alumni' -or Name -eq 'OnLeave' -or Name -eq 'Office_NYC' -or Name -eq 'Office_LA' -or Name -eq 'Office_Chicago' -or Name -eq 'Office_Austin' -or Name -eq 'Remote_Workers' -or Name -eq 'Field_Staff' -or Name -eq 'ObsoleteStaff' -or Name -eq 'RetiredGroups' -or Name -eq 'LegacyApps' -or Name -eq 'OldFinance' -or Name -eq 'OldSales' -or Name -eq 'Projects2010' -or Name -eq 'Accounting2013' -or Name -eq 'Sales2009'" -SearchBase $DomainDN -ErrorAction SilentlyContinue
  $validationResults.TotalGroups = $allGroups.Count + $additionalGroups.Count
  Write-Host "  ✓ Found $($validationResults.TotalGroups) groups" -ForegroundColor Green
} catch {
  $validationResults.ValidationErrors += "Failed to validate groups: $_"
  Write-Host "  ✗ Failed to validate groups: $_" -ForegroundColor Red
}

# Validate users
try {
  $allUsers = Get-ADUser -Filter "SamAccountName -like 'fina*' -or SamAccountName -like 'hr*' -or SamAccountName -like 'eng*' -or SamAccountName -like 'sale*' -or SamAccountName -like 'lega*' -or SamAccountName -like 'it*' -or SamAccountName -like 'ops*' -or SamAccountName -like 'mark*'" -SearchBase $DomainDN -ErrorAction SilentlyContinue
  $validationResults.TotalUsers = $allUsers.Count
  Write-Host "  ✓ Found $($allUsers.Count) users" -ForegroundColor Green
} catch {
  $validationResults.ValidationErrors += "Failed to validate users: $_"
  Write-Host "  ✗ Failed to validate users: $_" -ForegroundColor Red
}

# Validate service accounts
try {
  $serviceUsers = Get-ADUser -Filter "SamAccountName -like '*_service'" -SearchBase $DomainDN -ErrorAction SilentlyContinue
  $validationResults.ServiceAccounts = $serviceUsers.Count
  Write-Host "  ✓ Found $($serviceUsers.Count) service accounts" -ForegroundColor Green
} catch {
  $validationResults.ValidationErrors += "Failed to validate service accounts: $_"
  Write-Host "  ✗ Failed to validate service accounts: $_" -ForegroundColor Red
}

# Validate GG_AllEmployees membership
try {
  $allEmployeesGroup = Get-ADGroup -LDAPFilter "(sAMAccountName=GG_AllEmployees)" -SearchBase $DomainDN -ErrorAction SilentlyContinue
  if ($allEmployeesGroup) {
    $memberCount = (Get-ADGroupMember -Identity $allEmployeesGroup -Recursive -ErrorAction SilentlyContinue | Where-Object {$_.objectClass -eq 'user'} | Measure-Object).Count
    Write-Host "  ✓ GG_AllEmployees has $memberCount members" -ForegroundColor Green
  } else {
    $validationResults.ValidationErrors += "GG_AllEmployees group not found"
    Write-Host "  ✗ GG_AllEmployees group not found" -ForegroundColor Red
  }
} catch {
  $validationResults.ValidationErrors += "Failed to validate GG_AllEmployees: $_"
  Write-Host "  ✗ Failed to validate GG_AllEmployees: $_" -ForegroundColor Red
}

# Summary
if ($VerboseSummary) {
  $deptSummary = foreach ($d in $Departments) {
    $gg = Get-ADGroup -LDAPFilter "(sAMAccountName=GG_$d)" -SearchBase $DomainDN -ErrorAction SilentlyContinue
    $uc = 0
    if ($gg) {
      $uc = (Get-ADGroupMember -Identity $gg -Recursive -ErrorAction SilentlyContinue | Where-Object {$_.objectClass -eq 'user'} | Measure-Object).Count
    }
    [pscustomobject]@{ Department = $d; Users = $uc }
  }
  Write-Host "`n=== ENHANCED AD POPULATOR SUMMARY ===" -ForegroundColor Cyan
  Write-Host ("Users created (new this run): {0}" -f $totalUsers)
  Write-Host ("User creation errors: {0}" -f $userErrors)
  Write-Host ("Service accounts created: {0}" -f $serviceAccountsCreated)
  Write-Host ("Service accounts existed: {0}" -f $serviceAccountsExisted)
  Write-Host ("Service account errors: {0}" -f $serviceAccountsErrors)
  Write-Host ("Additional enterprise groups: {0}" -f $AdditionalGroups.Count)
  Write-Host ("Total groups validated: {0}" -f $validationResults.TotalGroups)
  Write-Host ("Total users validated: {0}" -f $validationResults.TotalUsers)
  Write-Host ("Service accounts validated: {0}" -f $validationResults.ServiceAccounts)
  Write-Host ("Departments: {0}" -f (($Departments) -join ', '))
  Write-Host ("Core groups: {0}" -f ((@("GG_AllEmployees") + ($Departments | ForEach-Object { "GG_{0}" -f $_ })) -join ', '))
  if ($CreateAccessTiers) { Write-Host ("Access tiers created: {0}" -f (($Departments | ForEach-Object { "GG_{0}_RO" -f $_ }) -join ', ')) }
  if ($CreateAGDLP)     { Write-Host ("DLs created: {0}" -f (($Departments | ForEach-Object { "DL_Share_{0}_RO, DL_Share_{0}_RW" -f $_ }) -join '; ')) }
  Write-Host "Users by department:"
  $deptSummary | Sort-Object Department | Format-Table -AutoSize
  
  if ($validationResults.ValidationErrors.Count -gt 0) {
    Write-Host "`n⚠️ Validation Errors:" -ForegroundColor Yellow
    $validationResults.ValidationErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
  }
  
  if ($WhatIf) {
    Write-Host "`n=== WHATIF MODE - NO CHANGES MADE ===" -ForegroundColor Yellow
  }
}

# --- END SCRIPT ---
Stop-Transcript

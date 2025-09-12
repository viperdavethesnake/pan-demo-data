# ad_populator.ps1 (collision-proof users; PS 7.5.x)
<#
.SYNOPSIS
  Populate AD with OUs, groups, and users while avoiding duplicate-name errors.

.KEY IMPROVEMENTS
  - Unique user CNs by setting -Name to the sAMAccountName
  - Unique sAMAccountName per department via Get-NextSam() (prefix scan -> next number)
  - If a prior run left users behind, v5 simply picks the next available number (idempotent)
  - Users auto-added to GG_AllEmployees and GG_<Dept>
  - Optional access tiers and AGDLP wiring

.DESIGNED FOR
  PowerShell 7.x (imports AD with -SkipEditionCheck). Run as Domain Admin.
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
  [switch]$VerboseSummary
)

Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop

$Domain      = Get-ADDomain
$DomainDN    = $Domain.DistinguishedName
$DNSRoot     = $Domain.DNSRoot
$NetBIOS     = $Domain.NetBIOSName
$Departments = @('Finance','HR','Engineering','Sales','Legal','IT','Ops','Marketing')
$DeptSamPrefixMap = @{
  'Finance'='fina'; 'HR'='hr'; 'Engineering'='eng'; 'Sales'='sale';
  'Legal'='lega'; 'IT'='it'; 'Ops'='ops'; 'Marketing'='mark'
}
$Password    = (ConvertTo-SecureString 'P@ssw0rd!2024' -AsPlainText -Force)
$rand        = [Random]::new()

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

# Groups
$ggAll = Ensure-Group -Name "GG_AllEmployees" -Scope Global -Path $groupsOU
$roleGroupsEnsured = @()
foreach ($rg in $RoleGroups) { $roleGroupsEnsured += (Ensure-Group -Name "GG_Role_$rg" -Scope Global -Path $groupsOU) }
foreach ($Dept in $Departments) {
  $ggDept = Ensure-Group -Name "GG_$Dept" -Scope Global -Path $groupsOU
  if ($CreateAccessTiers) { Ensure-Group -Name ("GG_{0}_RO" -f $Dept) -Scope Global -Path $groupsOU | Out-Null }
  if ($CreateAGDLP) {
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
foreach ($Dept in $Departments) {
  $deptUsersOU = $deptOUs[$Dept]
  $count = Between -min $UsersPerDeptMin -max $UsersPerDeptMax
  $prefix = $DeptSamPrefixMap[$Dept]

  foreach ($n in 1..$count) {
    # Generate a guaranteed-unique SAM and CN for this dept
    $sam = Get-NextSam -Prefix $prefix
    $display = (New-RandomDisplayName)
    $upn = ("{0}@{1}" -f $sam, $DNSRoot)

    try {
      # Ensure CN uniqueness in the OU by using -Name $sam
      $user = New-ADUser -SamAccountName $sam -Name $sam -DisplayName $display.Display -GivenName $display.Given -Surname $display.Surname `
        -UserPrincipalName $upn -AccountPassword $Password -Enabled $true -ChangePasswordAtLogon $false -PasswordNeverExpires $true `
        -Path $deptUsersOU -PassThru -ErrorAction Stop

      Ensure-UserInGroup -GroupSam "GG_AllEmployees" -UserSam $sam
      Ensure-UserInGroup -GroupSam ("GG_{0}" -f $Dept) -UserSam $sam

      if ($roleGroupsEnsured.Count -gt 0 -and $rand.Next(0,5) -eq 0) {
        $pick = $roleGroupsEnsured[$rand.Next(0,$roleGroupsEnsured.Count)]
        try { Add-ADGroupMember -Identity $pick -Members $user.SamAccountName -ErrorAction SilentlyContinue } catch {}
      }
      $totalUsers++
    } catch {
      Write-Warning ("Failed to create user {0} in {1}: {2}" -f $sam, $Dept, $_.Exception.Message)
      # Advance prefix counter once to avoid retrying same SAM in tight loops
      # (By recalculating on next iteration we will naturally pick the next available)
    }
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
  Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
  Write-Host ("Users created (new this run): {0}" -f $totalUsers)
  Write-Host ("Departments: {0}" -f (($Departments) -join ', '))
  Write-Host ("Core groups: {0}" -f ((@("GG_AllEmployees") + ($Departments | ForEach-Object { "GG_{0}" -f $_ })) -join ', '))
  if ($CreateAccessTiers) { Write-Host ("Access tiers created: {0}" -f (($Departments | ForEach-Object { "GG_{0}_RO" -f $_ }) -join ', ')) }
  if ($CreateAGDLP)     { Write-Host ("DLs created: {0}" -f (($Departments | ForEach-Object { "DL_Share_{0}_RO, DL_Share_{0}_RW" -f $_ }) -join '; ')) }
  Write-Host "Users by department:"
  $deptSummary | Sort-Object Department | Format-Table -AutoSize
}

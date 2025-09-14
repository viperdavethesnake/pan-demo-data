# ad_reset.ps1 — Thorough AD cleanup for demo runs (PS 7.5.x)
<#
.SYNOPSIS
  Thoroughly reset demo AD artifacts created by the populator scripts.

.DESCRIPTION
  - Deletes users, groups, and OUs that belong to a demo environment in a safe, idempotent way.
  - Fixes prior issues where some users/groups were left behind (leading to collisions).
  - Can optionally purge users by sAMAccountName prefix **anywhere** in the domain, not just under the Base OU.

.DESIGNED FOR
  PowerShell 7.x (imports AD with -SkipEditionCheck). Run as Domain Admin.

.EXAMPLES

# Preview (no changes)
.\ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -DoGroups -DoOUs -PurgeBySamPrefixes -WhatIf

# Do it for real (no prompts)
.\ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -DoGroups -DoOUs -PurgeBySamPrefixes -Confirm:$false
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
  [Parameter(Mandatory)][string]$BaseOUName,
  [switch]$DoUsers,
  [switch]$DoGroups,
  [switch]$DoOUs,
  # Purge users by dept prefixes anywhere in the domain (not just under Base OU)
  [switch]$PurgeBySamPrefixes,
  # Extra sAMAccountName prefixes to purge (e.g., 'qa','lab')
  [string[]]$ExtraSamPrefixes = @(),
  [switch]$VerboseSummary
)

# --- LOGGING & TRANSCRIPT ---
$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path -Path $logDir)) {
  New-Item -ItemType Directory -Path $logDir | Out-Null
}
$logFile = Join-Path $logDir ("ad_reset_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $logFile -Append

Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop

$Domain   = Get-ADDomain
$DomainDN = $Domain.DistinguishedName
$NetBIOS  = $Domain.NetBIOSName

# Standard dept prefixes used by the populator (v3+ and v5)
$DeptSamPrefixMap = @{
  'Finance'='fina'; 'HR'='hr'; 'Engineering'='eng'; 'Sales'='sale';
  'Legal'='lega'; 'IT'='it'; 'Ops'='ops'; 'Marketing'='mark'
}
$AllPrefixes = ($DeptSamPrefixMap.Values + $ExtraSamPrefixes) | Sort-Object -Unique

# OUs we expect
$RootOU        = "OU=$BaseOUName,$DomainDN"
$UsersOU       = "OU=Users,$RootOU"
$GroupsOU      = "OU=Groups,$RootOU"
$DepartmentsOU = "OU=Departments,$RootOU"
$ProjectsOU    = "OU=Projects,$RootOU"

function Disable-Protection {
  param([Parameter(Mandatory)][string]$DN)
  try {
    $obj = Get-ADObject -Identity $DN -Properties ProtectedFromAccidentalDeletion -ErrorAction Stop
    if ($obj.ProtectedFromAccidentalDeletion) {
      Set-ADObject -Identity $DN -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop
    }
  } catch {}
}

function Remove-Items {
  param([Parameter(Mandatory)][string[]]$DNs)
  foreach ($dn in $DNs) {
    if (-not $dn) { continue }
    Disable-Protection -DN $dn
    if ($PSCmdlet.ShouldProcess($dn, "Remove AD object")) {
      try { Remove-ADObject -Identity $dn -Recursive -Confirm:$false -ErrorAction Stop } catch {
        # Fallback by type
        try {
          $obj = Get-ADObject -Identity $dn -Properties objectClass -ErrorAction Stop
          switch ($obj.objectClass) {
            'user'    { Remove-ADUser -Identity $dn -Confirm:$false -ErrorAction Stop }
            'group'   { Remove-ADGroup -Identity $dn -Confirm:$false -ErrorAction Stop }
            'computer'{ Remove-ADComputer -Identity $dn -Confirm:$false -ErrorAction Stop }
            default   { Remove-ADObject -Identity $dn -Confirm:$false -ErrorAction Stop }
          }
        } catch {
          Write-Warning ("Failed to remove {0}: {1}" -f $dn, $_.Exception.Message)
        }
      }
    }
  }
}

function Find-UsersUnder {
  param([Parameter(Mandatory)][string]$BaseDN)
  try {
    return Get-ADUser -LDAPFilter "(objectClass=user)" -SearchBase $BaseDN -SearchScope Subtree -ErrorAction SilentlyContinue
  } catch { return @() }
}

function Find-GroupsUnder {
  param([Parameter(Mandatory)][string]$BaseDN)
  try {
    return Get-ADGroup -LDAPFilter "(objectClass=group)" -SearchBase $BaseDN -SearchScope Subtree -ErrorAction SilentlyContinue
  } catch { return @() }
}

function Find-UsersBySamPrefixes {
  param([Parameter(Mandatory)][string[]]$Prefixes)
  if (-not $Prefixes -or $Prefixes.Count -eq 0) { return @() }
  $terms = $Prefixes | ForEach-Object { "(sAMAccountName=$($_)*)" }
  $filter = "(|{0})" -f ($terms -join '')
  try {
    return Get-ADUser -LDAPFilter $filter -SearchBase $DomainDN -ErrorAction SilentlyContinue
  } catch { return @() }
}

# --- USERS ---
$userDNs = @()
if ($DoUsers) {
  # Users under the base OU (idempotent, scoped)
  if (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$RootOU)" -SearchBase $DomainDN -ErrorAction SilentlyContinue) {
    $u1 = Find-UsersUnder -BaseDN $RootOU
    if ($u1) { $userDNs += ($u1 | Select-Object -ExpandProperty DistinguishedName) }
  }

  # Optional: users anywhere matching our prefixes (catches leftovers from older runs)
  if ($PurgeBySamPrefixes -and $AllPrefixes.Count -gt 0) {
    $u2 = Find-UsersBySamPrefixes -Prefixes $AllPrefixes
    if ($u2) { $userDNs += ($u2 | Select-Object -ExpandProperty DistinguishedName) }
  }

  # Service accounts created by the populator
  $serviceAccountFilter = "(sAMAccountName=*_service)"
  try {
    $serviceAccounts = Get-ADUser -LDAPFilter $serviceAccountFilter -SearchBase $DomainDN -ErrorAction SilentlyContinue
    if ($serviceAccounts) { 
      $userDNs += ($serviceAccounts | Select-Object -ExpandProperty DistinguishedName)
      Write-Verbose "Found $($serviceAccounts.Count) service accounts to remove"
    }
  } catch {
    Write-Warning "Failed to find service accounts: $_"
  }

  $userDNs = $userDNs | Sort-Object -Unique
  if ($userDNs.Count -gt 0) {
    Remove-Items -DNs $userDNs
  } else {
    Write-Verbose "No users found to remove."
  }
}

# --- GROUPS ---
$groupDNs = @()
if ($DoGroups) {
  # Groups under the Groups OU
  if (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$GroupsOU)" -SearchBase $DomainDN -ErrorAction SilentlyContinue) {
    $g1 = Find-GroupsUnder -BaseDN $GroupsOU
    if ($g1) { $groupDNs += ($g1 | Select-Object -ExpandProperty DistinguishedName) }
  }
  # Also catch prefixed groups anywhere (GG_*, DL_Share_*, PG_*, enhanced groups)
  $gfilters = @("(sAMAccountName=GG_*)","(sAMAccountName=DL_Share_*)","(sAMAccountName=PG_*)","(sAMAccountName=GG_Role_*)","(sAMAccountName=GG_Location_*)","(sAMAccountName=GG_Archive_*)")
  $gf = "(|{0})" -f ($gfilters -join '')
  try {
    $g2 = Get-ADGroup -LDAPFilter $gf -SearchBase $DomainDN -ErrorAction SilentlyContinue
    if ($g2) { $groupDNs += ($g2 | Select-Object -ExpandProperty DistinguishedName) }
  } catch {}

  # Enterprise groups created by the populator
  $enterpriseGroups = @("SecurityTeam","AuditTeam","Compliance","DataStewards","ISOAdmins","BackupOps","DisasterRecovery","PrivilegedIT","MobileUsers","RemoteOnly","VPNUsers","AllStaff","AllContractors","ExternalVendors","Alumni","OnLeave","Office_NYC","Office_LA","Office_Chicago","Office_Austin","Remote_Workers","Field_Staff","ObsoleteStaff","RetiredGroups","LegacyApps","OldFinance","OldSales","Projects2010","Accounting2013","Sales2009")
  $enterpriseTerms = $enterpriseGroups | ForEach-Object { "(sAMAccountName=$_)" }
  $enterpriseFilter = "(|{0})" -f ($enterpriseTerms -join '')
  try {
    $enterpriseGroups = Get-ADGroup -LDAPFilter $enterpriseFilter -SearchBase $DomainDN -ErrorAction SilentlyContinue
    if ($enterpriseGroups) { 
      $groupDNs += ($enterpriseGroups | Select-Object -ExpandProperty DistinguishedName)
      Write-Verbose "Found $($enterpriseGroups.Count) enterprise groups to remove"
    }
  } catch {
    Write-Warning "Failed to find enterprise groups: $_"
  }
  $groupDNs = $groupDNs | Sort-Object -Unique
  if ($groupDNs.Count -gt 0) {
    Remove-Items -DNs $groupDNs
  } else {
    Write-Verbose "No groups found to remove."
  }
}

# --- OUs ---
if ($DoOUs) {
  $ouList = @()
  foreach ($ou in @($ProjectsOU,$DepartmentsOU,$UsersOU,$GroupsOU,$RootOU)) {
    if (-not $ou) { continue }
    $exists = Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$ou)" -SearchBase $DomainDN -ErrorAction SilentlyContinue
    if ($exists) { $ouList += $ou }
  }
  # Remove children before parent: Projects, Departments, Users, Groups, then Root
  foreach ($ou in $ouList) {
    Disable-Protection -DN $ou
    if ($PSCmdlet.ShouldProcess($ou, "Remove OU recursively")) {
      try { Remove-ADOrganizationalUnit -Identity $ou -Recursive -Confirm:$false -ErrorAction Stop } catch {
        # Fallback to generic
        try { Remove-ADObject -Identity $ou -Recursive -Confirm:$false -ErrorAction Stop } catch {
          Write-Warning ("Failed to remove OU {0}: {1}" -f $ou, $_.Exception.Message)
        }
      }
    }
  }
}

if ($VerboseSummary) {
  Write-Host "=== AD Reset Summary ===" -ForegroundColor Cyan
  "{0,-28}: {1}" -f "Users removed", $userDNs.Count
  "{0,-28}: {1}" -f "Groups removed", $groupDNs.Count
  "{0,-28}: {1}" -f "Service accounts removed", ($userDNs | Where-Object { $_ -like "*_service*" }).Count
  $ex = @()
  foreach ($ou in @($RootOU,$UsersOU,$GroupsOU,$DepartmentsOU,$ProjectsOU)) {
    $ex += [pscustomobject]@{ OU=$ou; Exists = [bool](Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$ou)" -SearchBase $DomainDN -ErrorAction SilentlyContinue) }
  }
  $ex | Format-Table -AutoSize
}

# --- END SCRIPT ---
Stop-Transcript

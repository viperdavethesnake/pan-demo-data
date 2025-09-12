# ad_reset.ps1
<#
.SYNOPSIS
  Remove AD objects created by the populator:
  - Users under OU=<BaseOUName>\Users
  - Groups matching GG_*, DL_Share_*, PG_* (scoped or domain-wide)
  - Department OUs and the root OU scaffolding

.DESIGNED FOR
  PowerShell 7.x (loads ActiveDirectory with -SkipEditionCheck).
  Run as Domain Admin.

.EXAMPLES
  # Dry run (recommended first):
  .\ad_reset.ps1 -BaseOUName DemoCorp -WhatIf

  # Actually delete users + groups + OUs (no prompts):
  .\ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -DoGroups -DoOUs -Confirm:$false

  # Only remove users:
  .\ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -Confirm:$false

  # Aggressive group cleanup (search whole domain for GG_*, DL_Share_*, PG_*):
  .\ad_reset.ps1 -BaseOUName DemoCorp -DoGroups -Aggressive -Confirm:$false
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
  [Parameter(Mandatory)][string]$BaseOUName,

  # What to remove
  [switch]$DoUsers,
  [switch]$DoGroups,
  [switch]$DoOUs,

  # Expand group cleanup beyond the Demo OU (search whole domain)
  [switch]$Aggressive
)

# --- Imports ---
Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop

# --- Domain/OU paths ---
$domain       = Get-ADDomain
$domainDN     = $domain.DistinguishedName
$netbios      = $domain.NetBIOSName
$rootOU       = "OU=$BaseOUName,$domainDN"
$usersOU      = "OU=Users,$rootOU"
$groupsOU     = "OU=Groups,$rootOU"
$deptsOU      = "OU=Departments,$rootOU"

function Test-OU([string]$dn) {
  try { [bool](Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$dn)" -SearchBase $domainDN -ErrorAction SilentlyContinue) }
  catch { $false }
}

function Remove-ADObjects {
  param(
    [Parameter(Mandatory)][string]$Type,   # 'user' | 'group' | 'ou'
    [Parameter(Mandatory)][string[]]$DNs
  )
  foreach ($dn in $DNs) {
    if (-not $dn) { continue }
    try {
      if ($Type -eq 'user')  { if ($PSCmdlet.ShouldProcess($dn,"Remove-ADUser"))              { Remove-ADUser               -Identity $dn -Confirm:$false } }
      if ($Type -eq 'group') { if ($PSCmdlet.ShouldProcess($dn,"Remove-ADGroup"))             { Remove-ADGroup              -Identity $dn -Confirm:$false } }
      if ($Type -eq 'ou')    { if ($PSCmdlet.ShouldProcess($dn,"Remove-ADOrganizationalUnit")){ Remove-ADOrganizationalUnit -Identity $dn -Recursive -Confirm:$false } }
    } catch {
      Write-Warning "Failed to remove $Type '$dn': $($_.Exception.Message)"
    }
  }
}

Write-Host "=== AD RESET (Base OU = $BaseOUName) ===" -ForegroundColor Yellow
Write-Host ("WhatIfPreference: {0}" -f $WhatIfPreference) -ForegroundColor DarkYellow

# ---------- 1) Users ----------
if ($DoUsers) {
  $userDNs = @()
  if (Test-OU $usersOU) {
    Write-Host "Collecting users under $usersOU ..."
    $userDNs = Get-ADUser -LDAPFilter '(objectClass=user)' -SearchBase $usersOU -SearchScope Subtree -ErrorAction SilentlyContinue | Select-Object -Expand DistinguishedName
  } else {
    Write-Host "Users OU not found ($usersOU) — skipping user collection from OU." -ForegroundColor DarkGray
  }

  # Heuristic catch: users created by the populator (dept-based sam prefixes)
  foreach ($dept in @("Finance","HR","Engineering","Sales","Legal","IT","Ops")) {
    $prefix = $dept.Substring(0,[Math]::Min(8,$dept.Length)).ToLower()
    try {
      $userDNs += Get-ADUser -LDAPFilter "(sAMAccountName=$prefix*)" -SearchBase $domainDN -ErrorAction SilentlyContinue |
                  Select-Object -Expand DistinguishedName
    } catch {}
  }

  $userDNs = $userDNs | Select-Object -Unique
  Write-Host ("Users to remove: {0}" -f $userDNs.Count)
  Remove-ADObjects -Type 'user' -DNs $userDNs
}

# ---------- 2) Groups ----------
if ($DoGroups) {
  $samFilters = @("GG_AllEmployees", "GG_*", "DL_Share_*", "PG_*")
  $groupDNs = @()

  if ($Aggressive) {
    Write-Host "Aggressive group search across domain..." -ForegroundColor DarkYellow
    foreach ($pat in $samFilters) {
      try {
        $groupDNs += Get-ADGroup -LDAPFilter "(sAMAccountName=$pat)" -SearchBase $domainDN -ErrorAction SilentlyContinue
      } catch {}
    }
  } else {
    Write-Host "Collecting groups under $groupsOU / $rootOU..." -ForegroundColor DarkYellow
    foreach ($base in @($groupsOU,$rootOU)) {
      if (Test-OU $base) {
        foreach ($pat in $samFilters) {
          try {
            $groupDNs += Get-ADGroup -LDAPFilter "(sAMAccountName=$pat)" -SearchBase $base -ErrorAction SilentlyContinue
          } catch {}
        }
      }
    }
  }

  $groups = $groupDNs | Select-Object -Unique
  Write-Host ("Groups to remove: {0}" -f $groups.Count)

  # Best-effort: remove nested members first
  foreach ($g in $groups) {
    try {
      $m = Get-ADGroupMember -Identity $g.DistinguishedName -Recursive -ErrorAction SilentlyContinue
      if ($m) {
        $userMembers  = $m | Where-Object {$_.objectClass -eq 'user'}
        $groupMembers = $m | Where-Object {$_.objectClass -eq 'group'}
        if ($userMembers)  { Remove-ADGroupMember -Identity $g.DistinguishedName -Members ($userMembers  | Select-Object -Expand SamAccountName) -Confirm:$false -ErrorAction SilentlyContinue }
        if ($groupMembers) { Remove-ADGroupMember -Identity $g.DistinguishedName -Members ($groupMembers | Select-Object -Expand SamAccountName) -Confirm:$false -ErrorAction SilentlyContinue }
      }
    } catch { Write-Verbose "Member cleanup warning on $($g.SamAccountName): $($_.Exception.Message)" }
  }

  Remove-ADObjects -Type 'group' -DNs ($groups | Select-Object -Expand DistinguishedName)
}

# ---------- 3) OUs ----------
if ($DoOUs) {
  $ouDNs = @()

  foreach ($ou in @($deptsOU,$groupsOU,$usersOU,$rootOU)) {
    if (Test-OU $ou) { $ouDNs += $ou }
  }

  # Remove child OUs first (Departments often has children)
  $childOUs = @()
  if (Test-OU $deptsOU) {
    try {
      $childOUs = Get-ADOrganizationalUnit -LDAPFilter '(objectClass=organizationalUnit)' -SearchBase $deptsOU -SearchScope OneLevel -ErrorAction SilentlyContinue |
                  Select-Object -Expand DistinguishedName
    } catch {}
  }

  $ordered = @()
  if ($childOUs) { $ordered += $childOUs }
  $ordered += ($ouDNs | Where-Object { $_ -ne $rootOU -and $_ -ne $deptsOU })
  if ($ouDNs -contains $deptsOU) { $ordered += $deptsOU }
  if ($ouDNs -contains $rootOU)  { $ordered += $rootOU }

  # STEP 1: Remove protection from accidental deletion
  Write-Host "Removing protection from accidental deletion..." -ForegroundColor Yellow
  foreach ($ouDN in $ordered) {
    try {
      $ou = Get-ADOrganizationalUnit -Identity $ouDN -ErrorAction SilentlyContinue
      if ($ou) {
        Set-ADOrganizationalUnit -Identity $ouDN -ProtectedFromAccidentalDeletion $false -ErrorAction SilentlyContinue
        Write-Host "  ✓ Unprotected: $($ou.Name)" -ForegroundColor Green
      }
    } catch {
      Write-Verbose "Could not unprotect $ouDN : $($_.Exception.Message)"
    }
  }

  # STEP 2: Now delete the OUs
  Write-Host ("OUs to remove (in order): {0}" -f $ordered.Count)
  Remove-ADObjects -Type 'ou' -DNs $ordered
}

Write-Host "AD reset routine completed. (Use -WhatIf to preview; add -Confirm:`$false to suppress prompts.)" -ForegroundColor Green

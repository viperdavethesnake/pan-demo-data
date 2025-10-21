# demo_report.ps1 — Domain-wide, recursive group membership report (PS 7.5.x)
<#
.SYNOPSIS
  Summarizes demo environment status with domain-wide, recursive group membership counts.

.DESIGNED FOR
  PowerShell 7.x (imports AD with -SkipEditionCheck). Run as Domain Admin or with read access to AD.

.NOTES
  - Counts users in GG_AllEmployees and GG_<Dept> groups domain-wide (no fragile SearchBase).
  - Uses -Recursive to include nested groups (AGDLP).
  - Optional sample member listing for spot checks.
#>

[CmdletBinding()]
param(
  [int]$SampleUsers = 3,
  [switch]$ShowSamples
)

# Modules
Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop

$Domain    = Get-ADDomain
$DomainDN  = $Domain.DistinguishedName
$Depts     = @('Finance','HR','Engineering','Sales','Legal','IT','Ops','Marketing')

function Get-UserCountFromGroup {
  param([Parameter(Mandatory)][string]$GroupSam)
  try {
    $g = Get-ADGroup -LDAPFilter "(sAMAccountName=$GroupSam)" -SearchBase $DomainDN -ErrorAction SilentlyContinue
    if (-not $g) { return @{ Count = 0; Users = @() } }
    $members = Get-ADGroupMember -Identity $g -Recursive -ErrorAction SilentlyContinue | Where-Object { $_.objectClass -eq 'user' }
    $users = @()
    if ($members) {
      # Rehydrate to get sAMAccountName if needed
      $users = $members | ForEach-Object {
        if ($_.PSObject.Properties.Match('SamAccountName').Count -gt 0 -and $_.SamAccountName) { $_.SamAccountName }
        else {
          try { (Get-ADUser -Identity $_.distinguishedName -ErrorAction SilentlyContinue).SamAccountName } catch { $null }
        }
      } | Where-Object { $_ } | Sort-Object -Unique
    }
    return @{ Count = ($users.Count); Users = $users }
  } catch {
    return @{ Count = 0; Users = @() }
  }
}

Write-Host "=== Demo Report (domain: $($Domain.DNSRoot)) ===" -ForegroundColor Cyan

# All Employees
$all = Get-UserCountFromGroup -GroupSam 'GG_AllEmployees'
Write-Host ("AllEmployees present: {0}, members: {1}" -f ($all.Count -ge 0), $all.Count)
if ($ShowSamples -and $all.Users.Count -gt 0) {
  $take = [Math]::Min($SampleUsers, $all.Users.Count)
  Write-Host ("  Samples: {0}" -f (($all.Users | Select-Object -First $take) -join ', '))
}

# Per-department
$rows = foreach ($d in $Depts) {
  $res = Get-UserCountFromGroup -GroupSam ("GG_{0}" -f $d)
  [pscustomobject]@{ Department = $d; Users = $res.Count; Sample = ($res.Users | Select-Object -First $SampleUsers) -join ', ' }
}

$rows | Sort-Object Department | Format-Table -AutoSize

if ($ShowSamples) {
  Write-Host ""
  foreach ($r in ($rows | Sort-Object Department)) {
    if ($r.Sample) { Write-Host ("{0,-12}: {1}" -f $r.Department, $r.Sample) }
  }
}

# ad-populator_v3.ps1
<#
.SYNOPSIS
  Create a realistic, randomized AD for demo/file-share scenarios.

.NOTES
  Run as Domain Admin. Requires ActiveDirectory module.
#>

[CmdletBinding()]
param(
  [string]$BaseOUName = "DemoCorp",
  [string[]]$Departments = @("Finance","HR","Engineering","Sales","Legal","IT","Ops"),

  # Randomized users per department
  [int]$UsersPerDeptMin = 12,
  [int]$UsersPerDeptMax = 55,

  # Extra groups
  [switch]$CreateAccessTiers,            # GG_<Dept>_{RO,RW,Owners}
  [string[]]$RoleGroups = @("Mgmt","Leads","Contractors","Interns","Auditors"), # GG_<Dept>_<Role>
  [switch]$CreateAGDLP,                  # DL_Share_<Dept>_{RO,RW,Owners} <- nest GG_*
  [int]$ProjectsPerDeptMin = 0,
  [int]$ProjectsPerDeptMax = 3,          # PG_<Dept>_<Code>
  [switch]$VerboseSummary
)

Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
$rand = New-Object System.Random

function Ensure-OU {
  param([string]$Name, [string]$ParentDN)
  $ouDN = "OU=$Name,$ParentDN"
  $obj = Get-ADOrganizationalUnit -LDAPFilter "(ou=$Name)" -SearchBase $ParentDN -ErrorAction SilentlyContinue
  if (-not $obj) { New-ADOrganizationalUnit -Name $Name -Path $ParentDN | Out-Null }
  return $ouDN
}

function Ensure-Group {
  param([string]$Name, [string]$Path, [ValidateSet("Global","DomainLocal")] [string]$Scope="Global")
  # Reuse existing group by SamAccountName anywhere in domain
  $domainDN = (Get-ADDomain).DistinguishedName
  $g = Get-ADGroup -LDAPFilter "(sAMAccountName=$Name)" -SearchBase $domainDN -ErrorAction SilentlyContinue
  if ($g) {
    if ($g.DistinguishedName -notlike "*$Path*") {
      try { Move-ADObject -Identity $g.DistinguishedName -TargetPath $Path -ErrorAction Stop } catch {}
    }
    return (Get-ADGroup -Identity $g.DistinguishedName)
  }
  $scopeArg = if ($Scope -eq "DomainLocal") { "DomainLocal" } else { "Global" }
  return New-ADGroup -Name $Name -SamAccountName $Name -GroupScope $scopeArg -GroupCategory Security -Path $Path -PassThru
}

function Add-MembersSafe { param($Group,$Members)
  foreach($m in $Members){ try { Add-ADGroupMember -Identity $Group -Members $m -ErrorAction SilentlyContinue } catch {} }
}

# Domain & OU scaffolding
$domain = Get-ADDomain
$domainDN = $domain.DistinguishedName
$netbios = $domain.NetBIOSName

$rootOU   = Ensure-OU -Name $BaseOUName -ParentDN $domainDN
$usersOU  = Ensure-OU -Name "Users"      -ParentDN $rootOU
$groupsOU = Ensure-OU -Name "Groups"     -ParentDN $rootOU
$deptsOU  = Ensure-OU -Name "Departments"-ParentDN $rootOU

$ggAll = Ensure-Group -Name "GG_AllEmployees" -Path $groupsOU -Scope Global

$totalUsers = 0
$deptUserCounts = @{}
$createdGroups = @()

foreach ($d in $Departments) {
  $deptOU = Ensure-OU -Name $d -ParentDN $deptsOU

  $ggDept = Ensure-Group -Name "GG_${d}" -Path $groupsOU -Scope Global
  $createdGroups += $ggDept.Name
  Add-MembersSafe -Group $ggAll -Members $ggDept

  $tiers = @()
  if ($CreateAccessTiers) {
    foreach($t in @("RO","RW","Owners")){
      $g = Ensure-Group -Name "GG_${d}_$t" -Path $groupsOU -Scope Global
      $createdGroups += $g.Name
      $tiers += $g.Name
      if ($t -eq "RW") { Add-MembersSafe -Group $g -Members $ggDept }
    }
  }

  $roleGs = @()
  foreach ($r in $RoleGroups) {
    $g = Ensure-Group -Name "GG_${d}_$r" -Path $groupsOU -Scope Global
    $createdGroups += $g.Name
    $roleGs += $g.Name
  }

  $dlRW=$null;$dlRO=$null;$dlOwn=$null
  if ($CreateAGDLP) {
    $dlRW  = Ensure-Group -Name "DL_Share_${d}_RW"     -Path $groupsOU -Scope DomainLocal
    $dlRO  = Ensure-Group -Name "DL_Share_${d}_RO"     -Path $groupsOU -Scope DomainLocal
    $dlOwn = Ensure-Group -Name "DL_Share_${d}_Owners" -Path $groupsOU -Scope DomainLocal
    $createdGroups += $dlRW.Name,$dlRO.Name,$dlOwn.Name

    if ($CreateAccessTiers) {
      Add-MembersSafe -Group $dlRW  -Members "GG_${d}_RW"
      Add-MembersSafe -Group $dlRO  -Members "GG_${d}_RO"
      Add-MembersSafe -Group $dlOwn -Members "GG_${d}_Owners"
    } else {
      Add-MembersSafe -Group $dlRW -Members $ggDept
    }
  }

  $uCount = $rand.Next([Math]::Min($UsersPerDeptMin,$UsersPerDeptMax), [Math]::Max($UsersPerDeptMin,$UsersPerDeptMax)+1)
  $deptUserCounts[$d] = $uCount

  $pwd = (ConvertTo-SecureString "P@ssw0rd!123" -AsPlainText -Force)
  for ($i=1; $i -le $uCount; $i++){
    $given = "$d$i"
    $sn    = "User"
    $sam   = ("{0}{1:00}" -f $d.Substring(0,[Math]::Min(8,$d.Length)), $i).ToLower()
    $upn   = "$sam@" + $domain.Forest

    $existing = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -SearchBase $usersOU -ErrorAction SilentlyContinue
    if (-not $existing) {
      New-ADUser -Name "$given $sn" -GivenName $given -Surname $sn `
        -SamAccountName $sam -UserPrincipalName $upn -Enabled $true `
        -AccountPassword $pwd -Path $usersOU -ChangePasswordAtLogon:$false -PasswordNeverExpires:$true | Out-Null
      $totalUsers++
    }

    Add-MembersSafe -Group $ggAll  -Members $sam
    Add-MembersSafe -Group $ggDept -Members $sam

    foreach ($r in $RoleGroups) {
      $prob = switch ($r) {
        "Mgmt"        { 0.05 }
        "Leads"       { 0.10 }
        "Contractors" { 0.15 }
        "Interns"     { 0.07 }
        "Auditors"    { 0.03 }
        default       { 0.05 }
      }
      if ($rand.NextDouble() -lt $prob) {
        Add-MembersSafe -Group "GG_${d}_$r" -Members $sam
      }
    }

    if ($CreateAccessTiers) {
      if ($rand.NextDouble() -lt 0.02) { Add-MembersSafe -Group "GG_${d}_Owners" -Members $sam }
      elseif ($rand.NextDouble() -lt 0.10) { Add-MembersSafe -Group "GG_${d}_RO" -Members $sam }
      else { Add-MembersSafe -Group "GG_${d}_RW" -Members $sam }
    }
  }

  $projCount = $rand.Next([Math]::Max(0,$ProjectsPerDeptMin), [Math]::Max($ProjectsPerDeptMax,$ProjectsPerDeptMin)+1)
  1..$projCount | ForEach-Object {
    $code = ("{0}-{1}" -f @("Apollo","Beacon","Cascade","Delta","Everest","Falcon","Gemini","Helix","Ion","Jupiter")[$rand.Next(0,10)], $rand.Next(10,99))
    $pg = Ensure-Group -Name ("PG_{0}_{1}" -f $d,$code) -Path $groupsOU -Scope Global
    $createdGroups += $pg.Name
    $members = @(Get-ADGroupMember -Identity $ggDept -Recursive -ErrorAction SilentlyContinue | Where-Object {$_.objectClass -eq 'user'})
    if ($members.Count -gt 0) {
      $take = $rand.Next(5, [Math]::Min(20,$members.Count)+1)
      $pick = $members | Get-Random -Count $take
      Add-MembersSafe -Group $pg -Members ($pick | ForEach-Object {$_.SamAccountName})
    }
  }
}

$groupTotal = ($createdGroups | Select-Object -Unique).Count
Write-Host "AD randomized build complete." -ForegroundColor Green
Write-Host ("Departments: {0}" -f ($Departments -join ', '))
Write-Host ("Users created (new only): {0}" -f $totalUsers)
Write-Host ("User counts by dept: " + ($deptUserCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" } -join ', '))
Write-Host ("Groups ensured/created (unique): {0}" -f $groupTotal)
if ($VerboseSummary) {
  Write-Host "Examples of groups:"
  ($createdGroups | Select-Object -Unique | Sort-Object | Select-Object -First 30) | ForEach-Object { Write-Host "  $_" }
}

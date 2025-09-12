# demo-report.ps1
<#
.SYNOPSIS
  Produce a quick AD + Share + Filesystem report for the demo environment.

.PARAMETERS
  -Root   Base folder (default S:\Shared)
  -Domain NetBIOS name (auto)
  -Sample How many sample items to display per category
  -Fast   Skip ACL sampling
#>

[CmdletBinding()]
param(
  [string]$Root = "S:\Shared",
  [string]$Domain = (Get-ADDomain).NetBIOSName,
  [int]$Sample = 10,
  [switch]$Fast
)

Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
Import-Module SmbShare        -SkipEditionCheck -ErrorAction Stop

Write-Host "=== AD Overview ===" -ForegroundColor Cyan
$depts = @("Finance","HR","Engineering","Sales","Legal","IT","Ops")
$ggAll = "$Domain\GG_AllEmployees"
Write-Host ("AllEmployees present: {0}" -f ([bool](Get-ADGroup -LDAPFilter "(sAMAccountName=GG_AllEmployees)" -ErrorAction SilentlyContinue)))

$deptCounts = @{}
$totalUsers = 0
foreach ($d in $depts) {
  $ggDeptSam = "GG_${d}"
  $count = 0
  try {
    $count = (Get-ADGroupMember -Identity "$Domain\$ggDeptSam" -Recursive | Where-Object {$_.objectClass -eq 'user'}).Count
  } catch {}
  $deptCounts[$d] = $count
  $totalUsers += $count
}
Write-Host ("Users by dept: " + ($deptCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" } -join ', '))
Write-Host ("Total users (by membership): {0}" -f $totalUsers)

$patterns = @(
  "GG_*","GG_*_RO","GG_*_RW","GG_*_Owners",
  "GG_*_Mgmt","GG_*_Leads","GG_*_Contractors","GG_*_Interns","GG_*_Auditors",
  "DL_Share_*_RO","DL_Share_*_RW","DL_Share_*_Owners",
  "PG_*_*"
)
$counts = @()
$domainDN = (Get-ADDomain).DistinguishedName
foreach ($p in $patterns) {
  $c = (Get-ADGroup -LDAPFilter "(cn=$p)" -SearchBase $domainDN -ErrorAction SilentlyContinue).Count
  $counts += [pscustomobject]@{ Pattern=$p; Count=$c }
}
$counts | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "`n=== Share & NTFS Overview ($Root) ===" -ForegroundColor Cyan
try {
  $share = Get-SmbShare | Where-Object { $_.Path -eq $Root } | Select-Object -First 1
  if ($share) {
    Write-Host ("Share Name: {0} Path: {1}" -f $share.Name,$share.Path)
    $perm = Get-SmbShareAccess -Name $share.Name | Select-Object Name,AccountName,AccessControlType,AccessRight
    $perm | Format-Table -AutoSize | Out-String | Write-Host
  } else {
    Write-Host "No SMB share found pointing to $Root"
  }
} catch { Write-Host "Share info unavailable: $($_.Exception.Message)" }

$dirCount = (Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue | Measure-Object).Count
$fileCount = (Get-ChildItem -Path $Root -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Host ("Folders: {0}   Files: {1}" -f $dirCount,$fileCount)

if (-not $Fast) {
  Write-Host "`nACL sample scan..."
  $sampled = 0; $protected=0; $deny=0
  $items = Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue | Get-Random -Count ([Math]::Min($Sample, $dirCount))
  foreach ($i in $items) {
    try {
      $acl = Get-Acl -LiteralPath $i.FullName
      if ($acl.AreAccessRulesProtected) { $protected++ }
      foreach ($ace in $acl.Access) { if ($ace.AccessControlType -eq 'Deny') { $deny++ } }
      $sampled++
    } catch {}
  }
  Write-Host ("Sampled folders: {0} | Protected ACLs: {1} | Deny ACEs (total within sample): {2}" -f $sampled,$protected,$deny)
}

Write-Host "`n=== Samples ===" -ForegroundColor Cyan
Get-ChildItem -Path $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First $Sample FullName | Format-Table -AutoSize | Out-String | Write-Host
Get-ChildItem -Path $Root -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First $Sample FullName,Length,LastWriteTime | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "`nReport complete." -ForegroundColor Green

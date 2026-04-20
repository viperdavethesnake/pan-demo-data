# Spot-check: 100 random files + 10 random folders from the 10M build.
# Verifies: scripts actually stamped real owners/ACLs/timestamps/sparse flags
# vs. Windows defaults leaking through.

$ErrorActionPreference = 'Stop'
$now = Get-Date

function Test-SparseFlag([string]$Path) {
    $attrs = [IO.File]::GetAttributes($Path)
    return (($attrs.value__ -band 0x200) -eq 0x200)   # FILE_ATTRIBUTE_SPARSE_FILE
}

Write-Host '=== Loading 100 random files from manifests ===' -ForegroundColor Cyan
$manifests = @(
  'manifest_20260419_180801.jsonl',
  'manifest_20260419_203335.jsonl',
  'manifest_20260419_230750.jsonl',
  'manifest_20260420_020245.jsonl'
) | ForEach-Object { "C:\Users\Administrator\Documents\pan-demo-data\logs\$_" }

# Reservoir sample 100 from all manifest lines combined.
$rng = [System.Random]::new()
$reservoir = New-Object 'System.Collections.Generic.List[string]' 100
$count = 0
foreach ($m in $manifests) {
    Get-Content $m -ReadCount 5000 | ForEach-Object {
        foreach ($line in $_) {
            $count++
            if ($reservoir.Count -lt 100) {
                $reservoir.Add($line)
            } else {
                $j = $rng.Next(0, $count)
                if ($j -lt 100) { $reservoir[$j] = $line }
            }
        }
    }
}
Write-Host ("Sampled from {0:N0} total manifest lines" -f $count)

# Parse sampled records
$records = @()
foreach ($line in $reservoir) {
    if ($line -match '"p":"([^"]+)"') { $p = $matches[1] -replace '\\\\','\' } else { continue }
    $ctStr = if ($line -match '"ct":"([^"]+)"') { $matches[1] } else { $null }
    $wtStr = if ($line -match '"wt":"([^"]+)"') { $matches[1] } else { $null }
    $atStr = if ($line -match '"at":"([^"]+)"') { $matches[1] } else { $null }
    $expOwner = if ($line -match '"o":"([^"]+)"') { $matches[1] -replace '\\\\','\' } else { $null }
    $bucket   = if ($line -match '"b":"([^"]+)"') { $matches[1] } else { $null }
    $records += [pscustomobject]@{
        Path      = $p
        ExpectedOwner  = $expOwner
        ExpectedBucket = $bucket
        ExpectedCT = if ($ctStr) { [datetime]$ctStr } else { $null }
        ExpectedWT = if ($wtStr) { [datetime]$wtStr } else { $null }
        ExpectedAT = if ($atStr) { [datetime]$atStr } else { $null }
    }
}

Write-Host ''
Write-Host '=== Checking 100 files ===' -ForegroundColor Cyan
$stats = @{
    Total          = 0
    Missing        = 0
    SparseOK       = 0
    SparseBad      = 0
    OwnerMatch     = 0
    OwnerMismatch  = 0
    CTOK           = 0  # within 1 sec
    CTBad          = 0
    WTOK           = 0
    WTBad          = 0
    ATOK           = 0
    ATBad          = 0
    InvariantOK    = 0  # CT <= WT <= AT
    InvariantBad   = 0
    FutureDate     = 0
    OwnerSet       = 0  # owner != Administrators/SYSTEM/CREATOR default
}
$anomalies = @()

foreach ($r in $records) {
    $stats.Total++
    if (-not (Test-Path -LiteralPath $r.Path)) {
        $stats.Missing++
        continue
    }
    $fi = Get-Item -LiteralPath $r.Path -Force
    # Sparse
    if (Test-SparseFlag $r.Path) { $stats.SparseOK++ } else { $stats.SparseBad++; $anomalies += "NOT SPARSE: $($r.Path)" }
    # Owner
    try {
        $acl = Get-Acl -LiteralPath $r.Path
        $actualOwner = $acl.Owner
        if ($actualOwner -eq $r.ExpectedOwner) {
            $stats.OwnerMatch++
        } else {
            $stats.OwnerMismatch++
            if ($anomalies.Count -lt 10) {
                $anomalies += "OWNER MISMATCH [$($r.ExpectedBucket)]: $($r.Path) | expected=$($r.ExpectedOwner) actual=$actualOwner"
            }
        }
        if ($actualOwner -and $actualOwner -notin @('BUILTIN\Administrators','NT AUTHORITY\SYSTEM','CREATOR OWNER','')) {
            $stats.OwnerSet++
        }
    } catch {
        if ($anomalies.Count -lt 20) { $anomalies += "ACL READ FAIL: $($r.Path) -> $_" }
    }
    # Timestamps
    if ($r.ExpectedCT) {
        $diff = [Math]::Abs(($fi.CreationTime - $r.ExpectedCT).TotalSeconds)
        if ($diff -lt 2) { $stats.CTOK++ } else { $stats.CTBad++; if ($anomalies.Count -lt 30) { $anomalies += "CT off: $($r.Path) exp=$($r.ExpectedCT) got=$($fi.CreationTime)" } }
    }
    if ($r.ExpectedWT) {
        $diff = [Math]::Abs(($fi.LastWriteTime - $r.ExpectedWT).TotalSeconds)
        if ($diff -lt 2) { $stats.WTOK++ } else { $stats.WTBad++; if ($anomalies.Count -lt 40) { $anomalies += "WT off: $($r.Path) exp=$($r.ExpectedWT) got=$($fi.LastWriteTime)" } }
    }
    if ($r.ExpectedAT) {
        $diff = [Math]::Abs(($fi.LastAccessTime - $r.ExpectedAT).TotalSeconds)
        if ($diff -lt 2) { $stats.ATOK++ } else { $stats.ATBad++; if ($anomalies.Count -lt 50) { $anomalies += "AT off: $($r.Path) exp=$($r.ExpectedAT) got=$($fi.LastAccessTime)" } }
    }
    # Invariants
    if ($fi.CreationTime -le $fi.LastWriteTime -and $fi.LastWriteTime -le $fi.LastAccessTime) {
        $stats.InvariantOK++
    } else {
        $stats.InvariantBad++
        if ($anomalies.Count -lt 60) { $anomalies += "INVARIANT VIOLATED: $($r.Path) CT=$($fi.CreationTime) WT=$($fi.LastWriteTime) AT=$($fi.LastAccessTime)" }
    }
    if ($fi.CreationTime -gt $now -or $fi.LastWriteTime -gt $now -or $fi.LastAccessTime -gt $now) {
        $stats.FutureDate++
    }
}

Write-Host ''
$stats.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0,-16} {1}" -f $_.Name, $_.Value }

if ($anomalies) {
    Write-Host ''
    Write-Host '=== ANOMALIES (first 20) ===' -ForegroundColor Yellow
    $anomalies | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
}

# === Folders ===
Write-Host ''
Write-Host '=== Checking 10 random folders ===' -ForegroundColor Cyan

$folderCandidates = @(
    'S:\Shared\Finance', 'S:\Shared\Engineering\Sensitive',
    'S:\Shared\Engineering\Temp', 'S:\Shared\HR\Employees',
    'S:\Shared\IT\Credentials', 'S:\Shared\Legal\Matters',
    'S:\Shared\Sales\Clients', 'S:\Shared\Marketing\Campaigns',
    'S:\Shared\Board', 'S:\Shared\__Archive'
) | Where-Object { Test-Path $_ } | Get-Random -Count 10

foreach ($f in $folderCandidates) {
    Write-Host ''
    Write-Host "--- $f ---" -ForegroundColor White
    $acl = Get-Acl -LiteralPath $f
    Write-Host "Owner: $($acl.Owner)"
    Write-Host "Inheritance disabled: $($acl.AreAccessRulesProtected)"
    Write-Host ("ACE count: {0}" -f $acl.Access.Count)
    $dlCount = @($acl.Access | Where-Object { $_.IdentityReference -like 'DEMO\DL_Share_*' }).Count
    $ggCount = @($acl.Access | Where-Object { $_.IdentityReference -like 'DEMO\GG_*' }).Count
    $everyone = @($acl.Access | Where-Object { $_.IdentityReference -like '*Everyone*' }).Count
    $deny    = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' }).Count
    Write-Host ("  DL_Share_*: {0}   GG_*: {1}   Everyone: {2}   Deny: {3}" -f $dlCount, $ggCount, $everyone, $deny)
    $acl.Access | Select-Object -First 3 | ForEach-Object {
        Write-Host ("    {0} {1} {2}" -f $_.IdentityReference, $_.AccessControlType, $_.FileSystemRights)
    }
}

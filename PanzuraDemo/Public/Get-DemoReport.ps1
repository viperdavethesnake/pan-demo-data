function Get-DemoReport {
<#
.SYNOPSIS
    Produce a scan-findings-oriented report across AD + filesystem + ACL mess.

.PARAMETER Config
.PARAMETER ExportJson
.PARAMETER ExportCsv
.PARAMETER ExportMarkdown

.OUTPUTS
    Report PSCustomObject; also writes to console.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$ExportJson,
        [string]$ExportCsv,
        [string]$ExportMarkdown
    )

    Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
    $domain   = (Get-ADDomain).NetBIOSName
    $domainDN = (Get-ADDomain).DistinguishedName

    $root = $Config.Share.Root

    Write-Host "=== Demo Report ===" -ForegroundColor Cyan

    # --- AD counts --------------------------------------------------------
    $userCountTotal = 0
    $userByDept = @{}
    foreach ($d in $Config.Departments) {
        $c = 0
        try {
            $g = Get-ADGroup -LDAPFilter "(sAMAccountName=GG_$($d.Name))" -ErrorAction SilentlyContinue
            if ($g) {
                $c = (Get-ADGroupMember -Identity $g -Recursive -ErrorAction SilentlyContinue |
                      Where-Object { $_.objectClass -eq 'user' } |
                      Measure-Object).Count
            }
        } catch {}
        $userByDept[$d.Name] = $c
        $userCountTotal += $c
    }
    $orphanAlive = 0
    try {
        $orphanAlive = (Get-ADUser -LDAPFilter '(employeeType=Former)' -SearchBase $domainDN -ErrorAction SilentlyContinue | Measure-Object).Count
    } catch {}
    $ggGroups = 0; $dlGroups = 0
    try {
        $ggGroups = (Get-ADGroup -LDAPFilter '(sAMAccountName=GG_*)' -SearchBase $domainDN -ErrorAction SilentlyContinue | Measure-Object).Count
        $dlGroups = (Get-ADGroup -LDAPFilter '(sAMAccountName=DL_Share_*)' -SearchBase $domainDN -ErrorAction SilentlyContinue | Measure-Object).Count
    } catch {}

    # --- Filesystem counts ------------------------------------------------
    $fileCount = 0
    $folderCount = 0
    $totalLogical = 0L
    $byDept = @{}
    $byExt = @{}
    $byClass = @{}
    $depthHist = @{}
    $fileCountPerFolder = @{}
    $dormantCount = 0
    $neverReadCount = 0
    $currentWeekStart = (Get-Date).Date.AddDays(-7)
    $currentWeekWriteHits = 0

    # Walk tree
    if (Test-Path -LiteralPath $root) {
        $allDirs = @($root) + [IO.Directory]::EnumerateDirectories($root, '*', [IO.SearchOption]::AllDirectories)
        $folderCount = $allDirs.Count
        foreach ($dir in $allDirs) {
            $rel = Get-RelativeFolderPath -Path $dir -ShareRoot $root
            $depth = ($rel -split '/' | Where-Object { $_ }).Count
            if (-not $depthHist.ContainsKey($depth)) { $depthHist[$depth] = 0 }
            $depthHist[$depth]++
            $dept = Resolve-DeptFromPath -Path $dir -ShareRoot $root -Departments $Config.Departments
            if (-not $dept) { $dept = '(cross-dept)' }
            try {
                $files = [IO.Directory]::EnumerateFiles($dir)
                $inFolder = 0
                foreach ($f in $files) {
                    $fileCount++
                    $inFolder++
                    $fi = New-Object System.IO.FileInfo($f)
                    $totalLogical += $fi.Length
                    $ext = $fi.Extension.ToLower()
                    if (-not $byExt.ContainsKey($ext)) { $byExt[$ext] = 0 }
                    $byExt[$ext]++
                    if (-not $byDept.ContainsKey($dept)) { $byDept[$dept] = 0 }
                    $byDept[$dept]++
                    $lw = $fi.LastWriteTime
                    $la = $fi.LastAccessTime
                    if ($la -lt (Get-Date).AddDays(-1095)) { $dormantCount++ }
                    if ([math]::Abs(($la - $lw).TotalSeconds) -lt 60) { $neverReadCount++ }
                    if ($lw -ge $currentWeekStart) { $currentWeekWriteHits++ }
                }
                $bucket = switch ($inFolder) {
                    0 { '0' }
                    { $_ -ge 1 -and $_ -le 10 }     { '1-10' }
                    { $_ -ge 11 -and $_ -le 100 }   { '11-100' }
                    { $_ -ge 101 -and $_ -le 1000 } { '101-1k' }
                    { $_ -ge 1001 -and $_ -le 10000 } { '1k-10k' }
                    default { '10k+' }
                }
                if (-not $fileCountPerFolder.ContainsKey($bucket)) { $fileCountPerFolder[$bucket] = 0 }
                $fileCountPerFolder[$bucket]++
            } catch {}
        }
    }

    # --- ACL mess scan (by sampling folders + files) -----------------------
    # Going cheap: walk all folder ACLs once, tally principal patterns.
    $aclFindings = @{
        EveryoneAce     = 0
        OrphanSidAce    = 0
        DenyAce         = 0
        InheritanceBroken = 0
        GGDirect        = 0
        DLShareAce      = 0
        BuiltinAdminOwner = 0
    }
    $aclOrphanSamples = @()

    if (Test-Path -LiteralPath $root) {
        foreach ($dir in @($root) + [IO.Directory]::EnumerateDirectories($root, '*', [IO.SearchOption]::AllDirectories)) {
            try {
                $acl = Get-Acl -LiteralPath $dir
                if ($acl.AreAccessRulesProtected) { $aclFindings.InheritanceBroken++ }
                foreach ($r in $acl.Access) {
                    $id = $r.IdentityReference.Value
                    if ($r.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny) { $aclFindings.DenyAce++ }
                    if ($id -match '^Everyone$|^NT AUTHORITY\\Authenticated Users$') { $aclFindings.EveryoneAce++ }
                    if ($id -match 'S-1-5-21-') { $aclFindings.OrphanSidAce++; if ($aclOrphanSamples.Count -lt 3) { $aclOrphanSamples += "$dir -> $id" } }
                    if ($id -match "^$domain\\GG_[A-Za-z&]+$" -and $id -notmatch 'GG_AllEmployees|GG_Contractors|GG_BackupOps') { $aclFindings.GGDirect++ }
                    if ($id -match "^$domain\\DL_Share_") { $aclFindings.DLShareAce++ }
                }
                if ($acl.Owner -eq 'BUILTIN\Administrators') { $aclFindings.BuiltinAdminOwner++ }
            } catch {}
        }
    }

    # File-ownership breakdown (sample up to 2000 random files for speed at scale)
    $fileOwnerCounts = @{
        DeptGroup = 0; User = 0; ServiceAccount = 0; OrphanSid = 0; BuiltinAdmin = 0; Other = 0
    }
    $fileExplicitAce = 0
    $fileDetached = 0
    $fileOrphanOwner = 0

    if ((Test-Path -LiteralPath $root) -and ($fileCount -gt 0)) {
        $sampleSize = [math]::Min(2000, $fileCount)
        $allFiles = [IO.Directory]::EnumerateFiles($root, '*', [IO.SearchOption]::AllDirectories) | Select-Object -First $sampleSize
        $realSams = @{}
        foreach ($d in $Config.Departments) {
            try {
                $members = Get-ADGroupMember -Identity "GG_$($d.Name)" -ErrorAction SilentlyContinue | Where-Object { $_.objectClass -eq 'user' }
                foreach ($m in $members) { $realSams[$m.SamAccountName] = $true }
            } catch {}
        }
        $svcSams = @{}
        foreach ($s in $Config.Mess.ServiceAccounts) { $svcSams[$s.Name] = $true }
        foreach ($f in $allFiles) {
            try {
                $acl = Get-Acl -LiteralPath $f
                $ownerStr = $acl.Owner
                $bucket = 'Other'
                if ($ownerStr -eq 'BUILTIN\Administrators') { $bucket = 'BuiltinAdmin' }
                elseif ($ownerStr -match 'S-1-5-21-') { $bucket = 'OrphanSid'; $fileOrphanOwner++ }
                elseif ($ownerStr -match "^$domain\\GG_") { $bucket = 'DeptGroup' }
                else {
                    $sam = ($ownerStr -split '\\')[-1]
                    if ($svcSams.ContainsKey($sam)) { $bucket = 'ServiceAccount' }
                    elseif ($realSams.ContainsKey($sam)) { $bucket = 'User' }
                }
                $fileOwnerCounts[$bucket]++
                if ($acl.AreAccessRulesProtected) { $fileDetached++ }
                foreach ($r in $acl.Access) {
                    if (-not $r.IsInherited) { $fileExplicitAce++; break }
                }
            } catch {}
        }
        $sampleN = $allFiles.Count
    } else {
        $sampleN = 0
    }

    # --- Predicted scan findings --------------------------------------------
    $findings = @(
        [pscustomobject]@{ Category='Orphan SIDs on ACLs';                   Count=$aclFindings.OrphanSidAce + $fileOrphanOwner; Severity='High' }
        [pscustomobject]@{ Category='Everyone / AuthUsers ACE';              Count=$aclFindings.EveryoneAce;                     Severity='High' }
        [pscustomobject]@{ Category='Deny ACEs';                             Count=$aclFindings.DenyAce;                         Severity='Medium' }
        [pscustomobject]@{ Category='GG_* directly on ACL (non-AGDLP)';      Count=$aclFindings.GGDirect;                        Severity='Medium' }
        [pscustomobject]@{ Category='Inheritance broken (folders)';          Count=$aclFindings.InheritanceBroken;               Severity='Medium' }
        [pscustomobject]@{ Category='Dormant files (>3yr LastAccess)';       Count=$dormantCount;                                Severity='Low' }
        [pscustomobject]@{ Category='Files owned by BUILTIN\Administrators'; Count=$fileOwnerCounts.BuiltinAdmin;                Severity='Low'; Sampled=$sampleN }
        [pscustomobject]@{ Category='Files with explicit ACEs (sampled)';    Count=$fileExplicitAce;                             Severity='Medium'; Sampled=$sampleN }
        [pscustomobject]@{ Category='Files with detached ACL (sampled)';     Count=$fileDetached;                                Severity='Medium'; Sampled=$sampleN }
        [pscustomobject]@{ Category='Service-account-owned files (sampled)'; Count=$fileOwnerCounts.ServiceAccount;              Severity='Low'; Sampled=$sampleN }
    )

    $report = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('o')
        Domain      = $domain
        Share       = $Config.Share
        AD          = [pscustomobject]@{
            Users            = $userCountTotal
            UsersByDept      = $userByDept
            OrphansAlive     = $orphanAlive
            GGGroups         = $ggGroups
            DLShareGroups    = $dlGroups
        }
        Filesystem  = [pscustomobject]@{
            Folders                  = $folderCount
            Files                    = $fileCount
            TotalLogicalBytes        = $totalLogical
            DormantFiles             = $dormantCount
            NeverReadFiles           = $neverReadCount
            CurrentWeekWrites        = $currentWeekWriteHits
            DepthHistogram           = $depthHist
            FilesPerFolderHistogram  = $fileCountPerFolder
            ExtensionsTop20          = ($byExt.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20)
            FilesByDept              = $byDept
        }
        AclMess     = [pscustomobject]@{
            InheritanceBroken        = $aclFindings.InheritanceBroken
            EveryoneAce              = $aclFindings.EveryoneAce
            OrphanSidFolderAce       = $aclFindings.OrphanSidAce
            GGDirectOnAcl            = $aclFindings.GGDirect
            DLShareOnAcl             = $aclFindings.DLShareAce
            DenyAce                  = $aclFindings.DenyAce
            OrphanSamples            = $aclOrphanSamples
            FileOwnershipMix         = $fileOwnerCounts
            FileOwnerSampleN         = $sampleN
            FileExplicitAce          = $fileExplicitAce
            FileDetachedAcl          = $fileDetached
        }
        Findings    = $findings
    }

    # --- Console summary ---------------------------------------------------
    Write-Host ""
    Write-Host "AD"
    Write-Host ("  Users (recursive GG_*):  {0}" -f $userCountTotal)
    Write-Host ("  Orphan-flagged alive:    {0}" -f $orphanAlive)
    Write-Host ("  GG_* groups:             {0}" -f $ggGroups)
    Write-Host ("  DL_Share_* groups:       {0}" -f $dlGroups)
    Write-Host ""
    Write-Host "Filesystem"
    Write-Host ("  Folders: {0}, Files: {1}" -f $folderCount, $fileCount)
    Write-Host ("  Logical bytes: {0:N0}" -f $totalLogical)
    Write-Host ("  Dormant (>3yr LastAccess): {0} ({1:P1})" -f $dormantCount, ($(if ($fileCount -gt 0) { $dormantCount / [double]$fileCount } else { 0 })))
    Write-Host ("  Files with LastWrite in current week: {0}" -f $currentWeekWriteHits)
    Write-Host ""
    Write-Host "ACL mess"
    Write-Host ("  Inheritance broken: {0}" -f $aclFindings.InheritanceBroken)
    Write-Host ("  Everyone ACE:       {0}" -f $aclFindings.EveryoneAce)
    Write-Host ("  Orphan folder ACE:  {0}" -f $aclFindings.OrphanSidAce)
    Write-Host ("  GG_* direct ACE:    {0}" -f $aclFindings.GGDirect)
    Write-Host ("  DL_Share_* ACE:     {0}" -f $aclFindings.DLShareAce)
    Write-Host ("  Deny ACE:           {0}" -f $aclFindings.DenyAce)
    Write-Host ""
    Write-Host "File ownership (sampled $sampleN files)"
    foreach ($k in $fileOwnerCounts.Keys | Sort-Object) {
        Write-Host ("  {0,-18} {1}" -f $k, $fileOwnerCounts[$k])
    }
    Write-Host ""
    Write-Host "Predicted scan findings"
    $findings | Format-Table Category, Count, Severity -AutoSize | Out-Host

    # --- Exports ----------------------------------------------------------
    if ($ExportJson)     { $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ExportJson -Encoding UTF8 }
    if ($ExportCsv)      { $findings | Export-Csv -Path $ExportCsv -NoTypeInformation }
    if ($ExportMarkdown) { Write-ReportMarkdown -Report $report -Path $ExportMarkdown }

    return $report
}

function Write-ReportMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Report, [Parameter(Mandatory)][string]$Path)
    $lines = @()
    $lines += "# PanzuraDemo Report"
    $lines += ""
    $lines += "Generated: $($Report.GeneratedAt)"
    $lines += "Domain: $($Report.Domain)"
    $lines += "Share: $($Report.Share.Root) ($($Report.Share.Name))"
    $lines += ""
    $lines += "## AD"
    $lines += ("- Users: $($Report.AD.Users)")
    $lines += ("- Orphans alive: $($Report.AD.OrphansAlive)")
    $lines += ("- GG groups: $($Report.AD.GGGroups), DL_Share groups: $($Report.AD.DLShareGroups)")
    $lines += ""
    $lines += "## Filesystem"
    $lines += ("- Folders: $($Report.Filesystem.Folders), Files: $($Report.Filesystem.Files)")
    $lines += ("- Logical bytes: {0:N0}" -f $Report.Filesystem.TotalLogicalBytes)
    $lines += ("- Dormant files: $($Report.Filesystem.DormantFiles)")
    $lines += ""
    $lines += "## Predicted scan findings"
    $lines += "| Category | Count | Severity |"
    $lines += "|---|---:|---|"
    foreach ($f in $Report.Findings) {
        $lines += "| $($f.Category) | $($f.Count) | $($f.Severity) |"
    }
    Set-Content -LiteralPath $Path -Value ($lines -join "`r`n") -Encoding UTF8
}

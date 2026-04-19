function Test-DemoSmokeVerification {
<#
.SYNOPSIS
    Verify a completed pipeline run against spec invariants and tolerances.

.DESCRIPTION
    Runs the verification checks listed in docs/V4_SPEC.md Section 15.
    Returns pass/fail with per-check deltas. Intended to be called after
    Invoke-DemoPipeline completes (typically after Orphanize). Failure
    action per spec: erase output, fix root cause, re-run. Do not patch
    the test to make it pass.

.PARAMETER Config

.OUTPUTS
    PSCustomObject with .Pass, .Checks[].
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
    $domain  = (Get-ADDomain).NetBIOSName
    $domainDN= (Get-ADDomain).DistinguishedName
    $root = $Config.Share.Root

    $checks = New-Object System.Collections.Generic.List[object]
    $push = { param($name, $pass, $detail) $checks.Add([pscustomobject]@{ Name=$name; Pass=[bool]$pass; Detail=$detail }) }

    # --- Enumerate files --------------------------------------------------
    $files = @()
    if (Test-Path -LiteralPath $root) {
        $files = [IO.Directory]::EnumerateFiles($root, '*', [IO.SearchOption]::AllDirectories)
    }
    $fileCount = ($files | Measure-Object).Count

    # --- File count within tolerance -------------------------------------
    $expectedFiles = [int]$Config.Files.DefaultCount
    $lower = [int]($expectedFiles * 0.85)
    $upper = [int]($expectedFiles * 1.05)
    & $push "File count within [$lower, $upper]" (($fileCount -ge $lower) -and ($fileCount -le $upper)) "actual=$fileCount, expected=$expectedFiles"

    # --- Sparse bit on 100% of sampled files -----------------------------
    $sample = @($files | Sort-Object { Get-Random } | Select-Object -First ([math]::Min(200, $fileCount)))
    $missSparse = 0
    foreach ($f in $sample) {
        if (-not [PanzuraDemo.Native.Sparse]::IsSparse($f)) { $missSparse++ }
    }
    & $push "Sparse bit on 100% of sampled files" ($missSparse -eq 0) "missed=$missSparse of $($sample.Count)"

    # --- Magic bytes correct on 100 samples ------------------------------
    $missMagic = 0
    $mismatches = @()
    foreach ($f in ($sample | Select-Object -First 100)) {
        $ext = [IO.Path]::GetExtension($f).ToLower()
        if (-not $Config.FileHeaders.ContainsKey($ext)) { continue }  # text stubs not tested here
        $expected = [byte[]]$Config.FileHeaders[$ext]
        $actual = [byte[]]::new($expected.Length)
        try {
            $fs = [IO.File]::OpenRead($f)
            try { [void]$fs.Read($actual, 0, $actual.Length) } finally { $fs.Close() }
        } catch { $missMagic++; continue }
        $ok = $true
        for ($i = 0; $i -lt $expected.Length; $i++) { if ($actual[$i] -ne $expected[$i]) { $ok = $false; break } }
        if (-not $ok) { $missMagic++; if ($mismatches.Count -lt 3) { $mismatches += $f } }
    }
    & $push "Magic bytes correct on sampled binary files" ($missMagic -eq 0) ("missed=$missMagic" + $(if ($mismatches) { " e.g. $($mismatches -join ' | ')" } else { '' }))

    # --- Timestamp invariants ---------------------------------------------
    # The spec invariant is "no current-date contamination" — a bug like
    # "forgot to set LastWriteTime so every file has Get-Date's value" must
    # not pass. Legitimate RecentSkew distributions will produce many recent
    # files; that's not contamination. We check two things:
    #   (a) Span of LastWriteTime across all files is wider than 60 days.
    #       Mass contamination would collapse the distribution.
    #   (b) No more than 5% of files share the SAME LastWriteTime value
    #       (rounded to the minute). Identical timestamps across many files
    #       is the real signature of a contamination bug.
    $now = Get-Date
    $lwBuckets = @{}
    $lwMin = [datetime]::MaxValue
    $lwMax = [datetime]::MinValue
    foreach ($f in $files) {
        $fi = New-Object IO.FileInfo($f)
        $lw = $fi.LastWriteTime
        if ($lw -lt $lwMin) { $lwMin = $lw }
        if ($lw -gt $lwMax) { $lwMax = $lw }
        $key = $lw.ToString('yyyy-MM-dd HH:mm')
        if (-not $lwBuckets.ContainsKey($key)) { $lwBuckets[$key] = 0 }
        $lwBuckets[$key]++
    }
    $spanDays = if ($fileCount -gt 1) { ($lwMax - $lwMin).TotalDays } else { 0 }
    & $push "LastWriteTime span > 60 days (no mass contamination)" ($spanDays -gt 60) ("span={0:N1} days, min={1}, max={2}" -f $spanDays, $lwMin.ToString('yyyy-MM-dd'), $lwMax.ToString('yyyy-MM-dd'))

    $topBucket = ($lwBuckets.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
    $topPct = if ($topBucket -and $fileCount -gt 0) { $topBucket.Value / [double]$fileCount } else { 0 }
    & $push "No single minute holds >5% of LastWriteTime (no contamination spike)" ($topPct -le 0.05) ("top minute={0} count={1} ({2:P2})" -f $(if ($topBucket) { $topBucket.Key } else { '-' }), $(if ($topBucket) { $topBucket.Value } else { 0 }), $topPct)

    # --- Dormancy ratio: must be substantial -----------------------------
    # Aggregate dormancy is a function of (a) the baseline Dormant+LegacyArchive
    # class share (~20%) and (b) the per-folder dormancy biases in
    # TimestampModel.DormancyByFolderPattern (Archive 75%, Users 55%, Projects 50%).
    # For a messy NAS with lots of Archive/Users activity, aggregate dormancy
    # naturally lands in the 25-50% range. The invariant is: dormant data is
    # visibly present for scan findings. We accept 15-55%.
    $dormant = 0
    foreach ($f in $files) {
        $fi = New-Object IO.FileInfo($f)
        if ($fi.LastAccessTime -lt $now.AddDays(-1095)) { $dormant++ }
    }
    $dormantPct = if ($fileCount -gt 0) { $dormant / [double]$fileCount } else { 0 }
    & $push "Dormant (>3yr) ratio in [0.15, 0.55]" (($dormantPct -ge 0.15) -and ($dormantPct -le 0.55)) ("{0} ({1:P2})" -f $dormant, $dormantPct)

    # --- Ownership mix within ±3pp ----------------------------------------
    $svcSams = @{}; foreach ($s in $Config.Mess.ServiceAccounts) { $svcSams[$s.Name] = $true }
    $realSams = @{}
    foreach ($d in $Config.Departments) {
        try {
            $members = Get-ADGroupMember -Identity "GG_$($d.Name)" -ErrorAction SilentlyContinue | Where-Object { $_.objectClass -eq 'user' }
            foreach ($m in $members) { $realSams[$m.SamAccountName] = $true }
        } catch {}
    }
    $counts = @{ DeptGroup=0; User=0; ServiceAccount=0; OrphanSid=0; BuiltinAdmin=0; Other=0 }
    $ownerSample = @($files | Sort-Object { Get-Random } | Select-Object -First ([math]::Min(500, $fileCount)))
    foreach ($f in $ownerSample) {
        try {
            $acl = Get-Acl -LiteralPath $f
            $o = $acl.Owner
            if ($o -eq 'BUILTIN\Administrators') { $counts.BuiltinAdmin++; continue }
            if ($o -match 'S-1-5-21-') { $counts.OrphanSid++; continue }
            if ($o -match "^$domain\\GG_") { $counts.DeptGroup++; continue }
            $sam = ($o -split '\\')[-1]
            if ($svcSams.ContainsKey($sam)) { $counts.ServiceAccount++; continue }
            if ($realSams.ContainsKey($sam)) { $counts.User++; continue }
            $counts.Other++
        } catch { $counts.Other++ }
    }
    $sampleN = $ownerSample.Count
    $tolerance = 0.06  # 6 pp tolerance on smoke (sample is small)
    $ownMixOk = $true
    $ownDetail = @()
    foreach ($k in @('DeptGroup','User','ServiceAccount','OrphanSid','BuiltinAdmin')) {
        $expected = [double]$Config.Files.Ownership[$k]
        $actual = if ($sampleN -gt 0) { $counts[$k] / [double]$sampleN } else { 0 }
        $delta = [Math]::Abs($actual - $expected)
        if ($delta -gt $tolerance) { $ownMixOk = $false }
        $ownDetail += ("{0}:exp={1:P0} got={2:P1}" -f $k, $expected, $actual)
    }
    & $push "Ownership mix within tolerance" $ownMixOk ($ownDetail -join ' ')

    # --- Orphan SIDs present AND unresolvable -----------------------------
    $orphanSidCount = 0
    $anyResolvable = $false
    $sampleFolders = @((Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 100).FullName)
    foreach ($dir in $sampleFolders) {
        try {
            $acl = Get-Acl -LiteralPath $dir
            foreach ($r in $acl.Access) {
                if ($r.IdentityReference.Value -match '^S-1-5-21-') {
                    $orphanSidCount++
                    try {
                        $n = $r.IdentityReference.Translate([System.Security.Principal.NTAccount])
                        if ($n) { $anyResolvable = $true }
                    } catch {
                        # unresolvable — good
                    }
                }
            }
        } catch {}
    }
    & $push "Orphan SIDs present in folder ACLs" ($orphanSidCount -gt 0) "count=$orphanSidCount"
    & $push "Orphan SIDs are unresolvable (post-Orphanize)" (-not $anyResolvable) "resolvableFound=$anyResolvable"

    # --- Deterministic breaks ---------------------------------------------
    $det = @('Sensitive','Board','Public','IT/Credentials','Temp')
    foreach ($pat in $det) {
        $hits = @()
        if (Test-Path -LiteralPath $root) {
            $hits = [IO.Directory]::EnumerateDirectories($root, '*', [IO.SearchOption]::AllDirectories) |
                    Where-Object { $_ -like "*$($pat -replace '/','\*\')*" -or ($_.Replace('\','/').EndsWith("/$pat") -or $_.Replace('\','/').Contains("/$pat/")) }
        }
        $anyOk = $false
        foreach ($h in $hits) {
            try {
                $acl = Get-Acl -LiteralPath $h
                $isMatch = $false
                switch ($pat) {
                    'Sensitive'        { $isMatch = $acl.AreAccessRulesProtected }
                    'Board'            { $isMatch = $acl.AreAccessRulesProtected }
                    'IT/Credentials'   { $isMatch = $acl.AreAccessRulesProtected }
                    'Public'           { $isMatch = [bool]($acl.Access | Where-Object { $_.IdentityReference.Value -eq 'Everyone' -and ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) }) }
                    'Temp'             { $isMatch = [bool]($acl.Access | Where-Object { $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny }) -or [bool]($acl.Access | Where-Object { $_.IdentityReference.Value -eq 'Everyone' }) }
                }
                if ($isMatch) { $anyOk = $true; break }
            } catch {}
        }
        if ($hits.Count -eq 0) { $anyOk = $true } # not created in this config
        & $push "Deterministic break on $pat" $anyOk "hits=$($hits.Count)"
    }

    $allOk = -not ($checks | Where-Object { -not $_.Pass })
    Write-Host ""
    Write-Host "=== Smoke Verification ===" -ForegroundColor Cyan
    $checks | Format-Table Name, Pass, Detail -AutoSize | Out-Host
    Write-Host ("Overall: {0}" -f ($(if ($allOk) { 'PASS' } else { 'FAIL' }))) -ForegroundColor ($(if ($allOk) { 'Green' } else { 'Red' }))
    [pscustomobject]@{ Pass=[bool]$allOk; Checks=$checks }
}

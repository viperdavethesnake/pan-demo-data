function New-DemoFile {
<#
.SYNOPSIS
    Generate files into the existing folder tree: sparse with correct magic,
    realistic names, heavy-tail distribution, 5-way ownership mix, coherent
    timestamps, and file-level ACL mess. Additive across runs.

.DESCRIPTION
    1. Enumerates folders under Config.Share.Root.
    2. Plans per-folder file counts via heavy-tail bucket sampler.
    3. Draws per-folder era dates (T2 coherence) once per run.
    4. Per file: picks ext, name, size, class, timestamps, creates sparse file,
       sets attributes+ADS, sets owner, applies file-level ACL mess, applies
       timestamps last (invariant: see spec section 2).
    5. Respects -MaxFiles; clamps total.
    6. Writes logs/manifest-<ts>.jsonl with created file records.

.PARAMETER Config
.PARAMETER MaxFiles
    Overrides scenario/default file count for this run.
.PARAMETER DatePreset
.PARAMETER MinDate
.PARAMETER MaxDate
.PARAMETER RecentBias
.PARAMETER Parallel
    Experimental. Uses ForEach-Object -Parallel for file IO; ownership + ACL
    mess are post-passes either way. Bench data (decision log #19): parallel
    is measurably SLOWER than sequential on NTFS for this workload because
    (a) ACL ops serialize at the kernel, (b) per-item runspace serialization
    overhead exceeds any kernel-concurrency gain. Default is sequential.
    Leave this off unless you have a reason.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Nullable[long]]$MaxFiles,
        [ValidateSet('Uniform','RecentSkew','YearSpread','LegacyMess')]
        [string]$DatePreset,
        [Nullable[datetime]]$MinDate,
        [Nullable[datetime]]$MaxDate,
        [Nullable[int]]$RecentBias,
        [switch]$Parallel
    )

    Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop

    # --- Resolve parameters against config defaults --------------------
    if (-not $MaxFiles) { $MaxFiles = [long]$Config.Files.DefaultCount }
    if (-not $DatePreset) { $DatePreset = $Config.Files.DefaultDatePreset }
    if (-not $RecentBias) { $RecentBias = [int]$Config.Files.DefaultRecentBias }
    if (-not $MinDate) { $MinDate = (Get-Date).AddYears(-3) }
    if (-not $MaxDate) { $MaxDate = (Get-Date) }

    $root = $Config.Share.Root
    if (-not (Test-Path -LiteralPath $root)) { throw "Share root not found: $root" }

    Write-Host "=== New-DemoFile: MaxFiles=$MaxFiles Preset=$DatePreset Bias=$RecentBias ===" -ForegroundColor Cyan

    # --- Build AD cache (once) -----------------------------------------
    $adCache = Get-ADUserCache -Config $Config

    # --- Scan folder tree -----------------------------------------------
    Write-Host "  Scanning folder tree..."
    $allFolders = @($root)
    $allFolders += [IO.Directory]::EnumerateDirectories($root, '*', [IO.SearchOption]::AllDirectories)
    Write-Host ("  Folders: {0}" -f $allFolders.Count)

    # --- Plan: per-folder file counts (heavy-tail) -----------------------
    $rng = [System.Random]::new()
    $plan = @()
    foreach ($folder in $allFolders) {
        $bucket = Get-HeavyTailBucket -Distribution $Config.Files.HeavyTailDistribution -Rng $rng
        if ($bucket.Count -le 0) { continue }
        $plan += [pscustomobject]@{
            Path  = $folder
            Count = $bucket.Count
            Bucket= $bucket.Bucket
        }
    }
    # Clamp to MaxFiles (proportional scaling down)
    $totalPlanned = ($plan | Measure-Object -Property Count -Sum).Sum
    if ($totalPlanned -gt $MaxFiles) {
        $scale = [double]$MaxFiles / [double]$totalPlanned
        foreach ($row in $plan) {
            $row.Count = [int]([math]::Floor($row.Count * $scale))
        }
        $plan = $plan | Where-Object { $_.Count -gt 0 }
    }
    $totalPlanned = ($plan | Measure-Object -Property Count -Sum).Sum
    Write-Host ("  Planned: {0} files across {1} non-empty folders" -f $totalPlanned, $plan.Count)

    # Write plan
    $logsDir = Join-Path (Split-Path -Parent $Config.ModuleRoot) 'logs'
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $planPath     = Join-Path $logsDir ("plan_{0}.jsonl" -f $ts)
    $manifestPath = Join-Path $logsDir ("manifest_{0}.jsonl" -f $ts)
    $plan | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $planPath -Encoding UTF8

    # --- Folder-era cache ------------------------------------------------
    $eraCache = @{}

    # --- Execute ---
    $created = 0
    $errors = 0
    $start = Get-Date
    $ownershipHits = @{ DeptGroup=0; User=0; ServiceAccount=0; OrphanSid=0; BuiltinAdmin=0 }
    $classHits = @{}
    $manifestWriter = [System.IO.StreamWriter]::new($manifestPath, $false, [System.Text.Encoding]::UTF8)

    if ($Parallel) {
        # --- PARALLEL PATH ------------------------------------------------
        # Parent plans every item (via same helpers as sequential), buffers
        # into chunks, dispatches each chunk to Invoke-ParallelFileChunk
        # (ForEach-Object -Parallel). Worker runspaces do pure IO only.
        # Ownership + file-level ACL mess are applied in a post-pass after
        # all chunks complete (icacls batch for owner, individual Set-Acl
        # for the ~3% mess). This avoids ACL-path kernel serialization.
        $throttle = [int]$Config.Parallel.ThrottleLimit
        if ($throttle -le 0) { $throttle = [Environment]::ProcessorCount * 2 }
        $chunkSize = 50000
        $buffer = New-Object System.Collections.Generic.List[object]
        $plannedPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        Write-Host ("  Parallel mode: throttle={0}, chunkSize={1}" -f $throttle, $chunkSize)

        try {
            foreach ($row in $plan) {
                if (($created + $buffer.Count) -ge $MaxFiles) { break }
                $folder = $row.Path
                $relFolder = Get-RelativeFolderPath -Path $folder -ShareRoot $root
                $dept = Resolve-DeptFromPath -Path $folder -ShareRoot $root -Departments $Config.Departments
                if (-not $dept) { $dept = 'General' }
                $deptRec = $Config.Departments | Where-Object { $_.Name -eq $dept } | Select-Object -First 1
                if (-not $deptRec) { $deptRec = $Config.Departments[0] }

                $era = Get-FolderEra -FolderPath $folder -Cache $eraCache `
                    -MinDate $MinDate -MaxDate $MaxDate -DatePreset $DatePreset `
                    -RecentBias $RecentBias `
                    -ArchiveYearOverrides ([bool]$Config.Files.ArchiveYearOverrides) -Rng $rng

                for ($i = 0; $i -lt $row.Count; $i++) {
                    if (($created + $buffer.Count) -ge $MaxFiles) { break }
                    try {
                        $hintExt = Get-WeightedChoice -Weights $deptRec.Extensions -Rng $rng
                        if (-not $Config.ExtensionProperties.ContainsKey($hintExt)) { continue }

                        $class = Get-FileClassRoll -Config $Config -RelFolderPath $relFolder -Rng $rng
                        if (-not $classHits.ContainsKey($class.Name)) { $classHits[$class.Name] = 0 }
                        $classHits[$class.Name]++

                        $ct = $null
                        if ($class.Name -in @('Dormant','LegacyArchive')) {
                            $oldUpper = (Get-Date).AddDays(-1096)
                            $oldLower = (Get-Date).AddDays(-1825)
                            $span = ($oldUpper - $oldLower).TotalDays
                            $ct = $oldLower.AddDays($rng.NextDouble() * $span)
                        } elseif ($Config.Files.FolderCoherence) {
                            $window = [int]$Config.Files.FolderEraWindowDays
                            $ct = Get-EraJitteredDate -Era $era -WindowDays $window -NowClamp $MaxDate -MinClamp $MinDate -Rng $rng
                        } else {
                            $ct = Get-RealisticDate -MinDate $MinDate -MaxDate $MaxDate -Preset $DatePreset -Bias $RecentBias -Rng $rng
                        }
                        $ts = Get-FileTimestampSet -Creation $ct -FileClass $class -NowClamp $MaxDate -Rng $rng

                        $fname = Get-FileName -Config $Config -RelFolderPath $relFolder -Extension $hintExt -CreationTime $ts.CreationTime -Department $dept -Rng $rng
                        $ext = [IO.Path]::GetExtension($fname).ToLower()
                        if (-not $Config.ExtensionProperties.ContainsKey($ext)) {
                            $fname = $fname + $hintExt
                            $ext = $hintExt
                        }
                        $sizeKB = $rng.Next([int]$Config.ExtensionProperties[$ext].MinKB, [int]$Config.ExtensionProperties[$ext].MaxKB + 1)
                        if ($sizeKB -lt 1) { $sizeKB = 1 }
                        $sizeBytes = [long]$sizeKB * 1024L

                        $filePath = Join-Path $folder $fname
                        # Uniqueness across this run's planned paths AND pre-existing files.
                        if ($plannedPaths.Contains($filePath) -or (Test-Path -LiteralPath $filePath)) {
                            $filePath = Join-Path $folder ("{0}_{1}{2}" -f ([IO.Path]::GetFileNameWithoutExtension($fname)), $rng.Next(10000,99999), $ext)
                        }
                        [void]$plannedPaths.Add($filePath)

                        $hdr = Write-FileMagic -Config $Config -Extension $ext -CreationTime $ts.CreationTime

                        # Attributes
                        $attrs = [int][IO.FileAttributes]::Normal
                        if ($rng.NextDouble() -lt [double]$Config.Files.Attributes.ReadOnlyChance) { $attrs = [int][IO.FileAttributes]::ReadOnly }
                        if ($rng.NextDouble() -lt [double]$Config.Files.Attributes.HiddenChance) {
                            $attrs = $attrs -bor [int][IO.FileAttributes]::Hidden
                            if ($attrs -band [int][IO.FileAttributes]::Normal) { $attrs = $attrs -band -bnot [int][IO.FileAttributes]::Normal }
                        }
                        $adsWanted = $rng.NextDouble() -lt [double]$Config.Files.Attributes.AdsChance

                        # Owner
                        $owner = Resolve-OwnerForFile -Config $Config -FilePath $filePath -Department $dept -ADCache $adCache -Rng $rng

                        # File-level ACL mess decision (pre-compute; worker just applies)
                        $roll = $rng.NextDouble()
                        $aclOp = 'None'
                        $aclIdentity = $null
                        $acc = 0.0
                        foreach ($key in @('PureInheritance','ExplicitUserAce','ExplicitOrphanAce','DetachedAcl','ExplicitDenyAce')) {
                            $acc += [double]$Config.Files.FileLevelAcl[$key]
                            if ($roll -lt $acc) {
                                switch ($key) {
                                    'PureInheritance' { }
                                    'ExplicitUserAce' {
                                        $sams = $adCache.ByDept[$dept]
                                        if ($sams -and $sams.Count -gt 0) {
                                            $pick = $sams[$rng.Next(0, $sams.Count)]
                                            $aclOp = 'AllowAce'
                                            $aclIdentity = "$($adCache.Domain)\$pick"
                                        }
                                    }
                                    'ExplicitOrphanAce' {
                                        if ($adCache.Orphans.Count -gt 0) {
                                            $o = $adCache.Orphans[$rng.Next(0, $adCache.Orphans.Count)]
                                            $aclOp = 'AllowAce'
                                            $aclIdentity = "$($adCache.Domain)\$o"
                                        }
                                    }
                                    'DetachedAcl' { $aclOp = 'Detach' }
                                    'ExplicitDenyAce' {
                                        $aclOp = 'DenyAce'
                                        $aclIdentity = "$($adCache.Domain)\GG_Contractors"
                                    }
                                }
                                break
                            }
                        }

                        $buffer.Add([pscustomobject]@{
                            Path        = $filePath
                            Size        = $sizeBytes
                            Hdr         = $hdr
                            Attrs       = $attrs
                            Ads         = $adsWanted
                            Owner       = $owner.Account
                            OwnerBucket = $owner.Bucket
                            AclOp       = $aclOp
                            AclIdentity = $aclIdentity
                            CT          = $ts.CreationTime
                            WT          = $ts.LastWriteTime
                            AT          = $ts.LastAccessTime
                            ClassName   = $class.Name
                        })

                        # Flush when chunk is full
                        if ($buffer.Count -ge $chunkSize) {
                            $r = Invoke-ParallelFileChunk -Chunk $buffer -ThrottleLimit $throttle
                            $created += $r.Created
                            $errors  += $r.Errors
                            foreach ($it in $r.Items) {
                                if ($it.OwnerBucket -and $ownershipHits.ContainsKey($it.OwnerBucket)) { $ownershipHits[$it.OwnerBucket]++ }
                                $manifestWriter.WriteLine((@{
                                    p=$it.Path; s=$it.Size; o=$it.Owner; b=$it.OwnerBucket; c=$it.ClassName
                                    ct=$it.CT.ToString('o'); wt=$it.WT.ToString('o'); at=$it.AT.ToString('o')
                                } | ConvertTo-Json -Compress))
                            }
                            $buffer.Clear()
                            $elapsed = ((Get-Date) - $start).TotalSeconds
                            $rate = if ($elapsed -gt 0) { $created / $elapsed } else { 0 }
                            Write-Host ("  [parallel] {0,8}/{1,-8} ({2:N0}/s, {3} errors)" -f $created, $MaxFiles, $rate, $errors)
                        }
                    } catch {
                        $errors++
                        Write-Verbose ("Plan error: {0}" -f $_.Exception.Message)
                    }
                }
            }
            # Flush remainder
            if ($buffer.Count -gt 0) {
                $r = Invoke-ParallelFileChunk -Chunk $buffer -ThrottleLimit $throttle
                $created += $r.Created
                $errors  += $r.Errors
                foreach ($it in $r.Items) {
                    if ($it.OwnerBucket -and $ownershipHits.ContainsKey($it.OwnerBucket)) { $ownershipHits[$it.OwnerBucket]++ }
                    $manifestWriter.WriteLine((@{
                        p=$it.Path; s=$it.Size; o=$it.Owner; b=$it.OwnerBucket; c=$it.ClassName
                        ct=$it.CT.ToString('o'); wt=$it.WT.ToString('o'); at=$it.AT.ToString('o')
                    } | ConvertTo-Json -Compress))
                }
                $buffer.Clear()
            }
        } finally {
            $manifestWriter.Close()
        }

        $elapsed = ((Get-Date) - $start)
        Write-Host ("  Created: {0} files, {1} errors, {2} (parallel)" -f $created, $errors, $elapsed.ToString('mm\:ss'))
        return [pscustomobject]@{
            Created       = $created
            Errors        = $errors
            Duration      = $elapsed
            ManifestPath  = $manifestPath
            PlanPath      = $planPath
            OwnershipHits = $ownershipHits
            ClassHits     = $classHits
            Mode          = 'Parallel'
            Throttle      = $throttle
        }
    }

    # --- SEQUENTIAL PATH --------------------------------------------------
    # Ownership + file-level ACL mess are applied INLINE (good NTFS cache
    # locality: Set-Acl hits immediately after file creation while metadata
    # is hot). Set-FileOwnershipInternal uses minimal FileSecurity to skip
    # the Get-Acl read.
    try {
        foreach ($row in $plan) {
            $folder = $row.Path
            $relFolder = Get-RelativeFolderPath -Path $folder -ShareRoot $root
            $dept = Resolve-DeptFromPath -Path $folder -ShareRoot $root -Departments $Config.Departments
            if (-not $dept) { $dept = 'General' }

            # If folder is a dept we know, look up its extension pool; else use any dept
            $deptRec = $Config.Departments | Where-Object { $_.Name -eq $dept } | Select-Object -First 1
            if (-not $deptRec) { $deptRec = $Config.Departments[0] }  # fallback pool

            # Folder era (drawn once per folder per run)
            $era = Get-FolderEra -FolderPath $folder -Cache $eraCache `
                -MinDate $MinDate -MaxDate $MaxDate -DatePreset $DatePreset `
                -RecentBias $RecentBias `
                -ArchiveYearOverrides ([bool]$Config.Files.ArchiveYearOverrides) -Rng $rng

            for ($i = 0; $i -lt $row.Count; $i++) {
                if ($created -ge $MaxFiles) { break }
                try {
                    # Extension from weighted-choice is the hint; the final
                    # filename may carry a different extension (name templates
                    # embed their own). The on-disk extension must drive the
                    # header + size lookups.
                    $hintExt = Get-WeightedChoice -Weights $deptRec.Extensions -Rng $rng
                    if (-not $Config.ExtensionProperties.ContainsKey($hintExt)) { continue }

                    # File class roll first, then decide CT.
                    $class = Get-FileClassRoll -Config $Config -RelFolderPath $relFolder -Rng $rng
                    if (-not $classHits.ContainsKey($class.Name)) { $classHits[$class.Name] = 0 }
                    $classHits[$class.Name]++

                    # CreationTime:
                    #  - Dormant / LegacyArchive classes: CT pinned 3-5 years ago
                    #    (ignores preset MinDate — dormant files are archival by
                    #    definition and need to predate the usual date window).
                    #    With WT ~= CT and AT ~= WT, LastAccessTime is genuinely 3+ yr old.
                    #  - Otherwise: folder-era jitter (T2) or preset draw.
                    $ct = $null
                    if ($class.Name -in @('Dormant','LegacyArchive')) {
                        $oldUpper = (Get-Date).AddDays(-1096)  # just over 3 years
                        $oldLower = (Get-Date).AddDays(-1825)  # 5 years ago
                        $span = ($oldUpper - $oldLower).TotalDays
                        $ct = $oldLower.AddDays($rng.NextDouble() * $span)
                    } elseif ($Config.Files.FolderCoherence) {
                        $window = [int]$Config.Files.FolderEraWindowDays
                        $ct = Get-EraJitteredDate -Era $era -WindowDays $window -NowClamp $MaxDate -MinClamp $MinDate -Rng $rng
                    } else {
                        $ct = Get-RealisticDate -MinDate $MinDate -MaxDate $MaxDate -Preset $DatePreset -Bias $RecentBias -Rng $rng
                    }

                    $ts = Get-FileTimestampSet -Creation $ct -FileClass $class -NowClamp $MaxDate -Rng $rng

                    # Name (template might dictate extension).
                    $fname = Get-FileName -Config $Config -RelFolderPath $relFolder -Extension $hintExt -CreationTime $ts.CreationTime -Department $dept -Rng $rng

                    # Final extension driven by on-disk filename.
                    $ext = [IO.Path]::GetExtension($fname).ToLower()
                    if (-not $Config.ExtensionProperties.ContainsKey($ext)) {
                        # Template produced an unknown ext: fall back to hintExt by appending.
                        $fname = $fname + $hintExt
                        $ext   = $hintExt
                    }
                    $sizeKB = $rng.Next([int]$Config.ExtensionProperties[$ext].MinKB, [int]$Config.ExtensionProperties[$ext].MaxKB + 1)
                    if ($sizeKB -lt 1) { $sizeKB = 1 }
                    $sizeBytes = [long]$sizeKB * 1024L

                    $filePath = Join-Path $folder $fname
                    if (Test-Path -LiteralPath $filePath) {
                        $filePath = Join-Path $folder ("{0}_{1}{2}" -f ([IO.Path]::GetFileNameWithoutExtension($fname)), $rng.Next(10000,99999), $ext)
                    }

                    # Magic bytes keyed to the on-disk extension.
                    $hdr = Write-FileMagic -Config $Config -Extension $ext -CreationTime $ts.CreationTime

                    # Create sparse file (steps 1-3 of invariant ordering)
                    New-SparseFileInternal -Path $filePath -SizeBytes $sizeBytes -HeaderBytes $hdr

                    # Attributes (step 4)
                    $attrs = [IO.FileAttributes]::Normal
                    if ($rng.NextDouble() -lt [double]$Config.Files.Attributes.ReadOnlyChance) {
                        $attrs = [IO.FileAttributes]::ReadOnly
                    }
                    if ($rng.NextDouble() -lt [double]$Config.Files.Attributes.HiddenChance) {
                        $attrs = $attrs -bor [IO.FileAttributes]::Hidden
                        if ($attrs -band [IO.FileAttributes]::Normal) {
                            $attrs = $attrs -band -bnot ([IO.FileAttributes]::Normal)
                        }
                    }
                    if ($attrs -ne [IO.FileAttributes]::Normal) {
                        [IO.File]::SetAttributes($filePath, $attrs)
                    }

                    # ADS (step 5) — must be BEFORE timestamps
                    if ($rng.NextDouble() -lt [double]$Config.Files.Attributes.AdsChance) {
                        try {
                            $adsStream = "${filePath}:Zone.Identifier"
                            [IO.File]::WriteAllText($adsStream, "[ZoneTransfer]`r`nZoneId=3`r`n")
                        } catch { Write-Verbose "ADS write failed: $($_.Exception.Message)" }
                    }

                    # Owner (inline; Set-FileOwnershipInternal uses minimal FileSecurity — 53% faster than Get-Acl+Set-Acl)
                    $owner = Resolve-OwnerForFile -Config $Config -FilePath $filePath -Department $dept -ADCache $adCache -Rng $rng
                    try {
                        Set-FileOwnershipInternal -Path $filePath -OwnerAccount $owner.Account
                        $ownershipHits[$owner.Bucket]++
                    } catch {
                        Write-Verbose ("Ownership set failed for {0} -> {1}: {2}" -f $filePath, $owner.Account, $_.Exception.Message)
                    }

                    # File-level ACL mess (inline)
                    $roll = $rng.NextDouble()
                    $acc = 0.0
                    foreach ($key in @('PureInheritance','ExplicitUserAce','ExplicitOrphanAce','DetachedAcl','ExplicitDenyAce')) {
                        $acc += [double]$Config.Files.FileLevelAcl[$key]
                        if ($roll -lt $acc) {
                            switch ($key) {
                                'ExplicitUserAce' {
                                    $sams = $adCache.ByDept[$dept]
                                    if ($sams -and $sams.Count -gt 0) {
                                        $pick = $sams[$rng.Next(0, $sams.Count)]
                                        try { Add-FileExplicitAce -Path $filePath -Identity "$($adCache.Domain)\$pick" -Rights Modify } catch {}
                                    }
                                }
                                'ExplicitOrphanAce' {
                                    if ($adCache.Orphans.Count -gt 0) {
                                        $o = $adCache.Orphans[$rng.Next(0, $adCache.Orphans.Count)]
                                        try { Add-FileExplicitAce -Path $filePath -Identity "$($adCache.Domain)\$o" -Rights Modify } catch {}
                                    }
                                }
                                'DetachedAcl' {
                                    try { Protect-AclFromInheritance -Path $filePath -KeepInherited:$true } catch {}
                                }
                                'ExplicitDenyAce' {
                                    try { Add-FileExplicitAce -Path $filePath -Identity "$($adCache.Domain)\GG_Contractors" -Rights Write -Type Deny } catch {}
                                }
                            }
                            break
                        }
                    }

                    # Timestamps (step 8 — ABSOLUTE LAST)
                    [IO.File]::SetCreationTime($filePath, $ts.CreationTime)
                    [IO.File]::SetLastWriteTime($filePath, $ts.LastWriteTime)
                    [IO.File]::SetLastAccessTime($filePath, $ts.LastAccessTime)

                    # Manifest
                    $rec = [pscustomobject]@{
                        p = $filePath
                        s = $sizeBytes
                        o = $owner.Account
                        b = $owner.Bucket
                        c = $class.Name
                        ct= $ts.CreationTime.ToString('o')
                        wt= $ts.LastWriteTime.ToString('o')
                        at= $ts.LastAccessTime.ToString('o')
                    }
                    $manifestWriter.WriteLine(($rec | ConvertTo-Json -Compress))

                    $created++
                    if (($created % 250) -eq 0) {
                        $elapsed = ((Get-Date) - $start).TotalSeconds
                        $rate = if ($elapsed -gt 0) { $created / $elapsed } else { 0 }
                        $eta = if ($rate -gt 0) { ($MaxFiles - $created) / $rate } else { 0 }
                        Write-Progress -Activity "Generating files" -Status ("{0}/{1} ({2:N1}/s)" -f $created, $MaxFiles, $rate) -CurrentOperation ("ETA ~{0:N0}s" -f $eta) -PercentComplete ([int](100 * $created / $MaxFiles))
                    }
                } catch {
                    $errors++
                    Write-Verbose ("File create failed for {0}: {1}" -f $filePath, $_.Exception.Message)
                }
            }
            if ($created -ge $MaxFiles) { break }
        }
    } finally {
        $manifestWriter.Close()
    }
    Write-Progress -Activity "Generating files" -Completed

    $elapsed = ((Get-Date) - $start)
    Write-Host ("  Created: {0} files, {1} errors, {2}" -f $created, $errors, $elapsed.ToString('mm\:ss'))
    [pscustomobject]@{
        Created       = $created
        Errors        = $errors
        Duration      = $elapsed
        ManifestPath  = $manifestPath
        PlanPath      = $planPath
        OwnershipHits = $ownershipHits
        ClassHits     = $classHits
        Mode          = 'Sequential'
    }
}

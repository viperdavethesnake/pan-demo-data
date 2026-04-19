function New-DemoFolderTree {
<#
.SYNOPSIS
    Create the folder structure, apply ACL patterns, and seed inheritance breaks.

.DESCRIPTION
    Per-dept subs + universal subs (Archive/<year>, Temp, Sensitive, Users, Projects) +
    cross-dept root folders. Applies ACL mess per Config.Mess.AclPatterns with
    deterministic overrides on Sensitive/Board/Public/IT/Credentials/Temp.

.PARAMETER Config
    Config from Import-DemoConfig.

.OUTPUTS
    PSCustomObject with folder counts.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
    $ad      = Get-ADDomain
    $domain  = $ad.NetBIOSName

    $root = $Config.Share.Root
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    # Create SMB share if configured
    if ($Config.Share.CreateShare) {
        try {
            Import-Module SmbShare -SkipEditionCheck -ErrorAction Stop
            if (-not (Get-SmbShare -Name $Config.Share.Name -ErrorAction SilentlyContinue)) {
                New-SmbShare -Name $Config.Share.Name -Path $root -FullAccess "Everyone" -ErrorAction Stop | Out-Null
                Write-Host "  Created SMB share '$($Config.Share.Name)' → $root"
            }
        } catch {
            Write-Warning "SMB share creation skipped: $($_.Exception.Message)"
        }
    }

    # Pull the list of orphan-designated users ONCE for ACL injection.
    $orphanSams = @()
    try {
        $o = Get-ADUser -LDAPFilter '(employeeType=Former)' -SearchBase $ad.DistinguishedName -ErrorAction SilentlyContinue
        if ($o) { $orphanSams = @($o | ForEach-Object { $_.SamAccountName }) }
    } catch {}

    $rng = [System.Random]::new()
    $orphanPicker = {
        if ($orphanSams.Count -eq 0) { return $null }
        $orphanSams[$rng.Next(0, $orphanSams.Count)]
    }.GetNewClosure()

    # Per-dept user name pool for user-home-dir folder naming.
    $userByDept = @{}
    foreach ($d in $Config.Departments) {
        $g = "GG_$($d.Name)"
        $sams = @()
        try {
            $members = Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue |
                       Where-Object { $_.objectClass -eq 'user' }
            if ($members) { $sams = @($members | ForEach-Object { $_.SamAccountName }) }
        } catch {}
        $userByDept[$d.Name] = $sams
    }

    $state = @{ FoldersCreated = 0 }
    $rec = {
        param($p)
        New-Item -ItemType Directory -Path $p -Force -ErrorAction SilentlyContinue | Out-Null
        $state.FoldersCreated++
    }.GetNewClosure()

    # --- Cross-dept root folders ------------------------------------------
    foreach ($name in $Config.FolderTree.CrossDeptFolders) {
        $p = Join-Path $root $name
        & $rec $p
        switch ($name) {
            'Public' {
                # Everyone FullControl — the nuclear finding.
                Add-FolderAce -Path $p -Identity 'Everyone' -Rights FullControl
            }
            'Shared' {
                Add-FolderAce -Path $p -Identity "$domain\GG_AllEmployees" -Rights ReadAndExecute
                Add-FolderAce -Path $p -Identity 'Everyone' -Rights ReadAndExecute
            }
            'Board' {
                Protect-AclFromInheritance -Path $p -KeepInherited:$false
                Add-FolderAce -Path $p -Identity 'BUILTIN\Administrators' -Rights FullControl
                Add-FolderAce -Path $p -Identity "$domain\Domain Admins" -Rights FullControl
            }
            'Inter-Department' {
                Add-FolderAce -Path $p -Identity "$domain\GG_AllEmployees" -Rights Modify
            }
            'Vendors' {
                Add-FolderAce -Path $p -Identity "$domain\GG_AllEmployees" -Rights ReadAndExecute
            }
            default {
                # Legacy-ish folders: random acl pattern + sometimes inheritance drift
                $pat = Get-AclMessRoll -Config $Config -Rng $rng
                $ctx = @{
                    Domain = $domain
                    DeptGG = 'GG_AllEmployees'
                    DLRw   = $null
                    DLRo   = $null
                    Contractors = 'GG_Contractors'
                    OrphanSamPicker = $orphanPicker
                }
                Set-AclPattern -Path $p -Pattern $pat -Context $ctx
            }
        }
    }

    # --- Per-dept structure -----------------------------------------------
    foreach ($d in $Config.Departments) {
        $deptName = $d.Name
        $deptPath = Join-Path $root $deptName
        & $rec $deptPath

        $ctx = @{
            Domain = $domain
            DeptGG = "GG_$deptName"
            DLRw   = "DL_Share_${deptName}_RW"
            DLRo   = "DL_Share_${deptName}_RO"
            Contractors = 'GG_Contractors'
            OrphanSamPicker = $orphanPicker
        }

        # Dept root gets proper AGDLP
        Set-AclPattern -Path $deptPath -Pattern 'ProperAGDLP' -Context $ctx
        try {
            $acl = Get-Acl -LiteralPath $deptPath
            $acl.SetOwner([System.Security.Principal.NTAccount]("$domain\GG_$deptName"))
            Set-Acl -LiteralPath $deptPath -AclObject $acl
        } catch { Write-Verbose "Set dept-root owner failed: $($_.Exception.Message)" }

        # Dept-specific subs
        foreach ($sub in $d.SubFolders) {
            $subPath = Join-Path $deptPath $sub
            & $rec $subPath
            $pat = Get-AclMessRoll -Config $Config -Rng $rng
            Set-AclPattern -Path $subPath -Pattern $pat -Context $ctx

            # Accidental inheritance drift
            if ($rng.NextDouble() -lt $Config.Mess.AccidentalInheritanceBreakChance) {
                Protect-AclFromInheritance -Path $subPath -KeepInherited:$true
            }

            # Legacy sub-duplicate
            if ($rng.NextDouble() -lt $Config.FolderTree.LegacyFolderChance.SubDuplicate) {
                $legacy = @("{0}_OLD","{0}_BACKUP","{0}_v2","{0}_2019","{0}_Legacy")[$rng.Next(0,5)]
                $legPath = Join-Path $deptPath ($legacy -f $sub)
                & $rec $legPath
                $pat2 = Get-AclMessRoll -Config $Config -Rng $rng
                Set-AclPattern -Path $legPath -Pattern $pat2 -Context $ctx
            }
        }

        # Universal subs
        foreach ($u in @('Archive','Temp','Sensitive','Users','Projects')) {
            $uPath = Join-Path $deptPath $u
            & $rec $uPath
            switch ($u) {
                'Sensitive' {
                    Protect-AclFromInheritance -Path $uPath -KeepInherited:$true
                    Remove-AclRulesForPrincipal -Path $uPath -Identity "$domain\GG_AllEmployees"
                    Remove-AclRulesForPrincipal -Path $uPath -Identity 'Everyone'
                    Add-FolderAce -Path $uPath -Identity "$domain\GG_$deptName" -Rights Modify
                    Add-FolderAce -Path $uPath -Identity 'BUILTIN\Administrators' -Rights FullControl
                }
                'Temp' {
                    Add-FolderAce -Path $uPath -Identity 'Everyone' -Rights Modify
                    Add-FolderAce -Path $uPath -Identity "$domain\GG_Contractors" -Rights Write -Type Deny
                }
                'Archive' {
                    # parent gets backup-ops + dept DL RW
                    Set-AclPattern -Path $uPath -Pattern 'ProperAGDLP' -Context $ctx
                    Add-FolderAce -Path $uPath -Identity "$domain\GG_BackupOps" -Rights Modify
                    # Year sub-folders (+ optional quarter sub-folders per v4.1)
                    $yr = $Config.FolderTree.ArchiveYearRange
                    $quarters = [bool]$Config.FolderTree.ArchiveQuarters
                    for ($y = [int]$yr.Start; $y -le [int]$yr.End; $y++) {
                        $yPath = Join-Path $uPath $y
                        & $rec $yPath
                        if ($rng.NextDouble() -lt 0.3) {
                            Set-AclPattern -Path $yPath -Pattern 'OrphanSidAce' -Context $ctx
                        }
                        if ($quarters) {
                            foreach ($q in 'Q1','Q2','Q3','Q4') {
                                & $rec (Join-Path $yPath $q)
                            }
                        }
                    }
                }
                'Users' {
                    # Per-user home dirs (dept-scoped). v4.1: DeptUserCount = $null
                    # means "all real users in the dept" — big folder-count lift.
                    $userPool = $userByDept[$deptName]
                    if ($userPool -and $userPool.Count -gt 0) {
                        $cfgCount = $Config.FolderTree.UserHomeDirs.DeptUserCount
                        $take = if ($null -eq $cfgCount) { $userPool.Count } else { [Math]::Min([int]$cfgCount, $userPool.Count) }
                        $picks = $userPool | Sort-Object { $rng.NextDouble() } | Select-Object -First $take
                        foreach ($sam in $picks) {
                            $hPath = Join-Path $uPath $sam
                            & $rec $hPath
                            try {
                                $acl = Get-Acl -LiteralPath $hPath
                                $acl.SetOwner([System.Security.Principal.NTAccount]("$domain\$sam"))
                                Set-Acl -LiteralPath $hPath -AclObject $acl
                            } catch { Write-Verbose "Set home-dir owner failed: $($_.Exception.Message)" }
                            Add-FolderAce -Path $hPath -Identity "$domain\$sam" -Rights FullControl
                        }
                    }
                }
                'Projects' {
                    $minP = [int]$Config.FolderTree.ProjectsPerDept.Min
                    $maxP = [int]$Config.FolderTree.ProjectsPerDept.Max
                    $nProj = if ($maxP -le $minP) { $minP } else { $rng.Next($minP, $maxP + 1) }
                    $pool  = $Config.DataPools.Projects | Sort-Object { $rng.NextDouble() } | Select-Object -First $nProj
                    # v4.1: every project gets the standard sub-folders (was 33% optional).
                    $projSubs = $Config.FolderTree.ProjectSubs
                    if (-not $projSubs) { $projSubs = @('Planning','Execution','Review','Resources','Documentation') }
                    foreach ($code in $pool) {
                        $pPath = Join-Path $uPath $code
                        & $rec $pPath
                        $pat = Get-AclMessRoll -Config $Config -Rng $rng
                        Set-AclPattern -Path $pPath -Pattern $pat -Context $ctx
                        foreach ($sub2 in $projSubs) {
                            & $rec (Join-Path $pPath $sub2)
                        }
                    }
                }
            }
        }

        # --- v4.1 dept-specific folder classes (Client/Matter/Vendor/Campaign/App) --
        $deptFolderClasses = @(
            @{ Key='ClientFolders';   Parent='Clients';   Pool='Clients' }
            @{ Key='MatterFolders';   Parent='Matters';   Pool='Matters' }
            @{ Key='VendorFolders';   Parent='Vendors';   Pool='Vendors' }
            @{ Key='CampaignFolders'; Parent='Campaigns'; Pool='Campaigns' }
            @{ Key='AppFolders';      Parent='Apps';      Pool='Apps' }
        )
        foreach ($fc in $deptFolderClasses) {
            $fcCfg = $Config.FolderTree[$fc.Key]
            if (-not $fcCfg -or -not $fcCfg.Enabled) { continue }
            $perDept = $fcCfg.PerDept
            if (-not $perDept -or -not $perDept.ContainsKey($deptName)) { continue }
            $range = $perDept[$deptName]
            $n = if ($range.Max -le $range.Min) { [int]$range.Min } else { $rng.Next([int]$range.Min, [int]$range.Max + 1) }
            if ($n -le 0) { continue }

            # Parent folder: <Dept>/<Parent>/ — create if missing (e.g. Sales/Clients).
            $parentPath = Join-Path $deptPath $fc.Parent
            if (-not (Test-Path -LiteralPath $parentPath)) { & $rec $parentPath }

            # Sample N distinct names from the data pool.
            $pool = $Config.DataPools[$fc.Pool]
            $take = [Math]::Min($n, $pool.Count)
            $picks = $pool | Sort-Object { $rng.NextDouble() } | Select-Object -First $take
            foreach ($name in $picks) {
                # Sanitize for filesystem: spaces/ampersands/etc. are OK on NTFS,
                # but keep names clean per CleanNamesOnly invariant.
                $clean = ($name -replace '[/\\:*?"<>|]', '_').Trim()
                $nPath = Join-Path $parentPath $clean
                & $rec $nPath
                $pat = Get-AclMessRoll -Config $Config -Rng $rng
                Set-AclPattern -Path $nPath -Pattern $pat -Context $ctx
                foreach ($sub in $fcCfg.SubFolders) {
                    & $rec (Join-Path $nPath $sub)
                }
            }
        }

        # IT/Credentials — deterministic restricted
        if ($deptName -eq 'IT' -and (Test-Path (Join-Path $deptPath 'Credentials'))) {
            $credPath = Join-Path $deptPath 'Credentials'
            Protect-AclFromInheritance -Path $credPath -KeepInherited:$true
            Remove-AclRulesForPrincipal -Path $credPath -Identity "$domain\GG_AllEmployees"
            Remove-AclRulesForPrincipal -Path $credPath -Identity 'Everyone'
            Add-FolderAce -Path $credPath -Identity "$domain\GG_$deptName" -Rights Modify
            Add-FolderAce -Path $credPath -Identity "$domain\GG_Contractors" -Rights ReadAndExecute -Type Deny
        }

        # Dept-level legacy root folder
        if ($rng.NextDouble() -lt $Config.FolderTree.LegacyFolderChance.DeptLevel) {
            $legName = @("OLD_$deptName","LEGACY_$deptName","${deptName}_MIXED","${deptName}_Backup")[$rng.Next(0,4)]
            $legPath = Join-Path $root $legName
            & $rec $legPath
            $pat = Get-AclMessRoll -Config $Config -Rng $rng
            Set-AclPattern -Path $legPath -Pattern $pat -Context $ctx
        }
    }

    # --- Root-scoped user home dirs ---------------------------------------
    if ($Config.FolderTree.UserHomeDirs.RootScoped) {
        $rootUsersDir = Join-Path $root 'Users'
        & $rec $rootUsersDir
        $allRealSams = @()
        foreach ($sams in $userByDept.Values) { $allRealSams += $sams }
        $allRealSams = $allRealSams | Where-Object { $orphanSams -notcontains $_ }
        $take = [int]([math]::Ceiling($allRealSams.Count * [double]$Config.FolderTree.UserHomeDirs.RootFraction))
        $picks = $allRealSams | Sort-Object { $rng.NextDouble() } | Select-Object -First $take
        foreach ($sam in $picks) {
            $hPath = Join-Path $rootUsersDir $sam
            & $rec $hPath
            try {
                $acl = Get-Acl -LiteralPath $hPath
                $acl.SetOwner([System.Security.Principal.NTAccount]("$domain\$sam"))
                Set-Acl -LiteralPath $hPath -AclObject $acl
            } catch {}
            Add-FolderAce -Path $hPath -Identity "$domain\$sam" -Rights FullControl
        }
        # A few orphan root homes so their ownership sticks after orphanize
        foreach ($sam in $orphanSams) {
            if ($rng.NextDouble() -lt 0.5) {
                $hPath = Join-Path $rootUsersDir $sam
                & $rec $hPath
                try {
                    $acl = Get-Acl -LiteralPath $hPath
                    $acl.SetOwner([System.Security.Principal.NTAccount]("$domain\$sam"))
                    Set-Acl -LiteralPath $hPath -AclObject $acl
                } catch {}
                Add-FolderAce -Path $hPath -Identity "$domain\$sam" -Rights FullControl
            }
        }
    }

    Write-Host ("  Folders created: {0}" -f $state.FoldersCreated)
    [pscustomobject]@{
        Root    = $root
        Count   = $state.FoldersCreated
    }
}

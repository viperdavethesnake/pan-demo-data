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
                    # year sub-folders
                    $yr = $Config.FolderTree.ArchiveYearRange
                    for ($y = [int]$yr.Start; $y -le [int]$yr.End; $y++) {
                        $yPath = Join-Path $uPath $y
                        & $rec $yPath
                        if ($rng.NextDouble() -lt 0.3) {
                            # some year folders get orphan SID ACE
                            Set-AclPattern -Path $yPath -Pattern 'OrphanSidAce' -Context $ctx
                        }
                    }
                }
                'Users' {
                    # per-user home dirs (dept-scoped), sampled from this dept's users
                    $userPool = $userByDept[$deptName]
                    if ($userPool -and $userPool.Count -gt 0) {
                        $take = [Math]::Min([int]$Config.FolderTree.UserHomeDirs.DeptUserCount, $userPool.Count)
                        $picks = $userPool | Sort-Object { $rng.NextDouble() } | Select-Object -First $take
                        foreach ($sam in $picks) {
                            $hPath = Join-Path $uPath $sam
                            & $rec $hPath
                            try {
                                $acl = Get-Acl -LiteralPath $hPath
                                $acl.SetOwner([System.Security.Principal.NTAccount]("$domain\$sam"))
                                Set-Acl -LiteralPath $hPath -AclObject $acl
                            } catch { Write-Verbose "Set home-dir owner failed: $($_.Exception.Message)" }
                            # explicit user ACE
                            Add-FolderAce -Path $hPath -Identity "$domain\$sam" -Rights FullControl
                        }
                    }
                }
                'Projects' {
                    $minP = [int]$Config.FolderTree.ProjectsPerDept.Min
                    $maxP = [int]$Config.FolderTree.ProjectsPerDept.Max
                    $nProj = if ($maxP -le $minP) { $minP } else { $rng.Next($minP, $maxP + 1) }
                    $pool  = $Config.DataPools.Projects | Sort-Object { $rng.NextDouble() } | Select-Object -First $nProj
                    foreach ($code in $pool) {
                        $pPath = Join-Path $uPath $code
                        & $rec $pPath
                        $pat = Get-AclMessRoll -Config $Config -Rng $rng
                        Set-AclPattern -Path $pPath -Pattern $pat -Context $ctx
                        # Occasional deeper nesting (within MaxDepth)
                        if ($rng.NextDouble() -lt 0.5) {
                            foreach ($sub2 in @('Planning','Execution','Review','Resources','Documentation')) {
                                if ($rng.NextDouble() -lt 0.5) {
                                    & $rec (Join-Path $pPath $sub2)
                                }
                            }
                        }
                    }
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

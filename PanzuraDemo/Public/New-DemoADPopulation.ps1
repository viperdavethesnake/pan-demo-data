function New-DemoADPopulation {
<#
.SYNOPSIS
    Create OUs, groups, users, orphan-designated users, and service accounts
    per the v4 spec.

.DESCRIPTION
    Idempotent. Uses sam-prefix search to detect existing users before creating.
    AGDLP: GG_<Dept> (Global) nested into DL_Share_<Dept>_RW (DomainLocal).
    Orphan-designated users carry employeeType='Former' so
    Remove-DemoOrphanUser can find them deterministically.

.PARAMETER Config
    Config hashtable from Import-DemoConfig.

.OUTPUTS
    PSCustomObject with creation counts.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
    $ad = Get-ADDomain
    $domainDN  = $ad.DistinguishedName
    $netbios   = $ad.NetBIOSName
    $dnsRoot   = $ad.DNSRoot
    $mailDom   = $Config.AD.MailDomain
    if (-not $mailDom) { $mailDom = $dnsRoot }

    $baseOU       = $Config.AD.BaseOUName
    $usersOU      = $Config.AD.UsersOU
    $groupsOU     = $Config.AD.GroupsOU
    $svcOU        = $Config.AD.ServiceOU
    $password     = ConvertTo-SecureString $Config.AD.Password -AsPlainText -Force

    Write-Host "=== AD populate: domain=$dnsRoot, baseOU=$baseOU ===" -ForegroundColor Cyan

    # --- OUs ----------------------------------------------------------------
    $rootPath        = Ensure-DemoOU -Segments @($baseOU)                -DomainDN $domainDN
    $usersRootPath   = Ensure-DemoOU -Segments @($baseOU, $usersOU)      -DomainDN $domainDN
    $groupsRootPath  = Ensure-DemoOU -Segments @($baseOU, $groupsOU)     -DomainDN $domainDN
    $svcOuPath       = Ensure-DemoOU -Segments @($baseOU, $svcOU)        -DomainDN $domainDN

    $deptOuPaths = @{}
    foreach ($d in $Config.Departments) {
        $deptOuPaths[$d.Name] = Ensure-DemoOU -Segments @($baseOU, $usersOU, $d.Name) -DomainDN $domainDN
    }

    # --- Groups -------------------------------------------------------------
    [void](Ensure-DemoGroup -Name 'GG_AllEmployees' -Scope Global      -Path $groupsRootPath)
    [void](Ensure-DemoGroup -Name 'GG_Contractors' -Scope Global       -Path $groupsRootPath)
    [void](Ensure-DemoGroup -Name 'GG_BackupOps'   -Scope Global       -Path $groupsRootPath)

    foreach ($d in $Config.Departments) {
        [void](Ensure-DemoGroup -Name ("GG_{0}" -f $d.Name)               -Scope Global      -Path $groupsRootPath)
        [void](Ensure-DemoGroup -Name ("DL_Share_{0}_RW" -f $d.Name)      -Scope DomainLocal -Path $groupsRootPath)
        [void](Ensure-DemoGroup -Name ("DL_Share_{0}_RO" -f $d.Name)      -Scope DomainLocal -Path $groupsRootPath)
    }

    # AGDLP nesting: GG_<Dept> member of DL_Share_<Dept>_RW and DL_Share_<Dept>_RO
    foreach ($d in $Config.Departments) {
        try {
            Add-ADGroupMember -Identity ("DL_Share_{0}_RW" -f $d.Name) -Members ("GG_{0}" -f $d.Name) -ErrorAction Stop
        } catch { if ($_.Exception.Message -notmatch 'already a member|already exists') { Write-Verbose $_.Exception.Message } }
        try {
            Add-ADGroupMember -Identity ("DL_Share_{0}_RO" -f $d.Name) -Members ("GG_{0}" -f $d.Name) -ErrorAction Stop
        } catch { if ($_.Exception.Message -notmatch 'already a member|already exists') { Write-Verbose $_.Exception.Message } }
    }

    # --- Users (real) -------------------------------------------------------
    $usedSams = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Pre-populate used SAMs with existing AD users under baseOU (so reruns don't collide)
    try {
        Get-ADUser -LDAPFilter '(objectClass=user)' -SearchBase ("OU=$baseOU,$domainDN") -ErrorAction SilentlyContinue |
            ForEach-Object { [void]$usedSams.Add($_.SamAccountName) }
    } catch {}

    $rng = [System.Random]::new()
    $titlesByLevel = $Config.Mess.TitlesByLevel
    $offices = $Config.Mess.Offices
    $createdByDept = @{}
    $allCreated = @()

    foreach ($d in $Config.Departments) {
        $deptPath = $deptOuPaths[$d.Name]
        $min = [int]$d.UsersPerDept.Min
        $max = [int]$d.UsersPerDept.Max
        $count = if ($max -le $min) { $min } else { $rng.Next($min, $max + 1) }
        $createdByDept[$d.Name] = 0
        $sams = @()

        for ($i = 0; $i -lt $count; $i++) {
            $person = Get-PersonName -NameCorpora $Config.Names -Rng $rng
            $sam = Reserve-UniqueSam -First $person.First -Last $person.Last -Used $usedSams -Rng $rng
            $existing = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -SearchBase $domainDN -ErrorAction SilentlyContinue
            if ($existing) {
                $sams += $sam
                continue  # already there — skip create
            }
            $titleLevel = Get-WeightedChoice -Weights @{ Exec=5; Senior=15; Mid=45; Junior=35 } -Rng $rng
            $title = $titlesByLevel[$titleLevel][$rng.Next(0, $titlesByLevel[$titleLevel].Count)]
            $office = $offices[$rng.Next(0, $offices.Count)]
            try {
                New-ADUser `
                    -Name $person.Display `
                    -SamAccountName $sam `
                    -GivenName $person.First `
                    -Surname  $person.Last `
                    -DisplayName $person.Display `
                    -UserPrincipalName "$sam@$dnsRoot" `
                    -EmailAddress       "$sam@$mailDom" `
                    -AccountPassword $password `
                    -Enabled $true `
                    -ChangePasswordAtLogon $false `
                    -PasswordNeverExpires $true `
                    -Path $deptPath `
                    -Department $d.Name `
                    -Title $title `
                    -Office $office `
                    -Company 'DemoCorp' `
                    -ErrorAction Stop | Out-Null
                $sams += $sam
                $createdByDept[$d.Name]++
                $allCreated += $sam
            } catch {
                Write-Warning "Create user $sam in $($d.Name) failed: $($_.Exception.Message)"
            }
        }
        Add-BulkGroupMember -GroupSam 'GG_AllEmployees'  -UserSams $sams
        Add-BulkGroupMember -GroupSam ("GG_{0}" -f $d.Name) -UserSams $sams
        Write-Host ("  {0,-14} → {1,3} users" -f $d.Name, $sams.Count)
    }

    # --- Orphan-designated users -------------------------------------------
    # Same naming convention as real employees (first.last). Flagged via
    # employeeType='Former'. Assigned to a random dept's GG_<Dept>.
    $orphanSams = @()
    $depts = $Config.Departments | ForEach-Object { $_.Name }
    for ($i = 0; $i -lt $Config.Mess.OrphanSidCount; $i++) {
        $person = Get-PersonName -NameCorpora $Config.Names -Rng $rng
        $sam = Reserve-UniqueSam -First $person.First -Last $person.Last -Used $usedSams -Rng $rng
        $existing = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -SearchBase $domainDN -ErrorAction SilentlyContinue
        if ($existing) { $orphanSams += $sam; continue }
        $assignedDept = $depts[$rng.Next(0, $depts.Count)]
        $deptPath = $deptOuPaths[$assignedDept]
        try {
            New-ADUser `
                -Name $person.Display `
                -SamAccountName $sam `
                -GivenName $person.First `
                -Surname  $person.Last `
                -DisplayName $person.Display `
                -UserPrincipalName "$sam@$dnsRoot" `
                -EmailAddress       "$sam@$mailDom" `
                -AccountPassword $password `
                -Enabled $true `
                -ChangePasswordAtLogon $false `
                -PasswordNeverExpires $true `
                -Path $deptPath `
                -Department $assignedDept `
                -Title 'Former Employee' `
                -Company 'DemoCorp' `
                -OtherAttributes @{ employeeType = 'Former' } `
                -ErrorAction Stop | Out-Null
            $orphanSams += $sam
        } catch {
            Write-Warning "Create orphan user $sam failed: $($_.Exception.Message)"
        }
    }
    if ($orphanSams.Count -gt 0) {
        Add-BulkGroupMember -GroupSam 'GG_AllEmployees' -UserSams $orphanSams
        # Add each orphan to their dept's GG via per-dept calls
        $byDept = @{}
        foreach ($d in $depts) { $byDept[$d] = @() }
        foreach ($os in $orphanSams) {
            $u = Get-ADUser -Identity $os -Properties Department -ErrorAction SilentlyContinue
            if ($u -and $u.Department) { $byDept[$u.Department] += $os }
        }
        foreach ($d in $depts) {
            if ($byDept[$d].Count -gt 0) { Add-BulkGroupMember -GroupSam ("GG_{0}" -f $d) -UserSams $byDept[$d] }
        }
    }
    Write-Host ("  Orphan-designated users (employeeType=Former): {0}" -f $orphanSams.Count)

    # --- Service accounts ---------------------------------------------------
    $svcCreated = 0
    foreach ($svc in $Config.Mess.ServiceAccounts) {
        $sam = $svc.Name
        $existing = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -SearchBase $domainDN -ErrorAction SilentlyContinue
        if ($existing) { continue }
        try {
            New-ADUser `
                -Name $sam `
                -SamAccountName $sam `
                -DisplayName $sam `
                -Description $svc.Description `
                -UserPrincipalName "$sam@$dnsRoot" `
                -AccountPassword $password `
                -Enabled $true `
                -ChangePasswordAtLogon $false `
                -PasswordNeverExpires $true `
                -Path $svcOuPath `
                -Title 'Service Account' `
                -Company 'DemoCorp' `
                -ErrorAction Stop | Out-Null
            $svcCreated++
        } catch {
            Write-Warning "Service account $sam failed: $($_.Exception.Message)"
        }
    }
    # Backup-related svc accounts go into GG_BackupOps
    $backupSvcs = @($Config.Mess.ServiceAccounts |
                    Where-Object { $_.Name -in @('svc_backup','svc_sql','svc_fileshare') } |
                    ForEach-Object { $_.Name })
    if ($backupSvcs.Count -gt 0) { Add-BulkGroupMember -GroupSam 'GG_BackupOps' -UserSams $backupSvcs }

    Write-Host ("  Service accounts created/existed: {0}/{1}" -f $svcCreated, $Config.Mess.ServiceAccounts.Count)

    [pscustomobject]@{
        BaseOU          = $baseOU
        UsersCreated    = $allCreated.Count
        UsersByDept     = $createdByDept
        OrphanCreated   = $orphanSams.Count
        ServiceCreated  = $svcCreated
        Domain          = $netbios
    }
}

function Ensure-DemoOU {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Segments, [Parameter(Mandatory)][string]$DomainDN)
    $currentPath = $DomainDN
    foreach ($seg in $Segments) {
        $existing = Get-ADOrganizationalUnit -LDAPFilter "(ou=$seg)" -SearchBase $currentPath -SearchScope OneLevel -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-ADOrganizationalUnit -Name $seg -Path $currentPath -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop | Out-Null
        }
        $currentPath = "OU=$seg,$currentPath"
    }
    return $currentPath
}

function Ensure-DemoGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Global','DomainLocal','Universal')][string]$Scope,
        [Parameter(Mandatory)][string]$Path
    )
    $existing = Get-ADGroup -LDAPFilter "(sAMAccountName=$Name)" -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.DistinguishedName -notlike "*$Path*") {
            try { Move-ADObject -Identity $existing.DistinguishedName -TargetPath $Path -ErrorAction SilentlyContinue } catch {}
        }
        return $existing
    }
    return New-ADGroup -Name $Name -SamAccountName $Name -GroupScope $Scope -GroupCategory Security -Path $Path -PassThru -ErrorAction Stop
}

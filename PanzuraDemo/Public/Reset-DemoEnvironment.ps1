function Reset-DemoEnvironment {
<#
.SYNOPSIS
    Remove demo AD artifacts (users, groups, OUs) and SMB share.
    Filesystem is NOT touched — user reformats between demos (per spec).

.PARAMETER Config
.PARAMETER Confirm
    Pass -Confirm:$false to skip prompts.
.PARAMETER IncludeShare
    Also removes the SMB share. Default true.
.PARAMETER IncludeLegacyGroups
    Additionally remove leftover GG_*/DL_*/PG_* groups anywhere in the domain
    (covers vNext2-era artifacts that aren't in the current config's baseOU).
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$IncludeShare = $true,
        [switch]$IncludeLegacyGroups = $true
    )

    Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
    $domainDN  = (Get-ADDomain).DistinguishedName
    $baseOU    = $Config.AD.BaseOUName
    $rootPath  = "OU=$baseOU,$domainDN"

    Write-Host "=== Reset-DemoEnvironment: baseOU=$baseOU ===" -ForegroundColor Cyan

    # --- Users under baseOU -----------------------------------------------
    $userDNs = @()
    if (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$rootPath)" -SearchBase $domainDN -ErrorAction SilentlyContinue) {
        try {
            $u = Get-ADUser -LDAPFilter '(objectClass=user)' -SearchBase $rootPath -SearchScope Subtree -ErrorAction SilentlyContinue
            if ($u) { $userDNs += ($u | ForEach-Object { $_.DistinguishedName }) }
        } catch {}
    }
    foreach ($dn in $userDNs) {
        if ($PSCmdlet.ShouldProcess($dn, "Remove AD user")) {
            try { Remove-ADUser -Identity $dn -Confirm:$false -ErrorAction Stop } catch {
                Write-Warning "Remove user failed: $($_.Exception.Message)"
            }
        }
    }

    # --- Groups under baseOU ----------------------------------------------
    $groupDNs = @()
    if (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$rootPath)" -SearchBase $domainDN -ErrorAction SilentlyContinue) {
        try {
            $g = Get-ADGroup -LDAPFilter '(objectClass=group)' -SearchBase $rootPath -SearchScope Subtree -ErrorAction SilentlyContinue
            if ($g) { $groupDNs += ($g | ForEach-Object { $_.DistinguishedName }) }
        } catch {}
    }
    if ($IncludeLegacyGroups) {
        # Also pick up loose GG_/DL_/PG_ anywhere (vNext2 leftovers, etc.)
        $legacyFilter = '(|(sAMAccountName=GG_*)(sAMAccountName=DL_*)(sAMAccountName=PG_*))'
        try {
            $lg = Get-ADGroup -LDAPFilter $legacyFilter -SearchBase $domainDN -ErrorAction SilentlyContinue
            if ($lg) { $groupDNs += ($lg | ForEach-Object { $_.DistinguishedName }) }
        } catch {}
    }
    $groupDNs = @($groupDNs | Sort-Object -Unique)
    foreach ($dn in $groupDNs) {
        if ($PSCmdlet.ShouldProcess($dn, "Remove AD group")) {
            try { Remove-ADGroup -Identity $dn -Confirm:$false -ErrorAction Stop } catch {
                Write-Warning "Remove group failed: $($_.Exception.Message)"
            }
        }
    }

    # --- Remove baseOU tree (disable protection first) --------------------
    $ouList = @()
    if (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$rootPath)" -SearchBase $domainDN -ErrorAction SilentlyContinue) {
        try {
            $children = Get-ADOrganizationalUnit -LDAPFilter '(objectClass=organizationalUnit)' -SearchBase $rootPath -SearchScope Subtree -ErrorAction SilentlyContinue
            if ($children) {
                # Sort by DN length descending → leaves first
                $ouList = $children | Sort-Object { $_.DistinguishedName.Length } -Descending | ForEach-Object { $_.DistinguishedName }
            }
        } catch {}
        if ($ouList -notcontains $rootPath) { $ouList += $rootPath }
    }
    foreach ($ou in $ouList) {
        try {
            $obj = Get-ADObject -Identity $ou -Properties ProtectedFromAccidentalDeletion -ErrorAction SilentlyContinue
            if ($obj -and $obj.ProtectedFromAccidentalDeletion) {
                Set-ADObject -Identity $ou -ProtectedFromAccidentalDeletion:$false -ErrorAction SilentlyContinue
            }
        } catch {}
        if ($PSCmdlet.ShouldProcess($ou, "Remove OU")) {
            try { Remove-ADOrganizationalUnit -Identity $ou -Recursive -Confirm:$false -ErrorAction Stop } catch {
                try { Remove-ADObject -Identity $ou -Recursive -Confirm:$false -ErrorAction Stop } catch {
                    Write-Warning "Remove OU failed: $($_.Exception.Message)"
                }
            }
        }
    }

    # --- SMB share --------------------------------------------------------
    if ($IncludeShare) {
        try {
            Import-Module SmbShare -SkipEditionCheck -ErrorAction SilentlyContinue
            $s = Get-SmbShare -Name $Config.Share.Name -ErrorAction SilentlyContinue
            if ($s) {
                if ($PSCmdlet.ShouldProcess($s.Name, "Remove SMB share")) {
                    Remove-SmbShare -Name $s.Name -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }

    $userCount  = @($userDNs).Count
    $groupCount = @($groupDNs).Count
    $ouCount    = @($ouList).Count
    Write-Host ("  Users removed: {0}, Groups removed: {1}, OUs removed: {2}" -f $userCount, $groupCount, $ouCount)
    [pscustomobject]@{
        UsersRemoved  = $userCount
        GroupsRemoved = $groupCount
        OUsRemoved    = $ouCount
    }
}

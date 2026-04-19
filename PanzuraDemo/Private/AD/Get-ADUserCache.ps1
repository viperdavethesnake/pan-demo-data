# Get-ADUserCache — build an in-memory cache of dept → user SAM list,
# plus orphan SAMs and service SAMs. Called once at file-generation time.
#
# Output shape:
#   @{
#     Domain    = 'DEMO'
#     DomainDN  = 'DC=demo,DC=panzura'
#     ByDept    = @{ Finance=@('jane.smith',...); HR=@(...); ... }
#     Orphans   = @('former.first.last', ...)
#     Services  = @('svc_backup', ...)
#     AllReal   = @(...)     # union of ByDept values (real employees only)
#   }
function Get-ADUserCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config
    )
    $ad = Get-ADDomain
    $domain   = $ad.NetBIOSName
    $domainDN = $ad.DistinguishedName

    $byDept = @{}
    foreach ($d in $Config.Departments) {
        $groupSam = "GG_$($d.Name)"
        $sams = @()
        try {
            $members = Get-ADGroupMember -Identity $groupSam -ErrorAction SilentlyContinue |
                       Where-Object { $_.objectClass -eq 'user' }
            if ($members) {
                $sams = @($members | ForEach-Object { $_.SamAccountName })
            }
        } catch {}
        $byDept[$d.Name] = $sams
    }

    # Orphan-designated users are identified by employeeType = "Former"
    $orphans = @()
    try {
        $orph = Get-ADUser -LDAPFilter '(employeeType=Former)' -SearchBase $domainDN -ErrorAction SilentlyContinue
        if ($orph) { $orphans = @($orph | ForEach-Object { $_.SamAccountName }) }
    } catch {}

    # Service accounts from config
    $services = @()
    foreach ($svc in $Config.Mess.ServiceAccounts) {
        try {
            $u = Get-ADUser -LDAPFilter "(sAMAccountName=$($svc.Name))" -SearchBase $domainDN -ErrorAction SilentlyContinue
            if ($u) { $services += $svc.Name }
        } catch {}
    }

    $allReal = @()
    foreach ($sams in $byDept.Values) {
        foreach ($s in $sams) {
            if ($orphans -notcontains $s) { $allReal += $s }
        }
    }

    return @{
        Domain   = $domain
        DomainDN = $domainDN
        ByDept   = $byDept
        Orphans  = $orphans
        Services = $services
        AllReal  = $allReal
    }
}

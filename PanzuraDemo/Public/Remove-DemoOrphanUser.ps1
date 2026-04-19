function Remove-DemoOrphanUser {
<#
.SYNOPSIS
    Delete orphan-designated AD users. Their SIDs remain on NTFS ACLs as
    unresolvable, which is exactly what a scan reports as "orphan SID".

.DESCRIPTION
    Finds AD users with employeeType='Former' and removes them. Idempotent:
    safe to run multiple times. Run once after all file-creation runs.

.PARAMETER Config
.PARAMETER Confirm
    Pass -Confirm:$false to skip prompts.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][hashtable]$Config)

    Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
    $domainDN = (Get-ADDomain).DistinguishedName

    $orphans = @()
    try {
        $orphans = @(Get-ADUser -LDAPFilter '(employeeType=Former)' -SearchBase $domainDN -Properties employeeType -ErrorAction SilentlyContinue)
    } catch {}

    Write-Host "=== Remove-DemoOrphanUser: found $($orphans.Count) flagged users ===" -ForegroundColor Cyan
    $removed = 0
    $errors  = 0
    foreach ($u in $orphans) {
        if ($PSCmdlet.ShouldProcess($u.DistinguishedName, "Remove orphan user")) {
            try {
                Remove-ADUser -Identity $u.DistinguishedName -Confirm:$false -ErrorAction Stop
                $removed++
            } catch {
                $errors++
                Write-Warning "Remove failed for $($u.SamAccountName): $($_.Exception.Message)"
            }
        }
    }
    Write-Host ("  Removed: {0}, Errors: {1}" -f $removed, $errors)
    [pscustomobject]@{ Removed = $removed; Errors = $errors; TotalFound = $orphans.Count }
}

# Set-FileOwnershipInternal — set NTFS owner on a file or folder.
# Uses a pre-resolved NTAccount string ("DOMAIN\principal"). Callers are
# expected to resolve names once up front and pass the cached string.
# Privileges (SeRestore, SeTakeOwnership) are enabled at module load.

function Set-FileOwnershipInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerAccount
    )
    $acl = Get-Acl -LiteralPath $Path
    $acct = New-Object System.Security.Principal.NTAccount($OwnerAccount)
    $acl.SetOwner($acct)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Set-FileOwnershipBySid — set the owner to a raw SID string.
# Used for orphan SID ownership when we've captured the SID before deletion
# and want to replay it (not used in v4 primary flow — orphan ownership
# is applied while the user still exists, then Remove-DemoOrphanUser deletes
# the account and the SID naturally becomes unresolvable). Here as a hook.
function Set-FileOwnershipBySid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SidString
    )
    $acl = Get-Acl -LiteralPath $Path
    $sid = New-Object System.Security.Principal.SecurityIdentifier($SidString)
    $acl.SetOwner($sid)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Add-FileExplicitAce — add a single explicit ACE on a file.
function Add-FileExplicitAce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][System.Security.AccessControl.FileSystemRights]$Rights,
        [ValidateSet('Allow','Deny')][string]$Type = 'Allow'
    )
    $acl = Get-Acl -LiteralPath $Path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights,
        [System.Security.AccessControl.AccessControlType]::$Type)
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Protect-AclFromInheritance — break inheritance on a file or folder.
# If $KeepInherited is true, copies current inherited ACEs into explicit ACEs
# before removing inheritance.
function Protect-AclFromInheritance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$KeepInherited
    )
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $KeepInherited.IsPresent)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Remove-AclRulesForPrincipal — strip all Allow ACEs for a given principal.
# Used for Sensitive/Board folders to remove broad read.
function Remove-AclRulesForPrincipal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Identity
    )
    $acl = Get-Acl -LiteralPath $Path
    $target = $null
    try { $target = (New-Object System.Security.Principal.NTAccount($Identity)).Translate([System.Security.Principal.SecurityIdentifier]) }
    catch { }
    $toRemove = @()
    foreach ($rule in $acl.Access) {
        if ($rule.IsInherited) { continue }
        $ruleSid = $null
        try { $ruleSid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]) } catch {}
        if (($target -and $ruleSid -and $ruleSid.Value -eq $target.Value) -or
            ($rule.IdentityReference.Value -ieq $Identity)) {
            $toRemove += $rule
        }
    }
    foreach ($r in $toRemove) { [void]$acl.RemoveAccessRule($r) }
    if ($toRemove.Count -gt 0) { Set-Acl -LiteralPath $Path -AclObject $acl }
}

# Set-AclPattern — apply a rolled ACL mess pattern to a folder.
# Context object provides the principals needed: $Context.DeptGG, .DLRw, .DLRo,
# .Contractors, .OrphanSamPicker (scriptblock), .Domain.
#
# Pattern names match $Config.Mess.AclPatterns[].Name.
function Set-AclPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][hashtable]$Context
    )
    $domain = $Context.Domain
    switch ($Pattern) {
        'ProperAGDLP' {
            if ($Context.DLRw) {
                Add-FolderAce -Path $Path -Identity "$domain\$($Context.DLRw)" -Rights Modify
            }
            if ($Context.DLRo) {
                Add-FolderAce -Path $Path -Identity "$domain\$($Context.DLRo)" -Rights ReadAndExecute
            }
        }
        'LazyGlobalGG' {
            if ($Context.DeptGG) {
                Add-FolderAce -Path $Path -Identity "$domain\$($Context.DeptGG)" -Rights Modify
            }
        }
        'OrphanSidAce' {
            $orphan = & $Context.OrphanSamPicker
            if ($orphan) {
                Add-FolderAce -Path $Path -Identity "$domain\$orphan" -Rights Modify
            }
        }
        'EveryoneRead' {
            Add-FolderAce -Path $Path -Identity 'Everyone' -Rights ReadAndExecute
        }
        'DenyAce' {
            if ($Context.Contractors) {
                Add-FolderAce -Path $Path -Identity "$domain\$($Context.Contractors)" -Rights Write -Type Deny
            }
        }
    }
}

function Add-FolderAce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][System.Security.AccessControl.FileSystemRights]$Rights,
        [ValidateSet('Allow','Deny')][string]$Type = 'Allow'
    )
    $acl = Get-Acl -LiteralPath $Path
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
               [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $prop    = [System.Security.AccessControl.PropagationFlags]::None
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights, $inherit, $prop,
        [System.Security.AccessControl.AccessControlType]::$Type)
    try {
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $acl
    } catch {
        Write-Verbose "Add-FolderAce failed for $Identity on $Path : $($_.Exception.Message)"
    }
}

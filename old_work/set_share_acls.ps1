$Domain = (Get-ADDomain).NetBIOSName
$Share  = "FS01-Shared"   # from your output

# Apply intended share-level permissions
Grant-SmbShareAccess -Name $Share -AccountName "$Domain\Domain Admins" -AccessRight Full -Force
Grant-SmbShareAccess -Name $Share -AccountName "$Domain\GG_AllEmployees" -AccessRight Read -Force
Revoke-SmbShareAccess -Name $Share -AccountName "Everyone" -Force

# Verify
Get-SmbShareAccess -Name $Share | Format-Table -Auto

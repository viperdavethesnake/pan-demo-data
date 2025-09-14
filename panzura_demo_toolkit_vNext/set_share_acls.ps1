# Import required modules
Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop
Import-Module SmbShare -SkipEditionCheck -ErrorAction Stop

$Domain = (Get-ADDomain).NetBIOSName
$Share  = "FS01-Shared"   # from your output

Write-Host "Cleaning up share permissions..." -ForegroundColor Yellow

# Clear ALL existing permissions first
$existing = Get-SmbShareAccess -Name $Share
foreach ($perm in $existing) {
    try {
        Revoke-SmbShareAccess -Name $Share -AccountName $perm.AccountName -Force -ErrorAction SilentlyContinue
    } catch {}
}

# Apply clean share-level permissions
Write-Host "Applying clean permissions..." -ForegroundColor Yellow
Grant-SmbShareAccess -Name $Share -AccountName "BUILTIN\Administrators" -AccessRight Full -Force
Grant-SmbShareAccess -Name $Share -AccountName "$Domain\Domain Admins" -AccessRight Full -Force
Grant-SmbShareAccess -Name $Share -AccountName "$Domain\GG_AllEmployees" -AccessRight Read -Force

# Verify final state
Write-Host "Final share permissions:" -ForegroundColor Green
Get-SmbShareAccess -Name $Share | Format-Table -Auto

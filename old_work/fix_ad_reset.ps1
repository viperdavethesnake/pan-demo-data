# Fix AD reset by removing protection from accidental deletion
# Usage: .\fix_ad_reset.ps1

param(
    [string]$BaseOUName = "DemoCorp"
)

Import-Module ActiveDirectory -SkipEditionCheck -ErrorAction Stop

Write-Host "=== Fixing AD Reset - Removing Protection ===" -ForegroundColor Yellow

$domain = Get-ADDomain
$domainDN = $domain.DistinguishedName
$rootOU = "OU=$BaseOUName,$domainDN"

# Get all OUs under DemoCorp
$allOUs = Get-ADOrganizationalUnit -Filter * | Where-Object { $_.DistinguishedName -like "*$BaseOUName*" }

Write-Host "Found $($allOUs.Count) OUs to unprotect" -ForegroundColor White

foreach ($ou in $allOUs) {
    Write-Host "Unprotecting: $($ou.Name)" -ForegroundColor Cyan
    try {
        Set-ADOrganizationalUnit -Identity $ou.DistinguishedName -ProtectedFromAccidentalDeletion $false
        Write-Host "  ✓ Unprotected successfully" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nNow run the AD reset script:" -ForegroundColor Yellow
Write-Host ".\ad_reset.ps1 -BaseOUName $BaseOUName -DoOUs -Confirm:`$false" -ForegroundColor White

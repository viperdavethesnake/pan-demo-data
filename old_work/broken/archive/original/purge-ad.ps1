# Set parameters
$ou = "OU=LabUsers,DC=plab,DC=local"

# Unprotect from accidental deletion
Set-ADOrganizationalUnit -Identity $ou -ProtectedFromAccidentalDeletion $false

# Remove ALL child groups and users (repeat just to be thorough)
Get-ADGroup -SearchBase $ou -Filter * | Remove-ADGroup -Confirm:$false
Get-ADUser  -SearchBase $ou -Filter * | Remove-ADUser -Confirm:$false

# Remove the OU itself
Remove-ADOrganizationalUnit -Identity $ou -Recursive -Confirm:$false

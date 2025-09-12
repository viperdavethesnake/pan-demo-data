# purge-ad-fixed.ps1
# FIXED VERSION - Works with CN=Users instead of OU=LabUsers

param(
    [string]$ContainerPath = "CN=Users,DC=plab,DC=local",  # Changed from OU=LabUsers
    [switch]$WhatIf = $false  # Safety switch to preview what would be deleted
)

Write-Host "Purging AD test environment from: $ContainerPath"

if ($WhatIf) {
    Write-Host "WHATIF MODE - No actual deletions will occur"
}

# Get all our test groups (groups that would have been created by ad-populator-fixed.ps1)
$testGroups = @(
    "HR","Engineering","Sales","Support","Marketing","IT","PreSales","Accounting","Legal","Finance",
    "QA","DevOps","SysAdmins","ProjectManagers","Contractors","TempStaff","Execs","Directors","Board","Partners",
    "Payroll","AR","AP","Recruiting","Facilities","Reception","FieldTechs","DesktopSupport","Helpdesk","Training",
    "R&D","ProductOwners","ChangeControl","DesignTeam","WebTeam",
    "SecurityTeam","AuditTeam","Compliance","DataStewards","ISOAdmins","BackupOps","DisasterRecovery","PrivilegedIT",
    "MobileUsers","RemoteOnly","VPNUsers","AllStaff","AllContractors","ExternalVendors","Alumni","OnLeave",
    "ObsoleteStaff","RetiredGroups","LegacyApps","OldFinance","OldSales","Projects2010","Accounting2013","Sales2009"
)

# Get all test users (users with our naming pattern)
Write-Host "Finding test users..."
$testUsers = Get-ADUser -Filter * -SearchBase $ContainerPath | Where-Object {
    $_.SamAccountName -match "^[a-z]+\.[a-z]+$" -and  # firstname.lastname pattern
    $_.DistinguishedName -like "*$ContainerPath"
}

Write-Host "Found $($testUsers.Count) test users to remove"

# Get existing test groups
Write-Host "Finding test groups..."
$existingTestGroups = @()
foreach ($groupName in $testGroups) {
    try {
        $group = Get-ADGroup -Filter "Name -eq '$groupName'" -SearchBase $ContainerPath -ErrorAction SilentlyContinue
        if ($group) {
            $existingTestGroups += $group
        }
    } catch {
        # Group doesn't exist, skip
    }
}

Write-Host "Found $($existingTestGroups.Count) test groups to remove"

if ($WhatIf) {
    Write-Host "`nWOULD DELETE THESE USERS:"
    $testUsers | ForEach-Object { Write-Host "  - $($_.SamAccountName) ($($_.Name))" }
    
    Write-Host "`nWOULD DELETE THESE GROUPS:"
    $existingTestGroups | ForEach-Object { Write-Host "  - $($_.Name)" }
    
    Write-Host "`nRun without -WhatIf to actually perform deletions"
    return
}

# Remove users from groups first
Write-Host "Removing users from groups..."
foreach ($user in $testUsers) {
    try {
        $userGroups = Get-ADPrincipalGroupMembership $user.SamAccountName -ErrorAction SilentlyContinue
        foreach ($group in $userGroups) {
            if ($group.Name -in $testGroups) {
                Remove-ADGroupMember -Identity $group.Name -Members $user.SamAccountName -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Host "Warning: Could not remove $($user.SamAccountName) from groups"
    }
}

# Remove test users
Write-Host "Removing test users..."
foreach ($user in $testUsers) {
    try {
        Remove-ADUser -Identity $user.SamAccountName -Confirm:$false
        Write-Host "Removed user: $($user.SamAccountName)"
    } catch {
        Write-Host "Failed to remove user: $($user.SamAccountName) - $_"
    }
}

# Remove test groups
Write-Host "Removing test groups..."
foreach ($group in $existingTestGroups) {
    try {
        Remove-ADGroup -Identity $group.Name -Confirm:$false
        Write-Host "Removed group: $($group.Name)"
    } catch {
        Write-Host "Failed to remove group: $($group.Name) - $_"
    }
}

Write-Host "Purge complete!"
Write-Host "NOTE: Standard Windows groups and non-test users were preserved"

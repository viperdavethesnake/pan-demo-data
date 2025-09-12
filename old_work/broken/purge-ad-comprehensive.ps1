# purge-ad-comprehensive.ps1
# Comprehensive AD cleanup for both old and new script patterns

param(
    [switch]$WhatIf = $true,  # Default to WhatIf for safety
    [switch]$IncludeOldPattern = $true,  # Include old firstname.lastname users
    [switch]$IncludeNewPattern = $true,  # Include new v2 users (finance01, hr05, etc.)
    [string]$BaseOUName = "DemoCorp",  # For v2 cleanup
    [switch]$RemoveOUs = $false  # Whether to remove the OUs too
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "COMPREHENSIVE AD CLEANUP" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "🔍 WHATIF MODE - No actual deletions will occur" -ForegroundColor Yellow
    Write-Host "   Add -WhatIf:`$false to actually perform deletions" -ForegroundColor Yellow
} else {
    Write-Host "⚠️  DELETION MODE - Changes will be permanent!" -ForegroundColor Red
}

Write-Host ""

# Domain info
$domainDN = (Get-ADDomain).DistinguishedName
$defaultContainer = "CN=Users,$domainDN"

# === CLEANUP NEW V2 PATTERN (DemoCorp OU structure) ===
if ($IncludeNewPattern) {
    Write-Host "=== CLEANING UP V2 PATTERN (DemoCorp OU) ===" -ForegroundColor Green
    
    $rootOU = "OU=$BaseOUName,$domainDN"
    
    if (Get-ADOrganizationalUnit -LDAPFilter "(ou=$BaseOUName)" -SearchBase $domainDN -ErrorAction SilentlyContinue) {
        Write-Host "Found DemoCorp OU structure" -ForegroundColor Yellow
        
        # Find all users in DemoCorp structure
        $v2Users = Get-ADUser -Filter * -SearchBase $rootOU -ErrorAction SilentlyContinue
        Write-Host "Found $($v2Users.Count) users in DemoCorp OU" -ForegroundColor White
        
        # Find all groups in DemoCorp structure  
        $v2Groups = Get-ADGroup -Filter * -SearchBase $rootOU -ErrorAction SilentlyContinue
        Write-Host "Found $($v2Groups.Count) groups in DemoCorp OU" -ForegroundColor White
        
        if ($WhatIf) {
            Write-Host "`n📋 WOULD DELETE V2 USERS:" -ForegroundColor Cyan
            $v2Users | ForEach-Object { Write-Host "  - $($_.SamAccountName) ($($_.Name))" -ForegroundColor Gray }
            
            Write-Host "`n📋 WOULD DELETE V2 GROUPS:" -ForegroundColor Cyan
            $v2Groups | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
            
            if ($RemoveOUs) {
                Write-Host "`n📋 WOULD DELETE OUs:" -ForegroundColor Cyan
                $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $rootOU | Sort-Object DistinguishedName -Descending
                $ous | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
                Write-Host "  - $BaseOUName (root)" -ForegroundColor Gray
            }
        } else {
            # Remove users first
            Write-Host "`n🗑️ Removing V2 users..." -ForegroundColor Yellow
            foreach ($user in $v2Users) {
                try {
                    Remove-ADUser -Identity $user.SamAccountName -Confirm:$false
                    Write-Host "  ✓ Removed user: $($user.SamAccountName)" -ForegroundColor Green
                } catch {
                    Write-Host "  ✗ Failed to remove user: $($user.SamAccountName) - $_" -ForegroundColor Red
                }
            }
            
            # Remove groups
            Write-Host "`n🗑️ Removing V2 groups..." -ForegroundColor Yellow
            foreach ($group in $v2Groups) {
                try {
                    Remove-ADGroup -Identity $group.Name -Confirm:$false
                    Write-Host "  ✓ Removed group: $($group.Name)" -ForegroundColor Green
                } catch {
                    Write-Host "  ✗ Failed to remove group: $($group.Name) - $_" -ForegroundColor Red
                }
            }
            
            # Remove OUs if requested (bottom-up order)
            if ($RemoveOUs) {
                Write-Host "`n🗑️ Removing OUs..." -ForegroundColor Yellow
                $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $rootOU | Sort-Object DistinguishedName -Descending
                foreach ($ou in $ous) {
                    try {
                        Remove-ADOrganizationalUnit -Identity $ou.DistinguishedName -Confirm:$false
                        Write-Host "  ✓ Removed OU: $($ou.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "  ✗ Failed to remove OU: $($ou.Name) - $_" -ForegroundColor Red
                    }
                }
                
                # Remove root OU last
                try {
                    Remove-ADOrganizationalUnit -Identity $rootOU -Confirm:$false
                    Write-Host "  ✓ Removed root OU: $BaseOUName" -ForegroundColor Green
                } catch {
                    Write-Host "  ✗ Failed to remove root OU: $BaseOUName - $_" -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "No DemoCorp OU found - skipping V2 cleanup" -ForegroundColor Gray
    }
}

# === CLEANUP OLD PATTERN (CN=Users container) ===
if ($IncludeOldPattern) {
    Write-Host "`n=== CLEANING UP OLD PATTERN (CN=Users) ===" -ForegroundColor Green
    
    # Old script groups
    $oldTestGroups = @(
        "HR","Engineering","Sales","Support","Marketing","IT","PreSales","Accounting","Legal","Finance",
        "QA","DevOps","SysAdmins","ProjectManagers","Contractors","TempStaff","Execs","Directors","Board","Partners",
        "Payroll","AR","AP","Recruiting","Facilities","Reception","FieldTechs","DesktopSupport","Helpdesk","Training",
        "R&D","ProductOwners","ChangeControl","DesignTeam","WebTeam",
        "SecurityTeam","AuditTeam","Compliance","DataStewards","ISOAdmins","BackupOps","DisasterRecovery","PrivilegedIT",
        "MobileUsers","RemoteOnly","VPNUsers","AllStaff","AllContractors","ExternalVendors","Alumni","OnLeave",
        "ObsoleteStaff","RetiredGroups","LegacyApps","OldFinance","OldSales","Projects2010","Accounting2013","Sales2009"
    )
    
    # Find old pattern users (firstname.lastname)
    $oldUsers = Get-ADUser -Filter * -SearchBase $defaultContainer | Where-Object {
        $_.SamAccountName -match "^[a-z]+\.[a-z]+$" -and  # firstname.lastname pattern
        $_.DistinguishedName -like "*$defaultContainer"
    }
    Write-Host "Found $($oldUsers.Count) old pattern users (firstname.lastname)" -ForegroundColor White
    
    # Find old pattern groups
    $existingOldGroups = @()
    foreach ($groupName in $oldTestGroups) {
        $group = Get-ADGroup -Filter "Name -eq '$groupName'" -SearchBase $defaultContainer -ErrorAction SilentlyContinue
        if ($group) {
            $existingOldGroups += $group
        }
    }
    Write-Host "Found $($existingOldGroups.Count) old pattern groups" -ForegroundColor White
    
    if ($WhatIf) {
        Write-Host "`n📋 WOULD DELETE OLD USERS:" -ForegroundColor Cyan
        $oldUsers | ForEach-Object { Write-Host "  - $($_.SamAccountName) ($($_.Name))" -ForegroundColor Gray }
        
        Write-Host "`n📋 WOULD DELETE OLD GROUPS:" -ForegroundColor Cyan
        $existingOldGroups | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
    } else {
        # Remove old users from groups first
        Write-Host "`n🗑️ Removing old users from groups..." -ForegroundColor Yellow
        foreach ($user in $oldUsers) {
            try {
                $userGroups = Get-ADPrincipalGroupMembership $user.SamAccountName -ErrorAction SilentlyContinue
                foreach ($group in $userGroups) {
                    if ($group.Name -in $oldTestGroups) {
                        Remove-ADGroupMember -Identity $group.Name -Members $user.SamAccountName -Confirm:$false -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                Write-Host "  ⚠ Could not remove $($user.SamAccountName) from groups" -ForegroundColor Yellow
            }
        }
        
        # Remove old users
        Write-Host "`n🗑️ Removing old pattern users..." -ForegroundColor Yellow
        foreach ($user in $oldUsers) {
            try {
                Remove-ADUser -Identity $user.SamAccountName -Confirm:$false
                Write-Host "  ✓ Removed user: $($user.SamAccountName)" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed to remove user: $($user.SamAccountName) - $_" -ForegroundColor Red
            }
        }
        
        # Remove old groups
        Write-Host "`n🗑️ Removing old pattern groups..." -ForegroundColor Yellow
        foreach ($group in $existingOldGroups) {
            try {
                Remove-ADGroup -Identity $group.Name -Confirm:$false
                Write-Host "  ✓ Removed group: $($group.Name)" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed to remove group: $($group.Name) - $_" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "CLEANUP SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "✅ WhatIf mode - No changes made" -ForegroundColor Green
    Write-Host ""
    Write-Host "To actually perform cleanup:" -ForegroundColor Yellow
    Write-Host "  .\purge-ad-comprehensive.ps1 -WhatIf:`$false" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -IncludeOldPattern:`$false   # Skip old firstname.lastname users" -ForegroundColor Gray
    Write-Host "  -IncludeNewPattern:`$false   # Skip new DemoCorp users" -ForegroundColor Gray
    Write-Host "  -RemoveOUs:`$true            # Also remove DemoCorp OUs" -ForegroundColor Gray
    Write-Host "  -BaseOUName 'CompanyXYZ'     # Different OU name" -ForegroundColor Gray
} else {
    Write-Host "✅ Cleanup completed!" -ForegroundColor Green
    Write-Host "   Standard Windows groups and system accounts were preserved" -ForegroundColor Gray
}

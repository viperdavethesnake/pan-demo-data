# --- AD Populator: Enhanced Fake Corp Environment ---
# Creates realistic enterprise AD with users, groups, service accounts, and proper attributes

param(
    [string]$Domain = "plab.local",
    [string]$ContainerPath = "CN=Users,DC=plab,DC=local",
    [int]$NumUsers = 220,
    [int]$NumServiceAccounts = 8,
    [string]$DefaultPassword = "Password123!",
    [string]$EmailDomain = "plab.local",
    [switch]$WhatIf
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "ENHANCED AD POPULATOR" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Domain: $Domain"
Write-Host "Container: $ContainerPath"
Write-Host "Users to create: $NumUsers"
Write-Host "Service accounts: $NumServiceAccounts"
Write-Host "WhatIf mode: $WhatIf"
Write-Host ""

# Realistic group list with hierarchy
$groups = @(
    # Core departments
    "HR","Engineering","Sales","Support","Marketing","IT","PreSales","Accounting","Legal","Finance",
    # Major roles
    "QA","DevOps","SysAdmins","ProjectManagers","Contractors","TempStaff","Execs","Directors","Board","Partners",
    # Functions/Teams
    "Payroll","AR","AP","Recruiting","Facilities","Reception","FieldTechs","DesktopSupport","Helpdesk","Training","R&D","ProductOwners","ChangeControl","DesignTeam","WebTeam",
    # Security/compliance
    "SecurityTeam","AuditTeam","Compliance","DataStewards","ISOAdmins","BackupOps","DisasterRecovery","PrivilegedIT",
    # Business/operational
    "MobileUsers","RemoteOnly","VPNUsers","AllStaff","AllContractors","ExternalVendors","Alumni","OnLeave",
    # Location-based
    "Office_NYC","Office_LA","Office_Chicago","Office_Austin","Remote_Workers","Field_Staff",
    # Legacy/abandoned (realistic enterprise mess)
    "ObsoleteStaff","RetiredGroups","LegacyApps","OldFinance","OldSales","Projects2010","Accounting2013","Sales2009"
) | Sort-Object -Unique

# Diverse name lists
$firstNames = @(
    "James","Mary","John","Patricia","Robert","Jennifer","Michael","Linda","William","Elizabeth",
    "David","Barbara","Richard","Susan","Joseph","Jessica","Thomas","Sarah","Charles","Karen",
    "Matthew","Anthony","Mark","Sandra","Carlos","Juan","Luis","Jorge","Miguel","Jose","Sofia","Maria",
    "Isabella","Valentina","Camila","Gabriela","Wei","Li","Ming","Xiao","Chen","Yuki","Haruto",
    "Sakura","Hana","Satoshi","Kenji","Naoko","Raj","Priya","Anil","Amit","Sanjay","Deepa","Ravi",
    "Sunita","Arjun","Vijay","Neha","Asha","Ahmed","Fatima","Omar","Aisha","Hassan","Zara"
)

$lastNames = @(
    "Smith","Johnson","Williams","Jones","Brown","Davis","Miller","Wilson","Moore","Taylor",
    "Anderson","Thomas","Jackson","White","Harris","Martin","Thompson","Wright","Garcia","Martinez",
    "Rodriguez","Hernandez","Lopez","Gonzalez","Perez","Sanchez","Ramirez","Torres","Flores","Cruz",
    "Morales","Reyes","Lee","Wang","Zhang","Chen","Liu","Lin","Huang","Kim","Park","Choi","Nguyen",
    "Tran","Patel","Sharma","Gupta","Reddy","Singh","Kumar","Nair","Joshi","Das","Mehta","Ali","Hassan"
)

# Realistic job titles with hierarchy
$titles = @{
    "Junior" = @("Junior Developer","Junior Analyst","Associate","Assistant","Coordinator","Specialist I")
    "Mid" = @("Developer","Analyst","Specialist","Consultant","Manager","Lead","Principal")
    "Senior" = @("Senior Developer","Senior Analyst","Senior Manager","Director","Principal Consultant","Architect")
    "Executive" = @("VP","SVP","CTO","CIO","CFO","CMO","CHRO","General Manager","Vice President")
}

# Office locations
$locations = @("New York","Los Angeles","Chicago","Austin","Seattle","Boston","Remote","Field")

# Service account definitions
$serviceAccounts = @(
    @{Name="sql_service"; Description="SQL Server Service Account"; Groups=@("ISOAdmins","BackupOps")}
    @{Name="backup_svc"; Description="Backup Service Account"; Groups=@("BackupOps","DisasterRecovery")}
    @{Name="web_app_pool"; Description="Web Application Pool Account"; Groups=@("WebTeam","IT")}
    @{Name="monitoring_svc"; Description="System Monitoring Service"; Groups=@("SysAdmins","IT")}
    @{Name="ad_sync_svc"; Description="AD Synchronization Service"; Groups=@("PrivilegedIT","SysAdmins")}
    @{Name="file_share_svc"; Description="File Share Service Account"; Groups=@("IT","BackupOps")}
    @{Name="print_svc"; Description="Print Spooler Service Account"; Groups=@("IT","DesktopSupport")}
    @{Name="crm_service"; Description="CRM Application Service"; Groups=@("Sales","IT")}
)

# Statistics tracking
$stats = @{
    GroupsCreated = 0
    GroupsExisted = 0
    UsersCreated = 0
    UsersExisted = 0
    ServiceAccountsCreated = 0
    ServiceAccountsExisted = 0
}

# --- CREATE GROUPS ---
Write-Host "Creating groups..." -ForegroundColor Yellow
foreach ($g in $groups | Select-Object -Unique) {
    try {
        if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
            if (-not $WhatIf) {
                New-ADGroup -Name $g -GroupScope Global -Path $ContainerPath
                Write-Host "  ✓ Created group: $g" -ForegroundColor Green
                $stats.GroupsCreated++
            } else {
                Write-Host "  WOULD CREATE group: $g" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  - Group already exists: $g" -ForegroundColor Gray
            $stats.GroupsExisted++
        }
    } catch {
        Write-Host "  ✗ Failed to create group $g : $_" -ForegroundColor Red
    }
}

# --- CREATE SERVICE ACCOUNTS ---
Write-Host "`nCreating service accounts..." -ForegroundColor Yellow
foreach ($svcAcct in $serviceAccounts[0..($NumServiceAccounts-1)]) {
    try {
        $sam = $svcAcct.Name
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
            if (-not $WhatIf) {
                New-ADUser -SamAccountName $sam -Name $svcAcct.Description `
                    -Description $svcAcct.Description -Path $ContainerPath -Enabled $true `
                    -AccountPassword (ConvertTo-SecureString $DefaultPassword -AsPlainText -Force) `
                    -UserPrincipalName "$sam@$EmailDomain" `
                    -Title "Service Account" -Department "IT"

                # Add to groups
                foreach ($g in $svcAcct.Groups) {
                    try {
                        Add-ADGroupMember -Identity $g -Members $sam -ErrorAction SilentlyContinue
                    } catch {
                        Write-Host "    ⚠ Failed to add $sam to group $g" -ForegroundColor Yellow
                    }
                }
                Write-Host "  ✓ Created service account: $sam" -ForegroundColor Green
                $stats.ServiceAccountsCreated++
            } else {
                Write-Host "  WOULD CREATE service account: $sam" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  - Service account already exists: $sam" -ForegroundColor Gray
            $stats.ServiceAccountsExisted++
        }
    } catch {
        Write-Host "  ✗ Failed to create service account $($svcAcct.Name) : $_" -ForegroundColor Red
    }
}

# --- CREATE USERS ---
Write-Host "`nCreating users..." -ForegroundColor Yellow
$users = @()
for ($i = 1; $i -le $NumUsers; $i++) {
    $fname = Get-Random $firstNames
    $lname = Get-Random $lastNames
    $sam = ($fname + "." + $lname).ToLower()
    $dept = Get-Random @("Engineering","Sales","Support","Marketing","IT","PreSales","Accounting","Legal","Finance","HR")
    $location = Get-Random $locations
    
    # Assign realistic title based on seniority
    $seniority = Get-Random -Min 1 -Max 100
    $titleCategory = if ($seniority -le 5) { "Executive" } 
                    elseif ($seniority -le 15) { "Senior" } 
                    elseif ($seniority -le 60) { "Mid" } 
                    else { "Junior" }
    $title = Get-Random $titles[$titleCategory]

    # Assign user to groups (always dept + AllStaff + location, plus random others)
    $userGroups = @($dept, "AllStaff", "Office_$($location.Replace(' ','_'))")
    $randGroups = Get-Random -Count (Get-Random -Min 1 -Max 4) -InputObject ($groups | Where-Object {$_ -notin $userGroups})
    $userGroups += $randGroups | Select-Object -Unique

    # Add some realistic group assignments based on role
    if ($title -like "*Manager*" -or $title -like "*Director*") { $userGroups += "ProjectManagers" }
    if ($title -like "*VP*" -or $title -like "*Executive*") { $userGroups += "Execs" }
    if ($location -eq "Remote") { $userGroups += "RemoteOnly", "VPNUsers" }
    if ($dept -eq "IT") { $userGroups += "MobileUsers" }

    # Some legacy/obsolete group memberships (realistic enterprise mess)
    if ((Get-Random -Max 8) -eq 1) { $userGroups += "ObsoleteStaff" }
    if ((Get-Random -Max 15) -eq 3) { $userGroups += "RetiredGroups" }

    try {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
            if (-not $WhatIf) {
                New-ADUser -SamAccountName $sam -Name "$fname $lname" `
                    -GivenName $fname -Surname $lname `
                    -Department $dept -Path $ContainerPath -Enabled $true `
                    -AccountPassword (ConvertTo-SecureString $DefaultPassword -AsPlainText -Force) `
                    -UserPrincipalName "$sam@$EmailDomain" `
                    -EmailAddress "$sam@$EmailDomain" `
                    -Title $title `
                    -Office $location `
                    -Company "Panzura Lab Corp"

                # Add to groups
                foreach ($g in $userGroups | Select-Object -Unique) {
                    try {
                        Add-ADGroupMember -Identity $g -Members $sam -ErrorAction SilentlyContinue
                    } catch {
                        # Silently continue if group doesn't exist
                    }
                }
                
                $users += @{
                    SamAccountName = $sam
                    Name = "$fname $lname"
                    Department = $dept
                    Title = $title
                    Location = $location
                    Groups = $userGroups -join ", "
                }
                $stats.UsersCreated++
                
                if (($i % 25) -eq 0) {
                    Write-Host "  Created $i users so far..." -ForegroundColor Green
                }
            } else {
                Write-Host "  WOULD CREATE user: $sam ($fname $lname) - $title in $dept" -ForegroundColor Cyan
            }
        } else {
            $stats.UsersExisted++
        }
    } catch {
        Write-Host "  ✗ Failed to create user $sam : $_" -ForegroundColor Red
    }
}

# --- SUMMARY REPORT ---
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "SUMMARY REPORT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Groups created: $($stats.GroupsCreated)" -ForegroundColor Green
Write-Host "Groups already existed: $($stats.GroupsExisted)" -ForegroundColor Yellow
Write-Host "Users created: $($stats.UsersCreated)" -ForegroundColor Green
Write-Host "Users already existed: $($stats.UsersExisted)" -ForegroundColor Yellow
Write-Host "Service accounts created: $($stats.ServiceAccountsCreated)" -ForegroundColor Green
Write-Host "Service accounts already existed: $($stats.ServiceAccountsExisted)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Total AD objects in environment:"
Write-Host "  Groups: $($stats.GroupsCreated + $stats.GroupsExisted)"
Write-Host "  Users: $($stats.UsersCreated + $stats.UsersExisted)"
Write-Host "  Service Accounts: $($stats.ServiceAccountsCreated + $stats.ServiceAccountsExisted)"
Write-Host ""
Write-Host "NOTE: All objects created in $ContainerPath for Symphony compatibility!" -ForegroundColor Cyan

if (-not $WhatIf) {
    # Export user list to CSV for reference
    $csvPath = "S:\Scripts\scripts_ad\users_created_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $users | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "User details exported to: $csvPath" -ForegroundColor Green
}

Write-Host "`nRealistic enterprise AD environment ready for Symphony testing!" -ForegroundColor Green

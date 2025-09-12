# --- AD Populator: Fake Corp, 200+ Users, 50+ Groups, Realistic Mess ---
# FIXED VERSION - Creates users/groups in CN=Users instead of OU=LabUsers

# Parameters
$containerPath = "CN=Users,DC=plab,DC=local"  # Changed from OU=LabUsers
$numUsers = 220

# Add a wild, realistic group list:
$groups = @(
    # Core departments
    "HR","Engineering","Sales","Support","Marketing","IT","PreSales","Accounting","Legal","Finance",
    # Major roles
    "QA","DevOps","SysAdmins","ProjectManagers","Contractors","TempStaff","Execs","Directors","Board","Partners",
    # Functions/Teams
    "Payroll","AR","AP","Recruiting","Facilities","Reception","FieldTechs","DesktopSupport","Helpdesk","Training","R&D","ProductOwners","ChangeControl","DesignTeam","WebTeam",
    # Security/compliance
    "SecurityTeam","AuditTeam","Compliance","DataStewards","ISOAdmins","BackupOps","DisasterRecovery","PrivilegedIT",
    # Misc/business
    "MobileUsers","RemoteOnly","VPNUsers","AllStaff","AllContractors","ExternalVendors","Alumni","OnLeave",
    # Legacy/abandoned
    "ObsoleteStaff","RetiredGroups","LegacyApps","OldFinance","OldSales","Projects2010","Accounting2013","Sales2009"
) | Sort-Object -Unique

# Name lists for diversity
$firstNames = @(
    "James","Mary","John","Patricia","Robert","Jennifer","Michael","Linda","William","Elizabeth",
    "David","Barbara","Richard","Susan","Joseph","Jessica","Thomas","Sarah","Charles","Karen",
    "Matthew","Anthony","Mark","Sandra","Carlos","Juan","Luis","Jorge","Miguel","Jose","Sofia","Maria",
    "Isabella","Valentina","Camila","Gabriela","Wei","Li","Ming","Xiao","Chen","Yuki","Haruto",
    "Sakura","Hana","Satoshi","Kenji","Naoko","Raj","Priya","Anil","Amit","Sanjay","Deepa","Ravi",
    "Sunita","Arjun","Vijay","Neha","Asha"
)
$lastNames = @(
    "Smith","Johnson","Williams","Jones","Brown","Davis","Miller","Wilson","Moore","Taylor",
    "Anderson","Thomas","Jackson","White","Harris","Martin","Thompson","Wright","Garcia","Martinez",
    "Rodriguez","Hernandez","Lopez","Gonzalez","Perez","Sanchez","Ramirez","Torres","Flores","Cruz",
    "Morales","Reyes","Lee","Wang","Zhang","Chen","Liu","Lin","Huang","Kim","Park","Choi","Nguyen",
    "Tran","Patel","Sharma","Gupta","Reddy","Singh","Kumar","Nair","Joshi","Das","Mehta"
)

Write-Host "Creating groups in $containerPath..."

# --- Create all groups if needed ---
foreach ($g in $groups | Select-Object -Unique) {
    try {
        if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $g -GroupScope Global -Path $containerPath
            Write-Host "Created group: $g"
        } else {
            Write-Host "Group already exists: $g"
        }
    } catch {
        Write-Host "Failed to create group $g : $_"
    }
}

Write-Host "Creating users in $containerPath..."

# --- User creation ---
$users = @()
for ($i = 1; $i -le $numUsers; $i++) {
    $fname = Get-Random $firstNames
    $lname = Get-Random $lastNames
    $sam   = ($fname + "." + $lname).ToLower()
    $dept  = Get-Random @("Engineering","Sales","Support","Marketing","IT","PreSales","Accounting","Legal","Finance","HR")

    # Assign user to 1-4 random groups, always dept + AllStaff, sometimes random legacy/weird groups
    $userGroups = @($dept, "AllStaff")
    $randGroups = Get-Random -Count (Get-Random -Min 1 -Max 4) -InputObject ($groups | Where-Object {$_ -ne $dept -and $_ -ne "AllStaff"})
    $userGroups += $randGroups | Select-Object -Unique

    # Some with legacy/obsolete tags
    if ((Get-Random -Max 8) -eq 1) { $userGroups += "ObsoleteStaff" }
    if ((Get-Random -Max 15) -eq 3) { $userGroups += "RetiredGroups" }
    if ((Get-Random -Max 11) -eq 4) { $userGroups += "LegacyApps" }

    $isManager = (Get-Random -Maximum 10) -eq 0 # 10% managers
    $isExec = (Get-Random -Maximum 40) -eq 0    # ~2% execs

    try {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
            New-ADUser -SamAccountName $sam -Name "$fname $lname" `
                -GivenName $fname -Surname $lname `
                -Department $dept -Path $containerPath -Enabled $true `
                -AccountPassword (ConvertTo-SecureString "Password123!" -AsPlainText -Force)

            # Add to groups
            foreach ($g in $userGroups | Select-Object -Unique) {
                try {
                    Add-ADGroupMember -Identity $g -Members $sam -ErrorAction SilentlyContinue
                } catch {
                    Write-Host "Failed to add $sam to group $g"
                }
            }
            # Set exec/manager attribute
            if ($isManager) { Set-ADUser $sam -Title "Manager" }
            if ($isExec)    { Set-ADUser $sam -Title "Executive" }
            $users += $sam
            
            if (($i % 25) -eq 0) {
                Write-Host "Created $i users so far..."
            }
        }
    } catch {
        Write-Host "Failed to create user $sam : $_"
    }
}

Write-Host "Created $($users.Count) users in $containerPath, with all the glorious sprawl."
Write-Host "NOTE: All users and groups created in CN=Users for Symphony compatibility!"

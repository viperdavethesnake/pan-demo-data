# create-folders.ps1
# --- Realistic Messy Company Folders with Group Permissions ---

$root = "S:\Shared"

# Groups (mirror your AD-populator!)
$groups = @(
    "HR","Engineering","Sales","Support","Marketing","IT","PreSales","Accounting","Legal","Finance",
    "QA","DevOps","SysAdmins","ProjectManagers","Contractors","TempStaff","Execs","Directors","Board","Partners",
    "Payroll","AR","AP","Recruiting","Facilities","Reception","FieldTechs","DesktopSupport","Helpdesk","Training",
    "R&D","ProductOwners","ChangeControl","DesignTeam","WebTeam",
    "SecurityTeam","AuditTeam","Compliance","DataStewards","ISOAdmins","BackupOps","DisasterRecovery","PrivilegedIT",
    "MobileUsers","RemoteOnly","VPNUsers","AllStaff","AllContractors","ExternalVendors","Alumni","OnLeave",
    "ObsoleteStaff","RetiredGroups","LegacyApps","OldFinance","OldSales","Projects2010","Accounting2013","Sales2009"
) | Sort-Object -Unique

# Department structure for plausible root/share/OU sprawl
$departments = @{
    "HR"           = @("Benefits", "Onboarding", "EmployeeRecords", "Recruiting", "Handbook")
    "Finance"      = @("Budgets", "Invoices", "Payroll", "TaxDocs", "Reimbursements", "Expenses")
    "Engineering"  = @("Projects", "Specs", "Code", "QA", "Releases", "LegacyCode", "DesignDocs")
    "Sales"        = @("Leads", "ClosedDeals", "Quotes", "Forecasts", "Territories", "Accounts")
    "Marketing"    = @("Images", "Campaigns", "Events", "Assets", "Social", "Presentations")
    "Support"      = @("Tickets", "Escalated", "Junk", "OldCases", "FAQ", "KnowledgeBase")
    "Legal"        = @("Cases", "Contracts", "IP", "Compliance", "Policies", "NDAs")
    "IT"           = @("Configs", "Backups", "PSTs", "Scripts", "Installers", "SysAdmin", "AD_Exports")
    "Accounting"   = @("Receivables", "Payables", "Statements", "YearEnd", "Audit", "Legacy", "Accounting2013")
    "PreSales"     = @("Demos", "POCs", "Trials", "SalesTools")
}

$coreFolders = @(
    "General", "AllHands", "zzz_Archive", "!DO_NOT_USE", "Temp", "ToSort", "Backup", "Legacy",
    "Projects", "Shared", "OldFiles", "TeamDrives", "Documentation", "TestData", "Lost+Found", "Recovered", "Review"
)
$junkFolders = @("Temp", "ToSort", "Old", "Backup", "zzz_Archive", "!_archive", "Personal", "Random", "Copy of", "Misc", "Unsorted", "Junk", "Hold", "Recovered", "Lost+Found", "Review")

$years = 2005..2025

$allFolders = @()

# Top-level core and department roots
$allFolders += $coreFolders | ForEach-Object { "$root\$_" }
$departments.Keys | ForEach-Object {
    $dept = $_
    $allFolders += "$root\$dept"
    foreach ($sub in $departments[$dept]) {
        $allFolders += "$root\$dept\$sub"
    }
}

# Lots of year/project/junk nesting
foreach ($dept in @($departments.Keys)) {
    foreach ($sub in $departments[$dept]) {
        foreach ($year in $years | Get-Random -Count 8) {
            $allFolders += "$root\$dept\$sub\$year"
            $allFolders += "$root\$dept\$sub\$year\$((Get-Random $junkFolders))"
            $allFolders += "$root\$dept\$sub\$year\$((Get-Random $junkFolders))\Staff"
            $allFolders += "$root\$dept\$sub\$year\Project_$(Get-Random -Maximum 500)\$(Get-Random $coreFolders)\$(Get-Random $junkFolders)"
        }
        1..(Get-Random -Minimum 2 -Maximum 5) | ForEach-Object {
            $allFolders += "$root\$dept\$sub\$((Get-Random $junkFolders))"
        }
    }
}

# Cross-department, deep projects
foreach ($x in 1..80) {
    $d1 = Get-Random @($departments.Keys)
    $d2 = Get-Random @($departments.Keys)
    $mix = "$root\Projects\$d1-$d2-Project_$(Get-Random -Maximum 2000)\$(Get-Random $junkFolders)"
    $allFolders += $mix
}

# Personal/junk folders, abandoned users, contractors
foreach ($user in 1..50) {
    $who = "User" + (Get-Random -Minimum 1 -Maximum 210)
    $allFolders += "$root\Temp\$who"
    $allFolders += "$root\General\Personal\$who"
    $allFolders += "$root\!DO_NOT_USE\$who\$((Get-Random $junkFolders))"
}

# Legacy/obsolete/test folders
$allFolders += "$root\Engineering\Specs\OldSpecss"
$allFolders += "$root\Accounting\Reimbursments"
$allFolders += "$root\zzz_Archive\OldFiles\Copy of 2012"
$allFolders += "$root\Marketing\Campains\Archive"
$allFolders += "$root\Legal\Contracts\zzzzz_Backup"

$allFolders = $allFolders | Sort-Object -Unique

Write-Host "Creating $($allFolders.Count) folders..."

foreach ($folder in $allFolders) {
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
}

# --- Assign permissions: Each folder gets a few random, plausible groups
foreach ($folder in $allFolders) {
    $permGroups = @()
    # Randomly pick 2–6 groups for each folder
    $permGroups = Get-Random -InputObject $groups -Count (Get-Random -Min 2 -Max 6)
    $permGroups = $permGroups | Sort-Object -Unique
    foreach ($g in $permGroups) {
        try {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$g", "Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
            $acl = Get-Acl $folder
            $acl.SetAccessRule($rule)
            Set-Acl $folder $acl
            Write-Host "Set permissions for $g on $folder"
        } catch {
            Write-Host "Failed to set $g on $folder"
        }
    }
}

Write-Host "Folder structure and permissions complete! True corporate chaos."

# Set root folder
$root = "S:\Shared"

# Define groups
$groups = @(
    "HR", "Engineering", "TechSupport", "Marketing", "IT", "Sales",
    "Legal", "Accounting", "AllStaff", "VPNUsers", "Managers"
)

# Define year range for old folders
$years = 2005..2025

# Helper for random element
function Get-RandomElement($array) { $array | Get-Random }

# Define core structure (expand as much as you want)
$coreFolders = @(
    "General", "AllHands", "zzz_Archive", "!DO_NOT_USE", "Temp", "ToSort", "Backup", "Legacy",
    "Projects", "Shared", "OldFiles", "TeamDrives", "Documentation"
)

# Department folders with some deep sub-structure
$departments = @{
    "HR"           = @("Benefits", "Onboarding", "EmployeeRecords", "Recruiting", "Handbook")
    "Finance"      = @("Budgets", "Invoices", "Payroll", "TaxDocs", "Reimbursements", "Expenses")
    "Engineering"  = @("Projects", "Specs", "Code", "QA", "Releases", "LegacyCode", "DesignDocs")
    "Sales"        = @("Leads", "ClosedDeals", "Quotes", "Forecasts", "Territories", "Accounts")
    "Marketing"    = @("Images", "Campaigns", "Events", "Assets", "Social", "Presentations")
    "TechSupport"  = @("Tickets", "Escalated", "Junk", "OldCases", "FAQ", "KnowledgeBase")
    "Legal"        = @("Cases", "Contracts", "IP", "Compliance", "Policies", "NDAs")
    "IT"           = @("Configs", "Backups", "PSTs", "Scripts", "Installers", "SysAdmin", "AD_Exports")
    "Accounting"   = @("Receivables", "Payables", "Statements", "YearEnd", "Audit", "Legacy")
}

# Junk folders and randoms
$junkFolders = @("Temp", "ToSort", "Old", "Backup", "zzz_Archive", "!_archive", "Personal", "Random", "Copy of", "Misc", "Unsorted", "Junk", "Hold")

# Generate lots of nested folders
$allFolders = @()

# Add top-level and department root folders
$allFolders += $coreFolders | ForEach-Object { "$root\$_" }
$departments.Keys | ForEach-Object {
    $dept = $_
    $allFolders += "$root\$dept"
    foreach ($sub in $departments[$dept]) {
        $allFolders += "$root\$dept\$sub"
    }
}

# Generate years, projects, junk, and mixes
foreach ($dept in $departments.Keys) {
    foreach ($sub in $departments[$dept]) {
        # Add folders for every year, project, and some "deep" paths
        foreach ($year in $years | Get-Random -Count 8) {
            $allFolders += "$root\$dept\$sub\$year"
            # Even deeper junk structure
            $allFolders += "$root\$dept\$sub\$year\$((Get-RandomElement $junkFolders))"
            $allFolders += "$root\$dept\$sub\$year\$((Get-RandomElement $junkFolders))\Staff"
            # Deep mixed folders
            $allFolders += "$root\$dept\$sub\$year\Project_$(Get-Random -Maximum 500)\$(Get-RandomElement $coreFolders)\$(Get-RandomElement $junkFolders)"
        }
        # Old project/junk folders
        1..(Get-Random -Minimum 2 -Maximum 4) | ForEach-Object {
            $allFolders += "$root\$dept\$sub\$((Get-RandomElement $junkFolders))"
        }
    }
}

# Cross-department and "messy" folders
foreach ($x in 1..50) {
    $d1 = Get-RandomElement $departments.Keys
    $d2 = Get-RandomElement $departments.Keys
    $mix = "$root\Projects\$d1-$d2-Project_$(Get-Random -Maximum 1000)\$((Get-RandomElement $junkFolders))"
    $allFolders += $mix
}

# Personal and "random" folders
foreach ($user in 1..30) {
    $who = "User" + (Get-Random -Minimum 1 -Maximum 100)
    $allFolders += "$root\Temp\$who"
    $allFolders += "$root\General\Personal\$who"
    $allFolders += "$root\!DO_NOT_USE\$who\$(Get-RandomElement $junkFolders)"
}

# Duplicates, spelling errors, abandoned
$allFolders += "$root\Engineering\Specs\OldSpecss"
$allFolders += "$root\Accounting\Reimbursments"
$allFolders += "$root\zzz_Archive\OldFiles\Copy of 2012"
$allFolders += "$root\Marketing\Campains\Archive"
$allFolders += "$root\Legal\Contracts\zzzzz_Backup"

# Remove duplicates and sort for cleaner output
$allFolders = $allFolders | Sort-Object -Unique

Write-Host "Creating $($allFolders.Count) folders..."

# Actually create the folders
foreach ($folder in $allFolders) {
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
}

# Map permissions (randomize some, others standard)
$groupMap = @{
    "HR"           = @("HR", "AllStaff", "Managers")
    "Finance"      = @("Accounting", "Finance", "Managers")
    "Engineering"  = @("Engineering", "IT", "Managers")
    "Sales"        = @("Sales", "Managers", "AllStaff")
    "Marketing"    = @("Marketing", "Sales", "AllStaff")
    "TechSupport"  = @("TechSupport", "IT", "Managers")
    "Legal"        = @("Legal", "Managers")
    "IT"           = @("IT", "TechSupport", "Managers")
    "Accounting"   = @("Accounting", "Finance", "Managers")
    "AllHands"     = @("AllStaff")
    "General"      = @("AllStaff")
    "Managers"     = @("Managers")
}

# Assign permissions (randomize if folder contains a dept)
foreach ($folder in $allFolders) {
    $permGroups = @()
    foreach ($k in $groupMap.Keys) {
        if ($folder -match $k) {
            $permGroups += $groupMap[$k]
        }
    }
    # Add some folders with "Everyone" access at random
    if ((Get-Random -Minimum 1 -Maximum 10) -gt 7) {
        $permGroups += "AllStaff"
    }
    # Add "VPNUsers" to some random folders
    if ($folder -match "Remote|VPN|Scripts|Backups" -or ((Get-Random -Minimum 1 -Maximum 15) -eq 10)) {
        $permGroups += "VPNUsers"
    }
    $permGroups = $permGroups | Sort-Object -Unique
    if ($permGroups.Count -gt 0) {
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
}

Write-Host "Folder structure and permissions complete! You have a true corporate mess."

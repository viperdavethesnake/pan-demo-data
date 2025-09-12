
:# Panzura Demo Toolkit (vNext)

This bundle sets up a realistic, messy enterprise-style file share under **S:\Shared** with optional AD-backed ownership and ACLs.

## What's new
- **Timestamp realism** in the file generator: randomized Creation/Write/Access times per file.
- **Collision‑proof AD populate**: unique sAMAccountName/CN per dept; idempotent re-runs.
- **Thorough reset**: catches leftover users/groups anywhere in the domain (prefix purge).
- **Report**: domain‑wide, recursive group counts with optional sample names.

## Requirements
- PowerShell **7.5.x** or later, run **as Administrator**.
- NTFS on `S:` for sparse files.
- RSAT / ActiveDirectory module available on the admin host.

> **Note**: PowerShell 7.5.x is recommended for best compatibility with the `-SkipEditionCheck` module imports and sparse file operations.

## Quick start
```powershell
# 0) Pre-flight
.\pre_flight.ps1

# 1) (Optional) Populate AD
.\ad_populator.ps1 -BaseOUName DemoCorp -UsersPerDeptMin 12 -UsersPerDeptMax 40 -CreateAccessTiers -CreateAGDLP -ProjectsPerDeptMin 0 -ProjectsPerDeptMax 3 -VerboseSummary

# 2) Create folder tree + share
.\create_folders.ps1 -UseDomainLocal
.\set_share_acls.ps1  # Note: hardcoded for share "FS01-Shared"

# 3) Generate messy files (sparse by default, with timestamp realism)
.\create_files.ps1 -MaxFiles 10000

# Examples with date controls:
#   - Spread across last 10 years, uniform
.\create_files.ps1 -MaxFiles 10000 -MinDate (Get-Date).AddYears(-10) -MaxDate (Get-Date) -DatePreset Uniform
#   - Heavy recent skew within last 18 months
.\create_files.ps1 -MaxFiles 10000 -MinDate (Get-Date).AddMonths(-18) -DatePreset RecentSkew -RecentBias 85
#   - Vintage mess (2000–2009, 2010–2019, last 5y mix)
.\create_files.ps1 -MaxFiles 10000 -DatePreset LegacyMess

# Examples with additional parameters:
#   - Skip AD integration (for non-domain environments)
.\create_files.ps1 -MaxFiles 5000 -NoAD
#   - Custom folder structure with different departments
.\create_folders.ps1 -Departments 'Sales','Marketing','Support' -Root "D:\CustomShare"
#   - Files without clutter or ADS
.\create_files.ps1 -MaxFiles 10000 -Clutter:$false -ADS:$false

# 4) Report
.\demo_report.ps1 -ShowSamples -SampleUsers 5
```

## Timestamp realism
The generator sets the three visible NTFS timestamps per file:
- **CreationTime** (“created”)
- **LastWriteTime** (“modified”)
- **LastAccessTime** (“accessed”)

> NTFS `ChangeTime` (often called “ctime”) is internal and not directly settable; Windows updates it automatically on metadata change.

Controls:
- `-Touch` (default **on**): enable timestamp randomization
- `-DatePreset`: `RecentSkew` (default), `Uniform`, `YearSpread`, `LegacyMess`
- `-MinDate` / `-MaxDate`: explicit bounds (defaults to last 3 years)
- `-RecentBias` (0–100): how strongly to skew toward recent dates (for `RecentSkew`)

## Additional Parameters

### create_files.ps1
- `-NoAD`: skip AD lookups and owner setting (useful for non-domain environments)
- `-Clutter`: drop desktop.ini, Thumbs.db, temp files occasionally (default: on)
- `-ADS`: add Alternate Data Streams for a subset of files (default: on)
- `-UserOwnership`: some files owned by random users, rest by GG_<Dept> (default: on)
- `-ProgressUpdateEvery`: progress reporting frequency in files (default: 200)

### create_folders.ps1
- `-Root`: custom root path (default: "S:\Shared")
- `-Departments`: custom department list (default: Finance,HR,Engineering,Sales,Legal,IT,Ops,Marketing)
- `-Domain`: custom domain (default: auto-detected)
- `-ShareName`: custom share name (default: "Shared")
- `-CreateShare`: toggle share creation (default: on)

**Customization Examples:**
```powershell
# Custom departments only
.\create_folders.ps1 -Departments 'Sales','Marketing','Support'

# Different drive/path
.\create_folders.ps1 -Root "D:\CompanyFiles" -ShareName "CompanyFiles"

# Skip share creation (folders only)
.\create_folders.ps1 -CreateShare:$false

# Custom domain context
.\create_folders.ps1 -Domain "CONTOSO" -ShareName "ContosoShared"
```

### ad_populator.ps1
- `-RoleGroups`: custom role groups array (default: Mgmt,Leads,Contractors,Interns,Auditors)

## Getting Help

Each script supports PowerShell's built-in help system. Use these commands to explore parameters:

```powershell
# Get help for any script
Get-Help .\ad_populator.ps1 -Full
Get-Help .\create_folders.ps1 -Full
Get-Help .\create_files.ps1 -Full
Get-Help .\ad_reset.ps1 -Full
Get-Help .\demo_report.ps1 -Full

# Get parameter list only
Get-Help .\create_files.ps1 -Parameter *

# Get examples
Get-Help .\ad_populator.ps1 -Examples
```

## Reset + re-run workflow
```powershell
# Preview a full cleanup (no changes)
.\ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -DoGroups -DoOUs -PurgeBySamPrefixes -WhatIf

# Do it (no prompts), then repopulate and report
.\ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -DoGroups -DoOUs -PurgeBySamPrefixes -Confirm:$false -VerboseSummary

.\ad_populator.ps1 -BaseOUName DemoCorp -UsersPerDeptMin 12 -UsersPerDeptMax 40 -CreateAccessTiers -CreateAGDLP -ProjectsPerDeptMin 0 -ProjectsPerDeptMax 3 -VerboseSummary

.\create_folders.ps1 -UseDomainLocal
.\set_share_acls.ps1  # Note: hardcoded for share "FS01-Shared"

# Files with timestamps
.\create_files.ps1 -MaxFiles 10000 -DatePreset RecentSkew

.\demo_report.ps1 -ShowSamples -SampleUsers 5
```

## Files included
- pre_flight.ps1
- create_folders.ps1
- set_share_acls.ps1
- set_privs.psm1
- update_shims.ps1
- sanity.ps1
- ad_populator.ps1
- ad_reset.ps1
- demo_report.ps1
- create_files.ps1

---
Generated: 2025-09-12T04:10:18.096184Z

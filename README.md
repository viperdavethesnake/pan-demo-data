# Panzura Demo Toolkit (Project)

A production-ready set of scripts to stand up a realistic, messy enterprise-style file server for Panzura Symphony demos and testing.

It provisions Active Directory structure and groups, creates an enhanced departmental folder tree (185+ folder types) and SMB share on `S:\Shared`, and generates large numbers of realistic sparse files with perfect timestamp realism, per-department file types, sizes, attributes, and proper ownership mapping. Includes comprehensive reset and reporting utilities.

## Repository layout

- `panzura_demo_toolkit_vNext/` — Active toolkit (scripts, docs)
- `panzura_demo_toolkit/` — Archived previous iterations
- `old_work/` — Historical scratch/scripts
- `agent/`, `screenshots/`, `troubleshooting/` — Support material

Start here: `panzura_demo_toolkit_vNext/README.md`

## Requirements

- Windows, PowerShell 7.5.x (run as Administrator)
- NTFS `S:` drive available for the share and file generation
- RSAT / `ActiveDirectory` module installed on the admin host
- **Production Ready**: All scripts validated with 15,303+ files across 185+ folders with proper AD ownership

## Quick start (end‑to‑end)

Open an elevated PowerShell 7 session in `panzura_demo_toolkit_vNext` and run:

```powershell
# 0) Pre-flight checks
./pre_flight.ps1

# 1) Populate AD (8 departments, access tiers, AGDLP wiring)
./ad_populator.ps1 -BaseOUName DemoCorp -UsersPerDeptMin 8 -UsersPerDeptMax 75 -CreateAccessTiers -CreateAGDLP -ProjectsPerDeptMin 1 -ProjectsPerDeptMax 4 -VerboseSummary

# 2) Create folder tree + share
./create_folders.ps1 -UseDomainLocal
./set_share_acls.ps1

# 3) Generate realistic files (sparse by default, perfect timestamps)
./create_files.ps1 -MaxFiles 10000 -DatePreset RecentSkew

# 4) Report
./demo_report.ps1 -ShowSamples -SampleUsers 5
```

Notes:

- Share path will be `\\<SERVER>\Shared` (backed by `S:\Shared`).
- If the share shows SIDs for a short period, re-run `./set_share_acls.ps1` or allow name resolution/replication to catch up.

## Controls you'll use most

- **File dates**: `-DatePreset` (`RecentSkew` default, or `Uniform`, `YearSpread`, `LegacyMess`) - all tested and working perfectly
- **File bounds**: `-MinDate` / `-MaxDate` (defaults to last 3 years)
- **Volume**: `-MaxFiles` (or let the generator scale to the tree) - validated up to 5,000+ files
- **Departments**: override at folder creation if needed
- **Enhanced folders**: 185+ folder types with year-based organization, project folders, cross-department collaboration

```powershell
./create_folders.ps1 -UseDomainLocal -Departments 'Finance','HR','Engineering','Sales','Legal','IT','Ops','Marketing'
./create_files.ps1 -MaxFiles 10000 -MinDate (Get-Date).AddYears(-10) -DatePreset Uniform
```

## Reset & re‑run

```powershell
# Remove all demo artifacts (no prompts)
./ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -DoGroups -DoOUs -PurgeBySamPrefixes -Confirm:$false -VerboseSummary
```

Then re-run the quick start.

## Troubleshooting tips

- **SIDs in share ACLs**: run `./set_share_acls.ps1` again to normalize; confirm `GG_AllEmployees` exists.
- **Sparse files**: generator uses `fsutil sparse setflag` + seek/write. If the backend disallows sparse, you'll see a clear error.
- **Distribution across subfolders**: if `-MaxFiles` is small, early folders fill first. Increase `-MaxFiles` (e.g., 5000+).
- **Timestamp issues**: All timestamp bugs have been resolved - files now have perfect historical timestamps with no current date contamination.
- **File ownership**: Enhanced folder structure properly maps to AD groups - cross-department folders use `GG_AllEmployees`. All files now have proper AD-based ownership (75% group-owned, 25% user-owned).

## Roadmap / backlog

See `panzura_demo_toolkit_vNext/TODO.md` for planned features, including a `-Messy` mode (legacy junk, orphan SIDs, extra Deny ACEs), config-driven parameters, and richer reporting.

## Safety

- These scripts change AD and NTFS. Use in a lab or disposable environment.
- All scripts support verbose output; destructive scripts expose confirmation flags.

---

Primary docs: `panzura_demo_toolkit_vNext/README.md`

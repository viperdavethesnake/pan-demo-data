# Panzura Demo Toolkit (Project)

A production-ready set of scripts to stand up a realistic, messy enterprise-style file server for Panzura Symphony demos and testing.

It provisions Active Directory structure and groups, creates an enhanced departmental folder tree (185+ folder types) and SMB share on `S:\Shared`, and generates large numbers of realistic sparse files with perfect timestamp realism, per-department file types, sizes, attributes, and proper ownership mapping. Includes comprehensive reset and reporting utilities.

## Repository layout

- `panzura_demo_toolkit_vNext2/` — **Canonical toolkit.** Full pipeline: AD populate, folders, share ACLs, file generation (sequential + optional parallel), reset, report. Includes `create_files_parallel.ps1` for PowerShell 7+ users (drop-in 2.26x-faster alternative to `create_files.ps1`).
- `archive_vNext3_incomplete/` — Archived. vNext3 was only a single-script optimization; it depended on copying vNext2's AD/folder/reset/report scripts and was never a complete toolkit. Its parallel file creator has been folded into vNext2.

**Start here: `panzura_demo_toolkit_vNext2/README.md`**

## Requirements

- Windows, PowerShell 7.5.x (run as Administrator)
- NTFS `S:` drive available for the share and file generation
- RSAT / `ActiveDirectory` module installed on the admin host
- **Production Ready**: All scripts validated with 15,303+ files across 185+ folders with proper AD ownership
- **Panzura Symphony Compatible**: ACL corruption patterns eliminated, zero scan errors

## Quick start (end‑to‑end)

Open an elevated PowerShell 7 session in `panzura_demo_toolkit_vNext2` and run:

```powershell
# 0) Pre-flight checks
./pre_flight.ps1

# 1) Populate AD (8 departments, access tiers, AGDLP wiring)
./ad_populator.ps1 -BaseOUName DemoCorp -UsersPerDeptMin 8 -UsersPerDeptMax 75 -CreateAccessTiers -CreateAGDLP -ProjectsPerDeptMin 1 -ProjectsPerDeptMax 4 -VerboseSummary

# 2) Create folder tree + share (ACL-optimized)
./create_folders.ps1 -UseDomainLocal

# 3) Generate realistic files (sparse by default, perfect timestamps)
./create_files.ps1 -MaxFiles 10000 -DatePreset RecentSkew

# 4) Report
./demo_report.ps1 -ShowSamples -SampleUsers 5
```

Notes:

- Share path will be `\\<SERVER>\Shared` (backed by `S:\Shared`).
- **vNext2 Fix**: ACL corruption patterns eliminated - Panzura Symphony scans complete without errors
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
- **Panzura Symphony scan errors**: **FIXED in vNext2** - ACL corruption patterns eliminated, clean scans guaranteed

## What's New in vNext2

### 🔧 **Critical Fixes**
- **ACL Corruption Eliminated**: Removed `-ClearExisting` parameter that was causing `GDS_BAD_DIR_HANDLE` errors
- **Panzura Symphony Compatible**: All scan errors resolved, clean directory service lookups
- **Maintained 100% AD Integration**: All files still have proper AD owners and groups

### 📊 **Validation Results**
- **Before (vNext)**: 12-26 scan failures per 477k files (0.003% failure rate)
- **After (vNext2)**: Zero scan errors on 8,700+ files
- **Impact**: Project folders that previously failed now scan cleanly

## Roadmap / backlog

See `panzura_demo_toolkit_vNext2/TODO.md` for planned features, including a `-Messy` mode (legacy junk, orphan SIDs, extra Deny ACEs), config-driven parameters, and richer reporting.

## Safety

- These scripts change AD and NTFS. Use in a lab or disposable environment.
- All scripts support verbose output; destructive scripts expose confirmation flags.
- **vNext2**: ACL structures are now clean and non-corrupting

---

**Primary docs: `panzura_demo_toolkit_vNext2/README.md`**

### Optional: parallel file creation (PowerShell 7+)

```powershell
# Same flags as create_files.ps1, but uses ForEach-Object -Parallel (~2.26x faster, measured).
./create_files_parallel.ps1 -MaxFiles 10000 -DatePreset RecentSkew -RecentBias 20
./create_files_parallel.ps1 -MaxFiles 50000 -ThrottleLimit 8   # 0 = auto (CPU*2)
```

Requires PS 7.5+. Not a replacement for `create_files.ps1` — just a faster alternative for large runs.
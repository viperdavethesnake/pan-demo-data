# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

PowerShell toolkit that provisions a realistic, "messy" enterprise file server (Active Directory + NTFS share on `S:\Shared`) for Panzura Symphony demos and testing. It creates AD OUs/groups/users, a departmental folder tree, and large numbers of sparse files with realistic timestamps, sizes, extensions, attributes, and ownership.

## Repository layout

- `panzura_demo_toolkit_vNext2/` — **Canonical toolkit.** Pipeline (AD, folders, files, reset, report). Includes both `create_files.ps1` (sequential, PS 5.1+) and `create_files_parallel.ps1` (PS 7.5+, ~2.26x faster, same flags).
- `archive_vNext3_incomplete/` — Archived. Originally shipped only `create_files_parallel.ps1` + `set_privs.psm1` and required copying the rest from vNext2; the parallel script has been folded into vNext2 and the rest of the directory is kept only for the audit/perf docs (`CURSOR_AGENT_AUDIT.md`, `OPTIMIZATION_SUMMARY.md`, `PERFORMANCE_REPORT.md`). Do not resurrect as a separate toolkit.

`old_work/`, `agent/`, `screenshots/`, `troubleshooting/` are referenced in the root README as historical/support material but are not present in the current working tree.

## Commands

All commands are PowerShell, run elevated. vNext2 is the default working directory unless a parallel file creation run is needed.

End-to-end (from `panzura_demo_toolkit_vNext2/`):

```powershell
./pre_flight.ps1
./ad_populator.ps1 -BaseOUName DemoCorp -UsersPerDeptMin 8 -UsersPerDeptMax 75 -CreateAccessTiers -CreateAGDLP -ProjectsPerDeptMin 1 -ProjectsPerDeptMax 4 -VerboseSummary
./create_folders.ps1 -UseDomainLocal
./create_files.ps1 -MaxFiles 10000 -DatePreset RecentSkew
./demo_report.ps1 -ShowSamples -SampleUsers 5
```

Parallel file creation (optional, requires PS 7.5+):

```powershell
./create_files_parallel.ps1 -MaxFiles 10000 -DatePreset RecentSkew -RecentBias 20
./create_files_parallel.ps1 -MaxFiles 50000 -ThrottleLimit 8   # tune threads; 0 = auto (CPU*2)
./create_files_parallel.ps1 -MaxFiles 10000 -NoAD              # skip AD ownership pass
```

Reset everything:

```powershell
./ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -DoGroups -DoOUs -PurgeBySamPrefixes -Confirm:$false -VerboseSummary
```

Targeted re-runs:

- `./test_permissions.ps1` — smoke-test ACL behavior.
- `./clean_shared.ps1` / `./create_temp_pollution.ps1` — scrub or reintroduce Temp-folder junk.

> **Share ACLs are out of scope.** `set_share_acls.ps1` still exists in the toolkit but is not part of the canonical pipeline — SMB share state is not a success criterion for this project. Don't add it back as a pipeline step.

Key parameters (see `DEVELOPMENT.md` for full list):

- Files: `-MaxFiles`, `-DatePreset` (`RecentSkew`|`Uniform`|`YearSpread`|`LegacyMess`), `-MinDate`/`-MaxDate`, `-RecentBias`, `-Touch`, `-ADS`.
- Folders: `-Departments`, `-UseDomainLocal`, `-CreateShare`.
- AD populator: `-UsersPerDeptMin/Max`, `-CreateAccessTiers`, `-CreateAGDLP`, `-ProjectsPerDeptMin/Max`.

## Pipeline architecture

Canonical phases, executed in order. Each script is designed to be independently re-runnable:

1. **AD populate** (`ad_populator.ps1`) — OUs under `BaseOUName`, AGDLP groups (`GG_*` global, `DL_Share_*` domain-local), users, optional project groups. Uniqueness enforced via sam-name prefixes so `ad_reset.ps1 -PurgeBySamPrefixes` can cleanly remove everything.
2. **Folder tree** (`create_folders.ps1`) — Builds 185+ folder types under `S:\Shared\<Dept>\...` (Projects, Archive, Temp, Sensitive, Vendors, cross-department `LEGACY_*`/`_MIXED`). Sets ownership, breaks inheritance in places, removes broad read on `Sensitive`, simulates Deny ACEs on `Temp`.
3. **File generation** (`create_files.ps1` sequential, or `create_files_parallel.ps1`) — Per-department extension weights and size distributions; sparse files created via `fsutil sparse setflag` + seek/write; realistic timestamps (creation/last-write/last-access coherent); attributes, ADS tags, and ownership realism (~75% group-owned, ~25% user-owned). Cross-department folders fall back to `GG_AllEmployees` owner.
4. **Report** (`demo_report.ps1`) — Environment summary with optional sampling.
5. **Reset** (`ad_reset.ps1`) — Removes demo AD artifacts by prefix/OU scope.

Share ACL normalization (`set_share_acls.ps1`) is explicitly not a pipeline step — see note above.

### Parallel file-creation model (`create_files_parallel.ps1`)

Scanning + work-item generation happens on the main thread, then fans out via `ForEach-Object -Parallel`. All helper functions are defined **inline** in the script (not imported) because `-Parallel` runspaces do not inherit the parent scope; `set_privs.psm1` is the only module dependency. Progress counters use synchronized hashtables. Do not refactor shared helpers into modules without accounting for this — doing so is what broke the earlier "Cursor agent" attempt documented in `archive_vNext3_incomplete/CURSOR_AGENT_AUDIT.md`. Real measured speedup is **~2.26x** (not the 10x claimed in `PERFORMANCE_REPORT.md` in the archive — those numbers are fictional; trust `OPTIMIZATION_SUMMARY.md`).

**Per-file write ordering is load-bearing — do not reorder.** For each file, the inline worker must execute in this sequence:

1. `New-Item` + `fsutil sparse setflag` + seek/write (file body)
2. `SetAttributes` (ReadOnly/Hidden flags)
3. Write ADS (`Zone.Identifier`) **before** timestamps
4. Set owner/group via `Set-OwnerAndGroupFromModule` (DACL change; safe for NTFS MAC times)
5. `SetCreationTime` / `SetLastAccessTime` / `SetLastWriteTime` **absolutely last**

Rationale: writing **any** NTFS stream (including alternate data streams like `:Zone.Identifier`) bumps the host file's `LastWriteTime` to the current time. Stamping timestamps before the ADS write silently contaminated ~15% of files with the current date (historical `CreationTime` but present-day `LastWriteTime`). `Set-Acl` does not touch MAC times and is safe before Touch, but keeping Touch as the absolute last step is the invariant — nothing data/stream-modifying may run after.

## Design invariants (don't regress)

- **No `-ClearExisting` on ACLs.** Removed in vNext2 because it produced `GDS_BAD_DIR_HANDLE` / scan failures in Panzura Symphony. ACL edits must be additive/targeted.
- **AGDLP wiring must hold.** Users → `GG_*` (global) → `DL_Share_*` (domain local) → NTFS/share permissions. Don't assign users or `GG_*` groups directly to ACLs.
- **Timestamp realism.** Generated files must not have current-date contamination; all three timestamps (creation, last-write, last-access) come from the same chosen historical date.
- **Sparse-file generation.** If the backend rejects sparse flags, surface the error — do not silently fall back to dense writes (it blows up disk use at demo scale).
- **Idempotency + safety.** Mutating scripts expose `-WhatIf`/`-Confirm` and rely on existence checks; destructive scripts require explicit flags.

## Requirements

- Windows with `S:` drive (NTFS, sparse support).
- PowerShell 7.5+ for vNext3; 5.1+ acceptable for vNext2.
- RSAT / `ActiveDirectory` module on the admin host; elevated session.

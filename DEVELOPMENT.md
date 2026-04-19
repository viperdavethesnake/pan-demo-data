# Development Guide

## Architecture overview

Phases:
1) AD populate (`ad_populator.ps1`) — OUs, groups (GG_*, DL_Share_*), users, optional projects.
2) Folders (`create_folders.ps1`) — `S:\Shared\<Dept>\{Projects,Archive,Temp,Sensitive,Vendors}` with NTFS ACLs, ownership, inheritance tweaks.
3) Files (`create_files.ps1` or `create_files_parallel.ps1`) — sparse files, realistic sizes/types, timestamps, attributes, ADS, ownership realism.
4) Report (`demo_report.ps1`) — environment summary.
5) Reset (`ad_reset.ps1`) — cleanup.

Share ACLs (`set_share_acls.ps1`) are out of scope — SMB share state is not a project success criterion.

## Design notes

- Idempotency: scripts should be re-runnable without catastrophic side effects; uniqueness via prefixes and existence checks.
- Safety: support `-WhatIf`/`-Confirm` on mutating scripts; default to safe values.
- Performance: file generator uses sparse seek/write and progress reporting.

## Script responsibilities

- `ad_populator.ps1`: ensure OUs/groups, create users, optional project groups; summary output.
- `create_folders.ps1`: create tree, set owner/ACLs, break inheritance randomly, remove broad read on Sensitive, simulate Deny on Temp.
- `create_files.ps1` / `create_files_parallel.ps1`: per-dept extension weights, size distributions, timestamp realism, ADS tags, ownership realism. Invariant: inside the per-file write loop, ADS writes must happen **before** final timestamp application, since writing any NTFS stream bumps the host file's `LastWriteTime`. Timestamps are always the last step.
- `ad_reset.ps1`: remove demo artifacts by prefix/OU scopes; summaries.
- `demo_report.ps1`: summarize users/groups/folders; sample outputs.

## Parameters of interest

- Files: `-MaxFiles`, `-DatePreset`, `-MinDate`, `-MaxDate`, `-RecentBias`, `-Touch`, `-ADS`.
- Folders: `-Departments`, `-UseDomainLocal`, `-CreateShare`.
- Populator: `-UsersPerDeptMin/Max`, `-CreateAccessTiers`, `-CreateAGDLP`, `-ProjectsPerDeptMin/Max`.

## Adding features

- Prefer feature flags (switches) over changing defaults.
- Keep extension weights and size profiles close to code until config is introduced; plan to externalize to JSON/YAML.
- Add help in `.SYNOPSIS` and examples.

## Testing

- Smoke test each phase in isolation.
- End-to-end: `run_all.ps1` (to be added) for a single command experience.
- Consider Pester tests for basic assertions.


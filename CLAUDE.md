# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

PowerShell + AD toolkit that provisions a realistic, messy enterprise file share (AD under `OU=DemoCorp,DC=demo,DC=panzura`, NTFS tree on `S:\Shared`) for Panzura Symphony demos and testing. Generates millions of sparse files with coherent historical timestamps, per-department extension/size/ownership distributions, and engineered ACL mess (orphan SIDs, lazy-AGDLP, Deny, Everyone, broken inheritance).

## Canonical tooling

**PanzuraDemo module at `PanzuraDemo/`** — version 4.1.0. Everything else is orchestration around it.

Public commands (after `Import-Module`):

- `Import-DemoConfig` — load `config/default.psd1` or `config/smoke.psd1`
- `Test-DemoPrerequisite` — pre-flight checks
- `New-DemoADPopulation` — OUs / GG_* / DL_Share_* / users / service accounts
- `New-DemoFolderTree` — tree + NTFS ACLs on `S:\Shared`
- `New-DemoFile` — sparse-file generator (sequential — do NOT use `-Parallel`, see invariants)
- `Remove-DemoOrphanUser` — deletes flagged "Former employee" accounts to leave orphan SIDs on files
- `Get-DemoReport` — environment summary
- `Reset-DemoEnvironment` — tear down AD + SMB share (does NOT touch `S:\Shared` contents)
- `Test-DemoSmokeVerification` — post-smoke spec checks
- `Invoke-DemoPipeline` — composes the above by phase

Orchestration scripts at repo root:

- `build-10M.ps1` — production layered 4-pass build (L1 LegacyMess -10y, L2 YearSpread -10y, L3 RecentSkew -3y, L4 Deadbeat 2019 cohort). ~8.5 h wall clock, ~10 M files, ~85 TB logical / ~1.2 TB physical sparse.
- `spot-check.ps1` — samples 100 random files + 10 folders from the manifest, verifies sparse flag / timestamps / owner / ACL against expected values.

## Commands

All PowerShell, run elevated. Always `pwsh` (7.5+), never `powershell` (5.1 fails silently).

```powershell
# Import (always first)
Import-Module '<repo>\PanzuraDemo\PanzuraDemo.psd1' -Force

# Probe current state (read-only)
$cfg = Import-DemoConfig -Path default
Get-DemoReport -Config $cfg

# Smoke (4 depts, ~2000 files, ~16 s)
Invoke-DemoPipeline -Config smoke -Scenario Smoke -Phase All
Test-DemoSmokeVerification -Config (Import-DemoConfig -Path smoke)

# Wipe (AD + SMB share only — filesystem separately)
Reset-DemoEnvironment -Config $cfg -IncludeShare -IncludeLegacyGroups -Confirm:$false
Get-ChildItem 'S:\Shared' -Force | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }

# Full 10 M build
pwsh -NoProfile -File '.\build-10M.ps1'

# Verify a completed build
pwsh -NoProfile -File '.\spot-check.ps1'
```

## Pipeline architecture

Canonical phases, composed by `Invoke-DemoPipeline -Phase`:

1. **PreFlight** — validates S: drive, AD connectivity, elevation, PS version.
2. **ADPopulate** — OUs under `BaseOUName` (default `DemoCorp`), AGDLP groups (`GG_*` global, `DL_Share_*_RW` / `_RO` domain local), users with per-dept counts, service accounts, orphan-flagged "Former employee" users. Uniqueness enforced via sam-name prefixes so `Reset-DemoEnvironment` can clean everything.
3. **Folders** — `S:\Shared\<Dept>\{Projects,Archive/<year>/<quarter>,Temp,Sensitive,Vendors,...}` plus cross-dept folders (`Board`, `Inter-Department`, `Public`, `Users`, `_install_files`, `__Archive`, `__OLD__`, `LEGACY_*`, `*_MIXED`). Deterministic inheritance breaks on `Sensitive`/`Board`/`IT/Credentials`/`Temp`/`Public`. Temp gets `Everyone:Modify` + `GG_Contractors:(Deny)`.
4. **Files** — `New-DemoFile` runs per-call with a `DatePreset` + date window. Per-dept extension weights, heavy-tail size distribution, sparse files via P/Invoke, coherent CT ≤ WT ≤ AT, per-file class (Active / Reference / Dormant / LegacyArchive / WriteOnceNeverRead / WriteOnceReadMany / Aging). Ownership 55/25/10/5/5 DeptGroup / User / OrphanSid / BuiltinAdmin / ServiceAccount. ACL patterns 55/25/10/5/5 ProperAGDLP / LazyGG / OrphanSidAce / EveryoneRead / DenyAce.
5. **Orphanize** — deletes the "Former employee" users so their SIDs become unresolvable on disk.
6. **Report** — `Get-DemoReport` with AD / FS / ACL / ownership counts.

Share ACL normalization is intentionally NOT in the pipeline — SMB share state is not a demo success criterion.

## Design invariants (don't regress)

- **`pwsh` 7.5+ required.** `powershell` 5.1 fails module import silently and cascades to "command not found".
- **No `-Parallel` on file generation.** `ForEach-Object -Parallel` measured slower than sequential at this workload (V4_SPEC.md decision #19). Native `SetNamedSecurityInfoW` P/Invoke sequential path is the fastest (decision #23, +42% wall-clock, 11× ACL speedup).
- **No `-ClearExisting` on ACLs.** Historical Panzura Symphony `GDS_BAD_DIR_HANDLE` / scan failures. ACL edits are additive/targeted only.
- **AGDLP wiring must hold.** Users → `GG_*` (global) → `DL_Share_*` (domain local) → NTFS/share permissions. Don't put users or `GG_*` directly on production ACLs (some engineered-mess folders intentionally DO have `GG_*` direct — that's the lazy-AGDLP anti-pattern we want visible).
- **Per-file write order is load-bearing.** Inside `New-DemoFile`'s write loop, for each file:
  1. `New-Item` + `fsutil sparse setflag` + seek/write (body)
  2. `SetAttributes` (ReadOnly/Hidden)
  3. Write ADS (`Zone.Identifier`) **before** timestamps
  4. Set owner via `Set-FileOwnershipInternal` (native SetNamedSecurityInfoW) — safe for MAC times
  5. `SetCreationTime` / `SetLastAccessTime` / `SetLastWriteTime` **absolutely last**

  Rationale: writing any NTFS stream (including `:Zone.Identifier`) bumps the host file's `LastWriteTime` to "now." Stamping timestamps before the ADS write silently contaminated ~15% of files with present-day dates in pre-v4. Keep Touch as the absolute last step.
- **Dormant / LegacyArchive CT is hard-pinned to 3–5 y ago** in `New-DemoFile.ps1` (lines 347–351), regardless of the preset's `MinDate`. The layered `build-10M.ps1` extends L1/L2 `MinDate` to `-10y` so preset-drawn ages blend smoothly with the dormant tail (no 3-y cliff).
- **Sparse-file surfacing.** If the backend rejects `fsutil sparse setflag`, surface the error — don't silently fall back to dense writes (would blow up disk usage at demo scale).
- **Idempotency + safety.** Mutating commands expose `-WhatIf` / `-Confirm`; destructive ones require explicit flags.

## Requirements

- Windows with `S:` drive (NTFS, sparse support).
- PowerShell 7.5+, elevated session.
- RSAT / `ActiveDirectory` module.
- Reference host: `PANZURA-SYM02`, domain `demo.panzura`, OU `DemoCorp`, share `AcmeShare` at `S:\Shared`.

## Where things live

| Area | File |
|---|---|
| Decision log (24 entries) | `docs/V4_SPEC.md` §18 |
| Module config (depts, ACL ratios, file classes, etc.) | `PanzuraDemo/config/default.psd1` |
| Smoke config | `PanzuraDemo/config/smoke.psd1` |
| Production build recipe | `build-10M.ps1` |
| Post-build verification | `spot-check.ps1` |
| Dashboard / architect handoff pack | `docs/demo-dataset/` |
| Session state | `RESUME.md` |
| Legacy vNext2 preserved at | branch `legacy/vnext2` (retired 2026-04-20) |

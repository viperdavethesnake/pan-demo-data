# Resume notes — pan-demo-data

**Last session: 2026-04-19 evening → 2026-04-20 morning**
**User: microbarley@icloud.com**
**Host: PANZURA-SYM02, domain demo.panzura, S:\ NVMe Gen4 DRAM, 16 CPU**

## ⚠ Starting a fresh chat for the next version?

Read [`docs/NEXT_VERSION_BRIEF.md`](docs/NEXT_VERSION_BRIEF.md) first. It captures the design inputs (C# rewrite candidates, config-format question, packaging options, open questions) collected at the end of the 2026-04-20 session.

## Where we are — built, documented, cleaned

### Repo state

- `main` at HEAD; this commit adds `build-10M.ps1` + `docs/demo-dataset/` (design handoff pack)
- PanzuraDemo module version: **4.1.0** (unchanged — no code changes this session)
- Tag on this commit: `build-2026-04-20`

### Demo dataset — built and on disk

**10M-file messy NAS generated and verified.**

- Wall clock: **8 h 46 m** (2026-04-19 18:07 → 2026-04-20 02:53)
- **9,962,001 files · 85.6 TB logical · ~1.2 TB physical (sparse) · 2,693 folders**
- **361 users / 15 depts / 18 `GG_*` / 30 `DL_Share_*` / 10 svc accounts**
- 40 orphan-flagged users created and removed post-build → 999 K files now owned by unresolvable SIDs (~10%)
- Dormancy: 69.8% of files with `LastAccess > 3 y`
- **Deadbeat Corp 2019 cohort visible** in CT histogram: 9.63% vs. 3–4% in 2018/2020 (L4 layer, 500 K Uniform files, CT 2019-only)
- Full phase timing + per-layer errors in `build-10M.log` (gitignored)
- Per-file manifests in `logs/manifest_*.jsonl` (5.4 GB, gitignored)

### Layered build recipe

`build-10M.ps1` at repo root, kicks off 4 stacked file-generation layers:

| Layer | Files | Preset | Window | Purpose |
|---|---:|---|---|---|
| L1 | 3.5 M | LegacyMess | -10 y → now | Old-skewed spread, no 3y cliff |
| L2 | 3.0 M | YearSpread | -10 y → now | Uniform fill across 10 y |
| L3 | 3.0 M | RecentSkew bias=30 | -3 y → now (default) | Recent activity tail |
| L4 | 0.5 M | Uniform | 2019-01-01 → 2019-12-31 | Deadbeat acquisition cohort |

Performance: L1 402 f/s (cold) → L4 260 f/s (dense). 35% density cost across layers, NTFS stays well under 200K/folder insert-cliff.

### Design handoff pack — `docs/demo-dataset/`

Four files written for designers + architects to build dashboards/reports on top of the dataset:

- `README.md` — folder index + audience guide
- `dataset-snapshot.md` — ground-truth numbers (counts, bytes, year histogram, per-dept table, ownership mix, ACL samples, sample paths per cohort, manifest schema)
- `demo-narrative-and-widgets.md` — 9 demo storylines + widget specs (JSON) + SQL pseudo-queries + dashboard layout sketch + color/emphasis guidance
- `build-recipe-and-caveats.md` — recipe rationale + per-layer perf + reproduction steps + the "don't say on stage" list (sparse vs. logical, no real content, Deadbeat is narrative-only, dates drift, etc.)

All cross-link to raw sources: `build-10M.log`, `logs/manifest_*.jsonl`, `PanzuraDemo/config/default.psd1`, `docs/V4_SPEC.md`.

## What's next when we resume

1. **If the dataset is still intact** — nothing needs rebuilding. Hand the docs to the designer + architect, iterate on dashboard mockups.
2. **If the build needs refreshing** (e.g., to re-age the Dormant/LegacyArchive 3–5 y peak relative to current date):

   ```powershell
   Import-Module 'C:\Users\Administrator\Documents\pan-demo-data\PanzuraDemo\PanzuraDemo.psd1' -Force
   $cfg = Import-DemoConfig -Path default
   Reset-DemoEnvironment -Config $cfg -IncludeShare -IncludeLegacyGroups -Confirm:$false
   Get-ChildItem 'S:\Shared' -Force | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
   pwsh -NoProfile -File 'C:\Users\Administrator\Documents\pan-demo-data\build-10M.ps1'
   ```

   Expect ~8.5 h wall clock. Monitor via `build-10M.log`.

3. **If tuning the dataset shape** — edit `build-10M.ps1` L1–L4 knobs (see `docs/demo-dataset/build-recipe-and-caveats.md` for rationale on current choices).

## Key technical notes (invariants — don't regress)

- **Always pwsh, never powershell.** PanzuraDemo requires PS 7+; `powershell` 5.1 fails import silently.
- **Do not use `-Parallel`** for file generation — measurably slower than sequential (decision #19).
- **Do not reintroduce `Get-Acl` before `Set-Acl`** (decision #20); minimal `FileSecurity` or native P/Invoke is the right path.
- **Native `SetNamedSecurityInfoW` P/Invoke** is wired in; 11× ACL speedup, +42% wall-clock (decision #23).
- **Per-file write order is load-bearing.** New-Item → fsutil sparse → SetAttributes → Write ADS → Set owner → SetCreationTime/LastAccessTime/LastWriteTime ABSOLUTELY LAST. Writing any NTFS stream bumps LastWriteTime; stamping before ADS write contaminates ~15% of files with present-day dates.
- **Dormant/LegacyArchive CT is hard-pinned to 3–5 y ago** in `New-DemoFile.ps1` (lines 347–351). This is why layered preset `MinDate` needed to be extended to -10 y — to avoid a cliff at the 3 y boundary where preset-drawn ages end and dormant pinning begins.

## Decision log pointer

Full history in `docs/V4_SPEC.md` §18 (decisions 1-24). Key entries:
- #19: why `-Parallel` doesn't scale
- #20: why deferred-ACL post-pass was walked back
- #22: Set-Acl minimal FileSecurity → +11% sequential
- #23: native `SetNamedSecurityInfoW` → +42% sequential
- #24: v4.1 folder density expansion

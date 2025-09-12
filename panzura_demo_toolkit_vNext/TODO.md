# TODO (vNext Enhancements)

This toolkit already builds a realistic mid‑size enterprise environment (AD + folders + share + files). Below are proposed enhancements to increase realism, observability, safety, and control.

## Messy mode (folders/ACLs)
- Add `-Messy` switch to `create_folders.ps1` to simulate legacy problems:
  - Randomly add duplicate/overlapping ACEs on some subfolders.
  - Sprinkle extra Deny ACEs (beyond Temp) on a small percentage of subtrees.
  - Break/restore inheritance inconsistently across nested levels.
  - Grant ACEs to a handful of users, then (optionally) remove those users to create orphan SIDs.
  - Age folder timestamps (very old Created/Modified for Archive, mixed for others).
  - Optionally introduce a few empty/unreadable junctions/symlinks in `Archive` (guarded by admin checks).

## File generator refinements
- Add `-Physical` switch (write real bytes) with throttled max size and progress reporting.
- Add `-FilesPerFolderMin/-FilesPerFolderMax` to control density when `-MaxFiles` is not used.
- Add `-Seed <int>` for reproducible runs.
- Add `-Messy` behaviors to files: more odd extensions, random illegal chars replaced, deeper duplicate chains, occasional zero‑byte files.
- Per‑department size/extension tuning via external config (see Config section).
- Optional junction/symlink files pointing to non‑existent targets (guarded).

## Reporting/observability
- Enhance `demo_report.ps1`:
  - Report ACL anomalies: broken inheritance, Deny ACEs, orphan SIDs, duplicate entries.
  - Summarize per‑department folder/file counts, size distributions, recentness histograms.
  - Sample effective membership for `GG_<Dept>` and `DL_Share_<Dept>_*`.
  - Emit CSV/JSON artifacts for downstream analysis.

## Reset/hygiene
- `ad_reset.ps1` add optional removal of project groups `PG_*` and DL/RO/RW scaffolding.
- Add script to scrub NTFS orphan SIDs (`icacls /remove:g SID` equivalents via .NET), with `-WhatIf`.
- Share ACL cleanup idempotence: ensure unique final ACEs and verified removal of Everyone.

## Configurability
- Introduce `config.json|yaml` (optional): departments, counts, extension weights, size profiles, file densities, ADS tags, timestamp presets.
- All top‑level scripts accept `-Config <path>` that overrides defaults.

## Preflight and sanity
- `pre_flight.ps1` ensure: PS 7.x, AD/SMB modules, SeRestore/SeTakeOwnership privileges, drive `S:` mounted/NTFS, long path policy enabled.
- `sanity.ps1` post‑run checks: share exists, department roots created, sample files present, no catastrophic deny at root.

## Performance & resilience
- Batch/parallel file creation with bounded degree of parallelism, adaptive progress.
- Fallback if `fsutil sparse setflag` fails: retry/backoff, clear attributes, log.
- Long path support (`\\?\` prefix) for deep trees.

## UX & safety
- Consistent `-WhatIf`/`-Confirm` across all mutating scripts.
- Verbose summaries standardized; quiet mode reduces noise in automation.
- Clear error messages with actionable hints.

## Orchestration
- Add a single `run_all.ps1` to execute: preflight → populate → folders → share ACLs → files → report, with toggles for each phase.

## Documentation
- README: add Messy mode examples; document config file; add troubleshooting for SIDs shown in share ACLs (name cache/replication timing).
- RUNBOOK: include `-Departments` override usage and `-Seed` reproducibility examples.

---
Backlog is intentionally modular. Happy to prioritize specific items next.


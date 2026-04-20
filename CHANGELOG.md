# Changelog

## [build-2026-04-20] — First production 10M build + design handoff

- `build-10M.ps1`: layered 4-pass production recipe (L1 LegacyMess -10y 3.5M, L2 YearSpread -10y 3M, L3 RecentSkew -3y 3M, L4 Deadbeat Corp 2019 Uniform 0.5M)
- Verified run 2026-04-19 18:07 → 2026-04-20 02:53 (8 h 46 m wall clock): 9,962,001 files, 85.6 TB logical / ~1.2 TB physical sparse, 2,693 folders, 361 users, 0.016% error rate
- `spot-check.ps1`: 100-file / 10-folder post-build verification — confirmed sparse flag, timestamps, ownership, ACL patterns all intact
- `docs/demo-dataset/`: handoff pack for dashboard designers and architects — dataset snapshot, demo-narrative-and-widgets (9 storylines + SQL + JSON widget specs), build recipe + caveats
- Retired `panzura_demo_toolkit_vNext2/` and `archive_vNext3_incomplete/` (preserved on branch `legacy/vnext2`). Rewrote `README.md` and `CLAUDE.md` to reflect PanzuraDemo module as canonical

## [v4.1.0] — 2026-04-19 — Folder density expansion

- Archive subtree now has per-year quarter subfolders (`Archive/<yyyy>/Q{1-4}`) to spread file density and keep NTFS insert performance below the 200K/folder cliff (spec decision #24)
- User home dirs uncapped: every real user gets a dept-scoped home dir and a root-scoped home dir (previously capped at 12 dept homes / 40% root)
- Per-project subfolder set (`Planning/Execution/Review/Resources/Documentation`) now mandatory instead of a 33%-per-sub roll
- Added dept-specific folder classes via config: `ClientFolders` (Sales), `MatterFolders` (Legal), `VendorFolders` (Procurement/Finance), `CampaignFolders` (Marketing), `AppFolders` (IT)
- Cross-dept folder list expanded to `Board`, `Vendors`, `Inter-Department`, `__Archive`, plus existing `Shared`, `Public`, `__OLD__`, `_install_files`

## [v4.0.0] — 2026-04-18 — Module rewrite (supersedes vNext2)

- Replaces the vNext2 script collection (`panzura_demo_toolkit_vNext2/`) with a proper PowerShell module at `PanzuraDemo/`. Config-driven (`config/default.psd1`), public cmdlets, private helpers
- Native `SetNamedSecurityInfoW` P/Invoke (`Private/Native/Security.cs` + `Set-FileOwnershipInternal`) replaces `Set-Acl` round-trips: **11× ACL speedup, +42% wall-clock** (spec decision #23). SID cache is process-lifetime, one LSA lookup per account
- Coherent timestamp model: file-class rolls (Active / Reference / Dormant / LegacyArchive / WriteOnceNeverRead / WriteOnceReadMany / Aging) drive CT ≤ WT ≤ AT with per-class gap distributions. Anti-contamination disperses clamp overflows across the last 7 days instead of pinning to Now
- Engineered ACL mess: `Mess.AclPatterns` with configurable ratios for ProperAGDLP / LazyGG / OrphanSid / EveryoneRead / DenyAce; deterministic inheritance breaks on Sensitive / Board / Public / IT/Credentials / Temp
- Orphan SID story: configurable count of "Former employee" users created with real AD accounts, stamp file ownership, then get deleted post-build via `Remove-DemoOrphanUser`
- Per-file manifests emitted as JSONL in `logs/`
- 24-entry decision log in `docs/V4_SPEC.md` §18 captures rationale for every non-obvious choice

---

## Pre-v4 history (`panzura_demo_toolkit_vNext2/`, retired 2026-04-20)

The script-collection era. Preserved on branch `legacy/vnext2` and in git history.

### vNext2 — 2025-10-15 — ACL-optimized edition

- Eliminated Panzura Symphony scan errors: `ERR_DIRACLINFO_ANALYZEUNPROTECTEDDACL_FAILED` and `GDS_BAD_DIR_HANDLE` caused by the `-ClearExisting` parameter on `Grant-FsAccess`. Removed the parameter and the ACL-clearing code path — ACL edits became additive only
- Simplified inheritance-breaking patterns in `create_folders.ps1` to prevent malformed directory handles
- Validated: zero scan errors where vNext had 12–26 failures per 477K files

### vNext — 2025-01-27 — Enhanced enterprise features

- First pass at the timestamp-realism and AD-ownership goals later formalized in v4
- 185+ folder types, service account integration, sophisticated file distribution
- Some claims here were aspirational; v4 delivers them with a rigorous design

### v5 and earlier (2024)

- Idempotent user creation, unique SAM-name enforcement (v5)
- Department + project + archive folder structure (v4)
- Initial AD integration, permission management (v3)
- Sparse file creation, historical timestamps (v2)
- Initial release (v1)

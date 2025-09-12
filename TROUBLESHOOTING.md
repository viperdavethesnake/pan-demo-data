# Troubleshooting

## Share shows SIDs instead of names
- Cause: name cache/replication delay or identity created recently.
- Fix: re-run `./set_share_acls.ps1`; verify `GG_AllEmployees` exists; wait a bit and re-check.

## Duplicate/Noisy share ACE output
- Cause: intermediate state during cleanup.
- Fix: ignore the transient table; the final table should show unique Admins Full + AllEmployees Read.

## Sparse files fail
- Symptom: `fsutil sparse setflag failed` errors.
- Fix: ensure NTFS on `S:` and admin rights; if backend blocks sparse, add a `-Physical` fallback (see TODO) or run on local NTFS.

## Files only appear in a few folders
- Cause: `-MaxFiles` too small; early folders fill first.
- Fix: increase `-MaxFiles` (e.g., 5000+) or add per-folder density controls (see TODO).

## AD module not found
- Fix: install RSAT; import with `Import-Module ActiveDirectory -SkipEditionCheck` in PS 7.

## Permissions errors
- Run as Administrator; ensure you have domain admin rights for AD and local admin for NTFS/SMB.

## Reset left artifacts
- Run `./ad_reset.ps1 -BaseOUName DemoCorp -DoUsers -DoGroups -DoOUs -PurgeBySamPrefixes -Confirm:$false -VerboseSummary`.
- If objects remain due to protection, re-run; check OU protection flags.


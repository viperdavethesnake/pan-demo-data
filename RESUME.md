# Resume notes — pan-demo-data

**Last session: 2026-04-18**
**User: microbarley@icloud.com**

## Context to rehydrate when we resume

We reviewed the repo and decided vNext3 was not a real successor to vNext2 — it only ever shipped a single parallel file creator (`create_files_parallel.ps1`) and depended on copying the rest of the pipeline from vNext2. Its `PERFORMANCE_REPORT.md` also contained fictional 10x numbers; the real measured speedup is 2.26x (see `OPTIMIZATION_SUMMARY.md`).

## What changed this session

1. Copied `panzura_demo_toolkit_vNext3/create_files_parallel.ps1` → `panzura_demo_toolkit_vNext2/create_files_parallel.ps1` (drop-in alongside `create_files.ps1`, same flags, PS 7.5+ only).
2. Renamed `panzura_demo_toolkit_vNext3/` → `archive_vNext3_incomplete/` via `git mv` (preserves audit/perf docs for history; not a working toolkit).
3. Rewrote root `README.md` layout + quick-start sections to reflect vNext2 as canonical and parallel as optional.
4. Created `CLAUDE.md` at repo root covering layout, commands, pipeline phases, and invariants (no `-ClearExisting`, AGDLP wiring, timestamp realism, sparse-file surfacing).
5. Updated `CLAUDE.md` to match the consolidation (archive path, parallel script now lives in vNext2).

**Not committed.** Changes are staged/working-tree only — user hasn't asked for a commit yet.

## State at reboot

Run these after the server comes back to re-orient:

```bash
git -C "C:\Users\Administrator\Documents\pan-demo-data" status
git -C "C:\Users\Administrator\Documents\pan-demo-data" diff --stat
ls "C:\Users\Administrator\Documents\pan-demo-data\panzura_demo_toolkit_vNext2" | grep parallel
ls "C:\Users\Administrator\Documents\pan-demo-data" | grep -i vnext
```

Expected:
- vNext2 contains `create_files_parallel.ps1` alongside `create_files.ps1`.
- `archive_vNext3_incomplete/` exists at repo root; `panzura_demo_toolkit_vNext3/` does not.
- Modified: `README.md`, new: `CLAUDE.md`, `RESUME.md`.
- The `git mv` rename of vNext3 → archive is already staged.

## Likely next steps

- Commit the consolidation (user hasn't asked yet — confirm message/scope first).
- Optional: verify `create_files_parallel.ps1` still runs cleanly from its new vNext2 location (it has no relative-path dependencies beyond `set_privs.psm1`, which is already in vNext2 and identical to the archived copy — diff showed no differences).
- Optional: delete or prune `archive_vNext3_incomplete/PERFORMANCE_REPORT.md` since its numbers are fictional, or add a header note marking it as such.

## Watch-outs

- vNext3's `PERFORMANCE_REPORT.md` claims 10x / 152 files-sec — fictional. `OPTIMIZATION_SUMMARY.md` has the real 2.26x / 30.5 files-sec. If resurrecting any claim from the archive, use the latter.
- `create_files_parallel.ps1` defines all helpers inline on purpose. `ForEach-Object -Parallel` runspaces don't inherit parent scope, so do **not** "clean it up" by extracting helpers into a module. Only `set_privs.psm1` is safe as an external module.
- Don't reintroduce `-ClearExisting` on ACL edits — that caused Symphony `GDS_BAD_DIR_HANDLE` scan failures and was the whole reason vNext2 existed.

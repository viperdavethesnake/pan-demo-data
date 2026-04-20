# Next-version brief

**Purpose:** hand off design context for a fresh chat about what comes after PanzuraDemo v4.1.0. Written 2026-04-20 after the first production 10 M build + repo cleanup.

**Ground rule from the last conversation:** *"speed matters, but quality matters more, just looking for efficiency gains if possible."* Don't design v5 as a performance rewrite. Design it as a quality/maintainability/distribution rewrite where performance is a bonus.

---

## 1. Starting state (2026-04-20)

- `PanzuraDemo` module v4.1.0 is canonical, production-validated
- First production 10 M-file build completed in 8 h 46 m (tag `build-2026-04-20`)
- 9,962,001 files · 85.6 TB logical · ~1.2 TB physical sparse · 2,693 folders · 361 users · 0.016 % error rate
- Spot-check verified: sparse flag 100 %, timestamps match manifest to the second, ownership/ACLs set as designed
- Repo cleaned: retired `panzura_demo_toolkit_vNext2/` (preserved on branch `legacy/vnext2`) and `archive_vNext3_incomplete/`. Root docs rewritten for module-first workflow
- Designer/architect handoff shipped at `docs/demo-dataset/`

Nothing is on fire. v5 planning can be deliberate.

## 2. What works — don't break these

| Win | Why it matters |
|---|---|
| **Layered date-preset build** (L1 LegacyMess -10y, L2 YearSpread -10y, L3 RecentSkew -3y, L4 2019 cohort) | Produces a visibly organic decay curve + a visible acquisition bulge, without looking square-bucketed |
| **Native `SetNamedSecurityInfoW` P/Invoke** (`Private/Native/Security.cs`) | 11× ACL speedup, +42 % wall-clock vs. `Set-Acl`. Process-lifetime SID cache (1 LSA lookup per account) |
| **Per-file write order invariant** (body → sparse → attrs → ADS → owner → timestamps **last**) | Prevents the ~15 % present-date contamination bug that haunted pre-v4 |
| **Coherent CT ≤ WT ≤ AT with anti-contamination dispersal** | Clamp overflows disperse across last 7 days, never pin to Now — scanners see no spike |
| **Dormant / LegacyArchive classes hard-pinned 3–5 y ago** (regardless of `MinDate`) | Creates a genuine "aged file" tail even when the preset window is narrow |
| **Engineered ACL-mess ratios** (`Mess.AclPatterns`) | Proper-AGDLP 55 / LazyGG 25 / OrphanSid 10 / Everyone 5 / Deny 5 — hits config targets within tolerance |
| **Folder density model (v4.1)** | Per-year quarter subfolders + uncapped home-dirs → avoids NTFS 200 K/folder insert-cliff |
| **Sparse file efficiency** | 85.6 TB logical → 1.2 TB physical (1.4 %). Critical for fitting demo-scale data on any reasonable volume |
| **Manifest JSONL** | Per-layer per-file record lets us verify after the fact + cross-check dashboards against source-of-truth |

## 3. Current friction / limitations

- **8 h 46 m wall clock for 10 M files.** Usable once; painful for iteration. Per-layer rate: 402 f/s cold → 260 f/s dense (35 % degradation end-to-end).
- **PowerShell-per-file overhead dominates.** Each file passes through multiple PS cmdlets; .NET method calls per file; Add-Content to manifest per file. This is the hot path.
- **Dormant 3–5 y range is hard-coded** in `New-DemoFile.ps1` lines 347–351. Not config-driven. Means the "middle-aged files" peak drifts as real time passes — builds done 6 months apart look subtly different.
- **No `-PathFilter` on `New-DemoFile`.** Blocks any story that needs a dedicated subtree (Option B Deadbeat subtree from the layer-design discussion couldn't be built without code changes).
- **`build-10M.ps1` is ad-hoc orchestration**, not composable. Good for one recipe; if we want to offer multiple named recipes (MessyLegacy, AcquisitionReplay, PostBreachCleanup) they'll all be similar copy-paste scripts.
- **No incremental mode.** Full rebuild is the only way to change anything. "Add 500 K more 2019 files" requires a full re-run.
- **`-Parallel` is measurably slower** at this workload (decision #19). PowerShell runspaces don't inherit parent scope, so the parallel path duplicates helpers inline and still can't match sequential. This is a PS-runtime limitation — not a ceiling on what's possible.
- **Config in `.psd1`** ties us to PowerShell. Fine today; blocker if any of the runtime moves to .NET without embedding PS.
- **Manifest is JSONL.** Great for `grep`; structured queries (group-by-dept, histogram-by-year) require re-parsing. Analytics tooling would rather eat Parquet or SQLite.

## 4. Ideas under consideration

### 4.1 Full C# rewrite (top of the design agenda)

**Framing:** not "rewrite for speed." Rewrite because half the codebase is already C# (the P/Invoke for ownership and ACLs), split across a PS shell that's paying per-file cmdlet overhead for something the C# side could do in one native call. Unifying the split probably improves quality and maintainability as much as speed.

**What's currently C# today:** just `PanzuraDemo/Private/Native/Security.cs` — `SetNamedSecurityInfoW` / `LookupAccountName` / SID cache. Everything else (file creation, sparse flag via `fsutil`, attributes, ADS writes, timestamps, manifest emission, folder tree, AD population, config loading, orchestration) is PowerShell.

**Candidates to consider moving to C#:**

- **Inner file-creation loop** — biggest single win. One C# method per file: create + sparse via `DeviceIoControl(FSCTL_SET_SPARSE)` instead of shelling to `fsutil` + seek/write + attributes + write ADS via `CreateFileW("path:stream")` + owner via existing P/Invoke + timestamps via `SetFileTime`. Eliminates all PS-per-file overhead.
- **True multi-threading** — real `Parallel.ForEach` or `Task` pool. Not subject to runspace scope issues that killed `-Parallel` in PS. Could plausibly hit 4–8× parallelism on a 16-core host if disk isn't the bottleneck. Worth measuring.
- **Manifest writer** — `System.IO.StreamWriter` with buffered write + periodic flush. Drop the Add-Content hot path.
- **Folder tree generator** — straightforward translation; not hot-path but benefits from typed code.
- **AD population** — `System.DirectoryServices.AccountManagement` gives typed objects vs. AD-module cmdlets; could be cleaner.
- **Config loader** — if config moves to YAML/JSON (see 4.2), this is trivial in C#.

**Trade-offs to weigh:**

- ✅ Unified codebase; one language; compiled perf; strong typing on the data model
- ✅ Real threading, real memory management, real error handling
- ✅ Easier to distribute (see 4.3 packaging)
- ❌ Contributors need .NET SDK, not just a PS session. Fewer people "just poke at a cmdlet."
- ❌ Loses PowerShell idempotency patterns (`-WhatIf`, `-Confirm`, ShouldProcess) — need to re-implement or skip
- ❌ REPL-style exploration (Import-Module → Get-DemoReport) gets further from the user
- ❌ More build complexity (nuget, csproj, CI build step before use)

**Hybrid options to consider instead of full rewrite:**

- **C# core + thin PS wrapper.** Ship a .NET assembly; PS cmdlets are thin wrappers around its methods. Best of both: PS users still get `Import-Module` + cmdlet experience, internals are compiled. This is probably the sweet spot.
- **C# generator only, rest stays PS.** Move only `New-DemoFile` (the hot path) to a C# binary; everything else stays as PS. Minimum disruption, captures most of the perf + quality wins.

### 4.2 Config format — externalize out of `.psd1`

**Current:** `PanzuraDemo/config/default.psd1` (~750 lines) is a PowerShell hashtable literal. It's nice — comments work, PS IDEs syntax-highlight it, `Import-DemoConfig` just evaluates the file.

**Problem if C# is involved:** `.psd1` is PowerShell syntax. A .NET binary can't read it natively — it would have to embed PowerShell to parse, or we write a custom parser, or we externalize.

**Options:**

| Format | Pros | Cons |
|---|---|---|
| Stay `.psd1` | Zero migration cost; PS-ergonomic | Not readable by C# without embedding PS |
| **YAML** | Comments, readable, expressive for nested structures, loaders in both PS (`powershell-yaml` module) and .NET (`YamlDotNet`) | External dependency in both worlds; whitespace-sensitive |
| JSON | Universal, no dependencies | No comments, noisy for deeply nested config, quote-heavy |
| JSON5 / JSONC | Comments in JSON, many loaders | Weaker tooling than YAML |
| TOML | Clean for flat-ish config, comments | Awkward for deeply nested (we're deeply nested) |

**Recommendation for the design chat:** default to **YAML** for portability + editability; keep the existing `.psd1` as a translation target if hybrid path is chosen. Schema stays identical across formats.

### 4.3 Packaging

**Current:** `git clone` + `Import-Module path\to\PanzuraDemo.psd1 -Force`. Works but isn't self-serve.

**Options, ranked by "cleanest hand-off to a demo operator who hasn't seen the repo":**

1. **PSGallery module** (if we stay PowerShell or hybrid): `Install-Module PanzuraDemo`. Zero setup for anyone with PS. Versioning via standard semver.
2. **.NET global tool** (if we go C#-first): `dotnet tool install --global PanzuraDemo.Generator` → `pan-demo` on PATH. Single-binary distribution, cross-version .NET-friendly.
3. **Chocolatey / Scoop** (either path): `choco install panzura-demo`. Traditional Windows package; good for enterprise.
4. **MSI installer**: heavier, opt-in for operators who need traditional installation.
5. **Container image**: not viable — NTFS sparse is Windows-only + AD is a heavy host dependency.

**Recommendation for the design chat:** target PSGallery *and* .NET global tool. Same codebase, two distribution pipelines. Install story for a new operator becomes a one-liner either way.

### 4.4 Structural improvements (independent of C# decision)

These are backlog items that would improve the current module or any rewrite:

- **Config-driven Dormant range** — unblock tuning the "aged file" cohort without editing code
- **`-PathFilter` on file generator** — enable dedicated-subtree stories (Deadbeat folder tree with unique AD group, regulatory-purge area, etc.)
- **First-class named scenarios** — `Invoke-DemoRecipe -Name MessyLegacy` / `AcquisitionReplay` / `PostBreach`; ship recipes with the module instead of ad-hoc build scripts
- **Incremental mode** — `Add-DemoFile -Count 500000 -DatePreset Uniform -Where 'Sales/*'` without rebuilding
- **Structured manifest format** — Parquet (bulk analytics) or SQLite (queries). JSONL stays as optional sidecar
- **Age-anchor config** — pin the "Now" for dormant pinning to a configured date so repeated builds over months don't drift

### 4.5 Demo-quality ideas

- More date-cohort stories to layer alongside Deadbeat:
  - Regulatory-purge cliff (sudden file-creation gap in a year after a compliance event)
  - Ransomware scar (narrow cluster of `.enc` / `.locked` files)
  - "Lost decade" (a department with nearly no files between dates X and Y)
- Dedicated subtree + unique AD group for Deadbeat once `-PathFilter` lands — richer story than date-cohort-only
- Operator-controllable scenario mixing — "demo the acquisition story + the compliance story together"

### 4.6 Observability + testing

- Structured progress events (JSON lines, not just Write-Host) — consumable by live dashboards during long builds
- Pester tests for module public surface
- Smoke-verification coverage expansion (check more invariants, not just ratios)

## 5. Open questions for the design chat

1. **Scope.** Full C# rewrite? C# core + PS wrapper (hybrid)? C# hot path only? Choice drives everything downstream.
2. **Version name.** `v5.0` if rewrite, `v4.2` if incremental additions. Affects branding + back-compat expectations.
3. **Config format.** YAML? Stay `.psd1`? Dual-loader (both)?
4. **Packaging.** PSGallery, .NET global tool, both? Picks the user install story.
5. **Back-compat with v4 configs.** Must new version read old `.psd1` files? Helpful for iteration, costs effort.
6. **Throughput target.** What's "efficiency gain worth the rewrite cost"? 2×? 5×? 10×? Without a number it's easy to design infinite scope.
7. **Idempotency model.** If PS cmdlet pattern goes away, what replaces `-WhatIf` / `-Confirm` / `ShouldProcess`? Dry-run flag? Transactional mode?
8. **Contributor surface.** Are we ok being ".NET SDK required" for contributions, or does the core need to stay editable by anyone with a PS session?

## 6. Read-this-first order (for a fresh agent)

1. `README.md` — 2 min, repo orientation
2. `CLAUDE.md` — 5 min, canonical workflow + invariants
3. `docs/V4_SPEC.md` §18 (decisions 1–24) — why every non-obvious choice was made
4. `RESUME.md` — where we left off
5. `docs/demo-dataset/dataset-snapshot.md` — what the generated data looks like
6. `build-10M.log` — real phase-by-phase numbers from production run
7. `PanzuraDemo/Public/New-DemoFile.ps1` — the hot path; most C# candidate
8. `PanzuraDemo/Private/Native/Security.cs` — the C# that's already there; starting template if we expand
9. `PanzuraDemo/config/default.psd1` — what config has to survive the rewrite (as-is or translated)
10. `spot-check.ps1` — how we verify a build is clean; must be reproducible across versions

## 7. Invariants — carry these forward no matter what

These are load-bearing. Any v5 design must preserve them or explicitly justify breaking them.

- **pwsh 7.5+ if any PowerShell surface remains.** `powershell` 5.1 silently fails on module import.
- **No `-Parallel` in the PS runtime.** Sequential + native P/Invoke beats `ForEach-Object -Parallel` at this workload (decision #19). C# real threading is a different question.
- **No `-ClearExisting` on ACL edits.** Historical Panzura Symphony `GDS_BAD_DIR_HANDLE` failures. Edits must be additive/targeted only.
- **AGDLP wiring.** Users → `GG_*` → `DL_Share_*` → NTFS. Don't put users or `GG_*` directly on production ACLs (some engineered-mess folders DO — that's the lazy-AGDLP anti-pattern we deliberately surface).
- **Per-file write order.** body (sparse) → attrs → ADS → owner → timestamps **absolutely last**. Writing any NTFS stream (including `:Zone.Identifier`) bumps `LastWriteTime` to now.
- **CT ≤ WT ≤ AT invariant + anti-contamination dispersal on clamp overflow.** Don't regress the 7-day dispersal — pinning overflow to Now creates scanner-visible spikes.
- **Sparse-file surfacing.** If the backend rejects sparse flags, surface the error. Never silently fall back to dense writes — would blow up physical disk usage at demo scale.
- **Idempotent + safe.** Any destructive operation requires an explicit flag or `-Confirm:$false`. `-WhatIf` (or equivalent dry-run) remains first-class.
- **Manifest is source of truth for verification.** Whatever format it's in, a post-build check must be able to re-derive "did this file get the right owner/timestamps/sparse flag?" from the manifest.

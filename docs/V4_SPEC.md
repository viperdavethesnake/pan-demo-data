# PanzuraDemo v4 — Specification

**Status:** Source of truth for v4 implementation.
**Supersedes:** `panzura_demo_toolkit_vNext2/` (archived on v4 release).
**Scope:** Complete rewrite as a PowerShell module. Not backwards compatible with vNext2 invocation surface.

---

## 1. Purpose

Provision a "messy enterprise NAS" on a single Windows host so that NAS security scans (ACL + file metadata) produce a realistic spread of findings. AD is a backing store for ACL principals, not a demo artifact in itself.

**North star:** every feature in v4 exists to make a specific scan finding surface. Anything that does not produce a scan finding does not ship.

---

## 2. Non-negotiables

- **No Panzura Symphony coupling.** Scan-compatibility constraints from vNext2 are dropped.
- **AGDLP naming must match.** `DL_Share_<Dept>_RW` / `DL_Share_<Dept>_RO`. These appear on ACLs; `GG_<Dept>` should not, except as deliberate mess.
- **Timestamp realism invariants:**
  - `CreationTime ≤ LastWriteTime ≤ LastAccessTime`
  - All three ≤ `Get-Date` at write time
  - No file has `LastWriteTime` in the current calendar week unless the run's `DatePreset` explicitly allows it.
- **Sparse-file generation must succeed.** On failure, surface the error; never fall back to dense writes.
- **Per-file write ordering** (load-bearing, from vNext2 lessons):
  1. `New-Item` → open stream
  2. Write magic-byte header
  3. `FSCTL_SET_SPARSE` (P/Invoke)
  4. Seek to `size - 1`, write one byte, close
  5. `SetAttributes` (ReadOnly/Hidden)
  6. Write ADS (`Zone.Identifier`)
  7. Set owner/group (ACL changes are safe on MAC times)
  8. Set creation/write/access timestamps **absolutely last**
- **Idempotency.** All mutating operations safe to re-run. Destructive ops require explicit flags.
- **No new languages beyond what's already sanctioned:** PowerShell 7+, C# via `Add-Type`. No Python, no external binaries.

---

## 3. Module layout

```
PanzuraDemo/
├── PanzuraDemo.psd1                    # manifest
├── PanzuraDemo.psm1                    # root loader
├── config/
│   ├── default.psd1                    # canonical config
│   ├── smoke.psd1                      # reduced-scale override for validation
│   └── names/
│       ├── first.psd1                  # first-name corpus
│       └── last.psd1                   # last-name corpus
├── Public/
│   ├── Invoke-DemoPipeline.ps1
│   ├── Test-DemoPrerequisite.ps1
│   ├── Test-DemoSmokeVerification.ps1
│   ├── New-DemoADPopulation.ps1
│   ├── New-DemoFolderTree.ps1
│   ├── New-DemoFile.ps1
│   ├── Remove-DemoOrphanUser.ps1
│   ├── Get-DemoReport.ps1
│   ├── Reset-DemoEnvironment.ps1
│   ├── Import-DemoConfig.ps1
│   └── Get-DemoScenario.ps1
├── Private/
│   ├── Config/Import-ConfigInternal.ps1
│   ├── Distribution/Get-NormalSample.ps1
│   ├── Distribution/Get-WeightedChoice.ps1
│   ├── Distribution/Get-HeavyTailBucket.ps1
│   ├── Date/Get-RealisticDate.ps1
│   ├── Date/Get-FileTimestampSet.ps1
│   ├── Date/Get-FolderEra.ps1
│   ├── Name/Get-PersonName.ps1
│   ├── Name/Get-FileName.ps1
│   ├── Name/Resolve-DeptFromPath.ps1
│   ├── Filesystem/New-SparseFileInternal.ps1
│   ├── Filesystem/Set-FileOwnershipInternal.ps1
│   ├── Filesystem/Write-FileMagic.ps1
│   ├── Filesystem/Set-AclPattern.ps1
│   ├── AD/Get-ADUserCache.ps1
│   ├── AD/Add-BulkGroupMember.ps1
│   ├── Mess/Get-AclMessRoll.ps1
│   ├── Mess/Add-OrphanSidAce.ps1
│   ├── Native/Sparse.cs                # sources for Add-Type
│   └── Native/Privilege.cs
└── tests/
    ├── Unit/
    │   ├── Distribution.Tests.ps1
    │   ├── Date.Tests.ps1
    │   ├── Name.Tests.ps1
    │   ├── PathResolution.Tests.ps1
    │   └── Config.Tests.ps1
    └── Integration/
        └── Smoke.Tests.ps1
```

`Public/*.ps1` are dot-sourced and exported. `Private/*.ps1` are dot-sourced and internal.

---

## 4. Public cmdlet surface

| Cmdlet | Purpose | Key params |
|---|---|---|
| `Invoke-DemoPipeline` | Orchestrator | `-Config`, `-Scenario`, `-Phase`, scenario overrides |
| `Test-DemoPrerequisite` | Env checks | `-Config` |
| `New-DemoADPopulation` | OUs, groups, users | `-Config` |
| `New-DemoFolderTree` | Folder tree + initial ACLs | `-Config` |
| `New-DemoFile` | One file-generation run | `-Config`, `-MaxFiles`, `-DatePreset`, `-MinDate`, `-MaxDate`, `-RecentBias`, `-Parallel` |
| `Remove-DemoOrphanUser` | Delete orphan-designated users | `-Config` |
| `Get-DemoReport` | AD + FS + mess report | `-Config`, `-ExportJson`, `-ExportCsv`, `-ExportMarkdown` |
| `Test-DemoSmokeVerification` | Post-run verification | `-Config` |
| `Reset-DemoEnvironment` | AD + share cleanup (not FS) | `-Config`, `-Confirm` |
| `Import-DemoConfig` | Load & validate config | `-Path` |
| `Get-DemoScenario` | List scenarios | `-Config` |

---

## 5. Configuration schema

Full schema lives in `config/default.psd1`. Summary of top-level keys:

- `Metadata` — version, description
- `Share` — `Root` (default `S:\Shared`), `Name` (`Shared`), `CreateShare`
- `AD` — `BaseOUName` (`DemoCorp`), `MailDomain` (null = derive from DNS root), `Password` (null = auto-generate)
- `Departments[]` — name, SamPrefix, UsersPerDept min/max, SubFolders, Extensions (weighted map)
- `ExtensionProperties` — per-extension MinKB / MaxKB
- `FileHeaders` — per-extension magic bytes (byte arrays)
- `NameTemplates` — per-folder-pattern file-name templates with `{token}` substitutions
- `DataPools` — Vendors, Clients, Projects, Products, Customers, Matters (arrays)
- `FolderTree` — ArchiveYearRange, UserHomeDirs config, MaxDepth, CleanNamesOnly, LegacyFolderChance, CrossDeptFolders, InheritanceBreaks
- `Files` — DefaultCount, DefaultDatePreset, DefaultRecentBias, FolderCoherence, ArchiveYearOverrides, LegacyFossilRate, HeavyTailDistribution, Attributes, Ownership, FileLevelAcl
- `TimestampModel` — FileClasses (7 classes with gap distributions), DormancyByFolderPattern
- `Mess` — OrphanSidCount, AclPatterns, ServiceAccounts (with PathPatterns)
- `Parallel` — ThrottleLimit, ManifestPath, PlanPath
- `Scenarios{}` — named multi-run recipes

### Config layering

1. Start with `config/default.psd1`
2. Merge user config (if `-Config <path>` supplied) over defaults (deep merge; arrays replaced)
3. Apply CLI param overrides (e.g. `-MaxFiles 5000`) last

---

## 6. AD layer — spec

### 6.1 OU structure

```
DemoCorp/
├── Users/
│   ├── Finance/ HR/ Engineering/ ... (one OU per dept in config)
├── Groups/                              (flat)
└── ServiceAccounts/
```

### 6.2 Groups (minimal, every group appears on at least one ACL)

- `GG_AllEmployees` (Global)
- `GG_<Dept>` per dept (Global)
- `DL_Share_<Dept>_RW` per dept (DomainLocal)
- `DL_Share_<Dept>_RO` per dept (DomainLocal)
- `GG_Contractors` (Global) — appears as Deny-ACE principal
- `GG_BackupOps` (Global) — appears on Archive/Backup folders

### 6.3 AGDLP wiring

`Add-ADGroupMember -Identity DL_Share_<Dept>_RW -Members GG_<Dept>` once per dept. Users are members of `GG_<Dept>`; they get RW via the DL group via AGDLP.

### 6.4 Users

**Real users**:
- Per-dept count from `Departments[].UsersPerDept` range, uniform random
- SAM = `first.last` (from bundled corpus). Collision ladder: `first.m.last` (middle init), `first.last2`, `first.last<N>`, `f.last`
- CN = `"First Last"`
- DisplayName = `"First Last"`
- GivenName / Surname set
- UPN = `first.last@<AD.DNSRoot>`
- mail = `first.last@<MailDomain | AD.DNSRoot>`
- Department, Title (from config title pool), Office (city), Company = `DemoCorp`
- Password = config `AD.Password` or auto-generated; `PasswordNeverExpires = $true`
- Added to `GG_AllEmployees` and `GG_<Dept>` in bulk (one `Add-ADGroupMember` per group, not per user)

**Service accounts** (10, from config `Mess.ServiceAccounts`):
- SAM = as specified (`svc_backup`, `svc_sql`, etc.)
- Description = human-readable purpose
- Placed in `ServiceAccounts/` OU
- Added to `GG_BackupOps` where relevant (`svc_backup`, `svc_sql`)

**Orphan-designated users** (`Mess.OrphanSidCount`, default 40):
- SAM = `first.last` from corpus (same naming as real users — they look ex-employee)
- `employeeType = "Former"` — the marker for `Remove-DemoOrphanUser`
- Added to `GG_AllEmployees` and a random dept's `GG_<Dept>` (so their SID will show in ACLs where that dept's ACL-pattern injector chooses them)
- At this stage they exist as normal AD objects; their SIDs resolve. They become orphans only after `Remove-DemoOrphanUser`.

### 6.5 Bulk membership (perf)

Current vNext2 uses `Get-ADGroupMember -Recursive` per add (O(N²)). v4 uses:
- Collect SAMs per dept into an array, then `Add-ADGroupMember -Members @(sams)` in one call
- Ignore `ADIdentityAlreadyExists` via try/catch (idempotent)

---

## 7. Folder layer — spec

### 7.1 Per-dept taxonomy (config `Departments[].SubFolders`)

Default:
```
Finance      AP, AR, Payroll, Budget, Tax, Audit, Forecasts, GeneralLedger
HR           Employees, Benefits, Onboarding, Reviews, Policies, Recruiting, Compliance
Engineering  Source, Builds, Releases, Specs, Reviews, Incidents, Sandbox
Sales        Clients, Pipeline, Proposals, Contracts, Commissions, Forecasts
Legal        Contracts, Matters, IP, Compliance, Litigation, NDA
IT           Configs, Scripts, Logs, Backups, Installs, Apps, Credentials
Ops          Runbooks, Inventory, Incidents, Workflows, Schedules
Marketing    Campaigns, Brand, Social, Events, Assets, Analytics
R&D          Research, Prototypes, Experiments, Patents, LabData
QA           TestPlans, TestResults, Automation, Bugs, Performance
Facilities   Blueprints, Maintenance, Leases, Safety, Incidents
Procurement  RFPs, POs, Vendors, Contracts, Receiving
Logistics    Shipments, Inventory, Customs, Tracking
Training     Curriculum, Materials, Schedules, Certificates
Support      Tickets, KB, Escalations, Reports
```

### 7.2 Universal subs (every dept)

- `Archive/<year>/` for each year in `ArchiveYearRange` (default 2015-2024)
- `Temp/`
- `Sensitive/` (inheritance broken)
- `Users/<first.last>/` for ~15 random dept users
- `Projects/<codename>/` for 2-4 random codenames from `DataPools.Projects`

### 7.3 Cross-dept root folders

From config `FolderTree.CrossDeptFolders`:
- `Shared/` — Everyone Read
- `Public/` — Everyone FullControl (the one big finding)
- `Inter-Department/` — GG_AllEmployees Modify
- `Board/` — inheritance broken, restricted
- `Vendors/` — cross-dept Modify for GG_AllEmployees
- `__Archive/`, `__OLD__/`, `_install_files/` — legacy/utility

### 7.4 Root user home dirs

If `UserHomeDirs.RootScoped = $true`: a fraction (`RootFraction`, default 0.4) of all real users get a `S:\Shared\Users\<first.last>\` folder in addition to (or instead of) their dept-scoped one.

### 7.5 ACL patterns

Per folder (weighted roll from `Mess.AclPatterns`):

| Pattern | Action |
|---|---|
| ProperAGDLP | Add `DL_Share_<Dept>_RW` Modify + `DL_Share_<Dept>_RO` ReadAndExecute |
| LazyGlobalGG | Add `GG_<Dept>` Modify directly (the anti-pattern) |
| OrphanSidAce | Add a random orphan-designated user as explicit Modify ACE |
| EveryoneRead | Add `Everyone` Read |
| DenyAce | Add `GG_Contractors` Deny-Write |

**Deterministic overrides** (applied regardless of roll):
- `*/Sensitive/*`, `*/Board/*`, `*/IT/Credentials/*` → `SetAccessRuleProtection($true, $true)` then remove any ACE for `GG_AllEmployees` or `Everyone`
- `*/Public/*` → add `Everyone FullControl`
- `*/Temp/*` → Deny-Write for `GG_Contractors` + `Everyone` Modify
- 5% of other folders → accidental `SetAccessRuleProtection($true, $true)` (inheritance drift)

### 7.6 Ownership at folder creation

- Dept folders → Owner = `GG_<Dept>`
- Cross-dept folders → Owner = `BUILTIN\Administrators`
- User home dirs → Owner = the user (real or orphan-designated)
- Archive/year folders → Owner = `svc_backup` (service account) for some years

### 7.7 Depth cap

`FolderTree.MaxDepth = 7`. Enforce at creation; any path that would exceed cap is truncated by dropping deeper children.

---

## 8. File layer — spec

### 8.1 Default run target

`Files.DefaultCount = 100000`. Smoke override in `config/smoke.psd1`.

### 8.2 Planning pass (main thread)

1. Enumerate folders via `[IO.Directory]::EnumerateDirectories`
2. For each folder:
   - Roll heavy-tail bucket (`Empty`, `Small`, `Med`, `Large`, `Mega`, `Ultra`) from `Files.HeavyTailDistribution`
   - Draw file count within bucket's range
   - Stash folder "era" date drawn from preset (for T2 coherence)
3. Build flat work-item list; clamp total to `-MaxFiles`; write plan JSONL

### 8.3 Execution (per file)

Per file, in order:
1. Pick extension via weighted draw from `Departments[dept].Extensions` (with `LegacyFossilRate` of tail-rare extensions)
2. Pick name via `NameTemplates` matching folder pattern; substitute tokens from `DataPools` + file context (year, dept, ext)
3. Pick size uniform from `ExtensionProperties[ext]` Min/Max
4. Pick file class from `TimestampModel.FileClasses`; bias by `DormancyByFolderPattern`
5. Compute timestamps:
   - `CT` = folder era ± 90 days (coherence), or draw from preset if no era; for `Archive/<year>/` clamp to year ± 180 days
   - `WT` = `CT + WriteGap` from class
   - `AT` = `WT + AccessGap` from class
   - Clamp all to `now`
6. Open FileStream; write magic bytes; `FSCTL_SET_SPARSE`; seek to `size - 1`; write 1 byte; close
7. `SetAttributes` (ReadOnly 5% / Hidden 2% per config)
8. Write ADS `Zone.Identifier` (15% of files)
9. Apply ownership per `Files.Ownership` mix:
   - 55% dept group `GG_<Dept>`
   - 25% random user from cached dept members
   - 5% service account, placed only where `PathPatterns` match
   - 10% orphan-designated user (they will become orphan SIDs after `Remove-DemoOrphanUser`)
   - 5% `BUILTIN\Administrators`
10. File-level ACL mess (per `Files.FileLevelAcl`):
    - 97% pure inheritance (nothing added)
    - 1% explicit user Modify ACE (random dept member)
    - 0.5% explicit orphan-user Modify ACE
    - 0.5% `SetAccessRuleProtection($true, $true)` (detached ACL)
    - 1% explicit Deny for `GG_Contractors`
11. `[IO.File]::SetCreationTime`, `SetLastWriteTime`, `SetLastAccessTime` — **absolute last**

### 8.4 Ownership batching optimization

The 55% dept-group owner applies to most files. After a file-gen run, do one `icacls <Root> /setowner "<NetBIOS>\GG_<Dept>" /T /C /Q` per dept on files that were flagged as "dept-group-owned" via an in-memory manifest, to cut per-file ACL round-trips.

*Deferred optimization:* If the per-file ownership step is fast enough in smoke (acceptable wall-clock), skip the batching layer. Re-evaluate at 1M scale.

### 8.5 Multi-run additive

Each `New-DemoFile` call is an independent pass. Folder eras are drawn per-run, so successive runs with different `DatePreset` produce layered temporal mess in the same folders.

---

## 9. Timestamp model

7 file classes, config-driven:

| Class | Pct | WriteGap (days) | AccessGap (days) |
|---|---|---|---|
| Active | 25 | 0-30 | 0-14 |
| Reference | 15 | 0-90 | 0-30 |
| WriteOnceReadMany | 10 | 0-1 | 0-14 |
| WriteOnceNeverRead | 15 | 0-1 | 0 |
| Aging | 15 | 0-180 | 30-365 |
| Dormant | 15 | 0-180 | 1095-1825 |
| LegacyArchive | 5 | 0-30 | 0 |

`DormancyByFolderPattern` biases the class draw for specific paths (Archive → 75% Dormant+Legacy, active IT/Logs → 5%).

---

## 10. Orphan SID workflow

Order:
1. `New-DemoADPopulation` creates orphan-designated users alongside real ones (flagged via `employeeType = "Former"`)
2. Folder + file runs reference them in ACEs and ownership
3. After all ACL/ownership writes are done, `Remove-DemoOrphanUser` deletes the flagged users
4. NTFS still holds their SIDs; AD no longer resolves → scan reports as orphan SIDs

Multi-run layering note: `Remove-DemoOrphanUser` should run ONCE after all `New-DemoFile` passes complete.

---

## 11. Reset

`Reset-DemoEnvironment`:
- Removes all `GG_*`, `DL_Share_*` groups in `Groups/` OU
- Removes all users in dept OUs + `ServiceAccounts/`
- Removes the `DemoCorp` OU (disables protection as needed, recursive)
- Removes `Shared` SMB share
- **Does not touch filesystem** (user reformats)

---

## 12. Report

`Get-DemoReport` output sections:

1. **AD summary** — user counts per dept, service accounts, orphan-designated status, group counts
2. **Filesystem summary** — total files, total bytes (sparse + logical), per-dept breakdowns, extension histogram, folder depth histogram, file-count-per-folder histogram
3. **Timestamp & dormancy** — dormant file count/%, age buckets, never-read files
4. **ACL mess** — orphan SID references (owner + ACE positions), Everyone/Authenticated-Users count, Deny-ACE count, broken-inheritance count, AGDLP-violation count, file-level ACL-oddity count, ownership mix actuals
5. **Predicted scan findings** — severity-tagged table tying each mess feature to its scan category

Export: `-ExportJson`, `-ExportCsv`, `-ExportMarkdown`.

---

## 13. Performance design

- Sparse via `Add-Type`-compiled C# calling `DeviceIoControl(FSCTL_SET_SPARSE)` on open `FileStream.SafeFileHandle`
- `SeRestore` + `SeTakeOwnership` enabled once per process (in module init)
- AD user cache: one `Get-ADGroupMember` per dept at run start, in-memory array, sampled by workers
- Interlocked counter for parallel progress tracking (no synchronized hashtable)
- Worker RNG = `[Random]::new([Guid]::NewGuid().GetHashCode())`
- Streaming folder enumeration (not `Get-ChildItem -Recurse`)
- Manifest JSONL append-only, mutex-guarded
- Plan persisted before dispatch; resumability via manifest diff

---

## 14. Smoke configuration (`config/smoke.psd1`)

Reduced-scale config for smoke validation. Loads on top of `default.psd1`.

- 4 departments: Finance, HR, Engineering, IT
- UsersPerDept: 5-15 (so ~40 users total)
- 3 service accounts (svc_backup, svc_sql, svc_web)
- OrphanSidCount: 5
- ArchiveYearRange: 2019-2023
- Default file count: 2000
- Single `Smoke` scenario = one run with `DatePreset=RecentSkew`

Smoke is the validation target. If it passes end-to-end, STOP and ask whether to proceed at full scale.

---

## 15. Verification step (`Test-DemoSmokeVerification`)

Run after smoke pipeline completes. Invariants checked:

**Pre-orphanize (while orphan users still exist):**
- Every ACL inspected, orphan SIDs resolve correctly

**Post-orphanize:**

| Check | Tolerance |
|---|---|
| File count within 5% of `MaxFiles` | 5% |
| 100% of files have sparse bit set (`FILE_ATTRIBUTE_SPARSE_FILE`) | zero miss |
| Sampled files (100) have correct magic bytes for extension | zero mismatch |
| Owner distribution across files matches config `Files.Ownership` mix | ±3 pp per bucket |
| ACL pattern distribution matches `Mess.AclPatterns` | ±5 pp per pattern |
| Dormant file ratio (LastAccess > 3yr ago) | 15-25% |
| Orphan SID count in ACLs | > 0 (and all unresolvable via `Get-ADUser`) |
| No file with `LastWriteTime` within current calendar week (smoke default preset is `RecentSkew` with current date allowed as max; the test applies to files generated before "today") — accept `LastWriteTime >= Start-of-today` only if preset permits | lenient |
| Deterministic-break folders (`Sensitive/`, `Public/`, `Board/`, `IT/Credentials/`, `Temp/`) have expected ACL properties | exact match |
| `Get-DemoReport` runs without error and produces all sections | exact |

**Failure action**: erase `S:\Shared`, reset AD, fix root cause, re-run. No partial salvage, no patching the test.

---

## 16. Build order

1. Scaffold module + manifest + loader
2. Native P/Invoke (Sparse, Privilege) — `Add-Type` + smoke test sparse bit on temp file
3. Import-DemoConfig + schema validation
4. Private helpers: distribution, date, name, path resolution
5. `Test-DemoPrerequisite`
6. `New-DemoADPopulation`
7. `New-DemoFolderTree`
8. `New-DemoFile`
9. `Remove-DemoOrphanUser`
10. `Get-DemoReport`
11. `Reset-DemoEnvironment`
12. `Invoke-DemoPipeline`
13. `Test-DemoSmokeVerification`
14. Unit tests (subset — distribution, date, name)
15. Smoke run end-to-end + verification

---

## 17. Acceptance (release gate)

- All sections of verification step pass on smoke scale
- `Get-Help` returns proper output for every `Public/` cmdlet
- Zero hardcoded dept lists, extension weights, or prefixes outside `config/`
- Reset → Populate round-trip produces the same state
- All generated files have correct sparse bit + correct magic bytes
- Orphan SID count > 0 after Remove-DemoOrphanUser, all unresolvable
- Ownership mix, ACL mix, dormancy ratio all within tolerance

---

## 18. Decision log

1. **2026-04-18**: AD is instrumental, not a demo artifact. Dropped manager hierarchy, tenure, title/seniority coherence, contractors-as-class, distribution groups, legacy naming fossils, disabled/locked/ghost users, computers OU, division hierarchy. Focus solely on what surfaces in file-system scans.
2. **2026-04-18**: Symphony scan compatibility dropped. v4 may use ACL patterns that previously caused scan errors; correctness on scan output is not a constraint.
3. **2026-04-18**: Group set reduced from ~90 to ~47 (15 × 3 per-dept + 2 mess + 1 org = 47). Every group appears on at least one ACL.
4. **2026-04-18**: 10 service accounts (up from 6 proposal) with path-pattern placement.
5. **2026-04-18**: Orphan SID flow is create-user → ACL → delete-user (not SID replay). Requires one explicit `Remove-DemoOrphanUser` call at end.
6. **2026-04-18**: `fsutil sparse setflag` replaced with `DeviceIoControl(FSCTL_SET_SPARSE)` via `Add-Type`. No external process forks per file.
7. **2026-04-18**: Folder coherence (T2) + Archive year override (T4) both on by default. Dormancy target 20% (T5).
8. **2026-04-18**: Heavy-tail file-per-folder distribution replaces vNext2 normal distribution. Enables 10M-file feasibility; mega folders absorb most volume.
9. **2026-04-18**: Name corpus bundled in `config/names/` (public-domain first + last).
10. **2026-04-18**: Smoke config is `config/smoke.psd1`, 4 depts / ~40 users / 2000 files. Smoke is the validation gate; full scale requires explicit go-ahead.

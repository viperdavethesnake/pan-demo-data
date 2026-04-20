# Dataset snapshot — 2026-04-20

Ground-truth numbers from the 10M build. Reference these when mocking up charts so the demo dashboard shows data that matches what's actually on disk.

## Headline numbers

| Metric | Value | Notes |
|---|---:|---|
| Files | **9,962,001** | 99.62% of 10M target; 1,649 errors across 4 layers (0.016%) |
| Folders | **2,693** | v4.1 density expansion |
| Logical bytes | **85.6 TB** | what `Get-ChildItem.Length` sums to |
| Physical on-disk | **~1.2 TB** | sparse-file writes; real footprint is ~1.4% of logical |
| Dormant (LastAccess > 3 y) | **69.8%** | 6,948,757 files |
| Files written this week | **171,572** | recent-activity tail |
| Build wall clock | **8 h 46 m** | 18:07 Apr 19 → 02:53 Apr 20 |

## Top-level tree under `S:\Shared`

```
Departments (15):
  Engineering  Facilities  Finance  HR   IT    Legal  Logistics
  Marketing    Ops         Procurement   Support     QA     R&D    Sales  Training

Cross-department / mess folders:
  Board           Inter-Department   Public        Shared     Users    Vendors
  __Archive       __OLD__            _install_files
  LEGACY_Engineering  LEGACY_Legal   LEGACY_R&D
  Marketing_MIXED     OLD_Training   Ops_Backup    QA_MIXED

Plus: ~2,600 files scattered loose at S:\Shared root (Shared_*.ext) simulating
unorganized top-level dumping.
```

## Files and bytes by top-level folder (top 20)

| Folder | Files | Logical |
|---|---:|---:|
| Users (home-dir tree) | 1,532,034 | 5.0 TB |
| Sales | 990,204 | 5.3 TB |
| Finance | 836,039 | 6.8 TB |
| Legal | 825,516 | 4.9 TB |
| Marketing | 739,019 | 7.3 TB |
| Procurement | 656,184 | 3.4 TB |
| Support | 628,485 | 6.3 TB |
| IT | 480,874 | **15.2 TB** — biggest: .bak up to 2 GB, .exe/.msi presence |
| R&D | 480,190 | 2.6 TB |
| Engineering | 460,414 | 2.4 TB |
| Facilities | 412,486 | 1.5 TB |
| QA | 393,381 | 3.8 TB |
| Logistics | 383,998 | 1.6 TB |
| Training | 383,758 | 7.3 TB |
| Ops | 373,313 | 2.2 TB |
| HR | 338,296 | 3.2 TB |
| LEGACY_R&D | 25,285 | 0.2 TB |
| Vendors | 15,644 | 0.1 TB |
| OLD_Training | 13,276 | 0.1 TB |
| __OLD__ | 11,509 | 0.1 TB |

## Creation-time year distribution (all 9.99 M files)

Drawn from per-file manifests. **The 2019 spike is the Deadbeat Corp acquisition cohort (~500 K files).**

```
2016   4.20%  ████████
2017   3.57%  ███████
2018   3.97%  ████████
2019   9.63%  ███████████████████   ← Deadbeat acquisition
2020   4.32%  █████████
2021  17.24%  ██████████████████████████████████
2022  24.64%  █████████████████████████████████████████████████
2023  14.52%  █████████████████████████████
2024   7.73%  ███████████████
2025   6.73%  █████████████
2026   3.45%  ███████
```

The 2021–2023 peak is an *artifact* of the demo's age: the Dormant / LegacyArchive file classes hard-pin CT to 3–5 years ago (see `V4_SPEC.md` for rationale). As the demo ages further, re-run the build to keep the peak tracking 3–5 y behind present.

## Ownership distribution (all 9.99 M files)

Exactly matches config targets (`PanzuraDemo/config/default.psd1` → `Files.Ownership`):

| Bucket | Files | Share | Who / what |
|---|---:|---:|---|
| DeptGroup | 5,495,468 | **55.0%** | `DEMO\GG_<Dept>` — healthy default |
| User | 2,498,780 | **25.0%** | one of the 361 real users created this run |
| OrphanSid | 999,072 | **10.0%** | 40 simulated ex-employees (Former), owners deleted post-build |
| BuiltinAdmin | 500,552 | **5.0%** | `BUILTIN\Administrators` |
| ServiceAccount | 499,064 | **5.0%** | one of 10 service accounts (`svc_backup`, `svc_sql`, …) |

Orphan SID owners (examples — accounts now deleted but owner SIDs persist on files):

```
DEMO\aaliyah.leon        8,984 files
DEMO\christine.vo        8,879 files
DEMO\rose.robertson      8,872 files
DEMO\tracy.moreno        8,865 files
DEMO\courtney.wagner     8,860 files
...
```

## File-class distribution (timestamp behavior)

Shapes the CreationTime → LastWriteTime → LastAccessTime story per file.

| Class | Share | Behavior |
|---|---:|---|
| Dormant | 33.7% | Old (3–5 y), WT ≈ CT, AT ≈ WT — hasn't been touched |
| Active | 17.2% | Fresh, frequent writes + reads |
| LegacyArchive | 11.2% | Old, write-once, never re-read |
| Aging | 10.4% | Written long ago, AT in 30–365 d past |
| WriteOnceNeverRead | 10.3% | AT = WT (never read since create) |
| Reference | 10.3% | Write-heavy recent, read-heavy recent |
| WriteOnceReadMany | 6.9% | One write, frequent reads |

## ACL mess (folder-level, counted by report)

| Pattern | Count | Story |
|---|---:|---|
| Inheritance broken | 20 | Sensitive, Board, Public, IT/Credentials, Temp — deterministic targets |
| Everyone:M / :R | 65 | over-permissive folders (classic audit finding) |
| Orphan folder ACEs | 463 | ACLs referencing deleted users' SIDs |
| `GG_*` direct ACE | 336 | lazy-AGDLP — global groups on ACLs (security anti-pattern) |
| `DL_Share_*` ACE | 4,924 | proper AGDLP wiring (the bulk of the tree) |
| Deny ACE | 88 | explicit denies (Temp folder `GG_Contractors:(DENY)`) |

### Sample ACL readouts

**Clean AGDLP (normal dept folder):**
```
S:\Shared\Finance
  BUILTIN\Administrators:(F)
  DEMO\DL_Share_Finance_RW:(OI)(CI)(M)
  DEMO\DL_Share_Finance_RO:(OI)(CI)(RX)
  ... (inherited entries)
```

**Lazy AGDLP (Sensitive subfolder — GG_ directly on ACL):**
```
S:\Shared\Engineering\Sensitive
  CREATOR OWNER:(OI)(CI)(IO)(F)
  DEMO\GG_Engineering:(OI)(CI)(M)       ← should be DL_, not GG_
  DEMO\DL_Share_Engineering_RW:(OI)(CI)(M)
  DEMO\DL_Share_Engineering_RO:(OI)(CI)(RX)
```

**Temp folder (Deny + Everyone = classic mess):**
```
S:\Shared\Engineering\Temp
  DEMO\GG_Contractors:(OI)(CI)(DENY)(WD,AD,WEA,WA)
  Everyone:(OI)(CI)(M)                   ← wide-open write
  DEMO\DL_Share_Engineering_RW:(I)(OI)(CI)(M)
  ...
```

**SMB share ACL:**
```
Shared : Everyone : Allow : Full    (NTFS enforces — AGDLP pattern)
```

## Active Directory population

| Entity | Count | Under |
|---|---:|---|
| Users | 361 | `OU=Users,OU=DemoCorp,DC=demo,DC=panzura` |
| `GG_*` global groups | 18 | one per dept + 2 cross-dept (Contractors, AllEmployees) |
| `DL_Share_*` domain-local groups | 30 | RW + RO per dept |
| Service accounts | 10 | `OU=ServiceAccounts` |
| Orphan-flagged users (created → removed) | 40 | simulated ex-employees |

## Top extensions (sampled from L1 manifest, 3.5 M files)

| Ext | Count | Ext | Count |
|---|---:|---|---:|
| .pdf | 950,273 | .zip | 93,986 |
| .docx | 658,135 | .msg | 64,077 |
| .xlsx | 620,354 | .json | 50,901 |
| .txt | 249,302 | .xml | 38,744 |
| .log | 150,554 | .png | 34,989 |
| .csv | 147,440 | .jpg | 34,267 |
| .pptx | 146,177 | .xls | 30,351 |
| — | — | .md | 26,929 |

Full list (52 extensions) in `PanzuraDemo/config/default.psd1` → `ExtensionProperties`.

## Sample file paths per cohort

**2019 Deadbeat cohort (L4, Uniform 2019-01 to 2019-12):**
```
S:\Shared\Shared_2019.log
S:\Shared\Shared_2019.xls
S:\Shared\Shared_2019.xlsx
S:\Shared\Shared_v12.bak
S:\Shared\Shared_v17.log
S:\Shared\Shared_v4_75251.xlsx
```

**2016 LegacyMess cohort (L1, deep tail):**
```
S:\Shared\HR\HR_96908.pptx
S:\Shared\Inter-Department\Inter-Department_2016.doc
S:\Shared\Inter-Department\Inter-Department_2016.pdf
S:\Shared\Inter-Department\Inter-Department_v18.pptx
```

**2026 RecentSkew cohort (L3, current activity):**
```
S:\Shared\HR\HR_2026.docx
S:\Shared\HR\HR_2026.pdf
S:\Shared\HR\HR_2026_29863.docx
S:\Shared\Inter-Department\Inter-Department_2026.xlsx
```

## One manifest record (schema reference)

```json
{
  "p":  "S:\\Shared\\Shared_2019.log",
  "s":  21358592,
  "o":  "DEMO\\GG_AllEmployees",
  "b":  "DeptGroup",
  "c":  "Active",
  "ct": "2019-01-01T00:00:00.0000000",
  "wt": "2019-01-29T20:31:00.0000000",
  "at": "2019-02-11T21:25:00.0000000"
}
```

Fields: `p` path · `s` size in bytes · `o` owner (SID-resolved name) · `b` ownership bucket · `c` timestamp file-class · `ct/wt/at` creation / last-write / last-access.

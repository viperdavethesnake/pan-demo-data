# Demo narrative & widget specs

Nine demo storylines this dataset is designed to surface, each with the metric that proves it, the source column, a suggested widget, and a sample query.

All numbers cited are from the 2026-04-20 build. See [`dataset-snapshot.md`](dataset-snapshot.md) for ground truth.

---

## 1. The Deadbeat Corp acquisition (2019 bulge)

**Hook:** *"7 years ago DemoCorp acquired Deadbeat Corp. Look at the intake — half a million files dumped into the share in a single year, concentrated at the root, owned by `GG_AllEmployees` because nobody bothered to re-ACL it."*

- **Metric:** file count by `CreationTime` year → 2019 at 9.63% vs. 3–4% baseline for 2017–2018 and 2020
- **Source:** `manifest_*.jsonl` → `ct` field (or Symphony scan: file CreationTime)
- **Widget:** vertical bar chart, years on X, file count on Y, **annotation arrow on the 2019 bar**
- **Must call out:** the ~2× spike vs. 2018 and 2020 neighbors

```sql
SELECT YEAR(CreationTime) AS year, COUNT(*) AS files
FROM scan_results
WHERE CreationTime >= '2015-01-01'
GROUP BY YEAR(CreationTime)
ORDER BY year;
```

---

## 2. The dormancy problem

**Hook:** *"70% of data here hasn't been touched in over 3 years. That's dead weight you're paying premium storage for."*

- **Metric:** files where `LastAccessTime < today - 3 years` → **6,948,757 / 9,962,001 = 69.8%**
- **Source:** scan `LastAccessTime`
- **Widget:** big KPI tile + ring gauge (Dormant / Recent)
- **Breakdown widget:** dormancy % by top-level folder (Archive ~75%, Users ~55%, IT/Logs ~5%)

```sql
SELECT
  SUM(CASE WHEN LastAccessTime < DATEADD(year, -3, GETDATE()) THEN 1 ELSE 0 END) AS dormant,
  SUM(CASE WHEN LastAccessTime < DATEADD(year, -5, GETDATE()) THEN 1 ELSE 0 END) AS dormant_5y,
  COUNT(*) AS total
FROM scan_results;
```

---

## 3. Ghost owners (10% of files owned by ex-employees)

**Hook:** *"Nearly a million files here are owned by accounts that don't exist anymore. 40 ex-employees left, their AD accounts got deleted, and their file ownership became unresolvable orphan SIDs."*

- **Metric:** file count where `OwnerResolved = false` → **999,072 files (10.0%)**, across ~40 unique orphan SIDs
- **Source:** manifest `b="OrphanSid"`, or scanner flag for unresolved SID
- **Widget:** table, "Top 20 orphan SIDs by file count"; columns: SID resolution hint, file count, total bytes
- **Sub-widget:** dept distribution — which depts have the most orphan-owned files

```sql
SELECT OwnerSid, OwnerNameHint, COUNT(*) AS files, SUM(Bytes) AS bytes
FROM scan_results
WHERE OwnerResolved = false
GROUP BY OwnerSid, OwnerNameHint
ORDER BY files DESC
LIMIT 20;
```

---

## 4. Lazy AGDLP (security anti-pattern)

**Hook:** *"AGDLP is the Windows best practice — users into Global groups, Global into Domain Local, Domain Local on ACLs. But 336 folders here have `GG_` global groups sitting directly on ACLs — someone cut the corner, now you can't re-org without breaking access."*

- **Metric:** ACE table where trustee starts with `GG_` → **336 folder-level ACEs**
- **Compare:** proper AGDLP via `DL_Share_*` → 4,924 ACEs (15× more — the healthy majority)
- **Widget:** Sankey or stacked bar — ACE trustees bucketed into `{ProperAGDLP (DL_), LazyGG, OrphanSID, Everyone, Deny}`
- **Story:** "5% of your ACLs are the weak link"

```sql
SELECT
  CASE
    WHEN Trustee LIKE 'DEMO\\DL_Share_%' THEN 'ProperAGDLP'
    WHEN Trustee LIKE 'DEMO\\GG_%'       THEN 'LazyGG'
    WHEN IsOrphanSid = 1                  THEN 'OrphanSID'
    WHEN Trustee = 'Everyone'             THEN 'Everyone'
    WHEN AceType = 'Deny'                 THEN 'Deny'
    ELSE 'Other'
  END AS pattern,
  COUNT(*) AS aces
FROM folder_aces
GROUP BY pattern
ORDER BY aces DESC;
```

---

## 5. Sensitive folders with broken inheritance

**Hook:** *"Every dept has a `Sensitive` folder where someone broke inheritance to lock it down — but they also left `GG_<Dept>` directly on the ACL. Your 'confidential' folder is still readable by the whole department."*

- **Metric:** folders with inheritance explicitly disabled → **20** (Sensitive, Board, Public, IT/Credentials, Temp deterministic breaks; plus ~5% random)
- **Source:** folder ACL scan flag `InheritanceDisabled`
- **Widget:** callout list or table, one row per broken-inheritance folder with current permissions summary

---

## 6. Temp folders (Deny + Everyone)

**Hook:** *"Every department's `Temp` folder has `Everyone: Modify` and a Deny ACE for contractors — the classic mess of patching access one exception at a time."*

- **Metric:** folders with `Everyone:(M)` + `DENY` ACE combined → matches per-dept Temp folders
- **Source:** folder ACE scan
- **Widget:** alert card — "88 Deny ACEs across the tree, 65 Everyone-writable folders"

---

## 7. Service account sprawl

**Hook:** *"10 service accounts touching data across the tree, no documentation on which one needs which access. `svc_antivirus` has permissions on every single Temp folder. `svc_backup` owns 500K files in Archive and nobody remembers why."*

- **Metric:** files owned by service accounts → **499,064 (5.0%)** across 10 accounts
- **Source:** manifest `b="ServiceAccount"`, or owner name matching `svc_*`
- **Widget:** table of service accounts × folders touched, heatmap optional

```sql
SELECT Owner, COUNT(*) AS files, COUNT(DISTINCT FolderPath) AS folders_touched
FROM scan_results
WHERE Owner LIKE 'DEMO\\svc_%'
GROUP BY Owner
ORDER BY files DESC;
```

---

## 8. The IT bloat problem

**Hook:** *"IT is 5% of the files but 18% of the bytes — `.bak` files up to 2 GB, `.exe` installers, log archives. A quarter of your storage goes to backup sprawl in one department."*

- **Metric:** bytes per top-level folder → **IT = 15.2 TB (17.7% of 85.6 TB total)** despite only 481 K files
- **Widget:** treemap or horizontal stacked bar, bytes per dept
- **Drill-down:** extension breakdown of IT — `.bak` alone is the majority

```sql
SELECT Dept, COUNT(*) AS files, SUM(Bytes)/1e12 AS tb
FROM scan_results
GROUP BY Dept
ORDER BY tb DESC;
```

---

## 9. File-class behavior mix

**Hook:** *"Not all files are created equal. 34% sit dormant, 17% see daily activity, 11% were written once and never read again — your access tiering is doing nothing."*

- **Metric:** file-class distribution (in manifest `c` field, or derivable from WT/AT gaps)
- **Widget:** donut or horizontal bar — classes: Dormant, Active, LegacyArchive, Aging, WriteOnceNeverRead, Reference, WriteOnceReadMany
- **Numbers** (of 9.99M):
  - Dormant 33.7%
  - Active 17.2%
  - LegacyArchive 11.2%
  - Aging 10.4%
  - WriteOnceNeverRead 10.3%
  - Reference 10.3%
  - WriteOnceReadMany 6.9%

---

# Suggested dashboard layout

```
┌─────────────────────────────────────────────────────────────────┐
│ KPI ROW                                                          │
│  9.96M files  │  85.6 TB logical  │  69.8% dormant │ 10% orphan │
├──────────────────────────┬──────────────────────────────────────┤
│ Files by CT year         │ Bytes by department (treemap)         │
│ [bar chart, 2019 flagged]│ [IT bloat visible]                    │
├──────────────────────────┼──────────────────────────────────────┤
│ ACL pattern sankey       │ Top 20 orphan owners (table)          │
│ ProperAGDLP / LazyGG /   │                                       │
│ Orphan / Everyone / Deny │                                       │
├──────────────────────────┴──────────────────────────────────────┤
│ File-class mix (donut) │ Dormancy by folder pattern (heatmap)    │
└─────────────────────────────────────────────────────────────────┘
```

# Sample widget specs (JSON, tool-neutral)

```json
{
  "widget": "files_by_ct_year",
  "type":   "bar",
  "title":  "Files by creation year",
  "data_source": {
    "kind":  "sql",
    "query": "SELECT YEAR(CreationTime) AS year, COUNT(*) AS files FROM scan_results GROUP BY YEAR(CreationTime) ORDER BY year"
  },
  "x": { "field": "year",  "type": "ordinal" },
  "y": { "field": "files", "type": "quantitative", "format": "0,0" },
  "annotations": [
    { "x": 2019, "text": "Deadbeat Corp acquisition",
      "style": "callout", "color": "#e67e22" }
  ]
}
```

```json
{
  "widget": "ownership_mix",
  "type":   "donut",
  "title":  "File ownership",
  "data_source": {
    "kind":    "aggregation",
    "groupBy": "ownership_bucket",
    "field":   "file_count"
  },
  "slices": [
    { "label": "Dept group",       "color": "#3498db", "expected_pct": 55 },
    { "label": "User",             "color": "#2ecc71", "expected_pct": 25 },
    { "label": "Orphan SID",       "color": "#e74c3c", "expected_pct": 10 },
    { "label": "Builtin Admin",    "color": "#95a5a6", "expected_pct": 5  },
    { "label": "Service account",  "color": "#f39c12", "expected_pct": 5  }
  ]
}
```

```json
{
  "widget": "dormancy_heatmap",
  "type":   "heatmap",
  "title":  "% dormant files by folder area",
  "rows":   "top_level_folder",
  "cols":   "age_bucket",
  "value":  "pct_dormant",
  "buckets": [
    { "name": "Recent (<1y)",   "max_days": 365 },
    { "name": "Aging (1-3y)",   "max_days": 1095 },
    { "name": "Dormant (3-5y)", "max_days": 1825 },
    { "name": "Ancient (>5y)",  "max_days": 999999 }
  ]
}
```

# Common queries (SQL-ish pseudo)

```sql
-- KPI tiles
SELECT COUNT(*)                AS total_files,
       SUM(Bytes)/1e12         AS total_tb_logical,
       AVG(CASE WHEN LastAccessTime < DATEADD(year,-3,GETDATE()) THEN 1.0 ELSE 0.0 END) AS pct_dormant,
       AVG(CASE WHEN OwnerResolved = false THEN 1.0 ELSE 0.0 END) AS pct_orphan
FROM scan_results;

-- Temporal distribution for the year chart
SELECT YEAR(CreationTime) AS year, COUNT(*) AS files
FROM scan_results
GROUP BY YEAR(CreationTime);

-- ACL pattern sankey source
SELECT pattern, COUNT(*) AS count FROM folder_aces_classified GROUP BY pattern;

-- Treemap of bytes by dept
SELECT Dept, SUM(Bytes)/1e9 AS gb FROM scan_results GROUP BY Dept;

-- Orphan owner table
SELECT OwnerSid, OwnerNameHint, COUNT(*) AS files, SUM(Bytes) AS bytes
FROM scan_results
WHERE OwnerResolved = false
GROUP BY OwnerSid, OwnerNameHint
ORDER BY files DESC LIMIT 20;

-- File-class donut
SELECT FileClass, COUNT(*) AS files FROM scan_results GROUP BY FileClass;

-- Service-account footprint
SELECT Owner, COUNT(*) AS files FROM scan_results
WHERE Owner LIKE 'DEMO\\svc_%' GROUP BY Owner ORDER BY files DESC;
```

# Color / emphasis guidance

- **Alert / risk colors** for: Orphan SID, Everyone, Deny, Lazy GG, inheritance broken
- **Neutral** for: Dept Group, Builtin Admin, Proper AGDLP
- **Warm highlight** (orange) specifically for the 2019 Deadbeat year — this is the demo's signature moment
- **Dormant** in gray / faded — visually "old"
- **Active / Recent** in green or bold blue

# What the dashboard must NOT show (realism guardrails)

- Don't expose raw SIDs verbatim (they're synthetic but still look noisy). Resolve to "Former employee: aaliyah.leon" style hints.
- Don't show the `S:\Shared` UNC path prominently — demo pitch is the generic "customer file share."
- File-body content is random / magic-bytes only. Do not preview file contents or claim document-level search/insight.
- See [`build-recipe-and-caveats.md`](build-recipe-and-caveats.md) for the full don't-say list.

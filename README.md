# pan-demo-data

Generate a realistic, messy enterprise file share for Panzura Symphony demos, scan testing, and dashboard development.

Builds an Active Directory population, a department folder tree with engineered ACL mess, and millions of sparse files with coherent historical timestamps — all at up to 10 M files / ~85 TB logical inside ~9 hours on a single host.

## Repository layout

```
pan-demo-data/
├── PanzuraDemo/            ← canonical module (v4.1.0). Import this.
├── build-10M.ps1           ← layered 4-pass production build recipe
├── spot-check.ps1          ← post-build verification (100 files + 10 folders)
├── docs/
│   ├── V4_SPEC.md          ← full technical spec + 24-entry decision log
│   └── demo-dataset/       ← handoff pack for dashboard designers & architects
├── RESUME.md               ← session state / "where did we leave off"
├── CHANGELOG.md
└── CLAUDE.md               ← canonical instructions for Claude Code sessions
```

## Quick start

Elevated **PowerShell 7.5+** session (NOT Windows PowerShell 5.1 — module fails silently on 5.1).

```powershell
# Always: import the module first
Import-Module 'C:\path\to\pan-demo-data\PanzuraDemo\PanzuraDemo.psd1' -Force

# Smoke validation (~16 s, 4 depts, 2000 files)
Invoke-DemoPipeline -Config smoke -Scenario Smoke -Phase All
Test-DemoSmokeVerification -Config (Import-DemoConfig -Path smoke)
```

If smoke passes, run the full 10 M build:

```powershell
# Wipe any prior state first
$cfg = Import-DemoConfig -Path default
Reset-DemoEnvironment -Config $cfg -IncludeShare -IncludeLegacyGroups -Confirm:$false
Get-ChildItem 'S:\Shared' -Force | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }

# Run the layered build (~8.5 h)
pwsh -NoProfile -File '.\build-10M.ps1'

# Spot-check 100 files + 10 folders after
pwsh -NoProfile -File '.\spot-check.ps1'
```

The build orchestrator runs four layered file-generation passes (LegacyMess -10y, YearSpread -10y, RecentSkew -3y, Deadbeat Corp 2019 acquisition cohort) plus AD populate, folders, orphanize, and final report. See `build-10M.ps1` inline for the knobs.

## Requirements

- Windows with an `S:` drive (NTFS, sparse-file support). S: is where `S:\Shared` + the SMB share live.
- PowerShell 7.5+ (elevated). `powershell` (5.1) silently fails module import.
- RSAT / `ActiveDirectory` module on the admin host.
- AD domain you can write test OUs into (`demo.panzura` on the reference host, under `OU=DemoCorp`).

## What to read next

| If you're… | Read |
|---|---|
| Building dashboards / reports for the demo | [`docs/demo-dataset/`](docs/demo-dataset/) |
| An architect tuning the dataset shape | [`docs/demo-dataset/build-recipe-and-caveats.md`](docs/demo-dataset/build-recipe-and-caveats.md) + [`docs/V4_SPEC.md`](docs/V4_SPEC.md) |
| Picking up a prior session | [`RESUME.md`](RESUME.md) |
| A Claude Code agent | [`CLAUDE.md`](CLAUDE.md) |
| Tracing the full decision history | [`docs/V4_SPEC.md`](docs/V4_SPEC.md) §18 |

## Safety

- These scripts change AD and NTFS. Use in a lab / disposable environment. The reference host is `PANZURA-SYM02`, domain `demo.panzura`, isolated from any production directory.
- All destructive operations require explicit flags or `-Confirm:$false`.
- Demo-invariant don't-regress items (no `-ClearExisting`, AGDLP wiring, timestamp write-order) are documented in [`CLAUDE.md`](CLAUDE.md) and [`docs/V4_SPEC.md`](docs/V4_SPEC.md).

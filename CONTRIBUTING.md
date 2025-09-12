# Contributing

Thanks for contributing to the Panzura Demo Toolkit.

## Workflow

- Branch from `main`; use short feature branches (e.g., `feat/messy-mode`, `fix/share-acls`).
- Open PRs early; include a short summary and any test notes.
- Keep PRs scoped and reviewable; prefer incremental changes over large refactors.

## Local setup

- Windows, PowerShell 7.x (run as Administrator for most scripts)
- RSAT / `ActiveDirectory` module installed
- NTFS `S:` drive for share

## Coding standards (PowerShell)

- Follow PSScriptAnalyzer (we include settings and a runner). Fix warnings where reasonable.
- Prefer clear names (no abbreviations), early returns, and guard rails (`-WhatIf`, `-Confirm`).
- Keep functions small; avoid deep nesting; handle errors meaningfully.
- Match existing formatting (indent, wrapping). No trailing spaces.

## Testing

- Smoke test each script: `-WhatIf` where applicable; small `-MaxFiles` for generators.
- Use `sanity.ps1` and reporting scripts where available.

## Safety

- These scripts mutate AD/NTFS. Use a lab environment.
- Defaults should be safe; only destructive actions when explicitly requested.

## Commit conventions

- Use concise subject lines; reference scripts/areas touched.
- Example: `feat(files): add -Seed option for reproducibility`.


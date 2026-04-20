# Demo dataset — handoff pack for design & architecture

**Purpose:** everything a designer or architect needs to build reports, dashboards, and visualizations for the Panzura Symphony demo on top of the generated 10M-file messy NAS.

**Build this pack describes:**
- Host: `PANZURA-SYM02` · domain `demo.panzura` · share `\\PANZURA-SYM02\Shared` (root `S:\Shared`)
- Generator version: **PanzuraDemo v4.1.0**
- Build window: **2026-04-19 18:07 → 2026-04-20 02:53** (8 h 46 m wall clock)
- Result: **9,962,001 files · 85.6 TB logical · 2,693 folders · 361 users across 15 departments**

## Who reads what

| Audience | Start with |
|---|---|
| Dashboard / chart designer | [`demo-narrative-and-widgets.md`](demo-narrative-and-widgets.md) — storylines, suggested widgets, sample JSON + SQL |
| Solutions architect / demo operator | [`build-recipe-and-caveats.md`](build-recipe-and-caveats.md) — how the dataset was made + what *not* to claim on stage |
| Anyone needing ground-truth numbers | [`dataset-snapshot.md`](dataset-snapshot.md) — actual counts, bytes, distributions, sample paths |

## Raw sources on the host (cite these, don't copy)

| File | What's in it |
|---|---|
| `build-10M.log` (repo root) | Phase-by-phase wall clock, per-layer counts, errors, final `Get-DemoReport` output |
| `logs/manifest_*.jsonl` | Per-file record: path, size, owner, ownership bucket, timestamp class, CT/WT/AT — four files, one per layer |
| `logs/plan_*.jsonl` | Pre-creation file plan (same schema, lets you see what was *intended* vs. what landed) |
| `PanzuraDemo/config/default.psd1` | The canonical config (dept weights, ACL pattern ratios, file classes, etc.) |
| `docs/V4_SPEC.md` | Deep spec + decision log (24 technical decisions). Architects: read §18 for rationale |

## Cross-refs

- Generator repo: [`/README.md`](../../README.md)
- Technical spec: [`/docs/V4_SPEC.md`](../V4_SPEC.md)
- Session history / reproduction: [`/RESUME.md`](../../RESUME.md)
- Developer setup: [`/DEVELOPMENT.md`](../../DEVELOPMENT.md)

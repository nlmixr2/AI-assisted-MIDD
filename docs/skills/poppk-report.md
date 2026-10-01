# `poppk-report`

Builds one PDF for a QC'd popPK version: every table and figure exactly as QC'd, the model
trail and final model as recorded in the spec, the source files and provenance, and the full
code of the version's scripts. It is the popPK counterpart of [pk-nca-report](pk-nca-report.md)
and uses the same report engine (ISoP pmx-report-template cover, headers and glossary). It has
no narrative chapters and never refits a model.

## When it is used

- You ask for a popPK report, a MAR, or one PDF with the tables, figures and code of a popPK
  version.
- Only after the version has passed QC (`run_version("poppk", n)` in [pk-project](pk-project.md)).
- New tables or figures belong in the version, not in the report: add them with `new_tlf()`.

## What it produces

| File or object | Location | Contents |
|---|---|---|
| Report project | `output/poppk/v{n}/MAR/` | Quarto book: `_quarto.yml`, `_setup.R`, `index.qmd`, `sections/1_tables.qmd` to `4_code.qmd`, `abbr.tex`, `engine/` |
| `poppk-v{n}-report.pdf` | `output/poppk/v{n}/MAR/report/` | The rendered report |
| `report-provenance.yaml` | `output/poppk/v{n}/MAR/` | PDF hash, spec path, hash and QC status, database payload hash, final model and OFV, QC run used, Quarto version |

| Chapter | Content |
|---|---|
| Overview | version at a glance: analysis, source data, participants and records, model trail, final model and OFV, QC result and status, spec |
| 1 Tables | every table in the spec (parameter table, model development table, custom tables), from its QC'd `gt` object |
| 2 Figures | every figure page (GOF, individual fits, ETA, VPC, ggPMX, traceplot, model diagram, custom figures), from its QC'd image |
| 3 Source files and provenance | verification; model trail, final model, recorded rationale, acceptance checks and caveats; provenance hashes; model dataset summary; fit archives; packages; run logs; file manifest |
| 4 Code | every script in run order, with its hash checked against the spec |

## How to use it

```r
source(".posit/assistant/skills/poppk-report/scripts/poppk_report.R")
create_poppk_report(2L)   # once per version; refuses to overwrite an existing MAR/
render_poppk_report(2L)   # refuses a version that changed since its spec or has no passing QC run
```

Cover fields come from `project.yaml`'s `report:` block; `report.poppk_report_number` sets this
report's number (default: `report.report_number`).

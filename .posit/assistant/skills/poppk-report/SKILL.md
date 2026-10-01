---
name: poppk-report
description: Renders one PDF of a QC'd popPK version with all its tables, figures, the model trail and final model, source files, provenance and code. Use when the user asks for a popPK report, MAR, or a PDF package of a popPK version.
---

# Population PK outputs report (one PDF)

## Overview

The popPK counterpart of `pk-nca-report`. Collects one QC'd popPK version
(`script/poppk/v{n}/` → `output/poppk/v{n}/`, see `poppk-estimation`) into a single PDF:
**tables, figures, source files and provenance, and code**. There are no narrative chapters:
nothing in it is written after the analysis. The cover page, headers/footers and glossary come
from the ISoP **pmx-report-template**
(<https://github.com/isop-phmx/pmx-report-template>, MIT, `assets/LICENSE-pmx-report-template`).

The report is **decoupled**: it reads the version's database (`read_poppk_db()`, payload hash
checked), spec, display objects and scripts, and never refits a model.

- **Tables and figures are the QC'd objects, not copies**: the `gt` tables and figure page
  images docorator saved as `output/poppk/v{n}/{tables,figures}/*.RDS`, each checked against
  the hash the spec records (`display_rds`). Every output the spec lists is included, in spec
  order, so a custom output (`new_tlf()`) appears without editing the report.
- **The model trail, final model, rationale and acceptance checks** are printed from the spec
  (`models`, `final_model`, `diagnostics.caveats`), as QC reviewed them.
- `render_poppk_report()` refuses to render unless the version still matches its spec and its
  latest QC run passed.

## Core Process

Helpers: `file:///{skill_dir}/scripts/poppk_report.R` (create/render) and
`file:///{skill_dir}/scripts/poppk_report_helpers.R` (popPK data summary and spec tables). The
shared report helpers (display objects, logs, QC result, Markdown tables) are
`pk-nca-report/scripts/nca_report_helpers.R`, sourced by the report's `_setup.R`.

1. **Prerequisites:** the popPK version passed `run_version("poppk", n)` (pk-project), and
   `project.yaml` has a `report:` block (see `pk-nca-report`). `report.poppk_report_number`
   sets this report's number (default: `report.report_number`).
2. **Scaffold** (once per version) and **render**:

```r
source(".posit/assistant/skills/poppk-report/scripts/poppk_report.R")
create_poppk_report(2L)        # -> output/poppk/v2/MAR/ ; refuses to overwrite an existing MAR
render_poppk_report(2L)        # verify spec + outputs + latest QC run, then quarto render
# -> output/poppk/v2/MAR/report/poppk-v2-report.pdf and MAR/report-provenance.yaml
render_poppk_report(2L, require_qc = FALSE)   # draft only, before QC has passed
```

   `report-provenance.yaml` records the PDF hash, the spec hash and QC status, the database
   payload hash, the final model and its OFV, the QC run used, and the Quarto version.

## What the PDF contains

| Chapter | Content (all from the version, nothing typed in) |
|---|---|
| Overview (`index.qmd`) | what the document is, its parts, and a version-at-a-glance table: analysis, source data, participants / observation / dose records, model trail length, final model and OFV, QC result and status, spec |
| 1 Tables | every `outputs.tables` entry (parameter table, model development table, custom tables), printed from its QC'd `gt` object |
| 2 Figures | every `outputs.figures` entry, every page, from its QC'd image, captioned with the spec description |
| 3 Source files and provenance | verification and QC result; model trail (OFV, dOFV, parameters, covariance step), final model with the recorded rationale, acceptance checks and caveats; provenance hashes; model dataset summary and the data-validation report; fit archives; packages; run logs; file manifest |
| 4 Code | the full text of every script in run order, each with its hash and whether it matches the spec |

## Rules

Same as `pk-nca-report`:

- **Report a QC'd version** (`require_qc = TRUE`); a draft must not be circulated as final.
- **Never compute or refit in the report.** New results belong in the version (a new version if
  the analysis changes); a `tbl-*.R`/`fig-*.R` added with `new_tlf()` appears automatically.
- **No narrative text.** Interpretation belongs to the analyst, outside the QC'd package.
- **Changes to one report go in its `MAR/` files; changes every future report should get go in
  `assets/mar-template/`.**
- **Keep the provenance fields.** The QC status comes from the spec; change it by QC sign-off,
  never by editing the report.

## Debugging quick reference

See `pk-nca-report` (same engine). popPK-specific:

| Symptom | Likely cause |
|---|---|
| `spec/poppk/v{n}.yaml not found` | run the version first (`run_version("poppk", n)`) |
| `popPK db entry for v{n} ... failed hash verification` while rendering | the version's database changed after it was written; re-run the version |
| `popPK database not found` | on a fresh clone the database is rebuilt from `db/snapshot/`; otherwise run the version |
| A report of an older version shows the final model's rationale as "--" | its spec predates `final_model.rationale` |

Verified with Quarto 1.9.36, TinyTeX (lualatex), nlmixr2 7.0.1.

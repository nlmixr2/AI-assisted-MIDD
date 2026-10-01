---
name: pk-nca-report
description: Renders one PDF of a QC'd NCA version with all its tables, figures, source files, provenance and code. Use when the user asks for an NCA report, MAR, or a PDF package of an NCA version.
---

# NCA outputs report (one PDF)

## Overview

Collects one QC'd NCA version (`script/nca/v{n}/` → `output/nca/v{n}/`, see `pk-nca`) into a
single PDF: **tables, figures, source files and provenance, and code**. There are no
narrative chapters (introduction, methods, discussion): nothing in it is written after the
analysis, so there is nothing to draft and nothing that can disagree with the QC'd outputs.
The cover page, headers/footers and glossary come from the ISoP **pmx-report-template**
(<https://github.com/isop-phmx/pmx-report-template>, MIT, `assets/LICENSE-pmx-report-template`).

The report is **decoupled**: it reads the version's database (`read_nca_db()`), spec, output
objects and scripts, and never re-runs PKNCA.

- **Tables and figures are the QC'd objects, not copies.** docorator saves the exact `gt`
  table or figure page images behind each PDF as `output/nca/v{n}/{tables,figures}/*.RDS`.
  The report prints those (`nca_table_display()` / `print_table_display()`, `qc_figure()`),
  each checked against the hash the spec records (`display_rds`).
- **Every output the spec lists is included**, in spec order, so a custom table or figure
  (`new_tlf()`) appears without editing the report. Figure captions are the spec's
  `outputs[].description`; multi-page figures show every page.
- `render_nca_report()` refuses to render unless the version still matches its spec and its
  latest QC run passed, so the PDF contains exactly what passed QC.

## Core Process

Helpers: `file:///{skill_dir}/scripts/nca_report.R` (create/render) and
`file:///{skill_dir}/scripts/nca_report_helpers.R` (reading the QC'd objects, logs and hashes).

1. **Prerequisites:**
   - The NCA version is complete and ready for QC: `run_version("nca", n)` passed (pk-project).
   - `project.yaml` has a `report:` block for the cover page: `report_number`, `drug_name`,
     `indication`, `sponsor`, `company`, `authors`, `reviewers`, `approvers`, `status`, and
     optionally `title` and `study_number` (defaults: the analysis title and the study ID).
     Missing or `<...>` values print as "TBD"; a missing or `<...>` `status` becomes "DRAFT".
2. **Scaffold** the report project (once per version):

```r
source(".posit/assistant/skills/pk-nca-report/scripts/nca_report.R")
create_nca_report(1L)          # -> output/nca/v1/MAR/ ; refuses to overwrite an existing MAR
```

3. **Render** (nothing to write in between):

```r
render_nca_report(1L)          # verify spec + outputs + latest QC run, then quarto render
# -> output/nca/v1/MAR/report/nca-v1-report.pdf and MAR/report-provenance.yaml
render_nca_report(1L, require_qc = FALSE)   # draft only, before QC has passed
```

   `report-provenance.yaml` records what the PDF was built from: the PDF hash, the spec hash
   and QC status, the database payload hash, the QC run used, and the Quarto version.

## What the PDF contains

| Chapter | Content (all from the version, nothing typed in) |
|---|---|
| Overview (`index.qmd`) | what the document is, a list of its parts, and a version-at-a-glance table: analysis, source data, participants and records, QC suite result, QC status, spec |
| 1 Tables | every `outputs.tables` entry of the spec, printed from its QC'd `gt` object, with its source file and script |
| 2 Figures | every `outputs.figures` entry, every page, from its QC'd image (legacy PNG figures included as files), captioned with the spec description |
| 3 Source files and provenance | verification statement and QC result; provenance table (data, database, script and spec hashes); dataset summary and the `pk-data-validation` report; package versions; latest run log and status of each script (`pk-nca-logging` run summary); file manifest of scripts, tables, figures and their objects with hashes |
| 4 Code | the full text of every script in run order (analysis, figures and tables, `generate-spec.R`), each with its hash and whether it matches the spec |

## Layout

```
output/nca/v{n}/MAR/
  _quarto.yml            book config + cover metadata (report-number, drug-name, ... from project.yaml)
  _setup.R               sourced by every chapter: reads project.yaml, the NCA database, spec, QC result
  index.qmd              overview
  sections/1_tables.qmd, 2_figures.qmd, 3_source.qmd, 4_code.qmd
  abbr.tex               glossary (ISoP list + NCA terms); use \gls{KEY} in text
  engine/                header.tex (incl. code-listing line wrapping), partials/{title,before-body,toc}.tex
  report/nca-v{n}-report.pdf    rendered output
  report-provenance.yaml        what the PDF was built from
```

The MAR folder lives inside the version's output folder, but it is not part of the version's
spec. It is generated *after* QC, from the QC'd results, so creating or re-rendering a report
never invalidates the version's QC.

## Rules

- **Report a QC'd version.** Render normally with `require_qc = TRUE`. A draft
  (`require_qc = FALSE`) must not be circulated as final.
- **Never compute in the report.** New numbers, tables or figures belong in the version (a
  new version if the analysis changes): add a `tbl-*.R`/`fig-*.R` with `new_tlf()` and it
  appears in the report automatically.
- **No narrative text.** Don't add introduction, results or discussion prose to this
  document. Interpretation belongs to the analyst, outside the QC'd package.
- **Figures and tables are the QC'd objects.** Don't re-plot or rebuild one in the report.
- **Changes to one report go in its `MAR/` files.** Changes that every future report should
  get go in `assets/mar-template/` (the skill).
- **Keep the provenance fields.** The QC status on the cover and in chapter 3 comes from
  the spec. Change it by QC sign-off in the spec, never by editing the report.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `Output file(s) inconsistent with spec` / `does not match its recorded hash` | the version changed after its spec was written; re-run it (`run_version()`) or report a new version |
| `has no passing QC run` | run `run_qc("nca", n)`; use `require_qc = FALSE` only for a draft |
| `Figure not found` / `Display object not found` | the version's `fig-*.R` didn't run, or its `.RDS` is missing; re-run the version |
| Code lines run off the page | `engine/header.tex` must load `fvextra` and redefine `Highlighting` with `breaklines` (the template does) |
| Run log status "incomplete" | that script's latest log never reached `nca_log_stop()`; re-run the version |
| A table floats away from its heading | a report-only table was produced as raw LaTeX; use `report_table()` (Markdown). Version tables go through `print_table_display()`, which pins them |
| `... does not match the hash recorded in the spec` / `not written in the same run` | a `tbl-*.RDS` changed after QC (or was regenerated without its PDF); re-run the version |
| `Table 'tbl-x' is not recorded in the spec` | that table script is missing from the version or didn't produce output |
| Cover field blank | a value like `<TBD>` is read as an HTML tag and dropped; fill in `project.yaml`'s `report:` block or `MAR/_quarto.yml` |
| LaTeX package missing (e.g. `tabularray`) | Quarto installs it on first render with TinyTeX; otherwise `tlmgr install tabularray mdframed glossaries threeparttable tex-gyre` |

Verified with Quarto 1.9.36, TinyTeX (lualatex), knitr 1.50, PKNCA 0.12.1.

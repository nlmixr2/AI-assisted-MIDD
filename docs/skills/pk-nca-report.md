# `pk-nca-report`

Builds one PDF for a QC'd NCA version: every table and figure exactly as QC'd, the source
files and provenance, and the full code of the version's scripts. It has no narrative
chapters, so nothing in it is written after the analysis and nothing can disagree with the
QC'd outputs.

## When it is used

- You ask for an NCA report, a MAR, an outputs or TLF package, a Quarto or PDF report, or
  one PDF with the tables, figures and code of an NCA version.
- Only after the version has passed QC (`run_version("nca", n)` in [pk-project](pk-project.md)).
- New tables or figures belong in the version, not in the report: add them with `new_tlf()`
  ([pk-project](pk-project.md)), see [pk-nca-tables](pk-nca-tables.md) and
  [pk-nca-figures](pk-nca-figures.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| Report project | `output/nca/v{n}/MAR/` | Quarto book: `_quarto.yml`, `_setup.R`, `index.qmd`, `sections/1_tables.qmd` to `4_code.qmd`, `abbr.tex`, `engine/` |
| `nca-v{n}-report.pdf` | `output/nca/v{n}/MAR/report/` | The rendered report |
| `report-provenance.yaml` | `output/nca/v{n}/MAR/` | What the PDF was built from: PDF hash, spec path, hash and QC status, database payload hash, the QC run used, Quarto version |

The PDF contains:

| Chapter | Content |
|---|---|
| Overview | what the document is, its parts, and a version-at-a-glance table (analysis, source data, participants and records, QC suite result, QC status, spec) |
| 1 Tables | every table listed in the spec, printed from its QC'd `gt` object, with its source file and script |
| 2 Figures | every figure listed in the spec, every page, from its QC'd image, captioned with the spec description |
| 3 Source files and provenance | verification statement and QC result; provenance table (data, database, script and spec hashes); dataset summary and the data-validation report; package versions; latest run log and status of each script; file manifest with hashes |
| 4 Code | the full text of every script in run order, each with its hash and whether it matches the spec |

The MAR folder is not part of the version's spec. Creating or re-rendering a report never
invalidates the version's QC.

## How to use it

1. Make sure the version passed QC, and fill in the `report:` block of `project.yaml` for the
   cover page: `report_number`, `drug_name`, `indication`, `sponsor`, `company`, `authors`,
   `reviewers`, `approvers`, `status`, and optionally `title` and `study_number`. Missing or
   `<...>` values print as "TBD"; a missing or `<...>` `status` becomes "DRAFT".
2. Scaffold the report project (once per version):

   ```r
   source(".posit/assistant/skills/pk-nca-report/scripts/nca_report.R")
   create_nca_report(1L)   # -> output/nca/v1/MAR/
   ```

3. Check the cover metadata in `MAR/_quarto.yml` if needed, then render. There is nothing to
   write in between:

   ```r
   render_nca_report(1L)                       # verify, then quarto render
   render_nca_report(1L, require_qc = FALSE)   # draft only, before QC has passed
   ```

Typical prompts: "Make the NCA report for v1", "Build one PDF with the tables, figures and
code of NCA v3".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `create_nca_report(project_number, overwrite = FALSE)` | Copies `assets/mar-template/` to `output/nca/v{n}/MAR/` and fills the cover metadata from `project.yaml`. Needs `spec/nca/v{n}.yaml`; refuses to replace an existing MAR unless `overwrite = TRUE` |
| `render_nca_report(project_number, require_qc = TRUE, quarto = Sys.which("quarto"))` | Verifies the spec and outputs, checks the latest QC run, runs `quarto render`, writes `report-provenance.yaml` |
| `latest_qc_result()` | Reads the latest `qc-tests-*.xml` of the version |
| `nca_table_display()`, `nca_output_display()` | Load the QC'd `gt` table or figure object (`.RDS`) and check it against the hash in the spec (`display_rds`) |
| `print_table_display()` | Prints a QC'd table into the PDF, pinned under its heading |
| `run_log_table()`, `data_validation_report()` | Run-log status per script and the latest data-validation report, for chapter 3 |
| `report_table()` | Report-only tables as Markdown, so they stay under their heading |
| `scripts/nca_report.R`, `scripts/nca_report_helpers.R` | Create/render helpers, and helpers used inside the report |
| `assets/mar-template/` | The Quarto book template, built on the ISoP pmx-report-template (MIT, `assets/LICENSE-pmx-report-template`) |

## Rules and checks

- `render_nca_report()` refuses to render unless the spec matches its sidecar hash, every
  output matches its recorded hash and (with `require_qc = TRUE`) the latest QC run passed.
- A draft made with `require_qc = FALSE` must not be circulated as final.
- Never compute in the report. It reads the version's database (`read_nca_db()`), spec,
  output objects and scripts, and never re-runs PKNCA. New numbers go in the version (a new
  version if the analysis changes).
- No narrative text. Do not add introduction, results or discussion prose. Interpretation
  belongs to the analyst, outside the QC'd package.
- Tables and figures are the QC'd objects. Do not re-plot or rebuild them in the report.
- Every output listed in the spec is included, in spec order, so a custom `new_tlf()` output
  appears without editing the report.
- Changes to one report go in its `MAR/` files. Changes every future report should get go in
  the skill's `assets/mar-template/`.
- The QC status on the cover and in chapter 3 comes from the spec. Change it only by QC
  sign-off in the spec, never by editing the report.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Output file(s) inconsistent with spec` / `does not match its recorded hash` | The version changed after its spec was written. Re-run it (`run_version()`) or report a new version |
| `has no passing QC run` | Run `run_qc("nca", n)`. Use `require_qc = FALSE` only for a draft |
| `Figure not found` / `Display object not found` | A `fig-*.R` did not run, or its `.RDS` is missing. Re-run the version |
| `... does not match the hash recorded in the spec` / `not written in the same run` | A table or figure `.RDS` changed after QC. Re-run the version |
| Run log status "incomplete" | That script's latest log never reached `nca_log_stop()`. Re-run the version |
| Cover field blank | A value like `<TBD>` is read as an HTML tag and dropped. Fill in `project.yaml`'s `report:` block or `MAR/_quarto.yml` |
| LaTeX package missing (e.g. `tabularray`) | Quarto installs it on first render with TinyTeX; otherwise `tlmgr install tabularray mdframed glossaries threeparttable tex-gyre` |
| `Quarto CLI not found on PATH` | Install Quarto (1.4 or later, see AGENTS.md) |

The skill was verified with Quarto 1.9.36, TinyTeX (lualatex), knitr 1.50 and PKNCA 0.12.1.

## Related

- [pk-nca-qc-tests](pk-nca-qc-tests.md): the QC run the report requires
- [pk-nca-run-spec](pk-nca-run-spec.md): the spec the report verifies and reads
- [pk-nca-database](pk-nca-database.md), [pk-nca-tables](pk-nca-tables.md), [pk-nca-figures](pk-nca-figures.md)
- [pk-nca-logging](pk-nca-logging.md): run logs shown in chapter 3
- [SKILL.md](../../.posit/assistant/skills/pk-nca-report/SKILL.md)
- [NCA workflow guide](../pk-nca/README.md)

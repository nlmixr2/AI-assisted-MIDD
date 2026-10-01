---
name: pk-nca-tables
description: Creates production NCA tables (PK parameters, concentrations by nominal time) with tfrmt and docorator. Use when the user asks for NCA tables, PK parameter tables, concentration tables or TLF tables.
---

# Formatting NCA results tables with tfrmt and docorator

Companion to the `pk-nca` skill: takes the `ncaRes` (`PKNCAresults`) object produced by
`pk.nca()` and turns it into a formatted `gt` table (via `tfrmt`), optionally decorated
into a production-ready PDF/RTF display (via `docorator`).

## Packages

Verify both are installed (`requireNamespace("tfrmt", quietly = TRUE)`,
`requireNamespace("docorator", quietly = TRUE)`); install from CRAN if missing.
`docorator`'s PDF rendering additionally requires a LaTeX installation
(`tinytex::is_tinytex()`); fall back to `render_rtf()` if none is available.

## Standard table orientation

One row per participant (numeric ID order, stub column headed "Participant ID"), one
column per PK parameter or per nominal sample time, followed by summary-statistic rows
(N, Mean, Median, Min/Max, and for concentration tables also BLQ N/%BLQ) computed across
all participants. Use this by default unless the user asks for a transposed layout or to
omit the summary rows.

## Templates

Two ready-to-adapt, runnable scripts, following the `pk-nca` skill's versioned-script
convention: each is `script/nca/v{project_number}/tbl-<name>.R`, starts with
`read_nca_db(project_number)` (see the companion **pk-nca-database** skill) to get
`cObsData`/`ncaRes` back from the NCA results database — no PKNCA re-run needed — and
saves to `output/nca/v{project_number}/tables/tbl-<name>.pdf` — the output directory
mirrors the script directory, so each version keeps its own tables; no project-number
suffix on the file name (see `pk-nca-run-spec`'s Gotchas).

- `templates/tbl-pk-parameters.R` — rows = participants + summary stats, columns = every
  requested PK parameter; column labels come from `display_names` (EDIT block) plus the
  units PKNCA attaches to each result (`PPORRESU`), so adding a parameter needs no label edit.
- `templates/tbl-conc-by-nominal-time.R` — rows = participants + summary stats (including
  BLQ N/%BLQ), columns = nominal sample time under a spanning header, paginated into a
  multi-page PDF. Nominal times and the LLOQ (BLQ rule) come from `project.yaml`'s `sampling:`
  block via `assign_nominal_time()`, shared with the `pk-nca-figures` mean plots, so table and
  figures agree.

**Precision per parameter:** `param_digits` (EDIT block; default `tmax = 2`, others
`default_digits = 1`) applies to a parameter's participant rows and its Mean, Median and
(Min, Max) rows, so every column has one precision.

**Shell and helpers:** both templates source the shared TLF shell
(`pk-project/scripts/tlf_shell.R`) near the top. It provides `render_tlf()` (the same
header/footer as every figure, footer with "Source data: <file>", **11 pt serif**) and the
tfrmt helpers in `pk-project/scripts/tfrmt_helpers.R`, which every table template uses
instead of repeating tfrmt boilerplate:

| Helper | Replaces |
|---|---|
| `fs(frmt, label =, group =)` | `frmt_structure(group_val = ".default", label_val = ".default", ...)` |
| `frmt_dp(d)`, `frmt_sig3()`, `frmt_min_max(d)` | hand-written `frmt("xx.x")`, the 3-significant-figure `frmt_when()`, the `"({Min}, {Max})"` `frmt_combine()` |
| `summary_ard(data, value, by, ...)` | the N / Mean / Median / Min / Max `summarise()` + `pivot_longer()`; extra statistics in `...` (e.g. `BLQ_N = sum(blq)`) |
| `stat_row_label(stat_type, labels)` | mapping Min and Max onto one "Min, Max" row (and renaming others) |
| `add_row_order(ard, levels)` | the `row_id` factor and `row_ord` sort key tfrmt needs |
| `participant_levels(ids)` | numeric ordering of participant IDs |
| `per_param_body_plan(params, digits)` | the per-parameter precision body plan of `tbl-pk-parameters` |
| `tlf_footnotes("text", N = "N = ...")` | `footnote_plan(footnote_structure(...), ...)`; a named note marks that row label |

Build a new table from these (via `new_tlf()`, pk-project); keep study choices (rows,
statistics, digits, footnote text) in the script's `EDIT` blocks.

docorator also saves the rendered `gt` object next to each PDF (`tbl-<name>.RDS`). Keep it:
`generate-spec.R` records its hash (`display_rds`), and `pk-nca-report` prints it so that
the report's tables are exactly these tables.

Both are scaffolded into `script/nca/v{n}/` by `new_version("nca")` (pk-project); headers use
`analysis_title("nca")` and units from `project.yaml`.

## Reference

Read `references/tfrmt-guide.md` for the tfrmt concepts the helpers wrap: how `tfrmt`'s
label/column/param/value roles work, why an explicit `sorting_cols` key is required,
span headers, combining two stats into one row, percent formatting, footnotes, manual
column-pagination, nominal-time derivation, and a full gotchas table. Consult it before
debugging unexpected `tfrmt` output or extending a template.

## References

- Companion skill: `pk-nca-database` — where `read_nca_db()` (used by both templates
  above) comes from; also lets a table script query across versions directly with SQL.
- tfrmt site: https://gsk-biostatistics.github.io/tfrmt/
- tfrmt examples article (AE/demography tables): https://gsk-biostatistics.github.io/tfrmt/articles/examples.html
- docorator site: https://gsk-biostatistics.github.io/docorator/
- Versions verified against: tfrmt 0.4.0, docorator 0.7.0 — re-check function signatures (`?tfrmt`, `?as_docorator`) if errors look like API drift. The serif font needs a docorator whose `render_pdf()` takes `header_latex` (present in the development version); with an older one `render_tlf()` says so and keeps docorator's default typewriter font.

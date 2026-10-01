---
name: pk-project
description: Sets up and runs versioned analyses in this template: study settings in project.yaml, NCA, popPK and simulation versions scaffolded from templates and run in order, QC status, and a project-wide results database. Use when starting a study or a new version, re-running a version, checking what is ready for QC, or asking questions across versions.
---

# PK analysis project: configuration, scaffolding, running

The glue for the `pk-nca-*` and `poppk-*` skills. It owns no analysis logic: it reads
`project.yaml`, copies the other skills' `templates/` into a new version folder, and runs
versions in the order every skill expects. Helpers:
`file:///{skill_dir}/scripts/project.R`.

## Starting a new study (fresh clone of the template)

1. Fill in `project.yaml` at the project root (template:
   `file:///{skill_dir}/assets/project-template.yaml`): `study.id`, analysis titles, and
   the units of the source data. `project_config()` refuses placeholder values (`<...>`).
2. Put the dataset(s) in `data/` (model files for simulation in `model/`).
3. Scaffold, edit, run:

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
new_version("nca")        # -> script/nca/v1/ (9 scripts) + tests/nca/v1/test-nca-qc.R
# edit the blocks marked "EDIT" (data file, column mapping, parameters, ...)
run_version("nca", 1L)    # analysis -> fig/tbl -> generate-spec -> QC suite
project_status()
```

## Functions

| Function | Does |
|---|---|
| `project_config()` | reads and validates `project.yaml`; every template calls it for titles/units |
| `analysis_title(type, cfg)` | the title for `"nca"`, `"poppk"`, `"poppk-sim"` (table headers, spec report title) |
| `new_version(type, n = next, from = NULL)` | creates `script/{type}/v{n}/` from the templates (or copies `v{from}`, rewriting its version number) and `tests/{type}/v{n}/`; refuses to overwrite |
| `run_version(type, n, qc = TRUE, only = NULL)` | runs `analysis-*.R` → other scripts (sorted) → `generate-spec.R`, each via `Rscript` in a fresh session, stopping at the first failure with the path of its log; then the QC suite |
| `run_qc(type, n)` | the version's QC-readiness suite (errors if not ready) |
| `list_versions(type)` | existing version numbers |
| `project_status()` | one row per version: spec present, `qc.status`, result of the latest QC run |
| `new_tlf(type, n, name, title, subtitle, footnotes, caption, description)` | scaffolds a **custom** `fig-*.R` / `tbl-*.R` into a version from `templates/custom-{figure,table}.R`, with the request's placeholders filled in; same TLF shell; registers the description in the version's `generate-spec.R` |
| `render_tlf(display, name, out_dir, cfg, type, source_data, title, subtitle, fontsize = 11, fig_dim = tlf_fig_dim)` (`scripts/tlf_shell.R`) | the shared docorator shell for every table and figure: analysis title + page header, "Source data:" + script + date-time footer, **11 pt serif** (`assets/tlf-serif.tex`; ggplot text set to serif by `tlf_serif()`). A figure's `title`/`subtitle` go here as centred header lines, never in the ggplot; a table's come from `tfrmt()`. Figures are `tlf_fig_dim` = `c(4.6, 8)` in (height, width); taller spills onto an extra, blank page |
| `update_project_db()`, `query_project_db(sql)` (`scripts/project_db.R`) | one project-wide DuckDB, `output/project.duckdb`, rebuilt automatically after every `run_version()` / `run_qc()`: every results table of every version and type (from the Parquet snapshots, with `project_number` and source `filename`), `versions` (QC state), `script_runs` (every script execution from the run logs) and `catalog`. Derived and git-ignored; never read by analysis scripts, so it cannot affect a version's hashes |
| `scripts/figure_helpers.R` (sourced by `tlf_shell.R`) | shared ggplot building blocks for every figure: `theme_tlf()` (theme_bw, 11 pt serif; `theme_pk()` and `theme_pmx()` are this theme), `tlf_out_dir(type, n)`, `lab_unit(what, unit, log =)` |
| `scripts/tfrmt_helpers.R` (sourced by `tlf_shell.R`) | shared tfrmt building blocks for every table: `fs()`, `frmt_dp()`, `frmt_sig3()`, `frmt_min_max()`, `summary_ard()`, `stat_row_label()`, `add_row_order()`, `participant_levels()`, `per_param_body_plan()`, `tlf_footnotes()` |

## Templates scaffolded per type

| Type | Scripts (from) |
|---|---|
| `nca` | `analysis-nca.R`, `fig-halflife-diagnostics.R` (pk-nca), `fig-mean-conc.R`, `fig-mean-conc-semilog.R`, `fig-ind-conc.R`, `fig-lambdaz.R` (pk-nca-figures), `tbl-pk-parameters.R`, `tbl-conc-by-nominal-time.R` (pk-nca-tables), `generate-spec.R` (pk-nca-run-spec) |
| `poppk` | `analysis-poppk.R`, `fig-gof.R`, `fig-individual-fits.R`, `fig-vpc.R`, `fig-eta.R`, `fig-traceplot.R`, `fig-pmx-diagnostics.R`, `fig-model-diagram.R` (poppk-estimation), `tbl-parameters.R`, `tbl-model-comparison.R` (poppk-tables), `generate-spec.R` (poppk-run-spec) |
| `poppk-sim` | `analysis-sim.R`, `fig-sim-profiles.R`, `fig-exposure.R`, `tbl-exposure-summary.R`, `generate-spec.R` (poppk-simulation) |

Templates contain `{{project_number}}`, replaced on scaffolding. Everything study-specific is
either read from `project.yaml` or sits in a block marked `EDIT`; the rest is the verified
standard pipeline — change it only deliberately, and prefer changing the template in the
skill (so every future version gets the fix) over one version's copy.

## Custom tables and figures

Every table and figure, standard or custom, uses the same shell and the same data rules. A
custom output is never a free-standing script: scaffold it with `new_tlf()`.

1. **Collect the placeholders from the request**, and ask for any that are missing:

   | Placeholder | Figure | Table |
   |---|---|---|
   | `name` | `fig-<short-name>` | `tbl-<short-name>` |
   | `title` | required | required |
   | `subtitle` | optional (e.g. population, scale) | optional |
   | `caption` / `footnotes` | `caption` (one line) | `footnotes` (character vector: abbreviations, statistics, rules) |
   | `description` | one line for the spec (defaults to the title) | same |
   | content | what is plotted: x, y, grouping, scale | rows (`label`), columns, statistics and their formats |

2. **Scaffold** into the version (still in development):

```r
new_tlf("nca", 3L, "tbl-halflife-summary", title = "Terminal Half-Life Summary",
        subtitle = "By span-ratio category",
        footnotes = c("Span ratio = regression interval / half-life.", "N = number of participants."))
```

3. **Fill in the EDIT block** from the version's database objects (listed in the script):
   - **Figure:** build a ggplot, or a list of ggplots for one page each.
   - **Table:** build a long ARD (`label`, `column`, `param`, `value`, `ord`) and a tfrmt
     `body_plan()`, with one `frmt` per `frmt_structure()`, `frmt_combine()` for
     "a [b, c]" cells, and `frmt_when()` for significant figures.
   - **Never recompute** results the analysis already produced.
4. **`run_version(type, n)`**, so the spec records the new output and QC covers it. If the
   version's spec is already under review, use `new_version(type, from = n)` instead.

## Rules

- **Scaffold, don't hand-write** a version folder: the QC suites check naming, logging, and version references that the templates already satisfy.
- **A change is a new version.** Use `new_version(type, from = n)` to iterate on version `n`; never edit a version whose spec exists (it is what QC reviews). Re-running the same version is fine while it is still being developed.
- **`run_version()` is the way to (re)run**, because order matters: `generate-spec.R` hashes everything produced before it. Use `only = "fig-vpc.R"` to re-run single scripts during development, then a full `run_version()` before QC.
- **Paths are relative to the project root**; run from there (`project.yaml` and `.here` mark it). `examples/abc-111/` is itself a project root (own `project.yaml`, `.here`, and a `.posit` link to the shared skills).
- Adding a new analysis type means: templates in a skill's `templates/`, a QC suite (`assets/test-*-qc-template.R` + create/run helpers), and one entry in `pk_types` in `scripts/project.R`.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `project.yaml not found` | not in the project root, or the file wasn't created from `assets/project-template.yaml` |
| `project.yaml: 'units.conc' is not set` | a placeholder `<...>` is still in `project.yaml` |
| `script/nca/v2 already exists` | pick another `n`, or continue editing that version |
| `analysis-nca.R failed (exit 1). Latest log: ...` | read that log — it has the R error and sessionInfo |
| A figure PDF has a blank first page (one page too many) | the figure is taller than the page leaves room for: keep `fig_dim` at `tlf_fig_dim` (4.6 in tall), don't pass docorator's 5 in |
| QC fails right after `run_version(..., only = )` | expected: the spec is stale until `generate-spec.R` re-runs; do a full `run_version()` |

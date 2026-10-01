# `pk-project`

The entry point of the template. It reads the study settings in `project.yaml`, scaffolds
new analysis versions from the other skills' templates, runs a version in the right order,
and reports the QC state of every version. It holds no analysis logic of its own.

## When it is used

- Starting a new study from a fresh clone of the template, or setting up `project.yaml`.
- Starting a new NCA, popPK or simulation version (`"nca"`, `"poppk"`, `"poppk-sim"`).
- Re-running a version, or running its QC-readiness suite.
- Asking "what versions exist?" or "what is ready for QC?".
- Adding a custom table or figure to a version (`new_tlf()`).
- For the analysis itself, use the analysis skills: [pk-nca](pk-nca.md) for NCA,
  `poppk-estimation` for popPK fitting, `poppk-simulation` for simulation. For checking a
  dataset, use [pk-data-validation](pk-data-validation.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| Version scripts | `script/{type}/v{n}/` | `analysis-*.R`, `fig-*.R`, `tbl-*.R`, `generate-spec.R`, copied from the skill templates (or from an earlier version) |
| QC suite | `tests/{type}/v{n}/` | the version's QC-readiness tests, created by the type's QC helper |
| Custom TLF script | `script/{type}/v{n}/fig-*.R` or `tbl-*.R` | from `templates/custom-figure.R` / `custom-table.R`, placeholders filled in |
| Rendered TLF | `output/{type}/v{n}/figures/` or `tables/` | `{name}.pdf` (RTF when TinyTeX is missing) and `{name}.RDS`, the display object |
| DB snapshot | `output/{type}/v{n}/db/snapshot/` | `<table>.parquet` per SQL table and `<meta>-payload.bin.xz` (written by the database skills through `db_snapshot_write()`) |
| Status table | returned by `project_status()` | one row per version: type, version, spec present, `qc_status`, result of the latest QC run |

## How to use it

1. Fill in `project.yaml` at the project root. Start from
   `.posit/assistant/skills/pk-project/assets/project-template.yaml` and replace every
   `<...>` value (study ID, analysis titles, data units). `project_config()` refuses
   placeholders for `study.id`, `units.conc`, `units.time` and `units.dose`.
2. Put the dataset in `data/` (model files for simulation go in `model/`).
3. Scaffold, edit and run, from the project root:

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
new_version("nca")              # script/nca/v1/ + tests/nca/v1/
# edit only the blocks marked EDIT (data file, column mapping, parameters, ...)
run_version("nca", 1L)          # analysis -> fig/tbl -> generate-spec -> QC suite
project_status()
```

4. To change something in a version, start a new one from it:

```r
new_version("nca", from = 1L)   # copies v1 to v2 and rewrites the version number
```

5. To add a custom table or figure to a version still in development:

```r
new_tlf("nca", 3L, "tbl-halflife-summary", title = "Terminal Half-Life Summary",
        subtitle = "By span-ratio category",
        footnotes = c("Span ratio = regression interval / half-life.", "N = number of participants."))
run_version("nca", 3L)
```

Fill in the script's EDIT block from the version's database objects, which are listed in
the script. Typical prompts: "set up the project for study ABC-111", "start a new popPK
version from v1", "re-run NCA v2", "which versions are ready for QC?", "add a table of
half-life by span-ratio category to NCA v3".

## The project database

`output/project.duckdb` holds every version and every run of the project in one DuckDB file.
`run_version()` and `run_qc()` rebuild it after every run, so it keeps filling as the project
grows; `update_project_db()` rebuilds it by hand.

| Table | Contents |
|---|---|
| `nca_*`, `poppk_*`, `sim_*` | every results table of every version, from the committed Parquet snapshots; each row keeps `project_number`, and `filename` names its source file |
| `versions` | every version of every type: spec present, QC status, last QC result (`project_status()`) |
| `script_runs` | every script execution: script, version, start and finish time, status, elapsed time, user, git commit, log file |
| `catalog` | each table with its rows, versions and build time |

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
query_project_db("SELECT type, version, qc_status, last_qc FROM versions")
query_project_db("SELECT project_number, run_id, objf, delta_ofv FROM poppk_runs WHERE final")
query_project_db("SELECT script, status, elapsed FROM script_runs WHERE status LIKE 'FAILED%'")
```

It is derived and git-ignored: it is rebuilt from files every clone has, and analysis, table,
figure and report scripts never read it, so it cannot change a version's hashes. A failed
rebuild (for example the file open in another R session) prints a message and never fails
the run.

## Main functions and files

| Function or file | Purpose |
|---|---|
| `project_config(path = "project.yaml")` | reads and validates `project.yaml` |
| `analysis_title(type, cfg)` | analysis title for table headers and the spec; falls back to "<type> analysis for <study id>" |
| `new_version(type, n, from)` | scaffolds `script/{type}/v{n}/` and `tests/{type}/v{n}/`; refuses to overwrite |
| `run_version(type, n, qc = TRUE, only = NULL)` | runs each script with `Rscript` in a fresh session; stops at the first failure and names its latest log |
| `run_qc(type, n)` | runs the version's QC-readiness suite |
| `list_versions(type)` | existing version numbers |
| `project_status()` | QC state of every version |
| `new_tlf(type, n, name, title, subtitle, footnotes, caption, description)` | scaffolds a custom `fig-*`/`tbl-*` script and registers its description in `generate-spec.R` |
| `render_tlf()` (`scripts/tlf_shell.R`) | the shared docorator shell: analysis title and page number in the header, "Source data:", script and date-time in the footer, 11 pt serif |
| `scripts/figure_helpers.R` | `theme_tlf()`, `tlf_out_dir()`, `lab_unit()` |
| `scripts/tfrmt_helpers.R` | `fs()`, `frmt_dp()`, `frmt_sig3()`, `frmt_min_max()`, `summary_ard()`, `stat_row_label()`, `add_row_order()`, `participant_levels()`, `per_param_body_plan()`, `tlf_footnotes()` |
| `scripts/db_snapshot.R` | `db_snapshot_write()` and `db_snapshot_restore()`: the committed Parquet + xz snapshot of a version's database, rebuilt into DuckDB on a fresh clone |
| `assets/project-template.yaml` | template for `project.yaml` |
| `assets/tlf-serif.tex` | serif font setting passed to docorator's PDF renderer |
| `update_project_db()`, `query_project_db(sql)` (`scripts/project_db.R`) | Rebuild / query `output/project.duckdb` (see above) |

## Rules and checks

- Scaffold, do not hand-write, a version folder. The QC suites check naming, logging and
  version references that the templates already satisfy.
- A change is a new version: `new_version(type, from = n)`. Never edit a version whose
  spec exists. Re-running a version still in development is fine.
- Use `run_version()` to run a version. Order matters: `analysis-*.R` first, then the other
  scripts in sorted order, then `generate-spec.R`, then the QC suite. `generate-spec.R`
  hashes everything produced before it.
- `only = "fig-vpc.R"` re-runs single scripts during development and skips the QC suite.
  Do a full `run_version()` before QC.
- Run from the project root (the folder with `project.yaml` and `.here`).
  `examples/abc-111/` is a project root of its own.
- Study values (titles, study ID, units) come from `project.yaml`; analysis choices go in
  `EDIT` blocks.
- Every custom table and figure goes through `new_tlf()` and `render_tlf()`. A figure's
  title and subtitle go in the header through `render_tlf()`, never in the ggplot.
- Fix a template bug in the skill's `templates/` file, so every future version gets it.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `project.yaml not found` | Not in the project root, or `project.yaml` was never created from `assets/project-template.yaml`. |
| `project.yaml: 'units.conc' is not set` | A `<...>` placeholder is still in `project.yaml`. Fill it in. |
| `script/nca/v2 already exists` | Pick another `n`, or keep working in that version. |
| `analysis-nca.R failed (exit 1). Latest log: ...` | Read that log. It has the R error. |
| QC fails right after `run_version(..., only = )` | Expected: the spec is stale until `generate-spec.R` re-runs. Do a full `run_version()`. |
| `name must start with 'fig-' (figure) or 'tbl-' (table)` | Rename the output passed to `new_tlf()`. |

## Related

- [pk-nca](pk-nca.md), [pk-data-validation](pk-data-validation.md),
  [pk-nca-logging](pk-nca-logging.md)
- [pk-nca-database](pk-nca-database.md), [pk-nca-run-spec](pk-nca-run-spec.md),
  [pk-nca-qc-tests](pk-nca-qc-tests.md)
- Source: [SKILL.md](../../.posit/assistant/skills/pk-project/SKILL.md)
- Workflow guides: [NCA](../pk-nca/README.md), [popPK](../poppk/README.md)

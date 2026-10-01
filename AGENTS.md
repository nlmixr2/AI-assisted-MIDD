# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Posit Assistant, and others) working in
this repository. Humans: see [README.md](README.md).

## What this repository is

A **template for reproducible, QC-ready pharmacometric analyses in R**:

- non-compartmental analysis (NCA) with PKNCA;
- Population PK estimation with nlmixr2;
- PopPK/PD simulations with rxode2.

The analysis procedures live as **skills** in `.posit/assistant/skills/` (also linked at
`.claude/skills/`). Each skill is a `SKILL.md` plus verified scripts, templates and references.
[The skills README](.posit/assistant/skills/README.md) maps them and lists suggested prompts;
[`docs/`](docs/README.md) has workflow guides with diagrams (start with `docs/pk-nca/README.md`) and
one page per skill (`docs/skills/`).

`examples/abc-111/` and `examples/gs-12345/` are complete worked examples. Each is a project
root of its own: run its scripts with that folder as the working directory. Treat them as
read-only reference material unless the user asks you to change them.

## Before doing anything

1. **Load the skill before acting.** Use this table, and read the skill's `SKILL.md` before
   writing any code:

   | Request | Skill |
   |---|---|
   | Setting up the study, starting or running versions, project status | `pk-project` |
   | Inspecting or validating a dataset, mapping columns, EVID/CMT coding | `pk-data-validation` |
   | NCA | `pk-nca` (+ `pk-nca-tables`, `pk-nca-run-spec`, `pk-nca-qc-tests`) |
   | NCA figures (mean/individual PK plots) | `pk-nca-figures` |
   | NCA report (Quarto PDF) | `pk-nca-report` |
   | popPK report (Quarto PDF) | `poppk-report` |
   | popPK fitting | `poppk-estimation` (+ `poppk-tables`, `poppk-run-spec`, `poppk-qc-tests`) |
   | Simulation | `poppk-simulation` |
   | Run logs, why a script failed, session hygiene | `pk-nca-logging` |
   | Saving, reading or querying NCA / popPK results in DuckDB | `pk-nca-database`, `poppk-database` |
   | Adding, changing or checking a skill | `manage-skills` |

2. **Check `project.yaml`** at the project root. If it still holds `<...>` placeholders, ask
   the user for the study ID, analysis titles and data units, and fill it in before
   scaffolding anything.
3. **Look at the data before mapping it** (`pk-data-validation`). Never guess column names,
   EVID/CMT coding, or units: map from `describe_pk_data()` output, and let
   `validate_pk_data()` pass before any analysis runs.

## How work is organised

| Folder | Contents |
|---|---|
| `data/` | input datasets (read from file, never from in-memory objects, so they can be hashed) |
| `model/` | model files for simulations from a user-provided model |
| `script/{type}/v{n}/` | one version's scripts: `analysis-*.R`, `fig-*.R`, `tbl-*.R`, `generate-spec.R` |
| `output/{type}/v{n}/` | `figures/`, `tables/`, `logs/`, `db/` for that version only. `db/*.duckdb` is local and git-ignored; `db/snapshot/` (Parquet + xz payload) is committed, and the database is rebuilt from it automatically on a fresh clone |
| `spec/{type}/v{n}.yaml` (+ `.hash`) | provenance record of the version |
| `tests/{type}/v{n}/` | QC-readiness test suite of the version |
| `output/project.duckdb` | project-wide query database of every version and script run, rebuilt after every `run_version()`/`run_qc()` from the committed snapshots and logs; local, git-ignored, never read by analysis scripts (`query_project_db()`) |
| `output/nca/v{n}/MAR/` | Quarto project of a QC'd NCA version's one-PDF report: tables, figures, provenance, code (`pk-nca-report`) |
| `output/poppk/v{n}/MAR/` | the same for a QC'd popPK version, plus its model trail and final model (`poppk-report`) |

Here `{type}` is `nca`, `poppk` or `poppk-sim`.

Always start and run versions through the `pk-project` helpers:

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
new_version("poppk")                # scaffold from the skill templates (or from = n to copy v{n})
# edit only the blocks marked EDIT
run_version("poppk", 1L)            # analysis -> figures/tables -> generate-spec -> QC suite
project_status()
```

## Rules

- **A change means a new version.** If the data, model trail, method, requested parameters
  or regimens change, create `new_version(type, from = n)`. Never edit a version whose spec
  exists. That version is what QC reviews, and its hashes would no longer match.
- **Keep the order.** The analysis script runs first, then figures and tables, then
  `generate-spec.R`, then the QC suite. `generate-spec.R` hashes everything produced before
  it, so re-running any script afterwards makes QC fail until the spec is regenerated.
  `run_version()` enforces the order.
- **Compute only in the analysis script.** Only `analysis-*.R` runs PKNCA, fits a model or
  simulates. Every other script reads results back with `read_nca_db()`,
  `read_poppk_db()` or `read_sim_db()`. For questions across versions and analysis types,
  query `output/project.duckdb` with `query_project_db()`; don't compute analysis results from it.
- **No hard-coded study values.** Titles, study ID and units come from `project.yaml`
  (`project_config()`, `analysis_title()`). Put analysis-specific choices inside `EDIT`
  blocks.
- **Custom tables and figures use the same shell.** Scaffold them with
  `new_tlf(type, n, "fig-..."/"tbl-...", title =, subtitle =, footnotes = / caption =)`
  (`pk-project`), filling the placeholders from the request and asking for missing ones.
  Tables are tfrmt (long ARD → `body_plan()`), built with the shared helpers in
  `pk-project/scripts/tfrmt_helpers.R` (`fs()`, `summary_ard()`, `tlf_footnotes()`, ...); figures
  use `theme_tlf()`, `tlf_out_dir()` and `lab_unit()` (`figure_helpers.R`); and
  everything renders through `render_tlf()` (11 pt serif);
  never use `ggsave()` or a hand-built `as_docorator()` for a deliverable. Titles and
  subtitles belong to the shell: `tfrmt(title =, subtitle =)` for tables,
  `render_tlf(title =, subtitle =)` for figures, never `labs(title/subtitle)` in the ggplot.
- **Log every script.** Each one is bookended by
  `nca_log_start("<script-name>", project_number = n, output_dir = "output/<type>")` and
  `nca_log_stop()`. The first argument is the script's file name without `.R`. The QC
  suites check this.
  Mark each numbered step with `nca_log_section("<n>. <title>")` (the analysis templates
  do). A log whose run summary says `status: FAILED` is a failed run: fix it and re-run.
- **Reproducibility:**
  - fix every seed (`saemControl(seed =)`, `set.seed()` before `vpcPlot()`, and the
    simulation base seed);
  - read popPK data with `read_csv(..., lazy = FALSE) |> as.data.frame()` so its hash is
    stable;
  - use `rlang::hash()` / `hash_file()` for fingerprints.
- **Fix templates in the skill.** A bug found in a scaffolded script usually belongs in the
  skill's `templates/` file. Fix it there, so every future version gets it, and mention it
  to the user.
  Changes to a skill follow `manage-skills`, and `check_skills.R` must report no fails.
- **Keep QC honest:**
  - never set `qc.status: approved`, which is the reviewer's sign-off;
  - never weaken a QC test to make it pass, or edit a spec by hand;
  - fix the cause instead: re-run the stale script, then `generate-spec.R`.
- **Report only QC'd results.** The NCA and popPK reports (`output/{nca,poppk}/v{n}/MAR/`)
  are one PDF of the version's tables, figures, source files and provenance, and code, read
  from its database, spec, output objects and scripts; never compute or refit in them and
  don't add narrative text. Render with `render_nca_report(n)` / `render_poppk_report(n)`,
  which refuse a version that changed since its spec or has no passing QC run.
- **Report faithfully.** State the ΔOFV, acceptance-check warnings and flagged subjects,
  and say which diagnostics you looked at. A version is "ready for QC" only when its suite
  passes; quote the result.
- **Only run what you need.** Don't re-run other versions, delete outputs, or clean
  `output/` unless the user asks. Logs are append-only history.

## Commands

Run everything from the project root (the folder with `project.yaml` and `.here`):

```sh
Rscript script/poppk/v1/analysis-poppk.R        # one script (logs to output/poppk/v1/logs/)
Rscript -e 'source(".posit/assistant/skills/pk-project/scripts/project.R"); run_version("nca", 1L)'
Rscript -e 'source(".posit/assistant/skills/pk-project/scripts/project.R"); run_qc("poppk-sim", 1L)'
Rscript -e 'source(".posit/assistant/skills/pk-project/scripts/project.R"); print(project_status())'
```

Messages about packages "built under R version x.y.z" and DuckDB's `~/.duckdb` storage
notice are expected noise, not errors.

## Environment

- **R and TinyTeX:** R ≥ 4.5; TinyTeX renders tables as PDF, otherwise they fall back to RTF.
- **Quarto** ≥ 1.4 on PATH for reports (`pk-nca-report`, `poppk-report`), rendered with lualatex.
- **Packages:** PKNCA, nlmixr2 (with rxode2, nlmixr2plot), tidyverse, tfrmt, docorator, gt, crane,
  duckdb, DBI, rlang, yaml, testthat, withr, here, patchwork, sessioncheck, whoami, pointblank,
  ggPMX (popPK diagnostics).
- **Tested versions:** PKNCA 0.12.1, nlmixr2 7.0.1, rxode2 5.1.6, duckdb 1.5.5.

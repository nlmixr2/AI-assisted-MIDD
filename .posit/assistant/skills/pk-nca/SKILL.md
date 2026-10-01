---
name: pk-nca
description: Runs non-compartmental analysis (NCA) of concentration-time data with PKNCA: PK parameters such as Cmax, Tmax, AUC and half-life, with terminal-phase checks. Use when the user asks for NCA, PKNCA, PK parameters, AUC or half-life.
---

# Running non-compartmental pharmacokinetic analysis

## Overview

This skill provides the procedure to execute non-compartmental pharmacokinetic (PK)
analysis using the PKNCA R package.

## When to use

Use this skill when the user asks about NCA, PK analysis, PK parameters, or half-life calculations.

### When NOT to use

Do not use this package for compartmental models or for fitting nonlinear mixed-effects
models (see the `poppk-estimation`/`poppk-simulation` skills instead).

## Core Process

**Start every versioned analysis by scaffolding it** (companion skill `pk-project`):

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
new_version("nca")              # script/nca/v{next}/ + tests/nca/v{next}/ from templates/
new_version("nca", from = 1L)   # ... or start from an existing version
# edit the blocks marked EDIT, then:
run_version("nca", 2L)          # analysis -> figures/tables -> generate-spec -> QC suite
```

**Source of truth.** The only verified-working pipeline is
`file:///{skill_dir}/templates/analysis-nca.R` (scaffolded as `analysis-nca.R`); the
diagnostic figure templates are `templates/fig-*.R`. Units come from `project.yaml` via
`project_config()`. The reference pages *explain* the steps. They are not code
to paste: when the prose and a template disagree, the template wins. Edit only the
`EDIT` blocks of a scaffolded script, and never retype the pipeline from memory.

### Grounding checks (do these, don't assume them)

Most wrong NCA runs start with a guess. Before writing or editing an `EDIT` block:

1. **Describe and validate the data first** with the `pk-data-validation` skill
   (`describe_pk_data()`, then `validate_pk_data()`; both already in the template's data
   block). Map columns from its output, not from the examples in the reference pages, and
   tell the user which column became `participant`, `time`, `cObs` and `dose`.
2. **Ask for what the file cannot tell you.** Units, route of administration, whether a
   dose column is per kg, and the dosing time for data without dose rows come from the
   user or `project.yaml`, never from a default. If they are missing, ask.
3. **Check an API before using it.** If a PKNCA function or argument is not in the
   template, confirm it exists with `args(PKNCA::fn)` or `?fn` before writing it.
   [references/troubleshooting.md](references/troubleshooting.md) lists functions that do
   **not** exist.
4. **Report only printed numbers.** Every value you quote (parameters, flagged
   subjects, counts) must come from script output, the log, or `read_nca_db()`. If you
   did not run it, say it has not been run.

**The pipeline in `analysis-nca.R`** (each step explained in
[references/pipeline.md](references/pipeline.md)):

1. Load packages.
2. Read the data file from `data/`.
3. Split it into `cObsData` (observations) and `doseData` (doses), renamed to
   `participant`/`time`/`cObs`/`dose`.
4. Build `PKNCAconc`/`PKNCAdose`.
5. Take units from `project.yaml`.
6. Request parameters as boolean columns of the intervals tibble.
7. Run `PKNCAdata()` then `pk.nca()`.
8. Build the λz fit summary (`halflife_fit`) and ask the user whether it looks OK.

The script then writes everything to the version's database (`pk-nca-database`).

### NCA Rules

- Read the input dataset from a file under `data/`, never an in-memory object, and validate it before building PKNCA objects (`pk-data-validation`; the file is what the spec hashes).
- Put steps 1-8 ([references/pipeline.md](references/pipeline.md)) in the versioned `analysis-nca.R` script (e.g. `script/nca/v1/analysis-nca.R`). It is the only script that runs PKNCA. Every downstream `tbl-*.R`/`fig-*.R` script reads the results back with `read_nca_db(project_number)`; never `source()` the analysis script or re-run `pk.nca()` in it (see Versioned run scripts & provenance below).
- Split the data first: observations to `PKNCAconc`, doses to `PKNCAdose`, never both to `PKNCAconc`. Which rows are which (EVID codes, sample layout) is set out in `pk-data-validation` (`references/data-layouts.md`).
- Standardize column names to `participant`/`time`/`cObs`/`dose` when building `cObsData`/`doseData`, even if the source dataset already has clear native names (e.g. `Subject`/`Time`/`conc`). This keeps formulas and downstream summarization code consistent across projects.
- Always pass a units table: via `pknca_units_table(concu=, timeu=, doseu=, amountu=)`. Without it results are unitless and CL/Vz scaling is ambiguous.
- Check parameters need to be calculated: request them as boolean columns (`TRUE`) in the `intervals` tibble passed to `PKNCAdata()` (or set them on `ncaObj$intervals` afterward) before `pk.nca()`. `cl.obs` is apparent CL (CL/F for extravascular route); derive F separately if needed. There is no `interval_add_param()` function in current PKNCA (0.12.1) — build/edit the intervals data frame's boolean columns directly.
- Set `route = "extravascular"` (or `"intravascular"`) and `dur = NA_real_` in the dose data frame; PKNCA picks these up by column name.
- Half-life comes from λz regression on the terminal phase; check `adj.r.squared` / `span.ratio` per subject before trusting it.
- Filter to the interval you requested when summarizing (`end == Inf` for the default 0–Inf interval). PKNCA returns one set of rows per interval (e.g. 0–24 h and 0–Inf), so without the filter each parameter appears once per interval.

## Diagnostics

Before reporting results, look at the terminal-phase diagnostics: `fig-halflife-diagnostics.pdf`
(span ratio vs adjusted R² for all participants, from `templates/fig-halflife-diagnostics.R`),
and the per-participant `fig-lambdaz.pdf` and `fig-ind-conc.pdf` (linear and semi-log) from
`pk-nca-figures`. Every figure is a PDF in the shared TLF shell (`render_tlf()`); none is
a PNG. All are scaffolded by `new_version("nca")`; load
[references/diagnostics.md](references/diagnostics.md) for how to interpret them.

When you report the λz check, list the flagged subjects exactly as printed by
`analysis-nca.R` ("Subjects with span.ratio < 2") and ask the user whether to accept the
fits or revise them in a new version. Do not decide for them, and do not drop flagged
subjects from summaries without being asked.

## Versioned run scripts & provenance

Each version lives in `script/nca/v{project_number}/` and writes only to
`output/nca/v{project_number}/`. `analysis-nca.R` is the only script that runs PKNCA
and ends with `write_nca_db()`. Every `fig-*.R`/`tbl-*.R` starts with
`read_nca_db(project_number)`. The run order is `analysis-nca.R` → every
`fig-*.R`/`tbl-*.R` → `generate-spec.R` (`pk-nca-run-spec`) → the QC suite
(`pk-nca-qc-tests`), which `run_version("nca", n)` enforces. A version is ready for QC
only when that suite passes with zero failures. Directory tree, database hand-off and
spec contents: [references/versioned-layout.md](references/versioned-layout.md).

## Reporting

- To persist results for reuse across `tbl-*.R`/`fig-*.R`/reports without re-running
  PKNCA, or to query results with SQL, use the companion `pk-nca-database` skill.
- For a formatted, presentation- or production-ready table of results (`tfrmt` + `docorator`), use the companion `pk-nca-tables` skill.
- For production figures (mean concentration plots with crane, individual plots one page per participant), use the companion `pk-nca-figures` skill.
- **Nominal times** (`scripts/nca_nominal.R`): if the data have a nominal-time column (CDISC `NFRLT`/`NRRLT`, `NTIME`, ...), `analysis-nca.R` detects it (`detect_nominal_time_col()`, overridable via `NOMINAL_TIME_COL` in its EDIT block) and stores it as `ntime` in `cObsData`, so it is hash-verified with the results and used by every nominal-time table and figure. Otherwise `project.yaml`'s `sampling.nominal_times` is matched to actual times. With both, every data value must be on the schedule (error otherwise) and the schedule's labels are used. The spec records the source (`data.nominal_time`). NCA parameters always use actual times.
- For the full analysis report (Quarto PDF in `output/nca/v{project_number}/MAR/`), use the companion `pk-nca-report` skill once the version is ready for QC.
- For a provenance/QC metadata record of a versioned run script, use the companion `pk-nca-run-spec` skill (see Versioned run scripts & provenance above).
- To confirm a version is ready for QC (and give the reviewer a JUnit report), use the companion `pk-nca-qc-tests` skill — one `tests/nca/v{project_number}/` suite per version.
- `summary(ncaRes)` prints a ready-made table: geometric mean [GCV] for AUClast/Cmax/AUCinf/CL/Vz, median and range for Tmax, mean ± SD for half-life.

## Reference files

Load these on demand; each links back here.

| File | Load when |
|---|---|
| `templates/analysis-nca.R`, `templates/fig-*.R` | Always: the verified scripts `new_version("nca")` scaffolds; edit only their `EDIT` blocks |
| [references/pipeline.md](references/pipeline.md) | Building `cObsData`/`doseData` from a validated dataset, units, requesting parameters, summarizing `ncaRes` |
| `pk-data-validation` skill | Inspecting and validating the data file, EVID/CMT coding, BLQ records |
| [references/diagnostics.md](references/diagnostics.md) | Reading the λz diagnostics (span-ratio plot, per-participant regressions and profiles), flagging subjects |
| [references/versioned-layout.md](references/versioned-layout.md) | Where scripts and outputs go, the database hand-off, what the spec records |
| [references/troubleshooting.md](references/troubleshooting.md) | An error or warning from PKNCA, or suspected API drift |
| [references/pknca-resources.md](references/pknca-resources.md) | PKNCA vignettes (intervals, AUC, half-life, BLQ, imputation, options) and the citation |
| `scripts/nca_nominal.R` | Nominal-time detection and matching (see Reporting above) |

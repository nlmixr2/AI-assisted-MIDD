# `pk-nca`

Runs a versioned non-compartmental analysis (NCA) with PKNCA from a validated dataset. It
maps observations and doses to PKNCA objects, takes units from `project.yaml`, runs
`pk.nca()`, summarises the results, checks the terminal-phase (lambda z) fits, and writes
everything to the version's results database.

## When it is used

- You ask for NCA, PKNCA, PK parameters, half-life or AUC from concentration-time data.
- You start or change an NCA version.
- Not for compartmental models or nonlinear mixed-effects fits: use `poppk-estimation` or
  `poppk-simulation`.
- Neighbouring tasks: data checks in [pk-data-validation](pk-data-validation.md); the
  results database in [pk-nca-database](pk-nca-database.md); tables in
  [pk-nca-tables](pk-nca-tables.md); production figures in
  [pk-nca-figures](pk-nca-figures.md); the spec in [pk-nca-run-spec](pk-nca-run-spec.md);
  QC tests in [pk-nca-qc-tests](pk-nca-qc-tests.md); the PDF report in
  [pk-nca-report](pk-nca-report.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `analysis-nca.R`, `fig-halflife-diagnostics.R` | `script/nca/v{n}/` | scaffolded from this skill's templates |
| Results database | `output/nca/v{n}/db/nca.duckdb` (snapshot in `db/snapshot/`) | `cObsData`, `doseData`, `ncaRes`, `res_wide`, `halflife_fit`, written by `write_nca_db()` |
| `fig-halflife-diagnostics.pdf` (+ `.RDS`) | `output/nca/v{n}/figures/` | span ratio vs adjusted R-squared for all participants, dashed line at the span-ratio threshold |
| Data validation report | `output/nca/v{n}/logs/data-validation-<timestamp>.html` | from [pk-data-validation](pk-data-validation.md) |
| Run log | `output/nca/v{n}/logs/analysis-nca-<timestamp>.log` | requested parameters per participant (`res_wide`), `summary(ncaRes)`, the lambda z fit table and the list "Subjects with span.ratio < 2" |

## How to use it

1. Fill in `project.yaml` (units at least) and put the data file in `data/`.
2. Scaffold a version ([pk-project](pk-project.md)):

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
new_version("nca")              # script/nca/v{next}/ + tests/nca/v{next}/
new_version("nca", from = 1L)   # ... or start from an existing version
```

3. Edit only the `EDIT` blocks of `script/nca/v{n}/analysis-nca.R`:
   - **1. Load data:** `pkDataPath`, and the `validate_pk_data()` layout and `pk_cols()`
     mapping, taken from `describe_pk_data()` output.
   - **2. Build concentration and dose data:** the column mapping to `participant`,
     `time`, `cObs` and `dose`, the `route` (`"extravascular"` or `"intravascular"`),
     and `NOMINAL_TIME_COL` if needed. The template shows the event layout; for the
     sample layout see `references/pipeline.md`, step 3.
   - **5. Intervals and parameters:** the parameters requested as `TRUE` columns of
     `intervalData`. The template requests `cmax`, `tmax`, `half.life`, `aucinf.obs` and
     `clast.obs`; add `cl.obs = TRUE` or `vz.obs = TRUE` for CL/F or Vz/F.
   - In `fig-halflife-diagnostics.R`: `span_min` (default 2, the same value as in
     `fig-lambdaz.R`).
4. Run the whole version:

```r
run_version("nca", 1L)          # analysis -> figures/tables -> generate-spec -> QC suite
```

5. Look at the lambda z diagnostics (below) and answer the question on flagged subjects.

Typical prompts: "run an NCA on data/pk-data.csv", "add CL/F and Vz/F in a new version",
"which subjects have a short terminal phase?", "is NCA v2 ready for QC?".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `templates/analysis-nca.R` | the only verified pipeline: load and validate data, build `cObsData`/`doseData`, `PKNCAconc()`/`PKNCAdose()`, `pknca_units_table()`, intervals, `PKNCAdata()` and `pk.nca()`, `res_wide`, `halflife_fit`, `write_nca_db()` |
| `templates/fig-halflife-diagnostics.R` | span-ratio vs adjusted R-squared figure, rendered in the shared TLF shell |
| `scripts/nca_nominal.R` | `detect_nominal_time_col()`, `nominal_schedule()`, `assign_nominal_time()`, `nominal_time_source()` |
| `references/pipeline.md` | each pipeline step explained, including the sample layout |
| `references/diagnostics.md` | how to read the lambda z figures and handle flagged participants |
| `references/versioned-layout.md` | folder layout, database hand-off, spec contents |
| `references/troubleshooting.md` | PKNCA errors and functions that do not exist |
| `references/pknca-resources.md` | PKNCA vignettes and citation |

## Rules and checks

- Describe and validate the data first ([pk-data-validation](pk-data-validation.md)).
  Map columns from its output, and tell the user which column became `participant`,
  `time`, `cObs` and `dose`.
- Units, route, per-kg dosing, and the dosing time for data without dose rows come from
  the user or `project.yaml`, never from a default.
- Read the data from a file under `data/`, never an in-memory object.
- Observations go to `PKNCAconc`, doses to `PKNCAdose`, never both to `PKNCAconc`.
- Always pass a units table; without it results are unitless.
- `cl.obs` is apparent clearance (CL/F for the extravascular route).
- Summaries filter to the requested interval (`end == Inf` for 0-Inf); otherwise each
  parameter appears once per interval.
- Only `analysis-nca.R` runs PKNCA. Every `fig-*.R`/`tbl-*.R` reads results back with
  `read_nca_db(project_number)`.
- Before reporting half-life or anything derived from it (`aucinf.obs`, `cl.obs`,
  `vz.obs`), look at `fig-halflife-diagnostics.pdf`, `fig-lambdaz.pdf` and
  `fig-ind-conc.pdf`.
- List flagged subjects exactly as printed ("Subjects with span.ratio < 2") and ask the
  user whether to accept the fits or revise them in a new version. Do not drop them from
  summaries or change the lambda z window without being asked. The spec records them in
  `diagnostics.flagged_subjects`.
- Nominal times: a nominal-time column in the data (`NFRLT`, `NRRLT`, `NTIME`, `NOMTIME`,
  `NTPD`, `TNOM`, matched case-insensitively) is stored as `ntime` in `cObsData`. Set
  `NOMINAL_TIME_COL` to override it, or to `NA` to use `sampling.nominal_times` from
  `project.yaml`. For multiple-dose data choose `NFRLT` or `NRRLT` deliberately. With both
  sources, every data value must be on the schedule. The spec records the source
  (`data.nominal_time`). NCA parameters always use actual times.
- Quote only numbers from script output, the log, or `read_nca_db()`.
- Tested with PKNCA 0.12.1. Backward compatibility is not guaranteed before PKNCA 1.0:
  check a function with `args(PKNCA::fn)` or `?fn` before using one the template does not.
- A version is ready for QC only when its QC suite passes with zero failures.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `unused argument` in `pknca_units_table` | API drift. Check `?pknca_units_table` for the installed signature. |
| `object 'PPTESTCODE' not found` | The column is `PPTESTCD` in current PKNCA. |
| No `cl.obs`/`vz.obs` in results | Not requested. Add `cl.obs = TRUE` to `intervalData` in the EDIT block. |
| Lambda z warnings for a subject | Too few terminal points or a curved terminal phase. Check `span.ratio` and `lambda.z.n.points`. |
| Duplicate interval rows in a summary | Filter `end == Inf`, or the interval you requested. |
| CL/F or Vz/F units not simplified (e.g. `mg/(h*mg/L)`) | PKNCA does not simplify derived units. Pass preferred units (`amountu_pref =`, `concu_pref =`) or a `conversions` table in the units step. |
| `object 'interval_add_param' not found` | That function does not exist in PKNCA 0.12.1. Set boolean columns in the intervals tibble. |
| `Found column named route, using it...` | Informational only. |

## Related

- [pk-project](pk-project.md), [pk-data-validation](pk-data-validation.md),
  [pk-nca-logging](pk-nca-logging.md)
- [pk-nca-database](pk-nca-database.md), [pk-nca-figures](pk-nca-figures.md),
  [pk-nca-tables](pk-nca-tables.md), [pk-nca-run-spec](pk-nca-run-spec.md),
  [pk-nca-qc-tests](pk-nca-qc-tests.md), [pk-nca-report](pk-nca-report.md)
- Source: [SKILL.md](../../.posit/assistant/skills/pk-nca/SKILL.md)
- Workflow guide: [NCA](../pk-nca/README.md)

# PK analysis skills: `pk-nca-*` and `poppk-*`

Assistant skills for reproducible, QC-ready pharmacokinetic analyses in R:

- **`pk-nca-*`**: non-compartmental analysis (NCA) with PKNCA.
- **`poppk-*`**: population PK model estimation with nlmixr2, and simulation with rxode2.

Each skill is a folder containing a `SKILL.md` (the instructions the assistant follows), verified R scripts and templates, and reference notes. You ask for an analysis in plain language, for example "Run NCA for `data/pk-data-2.csv`", "fit a popPK model", or "simulate 480 mg q12h from the v1 model". The assistant then loads the matching skill and follows it.

Both families work the same way. Each analysis is a numbered **version** (`v1`, `v2`, ...). A version's scripts write their results to a database, log every run, record provenance in a hashed spec file, and finish with a test suite that must pass before the version goes to QC.

Versions are never hand-written. The `pk-project` skill scaffolds them from each skill's `templates/` folder, fills in study settings from `project.yaml`, and runs them in the required order. To start a new study from this template, see the [project README](../../../README.md).

## Skills

| Skill | Role | Main helpers |
|---|---|---|
| [`pk-project`](pk-project/SKILL.md) | Entry point: `project.yaml`, scaffolding versions from templates, running versions, project status | `project_config()`, `new_version()`, `run_version()`, `run_qc()`, `project_status()` |
| [`pk-data-validation`](pk-data-validation/SKILL.md) | Describes a dataset for column mapping, then validates it with pointblank before NCA or popPK; HTML report in the version's logs | `describe_pk_data()`, `validate_pk_data()`, `pk_cols()` |
| [`pk-nca`](pk-nca/SKILL.md) | Core NCA pipeline: data → `PKNCAconc`/`PKNCAdose` → `pk.nca()` → λz diagnostics | `templates/analysis-nca.R`, `templates/fig-*.R` |
| [`pk-nca-database`](pk-nca-database/SKILL.md) | Stores NCA results in DuckDB, verified by content hash | `write_nca_db()`, `read_nca_db()`, `query_nca_db()` |
| [`pk-nca-tables`](pk-nca-tables/SKILL.md) | PK parameter and concentration tables (tfrmt + docorator) | `templates/tbl-pk-parameters.R`, `templates/tbl-conc-by-nominal-time.R` |
| [`pk-nca-run-spec`](pk-nca-run-spec/SKILL.md) | Provenance spec YAML plus a `.hash` sidecar file | `templates/generate-spec.R`, `collect_run_metadata()`, `write_spec()`, `verify_spec()`, `verify_outputs()` |
| [`pk-nca-logging`](pk-nca-logging/SKILL.md) | Timestamped run logs and session hygiene (used by **all** skills) | `nca_log_start()`, `nca_log_stop()` |
| [`pk-nca-figures`](pk-nca-figures/SKILL.md) | Mean (SD) concentration plots with crane (linear + semi-log, summary table) and individual plots one page per participant, in the table's docorator shell | `templates/fig-*.R`, `render_pk_display()` |
| [`pk-nca-report`](pk-nca-report/SKILL.md) | One PDF of a QC'd NCA version (tables, figures, source files and provenance, code) in `output/nca/v{n}/MAR/`, ISoP pmx-report-template cover | `create_nca_report()`, `render_nca_report()` |
| [`pk-nca-qc-tests`](pk-nca-qc-tests/SKILL.md) | QC-readiness test suite per NCA version | `create_qc_tests()`, `run_qc_tests()` |
| [`poppk-estimation`](poppk-estimation/SKILL.md) | Core popPK: model-building trail → nlmixr2 fits → acceptance checks → GOF/VPC | `templates/analysis-poppk.R`, `templates/fig-*.R`, `summarise_runs()`, `acceptance_checks()` |
| [`poppk-database`](poppk-database/SKILL.md) | Stores every fit of a version in DuckDB | `write_poppk_db()`, `read_poppk_db()`, `query_poppk_db()` |
| [`poppk-tables`](poppk-tables/SKILL.md) | Parameter table and model-comparison (OFV trail) table (tfrmt + docorator, shared TLF shell) | `templates/tbl-*.R` |
| [`poppk-run-spec`](poppk-run-spec/SKILL.md) | popPK spec: model trail, final model, rationale, acceptance checks | `templates/generate-spec.R`, `spec_models()`, `spec_final_model()`, `spec_caveats()` |
| [`poppk-qc-tests`](poppk-qc-tests/SKILL.md) | QC-readiness test suite per popPK version | `create_poppk_qc_tests()`, `run_poppk_qc_tests()` |
| [`poppk-report`](poppk-report/SKILL.md) | One PDF of a QC'd popPK version (tables, figures, model trail and final model, source files and provenance, code) in `output/poppk/v{n}/MAR/`, same engine as `pk-nca-report` | `create_poppk_report()`, `render_poppk_report()` |
| [`poppk-simulation`](poppk-simulation/SKILL.md) | rxode2 simulation from a **popPK fit** or a **model file**; exposure metrics; its own database, spec and QC tests | `templates/*.R`, `load_sim_model()`, `simulate_scenarios()`, `exposure_metrics()`, `run_sim_qc_tests()` |
| [`manage-skills`](manage-skills/SKILL.md) | Maintains the skills themselves: adds, changes, renames, retires and checks the skills, keeping frontmatter, templates, docs pages and skill maps in step | `scripts/check_skills.R`, `templates/SKILL-template.md` |

The poppk skills reuse the NCA helpers for logging (`pk-nca-logging`) and for generic provenance (`pk-nca-run-spec/scripts/build_spec.R`). They point those helpers at their own folders with arguments such as `output_dir = "output/poppk"`, so no code is duplicated.

## Project layout

Every analysis type uses the same four folders, and each version has its own subfolder:

```
project.yaml                       study ID, analysis titles, units (the only study-specific settings file)
data/                              input datasets (read from file so they can be hashed)
model/                             model files for poppk-simulation's "model-file" source

script/{nca,poppk,poppk-sim}/v{n}/     analysis-*.R, fig-*.R, tbl-*.R, generate-spec.R
output/{nca,poppk,poppk-sim}/v{n}/     figures/  tables/  logs/  db/ (*.duckdb local; db/snapshot/ committed)
spec/{nca,poppk,poppk-sim}/v{n}.yaml   provenance record (+ v{n}.yaml.hash)
tests/{nca,poppk,poppk-sim}/v{n}/      QC-readiness test suite
```

Conventions:

- **Versions are folders, not filenames.** Outputs are called `tbl-pk-parameters.pdf` in every version, and the version number comes from the folder path. Starting v2 never overwrites v1.
- **Change means a new version.** A different model trail, dataset, method, or regimen set becomes `v{n+1}`. Don't edit a version whose spec has already been written.
- **One analysis script per version.** `analysis-*.R` is the only script that runs PKNCA, fits a model, or simulates. Every `fig-*.R`, `tbl-*.R` and `generate-spec.R` script reads results back from the database and never recomputes them.
- **Every script is logged.** Each one opens with `nca_log_start("<script>", project_number = n, output_dir = ...)` and closes with `nca_log_stop()`.
- **Study values live in `project.yaml`.** Scripts read titles, study ID and units through `project_config()`. Anything else specific to one analysis is in a block marked `EDIT`.

## Workflows

Every analysis type follows the same three steps:

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
new_version("poppk")              # scaffold script/poppk/v{next}/ + tests/poppk/v{next}/  (from = n: copy v{n})
# edit the blocks marked EDIT
run_version("poppk", 1L)          # run every script in order, then the QC suite
```

`run_version()` runs each script with `Rscript` in a fresh R session, in the order below. The order matters because `generate-spec.R` hashes everything produced before it runs. To run a single script, use `Rscript script/<type>/v{n}/<script>.R` from the project root, or `run_version(type, n, only = "<script>.R")`.

### NCA

```
analysis-nca.R  →  fig-*.R, tbl-*.R  →  generate-spec.R  →  run_qc_tests(n)
```

The QC suite (`tests/nca/v{n}/test-nca-qc.R`, created by `new_version()`) writes a JUnit report to `output/nca/v{n}/logs/qc-tests-<timestamp>.xml`; `run_qc("nca", n)` runs it on its own.

### Population PK estimation

```
analysis-poppk.R  →  fig-gof.R, fig-individual-fits.R, fig-eta.R, fig-vpc.R, fig-traceplot.R, fig-pmx-diagnostics.R, fig-model-diagram.R,
                     tbl-parameters.R, tbl-model-comparison.R  →  generate-spec.R  →  run_poppk_qc_tests(n)
```

`analysis-poppk.R` works in these steps:

1. Define the models as a trail (`run001` is the base model, `run002` is `run001` piped with one change, and so on).
2. Record each run's parent and description in `run_info`.
3. Fit every run with the same method and a fixed seed.
4. Compare OFVs with `summarise_runs()`.
5. Record the chosen `final_run` and the reason in `final_rationale`; the rationale is stored in the database and copied into the spec.
6. Stop if `acceptance_checks()` reports any fail.

`run_qc("poppk", n)` runs the QC suite on its own.

### Simulation

```
analysis-sim.R  →  fig-sim-profiles.R, fig-exposure.R, tbl-exposure-summary.R  →  generate-spec.R  →  run_sim_qc_tests(n)
```

Set the model source in `analysis-sim.R`:

```r
sim_source <- list(type = "poppk-estimation", poppk_version = 1L)       # a fit from poppk-estimation (no refit)
sim_source <- list(type = "model-file", path = "model/one-cmt-oral.R")  # a model you provide
```

`run_qc("poppk-sim", n)` runs the QC suite on its own.

## Suggested prompts

Short prompts work because the skills supply the process. The assistant needs these facts from you; anything it has to guess, it will state as an assumption:

- **Data file:** the path under `data/`.
- **Title:** the title of the analysis.
- **Dosing:** route, and whether `AMT` is the total dose or a per-kg dose.
- **Units.**
- **Model or regimens:** what to fit (popPK) or which regimens to simulate (simulation).

**Custom tables and figures.** Any output you request gets the same shell (analysis title and
page in the header; "Source data:", script and date-time in the footer) and is scaffolded with
`new_tlf()`. Give the placeholders in the prompt:

| Placeholder | Figure | Table |
|---|---|---|
| name | `fig-<short-name>` | `tbl-<short-name>` |
| title | required | required |
| subtitle | optional | optional |
| caption / footnotes | one-line caption | footnotes, separated by `;` |
| content | x, y, grouping, scale | rows, columns, statistics, decimals |

The assistant asks for any placeholder you leave out, builds the output from that version's
database (never recomputing), and re-runs the version so the spec and QC include it.

### NCA (`pk-nca-*`)

| Goal | Prompt |
|---|---|
| New analysis | *Run NCA for `data/pk-data-2.csv`. The title of the analysis is "PK Analysis for ABC-111". Oral dose, AMT is total mg, concentrations in mg/L, time in h.* |
| Specific parameters | *Run NCA for `data/<file>.csv` and also report AUClast, CL/F and Vz/F, not just Cmax, Tmax, AUCinf and half-life.* |
| Multiple-dose data | *Run NCA for `data/<file>.csv` with dosing every 12 h; compute steady-state parameters over the last dosing interval (AUCtau, Cmax,ss, Ctrough).* |
| Review λz fits | *Show me the half-life diagnostics for NCA v2. Which subjects have a span ratio below 2, and what happens if I exclude them from half-life and AUCinf?* |
| Changed data | *The data file was updated. Rerun the NCA as a new version and compare the PK parameters with v2.* |
| Tables | *Create the PK parameter table and the concentration-by-nominal-time table for NCA v2. The nominal times are 0, 0.25, 0.5, 1, 2, 4, 8, 12 and 24 h, and LLOQ is 0.1 mg/L.* |
| QC readiness | *Generate the spec and run the QC tests for NCA v2. Is it ready for QC?* |
| Report | *Create the NCA report for v2 and render it to PDF.* |
| Custom figure: dose-normalized exposure | *Add a figure to NCA v3: name `fig-dn-exposure`, title "Dose-normalized Cmax and AUCinf by participant", subtitle "Dose-normalized to 100 mg", caption "Dashed line: geometric mean". Content: one dot per participant, Cmax/Dose and AUCinf/Dose in two panels.* |
| Custom figure: half-life | *Add a figure to NCA v3: name `fig-halflife-bar`, title "Terminal half-life by participant", caption "Red: span ratio < 2". Content: bar per participant ordered by half-life, coloured by the span-ratio flag.* |
| Custom table: geometric means | *Add a table to NCA v3: name `tbl-pk-geomean`, title "Summary of PK Parameters (Geometric Statistics)", footnotes "GCV = geometric coefficient of variation"; "Tmax: median (min, max)". Content: rows = Cmax, AUCinf, half-life, Tmax; columns = N, geometric mean (GCV%), median (min, max).* |
| Custom table: half-life by span ratio | *Add a table to NCA v3: name `tbl-halflife-summary`, title "Terminal Half-Life Summary", subtitle "By span-ratio category", footnotes "Span ratio = regression interval / half-life"; "N = number of participants". Content: rows = span ratio ≥ 2 / < 2; columns = N, mean half-life, (min, max).* |

### Population PK estimation (`poppk-estimation`, `poppk-*`)

| Goal | Prompt |
|---|---|
| Base model | *Develop a popPK model for `data/pk-data-2.csv` (title "PopPK Analysis for ABC-111"). Start with a one-compartment model with first-order absorption, use SAEM, and report estimates, diagnostics and a VPC.* |
| Structural comparison | *In a new popPK version, compare one- and two-compartment models and a lag time on absorption; keep the OFV trail and pick the final model.* |
| Covariates | *Starting from the popPK v1 final model, test body weight on CL/F and V/F (power model centred at 70 kg) one at a time; use ΔOFV < −3.84 for inclusion.* |
| Error model | *The CWRES vs PRED plot for popPK v1 fans out; try proportional and combined residual error in a new version.* |
| Method check | *Refit the popPK v1 final model with FOCEi, starting from the SAEM estimates, and compare the estimates and SEs.* |
| Precision | *Run a 200-replicate bootstrap on the popPK v1 final model and add bootstrap CIs to the parameter table.* |
| Explain results | *Explain the popPK v1 results: which parameters are well estimated, and what are the caveats (shrinkage, RSE, diagnostics)?* |
| QC readiness | *Generate the spec and run the QC tests for popPK v1.* |
| Custom figure: EBEs vs covariate | *Add a figure to popPK v2: name `fig-ebe-wt`, title "Individual CL/F and V/F versus body weight", subtitle "Empirical Bayes estimates, final model", caption "Red: loess smooth". Content: individual CL/F and V/F (from the final fit) vs WT, two panels.* |
| Custom figure: parameter forest | *Add a figure to popPK v2: name `fig-param-forest`, title "Final-model parameter estimates with 95% CI". Content: one row per structural parameter, back-transformed estimate and CI, log x-axis.* |
| Custom table: individual parameters | *Add a table to popPK v2: name `tbl-ebe-individual`, title "Individual PK Parameters (Empirical Bayes Estimates)", footnotes "Final model run001"; "Min, Max = minimum and maximum". Content: rows = participants plus N / Mean / Median / Min, Max; columns = Ka, CL/F, V/F, with 3 significant figures.* |
| Custom table: shrinkage and BSV | *Add a table to popPK v2: name `tbl-eta-summary`, title "ETA Shrinkage and BSV by Parameter", footnotes "BSV = between-subject variability"; "Shrinkage on the SD scale". Content: rows = ETAs; columns = OMEGA variance, BSV (CV%), shrinkage (%).* |

### Simulation from a fitted model (`poppk-simulation`, source = `poppk-estimation`)

| Goal | Prompt |
|---|---|
| Regimen comparison | *Using the popPK v1 final model, simulate 320 mg q12h, 480 mg q12h and 640 mg q24h for 7 days and compare steady-state Cmax, Cmin and AUC0-24, including parameter uncertainty.* |
| Target attainment | *From the popPK v1 model, what fraction of subjects keep Cmin,ss above 5 mg/L and Cmax,ss below 20 mg/L for each regimen?* |
| Loading dose | *Simulate a 640 mg loading dose followed by 320 mg q12h from the popPK v1 model; how fast is steady state reached compared with no loading dose?* |
| Fitted population | *Resample the fitted ABC-111 subjects (their post-hoc ETAs) instead of drawing new ones, and simulate 400 mg q12h.* |
| Adaptive dosing / TDM | *Simulate TDM with the popPK v1 model: 320 mg q12h, and if the day-3 trough is below 5 mg/L, increase to 480 mg q12h.* |
| QC readiness | *Generate the spec and run the QC tests for simulation v1.* |

### Simulation from a model file (`poppk-simulation`, source = `model-file`)

| Goal | Prompt |
|---|---|
| Your own model | *Here is my model in `model/abc111-2cmt.R`. Simulate 100 mg IV bolus q24h for 5 days in 500 subjects and summarise steady-state exposure.* |
| Literature model | *Write a model file for a one-compartment oral model with CL/F = 3 L/h (30% CV), V/F = 35 L (15% CV) and Ka = 1.2 /h (from <reference>), save it in `model/`, and simulate 250 mg q12h.* |
| Library model | *Take `PK_2cmt_des` from nlmixr2lib, save it as a model file with these parameter values: ..., and simulate a 2 h infusion of 200 mg.* |
| Uncertainty without a fit | *Simulate `model/<name>.R` with parameter uncertainty: 20% CV on CL/F and V/F, 50 studies of 40 subjects.* |

### Across analyses

| Goal | Prompt |
|---|---|
| New study | *Set up this template for study XYZ-222: fill in project.yaml (conc ng/mL, time h, dose mg) and start an NCA version for `data/xyz222-pk.csv`.* |
| Custom output (template) | *Add a [figure / table] to [NCA / popPK / simulation] v{n}: name `[fig / tbl]-<short-name>`, title "…", subtitle "…", [caption "…" / footnotes "…"; "…"]. Content: [x, y, grouping, scale / rows, columns, statistics and formats].* |
| Status | *Which NCA, popPK and simulation versions exist, and what is each one's QC status?* |
| Cross-version query | *Query the popPK databases: list the OFV and final model of every popPK version.* |
| NCA vs popPK | *Compare the NCA v2 CL/F (dose/AUCinf) and half-life with the popPK v1 estimates.* |
| Everything before review | *Run all QC suites and tell me which versions are ready for QC.* |

## Provenance and QC

Each version's spec records:

- a hash of every script;
- a hash of the source data file, and of the data objects derived from it;
- the database's payload hash;
- the table and figure files with their hashes;
- the analysis decisions:
  - **NCA:** subjects with a λz span ratio below 2;
  - **popPK:** the model trail, the final model, its rationale, and the acceptance checks;
  - **simulation:** the model source, seed, and scenarios.

`qc.status` starts as `pending`. Only a reviewer sets it to `approved`; the skills never do.

A version is **ready for QC** when its test suite passes. The suites check that:

- **Scripts:** every script refers only to its own version and logs its runs; each script's latest log shows it ran to completion without errors.
- **Spec:** it matches its `.hash` sidecar, and its required fields are filled in.
- **Hashes:** the scripts, data, database and outputs still match what the spec recorded.
- **Results:** they are complete and plausible:
  - **NCA:** every subject has every requested parameter;
  - **popPK:** the model trail matches the stored fits, and the final model passes its acceptance checks;
  - **simulation:** the metrics recompute from the stored simulations, and re-simulating from the recorded seed reproduces the stored results exactly.
- **Tamper detection:** an edited spec, a changed output, and a corrupted database are each caught. These checks run on temporary copies only.

Each run of a suite writes a JUnit XML report to the version's `logs/` folder for the reviewer.

Links between analyses are hash-checked too. A simulation records its source popPK database and spec hashes, so refitting popPK v1 afterwards makes simulation v1's QC fail until the simulation is re-run.

## Evaluations

Test prompts for the skills, with graded expected behaviour, are in [`evals/`](../../../evals/README.md) (currently six tests on `pkmerge-theoph.csv` for data validation and NCA).

## Worked example: `examples/abc-111/`

A complete study built with these skills. It is its own project root: it has its own `project.yaml` and `.here`, plus a `.posit` link to the shared skills. To run anything in it, use `examples/abc-111/` as the working directory. NCA v1/v2, popPK v1 and simulation v1 predate the `templates/` folders and hard-code the ABC-111 titles. **NCA v3, popPK v2 and simulation v2 are built from the current templates** and are the reference for new work.

| Version | Analysis | Data / source | Outcome |
|---|---|---|---|
| `nca/v1` | Theophylline NCA | `data/pk-data.csv` | 12 subjects; λz span ratio < 2 for subjects 1, 9, 10 |
| `nca/v2` | PK Analysis for ABC-111 | `data/pk-data-2.csv` (NONMEM format, EVID 101) | Same results as v1 (same data, different format) |
| `nca/v3` | PK Analysis for ABC-111 | `data/pk-data-2.csv` | **Current templates**: same results as v1/v2, plus crane mean profiles, individual and λz regression plots one page per participant, "Source data:" footers, and the full report in `output/nca/v3/MAR/` |
| `poppk/v1` | PopPK Analysis for ABC-111 | `data/pk-data-2.csv` | 1-compartment SAEM; weight effect on CL/F not supported (ΔOFV −0.62); final model `run001`: CL/F 2.76 L/h, V/F 31.5 L |
| `poppk-sim/v1` | PopPK Simulation for ABC-111 | `poppk/v1` final model | 320 mg q12h vs 480 mg q12h vs 640 mg q24h at steady state; 100 subjects × 10 studies |
| `poppk/v2` | PopPK Analysis for ABC-111 | `data/pk-data-2.csv` | **Current templates**: same trail and results as v1 (run001 final, ΔOFV −0.62), plus GOF/individual/ETA/VPC/traceplot figures and tfrmt tables in the TLF shell, nlmixr2save fit archives and a shareable no-data final fit (`output/poppk/v2/fits/`) |
| `poppk-sim/v2` | PopPK Simulation for ABC-111 | `poppk/v2` final model | **Current templates**: same regimens and results as simulation v1 |

## Requirements

- **Environment:** R 4.5 and TinyTeX, so tables render as PDF. Without TinyTeX the tables fall back to RTF.
- **Packages:** tested with these versions:

| Area | Packages |
|---|---|
| NCA | PKNCA 0.12.1 |
| popPK and simulation | nlmixr2 7.0.1, rxode2 5.1.6, nlmixr2plot, patchwork, ggPMX |
| General | tidyverse |
| Data validation | pointblank |
| Tables | tfrmt 0.4.0, docorator 0.7.0, gt 1.3.0 |
| Storage | duckdb 1.5.5, DBI |
| Hashing and specs | rlang, yaml |
| Testing | testthat 3.3.1, withr, here |
| Logging | sessioncheck 0.2.0, whoami |

## Pitfalls

- **Unstable dataset hash:** read popPK data with `read_csv(..., lazy = FALSE) |> as.data.frame()`. A lazy readr tibble produces a different hash in every R session, so the spec's data hash can't be re-verified.
- **Comparable OFVs:** fit SAEM with `tableControl(cwres = TRUE, npde = TRUE)` so every run's OFV is the FOCEi approximation (NPDE is stored for the ggPMX diagnostics).
- **Renamed compartments:** always simulate with `useLinCmt = FALSE` (the simulation helpers already do). Otherwise rxode2 converts linear models to closed form and renames compartments, e.g. `center` → `central`.
- **Unsafe `rm(list = ls())`:** don't use it. `nca_log_start()` runs `sessioncheck` and logs what it finds.
- **Stale spec:** if a script is re-run after `generate-spec.R`, re-run `generate-spec.R` too. Otherwise the QC suite reports hash mismatches, by design.

## Credits

The `poppk-estimation` and `poppk-simulation` skills are adapted from the `estimation` and `simulation` skills in [nlmixr2llm](https://github.com/mattfidler/nlmixr2llm/tree/merge-john-harrold/inst/skills), branch `merge-john-harrold`. Their `references/*.md` files are included with attribution headers.

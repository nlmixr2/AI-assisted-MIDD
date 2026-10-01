---
name: poppk-simulation
description: Simulates PK/PD with rxode2 from a popPK fit or a model file: dosing regimens, population and trial simulations, parameter uncertainty and steady-state exposure metrics. Use when the user asks to simulate a regimen, predict exposure or compare doses.
---

# PopPK simulation with rxode2

## Overview

Adapted from the nlmixr2llm `simulation` skill
(<https://github.com/mattfidler/nlmixr2llm/tree/merge-john-harrold/inst/skills/simulation>),
restructured to follow this project's `pk-nca` / `poppk-*` conventions: a versioned script
directory, a results database, logged runs, a provenance spec, formatted outputs, and QC tests.

## When to use

Every simulation has three parts; produce all three:

1. **Model** — from one of two sources (below).
2. **Event table** — one `et()` per scenario (regimen) with doses and sampling times.
3. **Solve** — `rxSolve()` via `simulate_scenarios()`, then exposure metrics and inspection.

## What NOT to do

- Don't invent syntax; check rxode2's `inst/syntax-functions.csv` / `inst/reserved-keywords.csv`.
- Don't deliver pseudocode or a model that never compiled — run it.
- Don't refit, or edit a fitted model's estimates, inside a simulation.
- Don't skip or change the seed between runs of the same version.

## Choosing the model source

| The user… | `sim_source` | What you get |
|---|---|---|
| wants to simulate from a model **we fitted** ("use the v1 model", "simulate new regimens for ABC-111 from the popPK") | `list(type = "poppk-estimation", poppk_version = 1L)` (final model) or `..., run_id = "run002"` | the stored nlmixr2 fit, read hash-verified from `output/poppk/v1/db/poppk.duckdb` (`poppk-database`); estimated THETA/OMEGA/SIGMA, and **automatic parameter uncertainty** when `nStud > 1` (`thetaMat = fit$cov`, `dfSub`, `dfObs`). No refit. |
| **provides a model file** or asks for a new/literature model ("simulate this model", "here is the model") | `list(type = "model-file", path = "model/<name>.R")` | the file's single `ini()/model()` function, compiled; its values are the truth; uncertainty only via `prior()` lines or an explicit `thetaMat=` |
| **provides a saved nlmixr2 fit**, e.g. a data-free fit shared by another team ("simulate from this fit.zip") | `list(type = "fit-file", path = "model/<run>-noData.zip")` | the fit restored with `nlmixr2save` (`load_fit_archive()`): estimates, OMEGA/SIGMA and, when present, the covariance, so parameter uncertainty works as for a popPK fit. Provenance records the file hash, whether it holds subject data, and the model-code hash; the spec adds a `fit_file_source` caveat |

Rules for the source:

- **Fit source**: check the source popPK version's QC status (`spec/poppk/v{n}.yaml`); if it is not `approved`, the simulation spec records a caveat that results are provisional. Never refit inside a simulation; if the model needs changing, that is a new `poppk-estimation` version.
- **Model-file source**: keep model files in `model/` (under version control), one function per file, nothing else executed at source time, parameter origin stated in a header comment. Template: `file:///{skill_dir}/assets/model-file-template.R`. Don't silently change the user's parameter values; say so if you must.
- A library model (`nlmixr2lib::readModelDb("PK_2cmt_des")`) is used by writing it to a model file first (`cat(deparse(as.function(readModelDb(...))), sep = "\n")` into `model/<name>.R`), so it gets a file hash like any other.

## Core Process

**Scaffold, don't retype** (companion skill `pk-project`): `new_version("poppk-sim")` (or
`from = 1L`), edit the EDIT blocks (model source, scenarios, subjects/studies/seed, windows),
then `run_version("poppk-sim", n)`. The canonical, verified-working version is
`file:///{skill_dir}/templates/analysis-sim.R` (example: three steady-state regimens from
popPK v1's final model, 100 subjects × 10 studies); units and titles come from `project.yaml`.

1. **Libraries, log, helpers**:

```r
library(rxode2); library(nlmixr2); library(tidyverse)
source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- 1L
nca_log_start("analysis-sim", project_number = project_number, output_dir = "output/poppk-sim")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim.R")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_db.R")
```

2. **Load the model** (see the table above): `src <- load_sim_model(sim_source)` — returns
   `src$model` and `src$provenance` (hashes that tie the simulation to its source).
3. **Scenarios**: a named list of event tables plus a `scenario_info` table (scenario,
   description), and the steady-state `windows` (scenario, start, end — **one dosing
   interval**, e.g. 156–168 h for q12h, 144–168 h for q24h).
4. **Simulate** with a fixed base seed; scenario *i* uses `seed + i - 1`, so each scenario is
   independently reproducible:

```r
settings <- list(seed = 20260927L, nSub = 100L, nStud = 10L, var = "cp", windows = windows)
sims <- simulate_scenarios(src$model, scenarios, nSub = settings$nSub, nStud = settings$nStud,
                           seed = settings$seed)
```

   **Long simulations: optional `nlmixr2save` cache.** Set `CACHE_SIMS <- TRUE` in the EDIT
   block. The simulation then runs through `simulate_source()` with nlmixr2save's seed-aware
   `:=` and is saved as `output/poppk-sim/v{n}/cache/sims.rds`. A re-run with the same model
   content, scenarios, settings and seed restores it instead of re-simulating; any change
   re-simulates. `simulate_source()` takes only plain data (source, `sim_source_key()`,
   events), because a loaded fit object hashes differently in every session and would never
   hit the cache. It gives the same results as `simulate_scenarios()`, which the QC
   re-simulation check confirms.

5. **Metrics and sanity checks**: `exposure_metrics()` (per subject: Cmax, Tmax after dose,
   Cmin = trough, AUCτ, AUC0-24 = AUCτ × 24/τ), `summarise_exposure()` (median, 5th/95th),
   `summarise_profiles()`; `stopifnot()` finite, non-negative concentrations and
   `nSub × nStud` subjects per scenario.
6. **Persist** with `write_sim_db(...)` → `output/poppk-sim/v{n}/db/sim.duckdb` (local, git-ignored) plus its committed snapshot `db/snapshot/` (Parquet tables + xz payload; rebuilt into `sim.duckdb` automatically on a fresh clone); `nca_log_stop()`.

## Versioned run scripts & provenance

```
model/<name>.R                        # model-file source only (version-controlled, hashed)

script/poppk-sim/v{n}/
  analysis-sim.R                      # Core Process 1-6
  fig-sim-profiles.R                  # median + 90% PI: all regimens, then one page per regimen
  fig-exposure.R                      # Cmax/Cmin/AUC0-24 boxplots by regimen
  tbl-exposure-summary.R              # tfrmt: median [5th, 95th] per regimen
  generate-spec.R                     # spec/poppk-sim/v{n}.yaml            (templates/generate-spec.R)

tests/poppk-sim/v{n}/test-sim-qc.R    # QC-readiness suite (assets/test-sim-qc-template.R)

output/poppk-sim/v{n}/
  figures/, tables/, logs/ (incl. qc-tests-*.xml), db/sim.duckdb
```

**Run order:** `analysis-sim.R` → every `fig-*.R`/`tbl-*.R` → `generate-spec.R` →
`run_sim_qc_tests(n)`:

```r
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_qc_tests.R")
create_sim_qc_tests(1L)   # once per version (new_version("poppk-sim") already did it)
run_sim_qc_tests(1L)      # must pass before telling the user the version is ready for QC
```

Downstream scripts start with `read_sim_db(project_number)` (assigns `source_provenance`,
`settings`, `events`, `scenario_info`, `sims`, `metrics`, `exposure_summary`, `profiles`) —
never re-simulate outside `analysis-sim.R`.

All three render in the shared TLF shell (`render_tlf()`, pk-project), exactly like the NCA and
popPK outputs: PDF + `.RDS`, analysis title and page in the header (figures add their
`title`/`subtitle` as centred header lines, never in the ggplot), and "Source data: <model
source>" (`sim_source_data()`, e.g. "popPK v2 run001 (fitted to data/pk-data-2.csv)"),
script and date-time in the footer. Add custom outputs with `new_tlf("poppk-sim", n, ...)`.

The spec (`spec/poppk-sim/v{n}.yaml`) records: `source` (fit: popPK version, run, DB payload
hash, source spec hash + QC status, model-code hash; file: path, hash, function, model-code
hash), `simulation` (seed, nSub, nStud, uncertainty), `scenarios` (description, seed,
window, events hash), `data.sim_db`, `results.exposure_summary`, `diagnostics.caveats`,
hashed outputs, and `qc: pending`. Helpers: `scripts/poppk_sim_spec.R`, plus
`pk-nca-run-spec`'s `build_spec.R` and `poppk-run-spec`'s `annotate_outputs()`.

The QC suite additionally checks that the **model source is unchanged** (a refit of the source
popPK version, a regenerated source spec, or an edited model file fails it), that stored
metrics **re-derive** from the stored simulations, and that **re-simulating** the first
scenario from its recorded seed reproduces the stored rows exactly.

## Authoring rules

1. **Compartments are named by `d/dt(name)`.** Dose by that exact name (`cmt = "depot"`); initial conditions live in `model({})` (`depot(0) <- 0`).
2. **Order matters.** Algebraic definitions (`cp <- center / v`) must precede their use.
3. **Parameters.** Fixed values `<-` in `ini({})`; BSV `eta.cl ~ 0.1` entering as `cl <- exp(tcl + eta.cl)`; residual error `cp ~ add(add.sd)` only matters for simulated observations (`sim` column) — summarise exposure on `cp` (no noise).
4. **Override at solve time**, not by editing the model: `simulate_scenarios(..., params = c(tcl = log(4)))`; `params=` also takes a per-subject data frame keyed by `id`.
5. **Name the sampling argument**: `et(time = 0:24)`; an unnamed piped vector errors.
6. **Units**: keep event times in the model's time unit (hours vs days is the classic bug); state units in the scenario descriptions.
7. **Reproducibility**: `simulate_scenarios()` sets both `set.seed()` and `rxSetSeed()`; report the seed.
8. **Pipe; don't retype**: `fit |> ini(...)` / `|> model(...)` for what-ifs and protocols.
9. **`useLinCmt = FALSE`** is always passed (by `simulate_scenarios()`): otherwise a linear ODE model is converted to `linCmt()` and compartments are renamed (`center` → `central`), breaking `cmt=` and output columns.
10. **With `nStud`, rxode2 returns only `sim.id`**; `simulate_scenarios()` derives `study` and `id` from it.

## Event-table cheatsheet

```r
et(amt = 100, cmt = "depot") |> et(time = 0:24)                        # single dose
et(amt = 100, addl = 9, ii = 12, cmt = "depot") |> et(time = 0:120)    # q12h x 10
et(amt = 100, ii = 12, ss = 1, cmt = "depot") |> et(time = 0:24)       # steady state
et(amt = 100, rate = 10, cmt = "center") |> et(time = 0:24)            # infusion by rate
et(amt = 100, dur = 2, cmt = "center") |> et(time = 0:24)              # infusion by duration
```

`etRbind()` stacks event tables; NONMEM-style data frames are accepted directly.

## Population and trial simulation

- `nSub` draws new subjects from OMEGA; `nStud > 1` replicates trials, drawing population parameters per study (automatic from a fit; `thetaMat=`/`dfSub=`/`dfObs=` or `prior()` for a model file). `references/uncertainty-and-priors.md`.
- To keep **fitted subjects** (post-hoc ETAs with their covariates), pass a per-subject `params=` table and no `nSub`. `references/population-simulation.md`.
- **Adaptive dosing** (titration, holds, rescue, TDM): pipe `bolus()`/`infuse()` rules onto the model or fit. `references/adaptive-dosing.md`.
- Covariates: static ones as `params=` columns; time-varying ones merged into the event table.
- Keep the seed fixed across scenarios so differences come from the design, not the draws.

## Checks before reporting

- Subjects per scenario = `nSub × nStud`; concentrations finite and non-negative.
- Steady state actually reached in the window (enough `addl`; compare the last two troughs).
- Metrics computed on the right variable (`cp`, not `center` or `sim`) over one dosing interval.
- Source caveats (unapproved source QC, model-file parameter origin) stated with the results.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `compartment 'X' not found` / all-zero output with a "dose to compartment ... ignored" warning | `cmt=` doesn't match a `d/dt(X)` — or `useLinCmt` renamed it (rule 9) |
| `cannot simulate from the prior` | prior mean ≠ estimate (e.g. a prior-bearing fit); pass `usePrior = FALSE` |
| `parameter 'X' not found` | symbol not in `ini({})`, not a compartment, not in `params=`, not a data column |
| `improper arguments to 'et'` | unnamed sampling vector piped into `et()` |
| `non-finite values` / max steps | division by zero, stiff system (`method = "lsoda"`), wrong initial conditions |
| Every subject identical | no `~` random effects, or `nSub` not passed |
| `write_sim_db()` fails in `dbAppendTable` | an older `sim.duckdb` in that version has a different table schema — delete the version's db file and re-run `analysis-sim.R` |
| QC "model source is unchanged" fails | the source popPK version was refit / its spec regenerated, or the model file edited, after this simulation — re-run the simulation (new version if already in QC) |
| `load_sim_model()`: "must define exactly one model function" | the model file defines helpers too; keep one function per file |

## References

- `scripts/poppk_sim.R` — `load_sim_model()`, `simulate_scenarios()`, `exposure_metrics()`, `summarise_exposure()`, `summarise_profiles()`.
- `scripts/poppk_sim_db.R` — `write_sim_db()`, `read_sim_db()`, `query_sim_db()`.
- `scripts/poppk_sim_spec.R` — spec blocks; `templates/generate-spec.R`.
- `scripts/poppk_sim_qc_tests.R`, `assets/test-sim-qc-template.R` — QC suite.
- `templates/*.R` — verified analysis, figure and table scripts scaffolded by `new_version("poppk-sim")`; `assets/model-file-template.R`.
- `references/population-simulation.md`, `references/uncertainty-and-priors.md`, `references/adaptive-dosing.md` (upstream).
- rxode2 vignettes: `rxode2-intro`, `rxode2-syntax`, `rxode2-event-table`, `rxode2-sim-var`, `articles/rxode2-clinical-trial-sim`, `articles/rxode2-parameter-uncertainty`, `articles/adaptive-dosing`.
- Companion skills: `poppk-estimation` (source fits), `poppk-database`, `poppk-run-spec`, `pk-nca-logging`, `pk-nca-run-spec`.

Verified with rxode2 5.1.6 / nlmixr2 7.0.1.

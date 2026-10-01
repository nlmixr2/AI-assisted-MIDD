# `poppk-simulation`

Runs a versioned PK/PD simulation with rxode2 in `script/poppk-sim/v{n}/`. It simulates
dosing regimens from a fitted popPK model, a model file or a saved fit, computes
steady-state exposure, and keeps its own database, spec and QC suite.

## When it is used

- You ask to simulate a regimen or predict exposure ("what does exposure look like if...").
- You mention rxode2, `rxSolve()`, `et()`/`eventTable()`, `nSub`/`nStud`, `thetaMat`,
  `bolus()`, or `nlmixr2lib`/`readModelDb()`.
- The model comes from one of three sources:
  - a popPK version's fit ("simulate from the v1 model");
  - a model file you provide ("simulate this model");
  - a saved nlmixr2 fit archive, for example a data-free fit from another team.
- Fitting or changing a model is [poppk-estimation](poppk-estimation.md), never this skill.

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `sim.duckdb` | `output/poppk-sim/v{n}/db/` | Settings, events, simulated rows, per-subject metrics, summaries, profiles (local, git-ignored) |
| `snapshot/` | `output/poppk-sim/v{n}/db/` | Committed Parquet + xz copy; rebuilds `sim.duckdb` on a fresh clone |
| `fig-sim-profiles.pdf` | `output/poppk-sim/v{n}/figures/` | Median and 90% prediction interval: all regimens, then one page per regimen |
| `fig-exposure.pdf` | `output/poppk-sim/v{n}/figures/` | Cmax,ss, Cmin,ss and AUC0-24,ss boxplots by regimen |
| `tbl-exposure-summary.pdf` | `output/poppk-sim/v{n}/tables/` | Median [5th, 95th percentile] of Cmax,ss, Cmin,ss, AUC0-24,ss, Tmax,ss per regimen |
| `v{n}.yaml` (+ `.hash`) | `spec/poppk-sim/` | Source, settings, scenarios, database entry, exposure summary, caveats, hashed outputs, `qc: pending` |
| `test-sim-qc.R` | `tests/poppk-sim/v{n}/` | QC-readiness suite |
| Logs and `qc-tests-*.xml` | `output/poppk-sim/v{n}/logs/` | Run logs and JUnit QC reports |
| `sims.rds` (optional) | `output/poppk-sim/v{n}/cache/` | nlmixr2save cache, only when `CACHE_SIMS <- TRUE` |

Outputs are PDF plus `.RDS`, or RTF without TinyTeX. The footer's "Source data:" line names
the model source, for example "popPK v2 run001 (fitted to data/pk-data-2.csv)".

## How to use it

1. Scaffold a version from the project root (or copy one with `from =`):

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   new_version("poppk-sim")
   ```

2. Edit the `EDIT` blocks of `analysis-sim.R`:
   - **Model source** (`sim_source`):

     ```r
     sim_source <- list(type = "poppk-estimation", poppk_version = 1L)   # or run_id = "run002"
     sim_source <- list(type = "model-file", path = "model/<name>.R")
     sim_source <- list(type = "fit-file", path = "model/<run>-noData.zip")
     ```

   - **Scenarios**: one `et()` per regimen, a `scenario_info` table (scenario, description),
     and `windows` (scenario, start, end) covering one dosing interval at steady state, for
     example 156-168 h for q12h and 144-168 h for q24h.
   - **Settings**: `seed`, `nSub`, `nStud`, and `CACHE_SIMS` for long simulations.
3. For a model-file source, start from `assets/model-file-template.R`: one function with
   `ini({})` and `model({})`, nothing else, and the parameter origin in a header comment.
   To use an nlmixr2lib model, write it to a file in `model/` first.
4. Run the version: analysis, figures and table, spec, QC suite:

   ```r
   run_version("poppk-sim", 1L)
   ```

Typical prompts: "Using the popPK v1 final model, simulate 320 mg q12h, 480 mg q12h and
640 mg q24h for 7 days and compare steady-state Cmax, Cmin and AUC0-24"; "Here is my model
in `model/abc111-2cmt.R`. Simulate 100 mg IV bolus q24h"; "Generate the spec and run the QC
tests for simulation v1".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `load_sim_model(sim_source)` | Returns `model` and `provenance` (hashes that tie the simulation to its source) |
| `simulate_scenarios(model, scenarios, nSub, nStud, seed, keep, ...)` | Solves each scenario with seed `seed + i - 1`; always passes `useLinCmt = FALSE`; `...` goes to `rxSolve()` (e.g. `params =`) |
| `simulate_source()`, `sim_source_key()` | Cache-friendly entry point and content key for nlmixr2save's `:=` |
| `exposure_metrics(sims, var, windows)` | Per subject over the window: Cmax, Tmax (from window start), Cmin, AUC (trapezoid), AUC scaled to 24 h |
| `summarise_exposure()`, `summarise_profiles()` | Median and 5th/95th percentiles by scenario, and by scenario and time |
| `write_sim_db()`, `read_sim_db()`, `query_sim_db()` | Write, read back (hash-verified) and query the database |
| `sim_source_data(provenance)` | "Source data:" text for the TLF footer |
| `spec_sim_source()`, `spec_sim_settings()`, `spec_scenarios()`, `spec_exposure()` | Spec blocks (`scripts/poppk_sim_spec.R`) |
| `create_sim_qc_tests(n)`, `run_sim_qc_tests(n)` | Generate and run the QC suite |
| `templates/analysis-sim.R`, `fig-sim-profiles.R`, `fig-exposure.R`, `tbl-exposure-summary.R`, `generate-spec.R` | Scripts scaffolded by `new_version("poppk-sim")` |
| `references/population-simulation.md`, `uncertainty-and-priors.md`, `adaptive-dosing.md` | Resampling fitted subjects, parameter uncertainty and priors, dose rules |

## Rules and checks

- Only `analysis-sim.R` simulates. Other scripts start with `read_sim_db(project_number)`.
- Never refit, or edit a fitted model's estimates, inside a simulation.
- Keep the seed fixed. Scenario *i* uses `seed + i - 1`, so each one reproduces on its own.
- Summarise exposure on `cp`, not `sim` (which carries residual error) or a compartment.
- Keep event times in the model's time unit, and name the sampling argument: `et(time = 0:24)`.
- Dose by the compartment name in `d/dt(name)`, for example `cmt = "depot"`.
- `nStud > 1` adds parameter uncertainty: automatic for a fit (`thetaMat = fit$cov`, `dfSub`,
  `dfObs`); for a model file only via `prior()` lines or an explicit `thetaMat=`.
- The analysis stops unless concentrations are finite and non-negative and each scenario has
  `nSub x nStud` subjects. Also check that steady state is reached in the window.
- The spec records caveats: an unapproved source popPK QC status (results provisional), a
  model-file source, or a fit-file source.
- The QC suite also checks that the model source is unchanged (no refit of the source
  version, no regenerated source spec, no edited model file), that metrics re-derive from
  the stored simulations, and that re-simulating the first scenario reproduces its rows.
- Verified with rxode2 5.1.6 and nlmixr2 7.0.1.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `compartment 'X' not found`, or all-zero output with a "dose to compartment ... ignored" warning | `cmt=` does not match a `d/dt(X)`, or `useLinCmt` renamed it |
| `cannot simulate from the prior` | Prior mean differs from the estimate; pass `usePrior = FALSE` |
| `parameter 'X' not found` | Symbol not in `ini({})`, not a compartment, not in `params=`, not a data column |
| `improper arguments to 'et'` | Unnamed sampling vector piped into `et()` |
| Every subject identical | No `~` random effects, or `nSub` not passed |
| `write_sim_db()` fails in `dbAppendTable` | An older `sim.duckdb` in that version has a different schema; remove that version's db file and re-run `analysis-sim.R` |
| QC "model source is unchanged" fails | The source popPK version was refit or its spec regenerated, or the model file edited. Re-run the simulation (a new version if it is already in QC) |
| "must define exactly one model function" | The model file defines helpers too; keep one function per file |

## Related

- [poppk-estimation](poppk-estimation.md), [poppk-database](poppk-database.md),
  [poppk-run-spec](poppk-run-spec.md), [poppk-qc-tests](poppk-qc-tests.md),
  [pk-project](pk-project.md), [pk-nca-logging](pk-nca-logging.md)
- Source: [SKILL.md](../../.posit/assistant/skills/poppk-simulation/SKILL.md)
- Workflow guide: [Population PK workflow](../poppk/README.md)

# PopPK simulation -- v{{project_number}}.
# Generated from the poppk-simulation skill's templates/analysis-sim.R by new_version("poppk-sim").
# Edit the blocks marked EDIT; the rest is the verified standard pipeline.
# Writes output/poppk-sim/v{{project_number}}/db/sim.duckdb (poppk-simulation); downstream
# tbl-*.R / fig-*.R scripts read_sim_db(project_number) instead of re-simulating.

library(rxode2)
library(nlmixr2)
library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("analysis-sim", project_number = project_number, output_dir = "output/poppk-sim")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()

source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim.R")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_db.R")

## 1. Model source -- EDIT --------------------------------------------------------
nca_log_section("1. Model source")
# One of: a poppk-estimation version (its final model, or run_id = "runNNN"); a model file
# list(type = "model-file", path = "model/<name>.R"); or an nlmixr2save fit archive
# list(type = "fit-file", path = "model/<run>-noData.zip") (e.g. a shared fit).

sim_source <- list(type = "poppk-estimation", poppk_version = 1L)
src <- load_sim_model(sim_source)
str(src$provenance, max.level = 2)

## 2. Scenarios -- EDIT: one event table per regimen (dose and time in project.yaml units)
nca_log_section("2. Scenarios")

sampling <- seq(0, 168, by = 1)
scenarios <- list(
  "320 mg q12h" = et(amt = 320, ii = 12, addl = 13, cmt = "depot") |> et(time = sampling),
  "480 mg q12h" = et(amt = 480, ii = 12, addl = 13, cmt = "depot") |> et(time = sampling),
  "640 mg q24h" = et(amt = 640, ii = 24, addl = 6,  cmt = "depot") |> et(time = sampling)
)
scenario_info <- tribble(
  ~scenario,     ~description,
  "320 mg q12h", "320 mg orally every 12 h for 7 days (14 doses)",
  "480 mg q12h", "480 mg orally every 12 h for 7 days (14 doses)",
  "640 mg q24h", "640 mg orally every 24 h for 7 days (7 doses); same daily dose as 320 mg q12h"
)

## 3. Simulate -- EDIT: subjects, studies, seed, steady-state windows -------------------
nca_log_section("3. Simulate")
# nStud > 1 draws population parameters from the fit's covariance (uncertainty);
# nSub subjects per study are drawn from OMEGA.

# Steady-state window = last dosing interval of day 7 (tau = 12 h or 24 h).
windows <- tribble(
  ~scenario,     ~start, ~end,
  "320 mg q12h", 156,    168,
  "480 mg q12h", 156,    168,
  "640 mg q24h", 144,    168
)
settings <- list(seed = 20260927L, nSub = 100L, nStud = 10L, var = "cp", windows = windows)
# Optional nlmixr2save cache (seed-aware `:=`): set TRUE for long simulations. An unchanged
# call (same model, scenarios, settings and starting random state) is restored from
# output/poppk-sim/v{n}/cache/sims.rds instead of re-simulated; any change re-simulates.
CACHE_SIMS <- FALSE
if (CACHE_SIMS) {
  library(nlmixr2save)
  saveFitRandom("simulate_source")
  options(nlmixr2save.dir = sprintf("output/poppk-sim/v%d/cache", project_number), nlmixr2save.prefix = "")
  source(".posit/assistant/skills/poppk-estimation/scripts/poppk_fits.R")   # with_message_sink()
  # := checks the starting random state; fix it (results are unaffected: simulate_scenarios()
  # seeds every scenario itself). Namespace-qualified: rlang/data.table also export `:=`.
  sim_seed(settings$seed)
  # simulate_source(): plain-data arguments (source, content key, events), so the cache key is
  # stable across sessions; identical results to simulate_scenarios().
  with_message_sink(nlmixr2save::`:=`(sims, simulate_source(
    sim_source, sim_source_key(src$provenance), scenario_events_df(scenarios),
    nSub = settings$nSub, nStud = settings$nStud, seed = settings$seed)))
  message("Simulations ", if (isTRUE(nlmixr2save::.assignRestore())) "restored from the nlmixr2save cache" else "run and cached")
} else {
  sims <- simulate_scenarios(src$model, scenarios, nSub = settings$nSub, nStud = settings$nStud,
                             seed = settings$seed)
}

## 4. Exposure metrics over the last dosing interval (steady state) and sanity checks ---
nca_log_section("4. Exposure metrics over the last dosing interval (steady state) and sanity checks")

metrics <- exposure_metrics(sims, var = settings$var, windows = settings$windows)
exposure_summary <- summarise_exposure(metrics)
profiles <- summarise_profiles(sims, var = settings$var)
print(exposure_summary, n = Inf)

stopifnot(
  all(is.finite(sims$cp)), all(sims$cp >= 0),
  all(count(metrics, scenario)$n == settings$nSub * settings$nStud)
)

## 5. Persist -------------------------------------------------------------------------
nca_log_section("5. Persist")

write_sim_db(project_number, source_provenance = src$provenance, settings = settings,
             scenarios = scenarios, scenario_info = scenario_info, sims = sims,
             metrics = metrics, exposure_summary = exposure_summary, profiles = profiles)

nca_log_stop()

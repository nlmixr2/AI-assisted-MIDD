# Helpers for a versioned popPK simulation (script/poppk-sim/v{n}/analysis-sim.R).
# Source this file, then:
#
#   src  <- load_sim_model(sim_source)           # model + provenance, from a poppk-estimation
#                                                 # version's fit OR from a model file
#   sims <- simulate_scenarios(src$model, scenarios, nSub = 100, nStud = 10, seed = 20260927)
#   met  <- exposure_metrics(sims, var = "cp", windows)   # windows: scenario, start, end
#   smry <- summarise_exposure(met)
#   prof <- summarise_profiles(sims, var = "cp")
#
# Two model sources (`sim_source`):
#   list(type = "poppk-estimation", poppk_version = 1L)             # final model of popPK v1
#   list(type = "poppk-estimation", poppk_version = 1L, run_id = "run002")
#   list(type = "model-file", path = "model/abc111-1cmt.R")         # file defining one ini/model function
#   list(type = "fit-file", path = "model/run001-noData.zip")       # nlmixr2save fit archive (saveFit /
#                                                                   # nlmixr2saveShare), e.g. a shared fit
#
# All paths are relative to the current working directory (the project root).

library(rxode2)
library(dplyr)
library(rlang)

# Project root at source time. nlmixr2save's `:=` evaluates the cached call from inside its
# cache directory, so simulate_source() switches back here before resolving any relative path.
.sim_project_root <- normalizePath(".")

#' Set both the R and the rxode2 seed (upstream rule 7).
sim_seed <- function(seed) {
  set.seed(seed)
  rxode2::rxSetSeed(seed)
  invisible(seed)
}

#' Load the model to simulate from, plus its provenance.
#'
#' - `type = "poppk-estimation"`: reads `output/poppk/v{n}/db/poppk.duckdb` via
#'   `read_poppk_db()` (hash-verified) and returns that version's final fit (or
#'   `run_id`). Simulating a fit gives estimated THETA/OMEGA/SIGMA and automatic
#'   parameter uncertainty (`thetaMat = fit$cov`, `dfSub`, `dfObs`) when `nStud > 1`.
#'   Provenance records the database payload hash and the source spec's hash + QC status.
#' - `type = "model-file"`: sources the file into a clean environment; it must define
#'   exactly one function with `ini({})`/`model({})`. Provenance records the file hash.
#' - `type = "fit-file"`: loads a fit saved with nlmixr2save (e.g. a data-free
#'   `<run>-noData.zip`) via `load_fit_archive()`; like a popPK fit it carries estimates,
#'   OMEGA/SIGMA and the covariance. Provenance records the file hash.
#'
#' @return list(model, provenance)
load_sim_model <- function(sim_source) {
  type <- sim_source$type
  if (identical(type, "poppk-estimation")) {
    source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R", local = TRUE)
    pn <- as.integer(sim_source$poppk_version)
    env <- new.env()
    meta <- read_poppk_db(pn, envir = env)
    run_id <- sim_source$run_id %||% env$final_run
    if (!run_id %in% names(env$fits)) stop("run_id '", run_id, "' not in popPK v", pn, call. = FALSE)
    fit <- env$fits[[run_id]]
    spec_path <- file.path("spec/poppk", sprintf("v%d.yaml", pn))
    qc_status <- if (file.exists(spec_path)) yaml::read_yaml(spec_path)$qc$status else NA_character_
    list(
      model = fit,
      provenance = list(
        type = type,
        poppk_version = pn,
        run_id = run_id,
        is_final_model = identical(run_id, env$final_run),
        poppk_db = list(path = poppk_db_path(pn), payload_hash = meta$payload_hash),
        spec = list(path = spec_path,
                    hash = if (file.exists(spec_path)) hash_file(spec_path) else NA_character_,
                    qc_status = qc_status),
        model_hash = hash(deparse(as.function(fit$ui)))
      )
    )
  } else if (identical(type, "model-file")) {
    path <- sim_source$path
    if (!file.exists(path)) stop("Model file not found: ", path, call. = FALSE)
    env <- new.env()
    sys.source(path, envir = env, keep.source = TRUE)
    fns <- Filter(is.function, as.list(env))
    if (length(fns) != 1) {
      stop(path, " must define exactly one model function (found ", length(fns), ")", call. = FALSE)
    }
    model <- rxode2::rxode2(fns[[1]])   # compile once; fails fast on syntax errors
    list(
      model = model,
      provenance = list(
        type = type,
        path = path,
        hash = hash_file(path),
        function_name = names(fns),
        model_hash = hash(deparse(as.function(model)))
      )
    )
  } else if (identical(type, "fit-file")) {
    # A fit saved with nlmixr2save (saveFit(), the `:=` cache, or nlmixr2saveShare() -- e.g. a
    # data-free <run>-noData.zip received from another team). It carries estimates, OMEGA/SIGMA
    # and the covariance, so nStud > 1 gives parameter uncertainty as for a poppk fit.
    source(".posit/assistant/skills/poppk-estimation/scripts/poppk_fits.R", local = TRUE)
    path <- sim_source$path
    fit <- load_fit_archive(path)
    list(
      model = fit,
      provenance = list(
        type = type,
        path = path,
        hash = hash_file(path),
        has_subject_data = !is.null(fit$origData),
        has_covariance = !is.null(fit$cov),
        est = fit$est,
        model_hash = hash(deparse(as.function(fit$ui)))
      )
    )
  } else {
    stop("sim_source$type must be 'poppk-estimation', 'model-file' or 'fit-file'", call. = FALSE)
  }
}

#' Simulate every scenario with the same design and a per-scenario seed.
#'
#' Each scenario is solved with `seed + i - 1` (i = scenario index), so any one
#' scenario can be re-simulated on its own and reproduce its stored rows exactly
#' (the QC tests do this). `useLinCmt = FALSE` keeps compartment names as written.
#'
#' @param model An nlmixr2 fit or rxode2 model/function.
#' @param scenarios Named list of event tables (`et()`), one per scenario.
#' @param nSub Subjects per study; `nStud` studies (> 1 adds parameter uncertainty).
#' @param seed Base seed.
#' @param keep Output columns to keep (besides scenario/sim.id/time).
#' @param ... Passed to `rxSolve()` (e.g. `params=`, `thetaMat=`, `usePrior = FALSE`).
#' @return data frame: scenario, study, id, sim.id, time, `keep` columns.
simulate_scenarios <- function(model, scenarios, nSub, nStud = 1L, seed, keep = c("cp", "sim"), ...) {
  stopifnot(is.list(scenarios), !is.null(names(scenarios)), all(nzchar(names(scenarios))))
  out <- lapply(seq_along(scenarios), function(i) {
    sim_seed(seed + i - 1L)
    s <- rxSolve(model, scenarios[[i]], nSub = nSub, nStud = nStud, useLinCmt = FALSE,
                 returnType = "data.frame", ...)
    missing <- setdiff(keep, names(s))
    if (length(missing)) stop("rxSolve output lacks: ", paste(missing, collapse = ", "), call. = FALSE)
    tibble(
      scenario = names(scenarios)[i],
      study = (s$sim.id - 1L) %/% nSub + 1L,
      id = (s$sim.id - 1L) %% nSub + 1L,
      sim.id = s$sim.id,
      time = s$time,
      !!!s[keep]
    )
  })
  bind_rows(out) |> mutate(scenario = factor(scenario, levels = names(scenarios)))
}

#' "Source data:" text for a simulation's tables and figures: where the model came from and,
#' for a popPK source, the dataset it was fitted to.
sim_source_data <- function(provenance) {
  p <- provenance
  if (identical(p$type, "poppk-estimation")) {
    fitted_to <- tryCatch(yaml::read_yaml(p$spec$path)$data$source_file$path, error = function(e) NULL)
    sprintf("popPK v%d %s%s", p$poppk_version, p$run_id,
            if (length(fitted_to)) sprintf(" (fitted to %s)", fitted_to) else "")
  } else if (identical(p$type, "fit-file")) {
    sprintf("nlmixr2save fit archive %s", p$path)
  } else {
    sprintf("model file %s", p$path)
  }
}

#' Content key of a model source: changes whenever the model code, the source file, or the
#' source popPK database changes (used as the nlmixr2save cache key for simulations).
sim_source_key <- function(provenance) {
  hash(list(provenance$type, provenance$model_hash, provenance$hash,
            provenance$poppk_db$payload_hash, provenance$run_id))
}

#' Cache-friendly simulation entry point for nlmixr2save's seed-aware `:=`.
#'
#' Every argument is plain data (the source description, its content key, events as a
#' data frame, settings), so `:=` computes a stable cache key across R sessions -- a loaded
#' fit object would hash differently every time. The model is loaded inside; if its content
#' no longer matches `source_key`, this stops rather than returning a stale result.
#' Results equal simulate_scenarios() with the same events and seed.
#'
#' @param events scenario_events_df(scenarios): all scenarios' events with a `scenario` column.
simulate_source <- function(sim_source, source_key, events, nSub, nStud = 1L, seed, keep = c("cp", "sim")) {
  old <- setwd(.sim_project_root)
  on.exit(setwd(old), add = TRUE)
  src <- load_sim_model(sim_source)
  if (!identical(sim_source_key(src$provenance), source_key)) {
    stop("Model source changed since source_key was computed -- recompute it", call. = FALSE)
  }
  lv <- unique(events$scenario)
  scenarios <- lapply(setNames(lv, lv), function(s) {
    e <- events[events$scenario == s, setdiff(names(events), "scenario")]
    rownames(e) <- NULL
    e
  })
  simulate_scenarios(src$model, scenarios, nSub = nSub, nStud = nStud, seed = seed, keep = keep)
}

#' Per-subject exposure over each scenario's window: Cmax, Tmax (from window start),
#' Cmin, AUC over the window (linear trapezoid), and AUC scaled to 24 h.
#'
#' Use one dosing interval at steady state as the window (e.g. 156-168 h for q12h,
#' 144-168 h for q24h): Tmax is then time after dose, Cmin is the trough, AUC is
#' AUCtau, and auc24 = AUCtau * 24 / tau is AUC0-24,ss (exact at steady state), so
#' regimens with different intervals are comparable.
#'
#' @param windows data frame: scenario, start, end (one row per scenario).
exposure_metrics <- function(sims, var = "cp", windows) {
  stopifnot(setequal(as.character(windows$scenario), levels(sims$scenario)))
  sims |>
    inner_join(mutate(windows, scenario = factor(scenario, levels = levels(sims$scenario))),
               by = "scenario") |>
    filter(time >= start, time <= end) |>
    arrange(scenario, sim.id, time) |>
    group_by(scenario, study, id, sim.id) |>
    summarise(
      cmax = max(.data[[var]]),
      tmax = time[which.max(.data[[var]])] - first(start),
      cmin = min(.data[[var]]),
      auc = sum(diff(time) * (head(.data[[var]], -1) + tail(.data[[var]], -1)) / 2),
      auc24 = auc * 24 / (first(end) - first(start)),
      .groups = "drop"
    )
}

#' Median and 5th/95th percentiles of each metric by scenario.
summarise_exposure <- function(metrics, probs = c(0.05, 0.5, 0.95)) {
  metrics |>
    tidyr::pivot_longer(c(cmax, tmax, cmin, auc, auc24), names_to = "metric", values_to = "value") |>
    group_by(scenario, metric) |>
    summarise(n = n(),
              p05 = quantile(value, probs[1]), median = quantile(value, probs[2]),
              p95 = quantile(value, probs[3]), .groups = "drop")
}

#' Median and 5th/95th percentile profile over time by scenario (for figures).
summarise_profiles <- function(sims, var = "cp", probs = c(0.05, 0.5, 0.95)) {
  sims |>
    group_by(scenario, time) |>
    summarise(p05 = quantile(.data[[var]], probs[1]), median = quantile(.data[[var]], probs[2]),
              p95 = quantile(.data[[var]], probs[3]), .groups = "drop")
}

#' Event table -> plain data frame (for storage/hashing; et objects hold environments).
scenario_events_df <- function(scenarios) {
  bind_rows(lapply(names(scenarios), function(nm) {
    mutate(as.data.frame(scenarios[[nm]]), scenario = nm, .before = 1)
  }))
}

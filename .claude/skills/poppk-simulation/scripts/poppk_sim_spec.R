# Simulation-specific helpers for building spec/poppk-sim/v{project_number}.yaml.
# Generic provenance helpers come from pk-nca-run-spec's scripts/build_spec.R
# (pass script_dir = "script/poppk-sim", output_dir = "output/poppk-sim",
# spec_dir = "spec/poppk-sim"); annotate_outputs() from poppk-run-spec's
# scripts/poppk_spec.R.
#
#   spec_sim_source(source_provenance)          -> `source` block
#   spec_sim_settings(settings)                 -> `simulation` block
#   spec_scenarios(scenario_info, events, settings) -> `scenarios` block
#   spec_exposure(exposure_summary)             -> `results.exposure_summary`

spec_sim_source <- function(source_provenance) {
  p <- source_provenance
  if (p$type == "poppk-estimation") {
    list(type = p$type, poppk_version = p$poppk_version, run_id = p$run_id,
         is_final_model = p$is_final_model, poppk_db = p$poppk_db,
         poppk_spec = p$spec, model_hash = p$model_hash)
  } else if (p$type == "fit-file") {
    list(type = p$type, path = p$path, hash = p$hash, est = p$est,
         has_subject_data = p$has_subject_data, has_covariance = p$has_covariance,
         model_hash = p$model_hash)
  } else {
    list(type = p$type, path = p$path, hash = p$hash,
         function_name = p$function_name, model_hash = p$model_hash)
  }
}

spec_sim_settings <- function(settings) {
  list(seed = as.integer(settings$seed), n_sub = as.integer(settings$nSub),
       n_stud = as.integer(settings$nStud),
       parameter_uncertainty = settings$nStud > 1,
       exposure_variable = settings$var,
       seed_rule = "scenario i is solved with seed + i - 1")
}

spec_scenarios <- function(scenario_info, events, settings) {
  lapply(seq_len(nrow(scenario_info)), function(i) {
    sc <- scenario_info$scenario[i]
    w <- settings$windows[settings$windows$scenario == sc, ]
    list(name = sc, description = scenario_info$description[i],
         seed = as.integer(settings$seed) + i - 1L,
         window = list(start = w$start, end = w$end),
         events_hash = rlang::hash(events[events$scenario == sc, ]))
  })
}

spec_exposure <- function(exposure_summary) {
  lapply(seq_len(nrow(exposure_summary)), function(i) {
    r <- exposure_summary[i, ]
    list(scenario = as.character(r$scenario), metric = r$metric, n = as.integer(r$n),
         p05 = signif(r$p05, 5), median = signif(r$median, 5), p95 = signif(r$p95, 5))
  })
}

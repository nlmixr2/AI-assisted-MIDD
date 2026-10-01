# popPK-specific helpers for building spec/poppk/v{project_number}.yaml.
# The generic provenance helpers (collect_run_metadata(), collect_data_provenance(),
# hash_data(), list_outputs(), write_spec(), verify_spec(), verify_outputs()) come
# from the pk-nca-run-spec skill's scripts/build_spec.R -- source it too and pass
# script_dir = "script/poppk", output_dir = "output/poppk", spec_dir = "spec/poppk".
#
#   spec_models(runs, fits)                 -> `models` block (the model-building trail)
#   spec_final_model(fit, final_run, checks, rationale) -> `final_model` block
#   spec_caveats(checks)                    -> `diagnostics.caveats` (warn-level checks)
#   annotate_outputs(paths, descriptions)   -> `outputs.tables` / `outputs.figures` entries

#' One spec entry per run: id, parent, description, method, OFV, dOFV, parameters.
spec_models <- function(runs, fits) {
  lapply(seq_len(nrow(runs)), function(i) {
    r <- runs[i, ]
    fit <- fits[[r$run_id]]
    list(
      run_id = r$run_id,
      parent_run = if (is.na(r$parent_run)) NULL else r$parent_run,
      description = r$description,
      est = r$est,
      objf = round(r$objf, 4),
      delta_ofv = if (is.na(r$delta_ofv)) NULL else round(r$delta_ofv, 4),
      n_par = as.integer(r$n_par),
      cov_ok = isTRUE(r$cov_ok),
      model_hash = rlang::hash(deparse(as.function(fit$ui)))   # fingerprint of the model code
    )
  })
}

#' The selected final model: id, method, OFV, rationale, estimates, and checks.
spec_final_model <- function(fit, final_run, checks, rationale) {
  pf <- fit$parFixedDf
  list(
    run_id = final_run,
    est = fit$est,
    objf = round(fit$objf, 4),
    rationale = rationale,
    parameters = lapply(rownames(pf), function(p) {
      list(name = p,
           estimate = signif(pf[p, "Back-transformed"], 5),
           rse = if (is.na(pf[p, "%RSE"])) NULL else round(pf[p, "%RSE"], 2),
           bsv_cv = if (is.na(pf[p, "BSV(CV%)"])) NULL else round(pf[p, "BSV(CV%)"], 2))
    }),
    acceptance_checks = lapply(seq_len(nrow(checks)), function(i) {
      list(check = checks$check[i], status = checks$status[i], detail = checks$detail[i])
    })
  )
}

#' Warn-level acceptance checks, to record as caveats in the spec.
spec_caveats <- function(checks) {
  w <- checks[checks$status == "warn", ]
  lapply(seq_len(nrow(w)), function(i) list(check = w$check[i], detail = w$detail[i]))
}

#' Spec output entries (path, description, hash) for a vector of output files.
annotate_outputs <- function(paths, descriptions) {
  lapply(paths, function(p) {
    entry <- list(path = p,
                  description = unname(descriptions[tools::file_path_sans_ext(basename(p))]),
                  hash = rlang::hash_file(p))
    entry$display_rds <- display_rds_entry(p)   # gt object behind a table (build_spec.R)
    entry
  })
}

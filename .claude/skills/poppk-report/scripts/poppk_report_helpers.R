# popPK-specific helpers used inside the popPK report (output/poppk/v{n}/MAR/*.qmd). Loaded
# by MAR/_setup.R after pk-nca-report's nca_report_helpers.R, which supplies the shared ones
# (nca_output_display(), print_table_display(), write_display_png(), report_table(),
# run_log_table(), latest_qc_result(), ...). Everything is read from the version's database
# (read_poppk_db()) and spec -- nothing is refitted or recomputed.

#' Model dataset summary: participants, observation and dose records, doses, time range,
#' covariate columns (anything beyond the NONMEM-style record columns).
poppk_data_summary <- function(pkData) {
  obs <- pkData$EVID == 0
  dose <- pkData$EVID != 0 & pkData$AMT > 0
  record_cols <- c("ID", "TIME", "DV", "AMT", "EVID", "CMT", "MDV", "DVID", "CENS", "LIMIT",
                   "RATE", "DUR", "II", "ADDL", "SS")
  list(
    n_subjects = length(unique(pkData$ID)),
    n_obs = sum(obs),
    n_doses = sum(dose),
    doses = sort(unique(signif(pkData$AMT[dose], 4))),
    time_range = range(pkData$TIME[obs]),
    other_cols = setdiff(names(pkData), record_cols)
  )
}

#' Model trail from the spec (models[]): one row per run, final run marked. Descriptions
#' and method are in tbl-model-comparison, so they are not repeated here.
spec_model_trail <- function(spec) {
  num <- function(x, d) if (is.null(x)) "--" else formatC(x, format = "f", digits = d)
  dplyr::bind_rows(lapply(spec$models, function(m) tibble::tibble(
    Run = paste0(m$run_id, if (identical(m$run_id, spec$final_model$run_id)) " (final)" else ""),
    Parent = m$parent_run %||% "--",
    OFV = num(m$objf, 2),
    dOFV = num(m$delta_ofv, 2),
    `N par` = as.character(m$n_par %||% "--"),
    `Cov. step` = if (isTRUE(m$cov_ok)) "yes" else "no"
  )))
}

#' Acceptance checks of the final model as recorded in the spec (poppk-estimation).
spec_acceptance_checks <- function(spec) {
  dplyr::bind_rows(lapply(spec$final_model$acceptance_checks, function(k) tibble::tibble(
    Check = md_escape(k$check), Status = k$status, Detail = md_escape(k$detail %||% "")
  )))
}

#' Fit archives (nlmixr2save) recorded in the spec, with hashes.
spec_fit_archives <- function(spec) {
  dplyr::bind_rows(lapply(spec$fit_archives, function(a) tibble::tibble(
    Run = a$run_id %||% "--", File = a$path, Hash = a$hash
  )))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

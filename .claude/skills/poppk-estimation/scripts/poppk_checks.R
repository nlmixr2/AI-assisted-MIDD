# Run-summary and acceptance-check helpers for a versioned popPK analysis
# (script/poppk/v{n}/analysis-poppk.R). Source this file, then:
#
#   runs   <- summarise_runs(fits, run_info)   # one row per run: OFV, AIC, BIC, dOFV vs parent, ...
#   checks <- acceptance_checks(fits$run002)   # pass / warn / fail per acceptance check
#
# `run_info` is a data frame with columns run_id, parent_run (NA for the base
# model), and description -- the model-building trail, written by the analyst.
#
# acceptance_checks() encodes the poppk-estimation skill's "Acceptance checks
# before reporting": a `fail` blocks reporting (and the QC tests); a `warn` must be
# recorded as a caveat in the spec's diagnostics.

library(dplyr)

#' Structural (non-residual, non-fixed) THETA names of a fit.
structural_thetas <- function(fit) {
  ini <- fit$iniDf
  ini$name[!is.na(ini$ntheta) & is.na(ini$err) & !ini$fix]
}

#' Estimated-parameter count (THETAs + OMEGA elements, excluding fixed ones).
n_estimated <- function(fit) sum(!fit$iniDf$fix)

#' Summarise every run: fit statistics plus dOFV vs its parent run.
#'
#' @param fits Named list of nlmixr2 fits (names = run IDs).
#' @param run_info Data frame: run_id, parent_run, description.
#' @param final_run Optional run ID to mark as final.
summarise_runs <- function(fits, run_info, final_run = NA_character_) {
  stopifnot(setequal(run_info$run_id, names(fits)))
  rows <- lapply(names(fits), function(id) {
    fit <- fits[[id]]
    obj <- fit$objDf
    tibble(
      run_id = id,
      est = fit$est,
      objf = fit$objf,
      aic = obj$AIC[1], bic = obj$BIC[1],
      n_id = length(unique(fit$ID)),
      n_obs = nrow(fit),
      n_par = n_estimated(fit),
      cov_ok = !is.null(fit$cov) && all(!is.na(fit$parFixedDf[structural_thetas(fit), "SE"]))
    )
  })
  out <- left_join(run_info, bind_rows(rows), by = "run_id")
  out$delta_ofv <- out$objf - out$objf[match(out$parent_run, out$run_id)]
  out$delta_par <- out$n_par - out$n_par[match(out$parent_run, out$run_id)]
  out$final <- out$run_id == final_run
  out
}

#' Acceptance checks for one fit.
#'
#' @param fit An nlmixr2 fit.
#' @param max_rse %RSE above which a structural THETA is flagged (warn).
#' @param max_shrink ETA SD-shrinkage (%) above which an ETA is flagged (warn).
#' @return A tibble: check, status ("pass"/"warn"/"fail"), detail.
acceptance_checks <- function(fit, max_rse = 50, max_shrink = 30) {
  pf <- fit$parFixedDf
  ini <- fit$iniDf
  th <- structural_thetas(fit)
  res <- list()
  add <- function(check, ok, detail, fail_status = "fail") {
    res[[length(res) + 1]] <<- tibble(check = check,
                                      status = if (ok) "pass" else fail_status,
                                      detail = detail)
  }

  add("ofv_finite", is.finite(fit$objf), sprintf("OFV = %.3f", fit$objf))
  add("covariance_step", !is.null(fit$cov), if (is.null(fit$cov)) "covariance step failed" else "covariance available")

  se_missing <- th[is.na(pf[th, "SE"])]
  add("structural_se_present", length(se_missing) == 0,
      if (length(se_missing)) paste("SE missing:", paste(se_missing, collapse = ", ")) else "all structural SEs present")

  thetas <- ini[!is.na(ini$ntheta) & !ini$fix, ]
  est <- fit$theta[thetas$name]
  tol <- 1e-4 * pmax(1, abs(est))
  on_bound <- thetas$name[(is.finite(thetas$lower) & abs(est - thetas$lower) < tol) |
                          (is.finite(thetas$upper) & abs(est - thetas$upper) < tol)]
  add("theta_not_on_bound", length(on_bound) == 0,
      if (length(on_bound)) paste("on bound:", paste(on_bound, collapse = ", ")) else "no THETA on a bound")

  high_rse <- th[!is.na(pf[th, "%RSE"]) & pf[th, "%RSE"] > max_rse]
  add("structural_rse", length(high_rse) == 0,
      if (length(high_rse)) sprintf("%%RSE > %g: %s", max_rse,
        paste(sprintf("%s (%.1f%%)", high_rse, pf[high_rse, "%RSE"]), collapse = ", "))
      else sprintf("all structural %%RSE <= %g", max_rse), fail_status = "warn")

  if (!is.null(fit$omega)) {
    shr <- fit$shrink["sd shrinkage (%)", colnames(fit$omega), drop = TRUE]
    high_shr <- names(shr)[shr > max_shrink]
    add("eta_shrinkage", length(high_shr) == 0,
        if (length(high_shr)) sprintf("SD shrinkage > %g%%: %s", max_shrink,
          paste(sprintf("%s (%.1f%%)", high_shr, shr[high_shr]), collapse = ", "))
        else sprintf("all ETA SD shrinkage <= %g%%", max_shrink), fail_status = "warn")

    bsv <- pf[!is.na(pf$`BSV(CV%)`), "BSV(CV%)", drop = FALSE]
    odd_bsv <- rownames(bsv)[bsv[[1]] < 1 | bsv[[1]] > 100]
    add("bsv_range", length(odd_bsv) == 0,
        if (length(odd_bsv)) paste("BSV CV% outside 1-100%:", paste(odd_bsv, collapse = ", "))
        else "all BSV CV% within 1-100%", fail_status = "warn")
  }

  err <- ini$name[!is.na(ini$err) & !ini$fix]
  add("residual_error_positive", all(fit$theta[err] > 0),
      paste(sprintf("%s = %.3g", err, fit$theta[err]), collapse = ", "))

  bind_rows(res)
}

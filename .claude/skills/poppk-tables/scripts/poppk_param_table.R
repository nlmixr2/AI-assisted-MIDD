# Final-model parameter table rows for templates/tbl-parameters.R, in three sections that
# mirror the source model's ini({}) block:
#   Fixed effects                                   every estimated THETA that is not residual error
#   Random effects (between-subject variability)    every ETA variance (omega^2, CV%, shrinkage),
#                                                   then every OMEGA-block correlation
#   Residual unexplained variability                every residual-error parameter
# check_param_table() then proves the table is complete and consistent with the source model
# (every parameter exactly once, estimates identical to the fit) and with the source data
# (participants and observations of the fit = those of the data file).
#
# The functions work on plain data frames (poppk_param_inputs(fit) extracts them), so they are
# testable without nlmixr2: see tests/test-poppk-param-table.R.

#' Everything the table needs from an nlmixr2 fit, as plain objects.
poppk_param_inputs <- function(fit) {
  mu <- tryCatch(fit$ui$muRefTable, error = function(e) NULL)
  list(
    iniDf = as.data.frame(fit$iniDf),                   # source model's ini({}), final estimates
    parFixedDf = as.data.frame(fit$parFixedDf),         # estimates, SE, CI, BSV, shrinkage per THETA
    omega = fit$omega,                                  # final OMEGA matrix
    mu_ref = if (is.null(mu)) data.frame(theta = character(), eta = character()) else
      as.data.frame(mu)[, c("theta", "eta")],           # which THETA each ETA belongs to
    n_id = length(unique(fit$ID)),
    n_obs = nrow(fit),
    objf = fit$objf,
    est = fit$est
  )
}

.label_of <- function(ini, name) {
  l <- ini$label[match(name, ini$name)]
  ifelse(is.na(l) | l == "", name, l)
}

.err_label <- c(add = "Additive residual SD", prop = "Proportional residual SD (fraction)",
                pow = "Power residual", pow2 = "Power residual exponent", lnorm = "Log-normal residual SD",
                boxCox = "Box-Cox lambda", yeoJohnson = "Yeo-Johnson lambda")

#' Long-format rows of the parameter table (one row per parameter).
#' Columns: section, kind, name, label, est, rse, lo, hi, bsv, shr, ord.
poppk_param_rows <- function(inputs) {
  ini <- inputs$iniDf
  pf <- inputs$parFixedDf
  col <- function(nm, v) if (v %in% names(pf)) unname(pf[nm, v]) else rep(NA_real_, length(nm))
  sections <- c(fixed = "Fixed effects", random = "Random effects (between-subject variability)",
                corr = "Random effects (between-subject variability)",
                ruv = "Residual unexplained variability")

  th <- ini[!is.na(ini$ntheta) & is.na(ini$err), ]
  th <- th[order(th$ntheta), ]
  fixed <- data.frame(
    kind = "fixed", name = th$name,
    label = paste0(.label_of(ini, th$name), ifelse(th$fix, " (fixed)", "")),
    est = col(th$name, "Back-transformed"), rse = ifelse(th$fix, NA, col(th$name, "%RSE")),
    lo = col(th$name, "CI Lower"), hi = col(th$name, "CI Upper"), bsv = NA_real_, shr = NA_real_
  )

  om <- inputs$omega
  et <- ini[!is.na(ini$neta1) & ini$neta1 == ini$neta2, ]
  et <- et[order(et$neta1), ]
  theta_of <- inputs$mu_ref$theta[match(et$name, inputs$mu_ref$eta)]
  random <- data.frame(
    kind = "random", name = et$name,
    label = ifelse(is.na(theta_of), paste("BSV", et$name), paste("BSV on", .label_of(ini, theta_of))),
    est = diag(om)[et$name], rse = NA_real_, lo = NA_real_, hi = NA_real_,
    # CV% and shrinkage are reported by nlmixr2 on the THETA row the ETA belongs to; an ETA
    # without a THETA (not mu-referenced) gets NA
    bsv = unname(col(theta_of, "BSV(CV%)")), shr = unname(col(theta_of, "Shrink(SD)%"))
  )

  off <- ini[!is.na(ini$neta1) & ini$neta1 != ini$neta2, ]
  corr <- fixed[0, ]
  if (nrow(off)) {
    eta_name <- function(i) ini$name[!is.na(ini$neta1) & ini$neta1 == ini$neta2 & ini$neta1 == i][1]
    # model order: the ETA defined first comes first (iniDf stores the lower triangle, neta1 > neta2)
    e1 <- vapply(pmin(off$neta1, off$neta2), eta_name, ""); e2 <- vapply(pmax(off$neta1, off$neta2), eta_name, "")
    lab_eta <- function(e) { t <- inputs$mu_ref$theta[match(e, inputs$mu_ref$eta)]; ifelse(is.na(t), e, .label_of(ini, t)) }
    corr <- data.frame(
      kind = "corr", name = paste0(e1, "~", e2),
      label = sprintf("Correlation: %s ~ %s", lab_eta(e1), lab_eta(e2)),
      est = om[cbind(e1, e2)] / sqrt(om[cbind(e1, e1)] * om[cbind(e2, e2)]),
      rse = NA_real_, lo = NA_real_, hi = NA_real_, bsv = NA_real_, shr = NA_real_
    )
  }

  er <- ini[!is.na(ini$err), ]
  er <- er[order(er$ntheta), ]
  lab <- .label_of(ini, er$name)
  lab <- ifelse(lab == er$name & er$err %in% names(.err_label), .err_label[er$err], lab)
  ruv <- data.frame(
    kind = "ruv", name = er$name, label = paste0(lab, ifelse(er$fix, " (fixed)", "")),
    est = col(er$name, "Estimate"), rse = ifelse(er$fix, NA, col(er$name, "%RSE")),
    lo = col(er$name, "CI Lower"), hi = col(er$name, "CI Upper"), bsv = NA_real_, shr = NA_real_
  )

  out <- rbind(fixed, random, corr, ruv)
  out$section <- unname(sections[out$kind])
  out$ord <- seq_len(nrow(out))
  rownames(out) <- NULL
  out[, c("section", "kind", "name", "label", "est", "rse", "lo", "hi", "bsv", "shr", "ord")]
}

#' Observation records of the source data, as nlmixr2 counts them: EVID 0 and not MDV 1.
data_obs_rows <- function(pkData) {
  obs <- if ("EVID" %in% names(pkData)) pkData$EVID == 0 else rep(TRUE, nrow(pkData))
  if ("MDV" %in% names(pkData)) obs <- obs & pkData$MDV %in% 0
  obs
}

#' Stop unless the rows cover the source model exactly once and agree with the fit's
#' estimates, and the fit's participants/observations equal the source data's.
#' @return (Invisibly) a one-line summary for the table footnote.
check_param_table <- function(rows, inputs, pkData, id_col = "ID") {
  ini <- inputs$iniDf
  problems <- character()
  same <- function(kind, expected, what) {
    got <- rows$name[rows$kind == kind]
    miss <- setdiff(expected, got); extra <- setdiff(got, expected); dup <- got[duplicated(got)]
    if (length(miss)) problems <<- c(problems, sprintf("%s missing from the table: %s", what, paste(miss, collapse = ", ")))
    if (length(extra)) problems <<- c(problems, sprintf("%s not in the model: %s", what, paste(extra, collapse = ", ")))
    if (length(dup)) problems <<- c(problems, sprintf("%s listed twice: %s", what, paste(unique(dup), collapse = ", ")))
  }
  same("fixed", ini$name[!is.na(ini$ntheta) & is.na(ini$err)], "Fixed effects (THETA)")
  same("random", ini$name[!is.na(ini$neta1) & ini$neta1 == ini$neta2], "Random effects (ETA)")
  same("ruv", ini$name[!is.na(ini$err)], "Residual error parameters")
  n_off <- sum(!is.na(ini$neta1) & ini$neta1 != ini$neta2)
  if (sum(rows$kind == "corr") != n_off) {
    problems <- c(problems, sprintf("OMEGA correlations: %d in the model, %d in the table", n_off, sum(rows$kind == "corr")))
  }

  pf <- inputs$parFixedDf
  fx <- rows[rows$kind == "fixed", ]
  if (!isTRUE(all.equal(fx$est, unname(pf[fx$name, "Back-transformed"]), check.attributes = FALSE))) {
    problems <- c(problems, "Fixed-effect estimates differ from the fit's back-transformed estimates")
  }
  rd <- rows[rows$kind == "random", ]
  if (!isTRUE(all.equal(rd$est, unname(diag(inputs$omega)[rd$name]), check.attributes = FALSE))) {
    problems <- c(problems, "Random-effect variances differ from the fit's OMEGA diagonal")
  }

  n_id_data <- length(unique(pkData[[id_col]]))
  n_obs_data <- sum(data_obs_rows(pkData))
  if (n_id_data != inputs$n_id) {
    problems <- c(problems, sprintf("Participants: %d in the fit, %d in the source data", inputs$n_id, n_id_data))
  }
  if (n_obs_data != inputs$n_obs) {
    problems <- c(problems, sprintf("Observations: %d in the fit, %d in the source data (EVID 0, MDV 0)", inputs$n_obs, n_obs_data))
  }
  if (length(problems)) {
    stop("Parameter table is not consistent with the source model/data:\n  - ",
         paste(problems, collapse = "\n  - "), call. = FALSE)
  }
  invisible(sprintf("%d participants, %d observations (source data and fit agree)", inputs$n_id, inputs$n_obs))
}

# Helpers for popPK figure scripts (script/poppk/v{n}/fig-*.R) built from the
# poppk-estimation templates. Source after project.R (for analysis_title()).
#
#   render_poppk_display(p, "fig-gof", out_dir, cfg, source_data = db_meta$source_file_path)
#
# Rendering uses the shared TLF shell (pk-project scripts/tlf_shell.R), identical to the NCA
# tables/figures and the popPK tables: header = analysis title + "Page x of y"; footer =
# "Source data: <file>" + script path + date-time. A list of ggplots gives one page each.
# Output: {name}.pdf (RTF without TinyTeX) + {name}.RDS (the exact rendered display object,
# recorded in the spec as display_rds).

library(ggplot2)
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")

#' Render a ggplot, or a list of ggplots (one page each), in the standard TLF shell.
#' `title`/`subtitle` go in the docorator header (not the ggplot).
render_poppk_display <- function(display, display_name, out_dir, cfg, source_data = NULL,
                                 title = NULL, subtitle = NULL,
                                 fig_dim = tlf_fig_dim) {   # tlf_shell.R; taller spills onto an extra, blank page
  render_tlf(display, display_name, out_dir, cfg, type = "poppk", source_data = source_data,
             title = title, subtitle = subtitle, fig_dim = fig_dim)
}

#' Shared look for popPK figures: the TLF figure theme (pk-project scripts/figure_helpers.R).
theme_pmx <- theme_tlf

#' IDs in numeric order (character): participant_levels() from the shared helpers.
id_order <- participant_levels

#' Baseline covariates: numeric data columns that are constant within every ID, excluding
#' the NONMEM-style record columns. Used for ETA-vs-covariate plots.
baseline_covariates <- function(pkData,
                                exclude = c("ID", "TIME", "DV", "AMT", "EVID", "CMT", "MDV",
                                            "RATE", "DUR", "II", "ADDL", "SS", "CENS", "LIMIT",
                                            "DVID", "BLQ", "NTIME", "NFRLT", "NRRLT")) {
  cand <- setdiff(names(pkData)[vapply(pkData, is.numeric, logical(1))], exclude)
  keep <- vapply(cand, function(v) all(tapply(pkData[[v]], pkData$ID, function(x) length(unique(x)) == 1)),
                 logical(1))
  cand[keep]
}

#' The `n` worst-fitting individuals by mean |IWRES| (for flagging in individual plots).
worst_fitting <- function(fit_df, n = 3) {
  s <- tapply(abs(fit_df$IWRES), as.character(fit_df$ID), mean, na.rm = TRUE)
  head(names(sort(s, decreasing = TRUE)), n)
}

## VPC helpers (templates/fig-vpc.R) ---------------------------------------------------
## Standard and prediction-corrected VPCs come from nlmixr2plot::vpcPlot() / vpcPlotTad().
## vpcPlot() has no dose normalization, so the dose-normalized VPC is computed here from one
## nlmixr2est::vpcSim() simulation and the dataset's dose records (public interfaces only).

#' Add the most recent dose (`dose`) and time after that dose (`tad`) to rows of `d`, from
#' the dose records `doses` (columns ID, TIME, AMT). Rows before a participant's first dose
#' get NA.
add_last_dose <- function(d, doses, id = "id", time = "time") {
  d$dose <- NA_real_
  d$tad <- NA_real_
  doses <- doses[order(doses$ID, doses$TIME), ]
  for (i in unique(as.character(d[[id]]))) {
    r <- which(as.character(d[[id]]) == i)
    dd <- doses[as.character(doses$ID) == i, ]
    if (!nrow(dd)) next
    k <- findInterval(d[[time]][r], dd$TIME)   # last dose at or before each time
    ok <- k > 0
    d$dose[r[ok]] <- dd$AMT[k[ok]]
    d$tad[r[ok]] <- d[[time]][r[ok]] - dd$TIME[k[ok]]
  }
  d
}

#' Quantile VPC summary: observed 5th/50th/95th percentiles per bin and the 95% interval of
#' the same percentiles across simulated replicates. `obs` has columns x, y; `sim` has
#' sim.id, x, y. Bins are quantiles of the observed x (`n_bins`) unless `breaks` is given.
vpc_summary <- function(obs, sim, n_bins = 8, breaks = NULL, pi = c(0.05, 0.5, 0.95), ci = c(0.025, 0.975)) {
  if (is.null(breaks)) breaks <- unique(stats::quantile(obs$x, seq(0, 1, length.out = n_bins + 1), names = FALSE))
  bin_of <- function(x) cut(x, breaks, include.lowest = TRUE)
  obs$bin <- bin_of(obs$x)
  sim$bin <- bin_of(sim$x)
  mids <- tapply(obs$x, obs$bin, mean)
  q <- function(v) stats::quantile(v, pi, names = FALSE, na.rm = TRUE)
  obs_q <- do.call(rbind, lapply(split(obs$y, obs$bin, drop = TRUE), function(v) data.frame(pi = pi, obs = q(v))))
  obs_q$bin <- rep(names(split(obs$y, obs$bin, drop = TRUE)), each = length(pi))
  sim_q <- stats::aggregate(y ~ sim.id + bin, data = sim, FUN = q)
  sim_q <- data.frame(bin = rep(as.character(sim_q$bin), each = length(pi)), pi = rep(pi, nrow(sim_q)),
                      v = as.vector(t(sim_q$y)))
  sim_ci <- stats::aggregate(v ~ bin + pi, data = sim_q, FUN = function(v) stats::quantile(v, c(ci, 0.5), names = FALSE))
  sim_ci <- data.frame(bin = sim_ci$bin, pi = sim_ci$pi, lo = sim_ci$v[, 1], hi = sim_ci$v[, 2], med = sim_ci$v[, 3])
  out <- merge(sim_ci, obs_q, by = c("bin", "pi"), all.x = TRUE)
  out$x <- as.numeric(mids[as.character(out$bin)])
  out[order(out$pi, out$x), ]
}

#' Plot a vpc_summary(): shaded 95% intervals of the simulated percentiles, observed
#' percentiles as lines (median solid, 5th/95th dashed), optional observed points.
vpc_quantile_plot <- function(summ, obs = NULL, log_y = FALSE) {
  if (log_y) {   # values <= 0 cannot be shown on a log axis
    for (v in c("lo", "hi", "med", "obs")) summ[[v]][summ[[v]] <= 0] <- NA
    if (!is.null(obs)) obs <- obs[obs$y > 0, ]
  }
  summ$band <- factor(ifelse(summ$pi == 0.5, "median", "outer"), levels = c("outer", "median"))
  p <- ggplot(summ, aes(x)) +
    geom_ribbon(aes(ymin = lo, ymax = hi, group = pi, fill = band), alpha = 0.3) +
    scale_fill_manual(values = c(outer = "steelblue", median = "firebrick"), guide = "none")
  if (!is.null(obs)) p <- p + geom_point(data = obs, aes(x, y), inherit.aes = FALSE, alpha = 0.3, size = 0.8)
  p <- p + geom_line(aes(y = obs, group = pi, linetype = pi == 0.5)) +
    scale_linetype_manual(values = c(`TRUE` = "solid", `FALSE` = "dashed"), guide = "none") +
    theme_tlf()
  if (log_y) p + scale_y_log10() else p
}

# Visual predictive checks for the final model (checklist item 5): a collection of VPCs, one
# per page, in the standard TLF shell --
#   type:   standard, prediction-corrected (pcVPC), dose-normalized
#   x-axis: time after first dose, time after dose
#   y-axis: linear, logarithmic
# Standard and pcVPCs are nlmixr2plot::vpcPlot() / vpcPlotTad(); the dose-normalized VPC is
# computed from one nlmixr2est::vpcSim() simulation (scripts/poppk_figures.R: add_last_dose(),
# vpc_summary(), vpc_quantile_plot()), because vpcPlot() has no dose normalization.
# Every VPC uses the same seed and number of replicates. Fixed seed -> reproducible.
# Saves output/poppk/v{{project_number}}/figures/fig-vpc.pdf (+ .RDS).

library(nlmixr2)
library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-vpc", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), fits, runs, pkData -- no refit
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_figures.R")

out_dir <- tlf_out_dir("poppk", project_number)
u <- cfg$units

## EDIT: which VPCs, replicates, binning -----------------------------------------------
vpc_types <- c(standard = "VPC", pred_corr = "Prediction-corrected VPC", dose_norm = "Dose-normalized VPC")
x_axes <- c(time = "Time after first dose", tad = "Time after dose")
y_scales <- c(linear = FALSE, log = TRUE)
n_sim <- 500
bins <- "jenks"        # vpcPlot() binning ("jenks", "time", or a vector of bin edges)
n_bins_dn <- 8         # dose-normalized VPC: quantile bins of the observed x
seed <- 20260927
# With one dose per participant, time after dose equals time after first dose: skip the
# duplicate TAD pages unless you want them anyway.
skip_duplicate_tad <- TRUE

doses <- pkData |> filter(EVID != 0, AMT > 0) |> select(ID, TIME, AMT)
multiple_dosing <- any(table(doses$ID) > 1)
if (skip_duplicate_tad && !multiple_dosing) {
  message("One dose per participant: time after dose = time after first dose; TAD VPCs skipped")
  x_axes <- x_axes["time"]
}

## Observed and simulated data for the dose-normalized VPC (one simulation) ---------------
if ("dose_norm" %in% names(vpc_types)) {
  obs_rows <- pkData$EVID == 0 & (if ("MDV" %in% names(pkData)) pkData$MDV == 0 else TRUE)
  dn_obs <- pkData[obs_rows, ] |> transmute(id = ID, time = TIME, y = DV) |> add_last_dose(doses)
  dn_sim <- nlmixr2est::vpcSim(fit, n = n_sim, seed = seed)
  names(dn_sim)[tolower(names(dn_sim)) == "id"] <- "id"
  if ("evid" %in% names(dn_sim)) dn_sim <- dn_sim[dn_sim$evid == 0, ]
  dn_sim <- dn_sim |> transmute(sim.id, id, time, y = sim) |> add_last_dose(doses)
  dn_obs$y <- dn_obs$y / dn_obs$dose
  dn_sim$y <- dn_sim$y / dn_sim$dose
}

y_label <- c(standard = lab_unit("Concentration", u$conc),
             pred_corr = lab_unit("Prediction-corrected concentration", u$conc),
             dose_norm = lab_unit("Dose-normalized concentration", sprintf("%s per %s", u$conc, u$dose)))

vpc_page <- function(type, x, scale) {
  log_y <- y_scales[[scale]]
  if (type == "dose_norm") {
    o <- dn_obs |> transmute(x = .data[[x]], y) |> filter(!is.na(x), !is.na(y))
    s <- dn_sim |> transmute(sim.id, x = .data[[x]], y) |> filter(!is.na(x), !is.na(y))
    p <- vpc_quantile_plot(vpc_summary(o, s, n_bins = n_bins_dn), obs = o, log_y = log_y)
  } else {
    vpc_fun <- if (x == "tad") nlmixr2plot::vpcPlotTad else nlmixr2plot::vpcPlot
    p <- vpc_fun(fit, n = n_sim, bins = bins, pred_corr = type == "pred_corr", log_y = log_y,
                 show = list(obs_dv = TRUE), seed = seed) + theme_tlf()
  }
  p + labs(
    x = lab_unit(x_axes[[x]], u$time), y = y_label[[type]],
    title = sprintf("%s | %s | %s scale", vpc_types[[type]], tolower(x_axes[[x]]), scale),   # page label
    caption = "Lines: observed 5th/50th/95th percentiles; shaded: 95% intervals of the simulated percentiles."
  )
}

if ("tad" %in% names(x_axes) && !exists("vpcPlotTad", envir = asNamespace("nlmixr2plot"))) {
  stop("This nlmixr2plot has no vpcPlotTad(): update nlmixr2plot, or drop \"tad\" from x_axes", call. = FALSE)
}

vpc_grid <- expand_grid(type = names(vpc_types), x = names(x_axes), scale = names(y_scales))
pages <- pmap(vpc_grid, vpc_page)
names(pages) <- with(vpc_grid, paste(type, x, scale, sep = "_"))

# Title and subtitle go in the docorator header (render_tlf), not the ggplot.
render_poppk_display(pages, "fig-vpc", out_dir, cfg, source_data = db_meta$source_file_path,
                     title = sprintf("Visual Predictive Checks -- %s (Final Model)", final_run),
                     subtitle = sprintf("n = %d simulated replicates per VPC; seed %d; bins: %s (dose-normalized: %d quantile bins); %d pages",
                                        n_sim, seed, paste(bins, collapse = ", "), n_bins_dn, length(pages)))

nca_log_stop()

# Steady-state exposure summary (tfrmt + docorator), same tfrmt approach and TLF shell as the
# NCA and popPK tables: one row per regimen; Cmax,ss, Cmin,ss, AUC0-24,ss and Tmax,ss as
# median [5th, 95th percentile] across simulated subjects (3 significant figures).
# Saves output/poppk-sim/v{{project_number}}/tables/tbl-exposure-summary.pdf (+ .RDS: the gt object).

library(tidyverse)
library(tfrmt)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("tbl-exposure-summary", project_number = project_number, output_dir = "output/poppk-sim")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim.R")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_db.R")
read_sim_db(project_number)   # sims, metrics, exposure_summary, profiles, settings, source_provenance
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")
source_data <- sim_source_data(source_provenance)   # "Source data:" line of the TLF shell
u <- cfg$units

out_dir <- sprintf("output/poppk-sim/v%d/tables", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

## EDIT: title --------------------------------------------------------------------
title <- "Simulated Steady-State Exposure"

metric_labels <- c(cmax = sprintf("Cmax,ss (%s)", u$conc), cmin = sprintf("Cmin,ss (%s)", u$conc),
                   auc24 = sprintf("AUC0-24,ss (%s*%s)", u$conc, u$time), tmax = sprintf("Tmax,ss (%s)", u$time))

# ARD: one row per regimen x metric x statistic (tfrmt's long input)
exp_ard <- exposure_summary |>
  filter(metric %in% names(metric_labels)) |>
  transmute(regimen = as.character(scenario), ord = as.integer(scenario),
            column = factor(metric_labels[metric], levels = metric_labels),
            median, p05, p95) |>
  pivot_longer(c(median, p05, p95), names_to = "param", values_to = "value") |>
  arrange(ord, column)   # tfrmt orders columns by first appearance: keep metric_labels order

sig3 <- frmt_sig3()

tfrmt_exp <- tfrmt(
  label = regimen, column = column, param = param, value = value, sorting_cols = ord,
  title = title,
  subtitle = sprintf("%s; model: %s", cfg$study$id, sim_source_data(source_provenance)),
  body_plan = body_plan(
    fs(frmt_combine("{median} [{p05}, {p95}]", median = sig3, p05 = sig3, p95 = sig3))
  ),
  col_plan = col_plan(Regimen = regimen, everything(), -ord),
  footnote_plan = tlf_footnotes(
    "Median [5th, 95th percentile] across simulated subjects.",
    sprintf("Metrics over the last dosing interval of day 7; %d subjects x %d studies per regimen (parameter uncertainty across studies); seed %d.",
            settings$nSub, settings$nStud, settings$seed),
    "Tmax,ss = time after the last dose; Cmin,ss = trough; AUC0-24,ss = AUCtau x 24/tau.",
    sprintf("%s: %s.", scenario_info$scenario, scenario_info$description)
  )
)

render_tlf(print_to_gt(tfrmt_exp, .data = exp_ard), "tbl-exposure-summary", out_dir, cfg, type = "poppk-sim",
           source_data = source_data)

nca_log_stop()

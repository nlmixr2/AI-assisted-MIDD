# Final-model parameter table (tfrmt + docorator), from the poppk-tables skill, in the shared
# TLF shell. Three sections that mirror the model's ini({}) block (scripts/poppk_param_table.R):
#   Fixed effects                  every estimated THETA except residual error: back-transformed
#                                  estimate, %RSE, 95% CI ("(fixed)" and no RSE for fixed THETAs)
#   Random effects (BSV)           every ETA: variance (omega^2), CV% and shrinkage (SD%), labelled
#                                  by its THETA; then every OMEGA-block correlation
#   Residual unexplained variability  every residual-error parameter: estimate, %RSE, 95% CI
# check_param_table() stops the script unless every model parameter appears exactly once,
# estimates equal the fit's, and the fit's participants/observations equal the source data's.
# Saves output/poppk/v{{project_number}}/tables/tbl-parameters.pdf (+ .RDS: the gt object).

library(tidyverse)
library(tfrmt)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("tbl-parameters", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), pkData (source data) -- no refit
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")   # render_tlf() + tfrmt helpers
source(".posit/assistant/skills/poppk-tables/scripts/poppk_param_table.R")

out_dir <- tlf_out_dir("poppk", project_number, "tables")

## EDIT: title / subtitle ----------------------------------------------------------
title <- "Population PK Parameter Estimates"
subtitle <- sprintf("%s, final model %s (%s)", cfg$study$id, final_run, toupper(fit$est))

## Rows from the source model, checked against the model and the source data -------------
inputs <- poppk_param_inputs(fit)
par_rows <- poppk_param_rows(inputs)
consistency <- check_param_table(par_rows, inputs, pkData)   # stops on any mismatch
print(par_rows[, c("section", "label", "est", "rse", "bsv", "shr")], row.names = FALSE)

# ARD: one row per parameter x statistic (tfrmt's long input)
col_names <- c(est = "Estimate", rse = "%RSE", lo = "95% CI", hi = "95% CI",
               bsv = "BSV (CV%)", shr = "Shrinkage (SD%)")
par_ard <- par_rows |>
  select(section, label, ord, est, rse, lo, hi, bsv, shr) |>
  pivot_longer(c(est, rse, lo, hi, bsv, shr), names_to = "param", values_to = "value") |>
  mutate(column = factor(col_names[param], levels = unique(col_names)))

sig3 <- frmt_sig3()
tfrmt_par <- tfrmt(
  group = section, label = label, column = column, param = param, value = value,
  sorting_cols = ord,
  title = title, subtitle = subtitle,
  body_plan = body_plan(
    fs(est = sig3),
    fs(frmt_combine("{lo}, {hi}", lo = sig3, hi = sig3, missing = "--")),
    fs(rse = frmt_dp(1, missing = "--")),
    fs(bsv = frmt_dp(1, missing = "--")),
    fs(shr = frmt_dp(1, missing = "--"))
  ),
  col_plan = col_plan(Parameter = label, everything(), -ord),
  footnote_plan = tlf_footnotes(
    sprintf("OFV = %.2f; %s.", inputs$objf, consistency),
    "Fixed effects: estimates and CIs back-transformed to the parameter scale; %RSE on the estimation scale.",
    "Random effects: Estimate = variance of the ETA (omega^2); BSV = CV% as reported by nlmixr2; correlations are between ETAs.",
    "BSV = between-subject variability; RSE = relative standard error; -- = not applicable or not estimated."
  )
)

render_tlf(print_to_gt(tfrmt_par, .data = par_ard), "tbl-parameters", out_dir, cfg, type = "poppk",
           source_data = db_meta$source_file_path)

nca_log_stop()

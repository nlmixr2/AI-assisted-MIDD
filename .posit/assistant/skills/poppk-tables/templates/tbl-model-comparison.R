# Model-development table (tfrmt + docorator), from the poppk-tables skill -- same
# tfrmt/docorator approach and TLF shell as the NCA tables (pk-nca-tables).
# One row per run of the trail (label: run, parent, description; * = final model):
# number of estimated parameters, OFV, dOFV vs parent, AIC, BIC, covariance step.
# Saves output/poppk/v{{project_number}}/tables/tbl-model-comparison.pdf (+ .RDS: the gt object).

library(tidyverse)
library(tfrmt)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("tbl-model-comparison", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)

out_dir <- sprintf("output/poppk/v%d/tables", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")   # render_tlf() + tfrmt helpers
run_label <- sprintf("%s%s%s: %s", runs$run_id, if_else(runs$final, "*", ""),
                     if_else(is.na(runs$parent_run), " (base)", sprintf(" (from %s)", runs$parent_run)),
                     runs$description)
col_names <- c(n_par = "N par", objf = "OFV", delta_ofv = "dOFV", aic = "AIC", bic = "BIC", cov_ok = "Cov. step")
cmp_ard <- runs |>
  mutate(label = run_label, ord = row_number(), cov_ok = as.numeric(cov_ok)) |>
  select(label, ord, n_par, objf, delta_ofv, aic, bic, cov_ok) |>
  pivot_longer(-c(label, ord), names_to = "param", values_to = "value") |>
  mutate(column = factor(col_names[param], levels = col_names))

tfrmt_cmp <- tfrmt(
  label = label, column = column, param = param, value = value, sorting_cols = ord,
  title = "Model Development Summary",
  subtitle = sprintf("%s population PK; estimation method %s", cfg$study$id,
                     paste(unique(toupper(runs$est)), collapse = "/")),
  body_plan = body_plan(
    fs(frmt("xxxx.xx", missing = "--")),
    fs(n_par = frmt("xx")),
    fs(cov_ok = frmt_when("==1" ~ "Yes", TRUE ~ "No"))
  ),
  col_plan = col_plan(Run = label, everything(), -ord),
  footnote_plan = tlf_footnotes(
    "* Final model.",
    "dOFV = OFV(run) - OFV(parent); < -3.84 for one added parameter is significant at p < 0.05.",
    "OFV from the FOCEi approximation (SAEM fits with CWRES), comparable across runs."
  )
)

render_tlf(print_to_gt(tfrmt_cmp, .data = cmp_ard), "tbl-model-comparison", out_dir, cfg, type = "poppk",
           source_data = db_meta$source_file_path)

nca_log_stop()

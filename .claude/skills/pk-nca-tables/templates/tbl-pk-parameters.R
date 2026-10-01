# Individual PK-parameter table (tfrmt + docorator), from the pk-nca-tables skill.
# One row per participant (numeric ID order), one column per requested PK parameter
# (labels + units from PKNCA's PPORRESU), then N / Mean / Median / Min, Max rows.
# Shared tfrmt helpers (summary_ard(), per_param_body_plan(), ...) come with the TLF shell
# (pk-project scripts/tlf_shell.R); see references/tfrmt-guide.md for the tfrmt concepts.
# Saves output/nca/v{{project_number}}/tables/tbl-pk-parameters.pdf (RTF without TinyTeX)

library(tidyverse)
library(tfrmt)
library(docorator)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("tbl-pk-parameters", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
db_meta <- read_nca_db(project_number)
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")   # render_tlf() + tfrmt helpers

out_dir <- sprintf("output/nca/v%d/tables", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

## EDIT: subtitle, parameter display names -----------------------------------------
subtitle <- sprintf("%s; N, Mean, Median, and Min/Max summarize across all participants", cfg$study$id)
display_names <- c(cmax = "Cmax", tmax = "Tmax", half.life = "Half-life", aucinf.obs = "AUCinf",
                   auclast = "AUClast", clast.obs = "Clast", cl.obs = "CL/F", vz.obs = "Vz/F",
                   lambda.z = "Lambda z", ctrough = "Ctrough", cav = "Cav")
# Decimals per parameter, used for its participant rows AND its Mean / Median / Min, Max rows,
# so each column has one precision. Parameters not listed use default_digits.
param_digits <- c(tmax = 2)
default_digits <- 1

pk_params <- setdiff(names(res_wide), "participant")
res_inf <- ncaRes$result |> filter(end == Inf, PPTESTCD %in% pk_params)
units_by_param <- res_inf |> distinct(PPTESTCD, PPORRESU)
col_label <- function(code) {
  u <- units_by_param$PPORRESU[match(code, units_by_param$PPTESTCD)]
  nm <- ifelse(code %in% names(display_names), display_names[code], code)
  ifelse(is.na(u) | u == "unitless", nm, sprintf("%s (%s)", nm, u))
}
row_levels <- c(participant_levels(cObsData$participant), "N", "Mean", "Median", "Min, Max")

# ARD: participant rows (param = parameter code) + summary rows (param = "<code>__<stat>",
# so each statistic is formatted with its parameter's digits)
nca_ard <- bind_rows(
  res_inf |> transmute(row_id = as.character(participant), PPTESTCD, stat_type = PPTESTCD, value = PPORRES),
  summary_ard(res_inf, PPORRES, by = PPTESTCD) |>
    mutate(row_id = stat_row_label(stat_type), stat_type = paste0(PPTESTCD, "__", stat_type))
) |>
  # transmute (not mutate): an extra PPTESTCD column would become a grouping key in tfrmt
  transmute(row_id, param_col = factor(col_label(PPTESTCD), levels = col_label(pk_params)), stat_type, value) |>
  add_row_order(row_levels)

tfrmt_nca <- tfrmt(
  label = row_id, column = param_col, param = stat_type, value = value, sorting_cols = row_ord,
  title = "Individual PK Parameters",
  subtitle = subtitle,
  body_plan = per_param_body_plan(pk_params, digits = param_digits, default = default_digits),
  col_plan = col_plan("Participant ID" = row_id, everything(), -row_ord),
  footnote_plan = tlf_footnotes(N = "N = number of subjects",
                                `Min, Max` = "Min, Max = minimum and maximum observed value")
)

render_tlf(print_to_gt(tfrmt_nca, .data = nca_ard), "tbl-pk-parameters", out_dir, cfg,
           source_data = db_meta$source_file_path)

nca_log_stop()

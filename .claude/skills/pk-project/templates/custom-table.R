# {{description}}
# Custom table scaffolded by new_tlf() (pk-project) from the request's placeholders. Same
# approach as every table: long ARD -> tfrmt() body plan -> print_to_gt() -> render_tlf()
# (title + page header; "Source data:", script and date-time footer). Reads the version's
# results database -- never recompute.
# Saves output/{{type}}/v{{project_number}}/tables/{{name}}.pdf (+ .RDS: the gt object).

library(tidyverse)
library(tfrmt)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("{{name}}", project_number = project_number, output_dir = "output/{{type}}")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")
{{db_block}}

out_dir <- sprintf("output/{{type}}/v%d/tables", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
u <- cfg$units

## Placeholders from the request -------------------------------------------------------
title <- {{title}}
subtitle <- {{subtitle}}
footnotes <- {{footnotes}}

## EDIT: build the ARD -- one row per row label x column x statistic ----------------------
# Available: {{objects}}
# `label` = row label, `column` = column header (a factor sets the order), `param` = statistic
# name used by the body plan, `value` = the number; add `group` for grouped rows, `ord` to sort.
ard <- tibble(label = "EDIT: row", column = factor("EDIT: column"), param = "value",
              value = NA_real_, ord = 1L) |>
  arrange(ord, column)   # tfrmt orders columns by first appearance

## EDIT: formats -- fs() per rule (label = one row); frmt_dp(), frmt_sig3(), frmt_min_max(),
## frmt_combine() for "a [b, c]" cells (helpers: pk-project scripts/tfrmt_helpers.R) ------------
tbl_plan <- body_plan(
  fs(value = frmt_sig3())
)

tfrmt_tbl <- tfrmt(
  label = label, column = column, param = param, value = value, sorting_cols = ord,
  title = title, subtitle = subtitle,
  body_plan = tbl_plan,
  col_plan = col_plan(everything(), -ord),
  footnote_plan = tlf_footnotes(footnotes)
)

render_tlf(print_to_gt(tfrmt_tbl, .data = ard), "{{name}}", out_dir, cfg, type = "{{type}}", source_data = source_data)

nca_log_stop()

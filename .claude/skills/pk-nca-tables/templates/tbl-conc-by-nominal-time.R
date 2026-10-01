# Concentrations-by-nominal-sample-time table (tfrmt + docorator), from the pk-nca-tables skill.
# One row per participant, one column per nominal sample time under a "Nominal Postdose
# Sample Time" span header, then N / Mean / Median / Min, Max / BLQ N / %BLQ rows.
# Paginated at 4 time columns per page, bundled into one multi-page document.
# Shared tfrmt helpers come with the TLF shell (pk-project scripts/tlf_shell.R); see
# references/tfrmt-guide.md for the tfrmt concepts.
# Saves output/nca/v{{project_number}}/tables/tbl-conc-by-nominal-time.pdf (RTF without TinyTeX)

library(tidyverse)
library(tfrmt)
library(docorator)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("tbl-conc-by-nominal-time", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
db_meta <- read_nca_db(project_number)

source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")   # render_tlf() + tfrmt helpers
out_dir <- sprintf("output/nca/v%d/tables", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

## Nominal times and BLQ rule (shared with fig-mean-conc*.R) -------------------------
# Nominal times: the data's nominal-time column if analysis-nca.R carried one (ntime),
# else project.yaml `sampling:`. LLOQ: project.yaml sampling.lloq.
# assign_nominal_time() is the single definition of which sample belongs to which nominal
# time, so this table and the mean-concentration figures always agree.
source(".posit/assistant/skills/pk-nca/scripts/nca_nominal.R")
sched <- nominal_schedule(cfg, required = !"ntime" %in% names(cObsData))   # data column wins
conc_by_nominal <- assign_nominal_time(cObsData, sched) |>
  mutate(nominal_time = ntime, nominal_label = ntime_label,
         # BLQ: concentration 0, or below sampling.lloq when set
         blq = cObs == 0 | (!is.na(sched$lloq) & cObs < sched$lloq))
nominal_labels <- levels(conc_by_nominal$nominal_label)   # timepoints present, in time order

row_levels <- c(participant_levels(cObsData$participant), "N", "Mean", "Median", "Min, Max", "BLQ N", "%BLQ")

conc_ard <- bind_rows(
  conc_by_nominal |> transmute(row_id = as.character(participant), nominal_label, stat_type = "conc", value = cObs),
  summary_ard(conc_by_nominal, cObs, by = nominal_label, BLQ_N = sum(blq), PCT_BLQ = 100 * mean(blq)) |>
    mutate(row_id = stat_row_label(stat_type, c(BLQ_N = "BLQ N", PCT_BLQ = "%BLQ")))
) |>
  mutate(span_label = "Nominal Postdose Sample Time") |>
  add_row_order(row_levels)

blq_note <- if (is.na(sched$lloq)) "BLQ = below the limit of quantification (concentration = 0)" else
  sprintf("BLQ = below the limit of quantification (< %s %s)", sched$lloq, cfg$units$conc)

tfrmt_conc <- tfrmt(
  label = row_id,
  column = c(span_label, nominal_label),   # 2-level column: span header + nominal time
  param = stat_type, value = value, sorting_cols = row_ord,
  title = sprintf("%s Concentrations by Nominal Postdose Sample Time", cfg$study$id),
  subtitle = sprintf("Concentrations in %s; N, Mean, Median, Min/Max, and %%BLQ summarize across all participants", cfg$units$conc),
  body_plan = body_plan(
    fs(frmt_dp(1)),
    fs(frmt("xx"), label = "N"),
    fs(frmt("xx"), label = "BLQ N"),
    fs(frmt("xx.x%"), label = "%BLQ"),
    fs(frmt_min_max(1), label = "Min, Max")
  ),
  col_plan = col_plan("Participant ID" = row_id, everything(), -row_ord),
  footnote_plan = tlf_footnotes(
    N = "N = number of subjects with a concentration observation at the nominal sample time",
    `Min, Max` = "Min, Max = minimum and maximum observed concentration",
    `BLQ N` = blq_note,
    `%BLQ` = "%BLQ = percentage of subjects BLQ at the nominal sample time"
  )
)

## EDIT: nominal-time columns per page -------------------------------------------------
# tfrmt has no max-columns-per-page option: split the times into pages and bundle the gt
# tables into one gt_group (one multi-page document).
times_per_page <- 4
time_chunks <- split(nominal_labels, ceiling(seq_along(nominal_labels) / times_per_page))
conc_tables <- map(time_chunks, function(times) {
  d <- conc_ard |> filter(nominal_label %in% times) |> mutate(nominal_label = droplevels(nominal_label))
  print_to_gt(tfrmt_conc, .data = d)
})

render_tlf(do.call(gt::gt_group, conc_tables), "tbl-conc-by-nominal-time", out_dir, cfg,
           source_data = db_meta$source_file_path)

nca_log_stop()

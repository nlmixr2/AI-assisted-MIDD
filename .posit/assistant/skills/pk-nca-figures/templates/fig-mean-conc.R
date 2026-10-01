# Mean (SD) concentration-time profile by nominal time (numeric time axis), linear scale, with
# an n / mean / SD summary table under the plot at selected timepoints
# (crane::gg_pkc_lineplot() + crane::annotate_pkc_df()).
# From the pk-nca-figures skill. Nominal times and LLOQ come from project.yaml (`sampling:`),
# shared with tbl-conc-by-nominal-time.R.
# Saves output/nca/v{{project_number}}/figures/fig-mean-conc.pdf (+ .RDS), docorator shell as the tables.

library(tidyverse)
library(crane)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-mean-conc", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
db_meta <- read_nca_db(project_number)
source(".posit/assistant/skills/pk-nca/scripts/nca_nominal.R")
source(".posit/assistant/skills/pk-nca-figures/scripts/nca_figures.R")

out_dir <- sprintf("output/nca/v%d/figures", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

sched <- nominal_schedule(cfg, required = !"ntime" %in% names(cObsData))   # data column wins

## EDIT: grouping (one line per group), statistic, variability, table timepoints --------
# One group by default. For dose groups, e.g.:
#   left_join(distinct(doseData, participant, dose), by = "participant") |>
#   mutate(group = paste(dose, cfg$units$dose))
conc <- assign_nominal_time(cObsData, sched) |>
  mutate(group = "All participants")
stat <- "mean"
variability <- "sd"
# Timepoints shown in the summary table and as x-axis ticks. NULL = automatic: nominal times
# at least 8% of the time range apart (always the first and last); or e.g. c(0, 1, 2, 4, 8, 12, 24).
table_times <- NULL

if (is.null(table_times)) table_times <- spaced_times(sort(unique(conc$ntime)), min_gap = 0.08)

# Numeric nominal time, so the x-axis is spaced in real time (all timepoints are plotted;
# only table_times get a tick and a column in the summary table).
p <- gg_pkc_lineplot(
  conc, time_var = ntime, analyte_var = cObs, group = group,
  stat = stat, variability = variability, log_y = FALSE, lloq = sched$lloq
) +
  scale_x_continuous(breaks = table_times) +
  labs(
    x = sprintf("Nominal time (%s)", cfg$units$time),
    y = sprintf("Concentration (%s)", cfg$units$conc),
    colour = NULL
  ) +
  pk_legend(conc$group)

p_annotated <- annotate_pkc_df(
  p, data = filter(conc, ntime %in% table_times),
  time_var = "ntime", analyte_var = "cObs", group = "group",
  # same rounding as tbl-conc-by-nominal-time (frmt "xx.x"), so figure and table agree
  summary_stats = c("n", stat, variability), digits = c(0, 1, 1), text_size = 3
)

# Title and subtitle go in the docorator header (render_tlf), not the ggplot.
render_pk_display(
  p_annotated, "fig-mean-conc", out_dir, cfg, source_data = db_meta$source_file_path,
  title = sprintf("%s (%s) Concentration-Time Profile", str_to_title(stat), toupper(variability)),
  subtitle = sprintf("%s; linear scale%s", cfg$study$id,
                     if (is.na(sched$lloq)) "" else sprintf("; dashed line: LLOQ = %s %s", sched$lloq, cfg$units$conc))
)

nca_log_stop()

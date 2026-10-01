# Mean (SD) concentration-time profile, semi-logarithmic scale, actual spacing of the
# nominal times, with the LLOQ line when project.yaml sets sampling.lloq
# (crane::gg_pkc_lineplot()). From the pk-nca-figures skill.
# Saves output/nca/v{{project_number}}/figures/fig-mean-conc-semilog.pdf (+ .RDS), docorator shell as the tables.

library(tidyverse)
library(crane)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-mean-conc-semilog", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
db_meta <- read_nca_db(project_number)
source(".posit/assistant/skills/pk-nca/scripts/nca_nominal.R")
source(".posit/assistant/skills/pk-nca-figures/scripts/nca_figures.R")

out_dir <- sprintf("output/nca/v%d/figures", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

sched <- nominal_schedule(cfg, required = !"ntime" %in% names(cObsData))   # data column wins

## EDIT: grouping, statistic, variability (keep in line with fig-mean-conc.R) --------
conc <- assign_nominal_time(cObsData, sched) |>
  mutate(group = "All participants")
stat <- "mean"
variability <- "sd"

p <- gg_pkc_lineplot(
  conc, time_var = ntime, analyte_var = cObs, group = group,
  stat = stat, variability = variability, log_y = TRUE, lloq = sched$lloq
) +
  labs(
    x = sprintf("Nominal time (%s)", cfg$units$time),
    y = sprintf("Concentration (%s, log scale)", cfg$units$conc),
    colour = NULL,
    caption = "Summary values of zero, and lower error bounds at or below zero, cannot be shown on the log scale."
  ) +
  scale_x_continuous(breaks = scales::breaks_pretty(8)) +   # readable ticks (nominal times cluster early)
  pk_legend(conc$group)

# Title and subtitle go in the docorator header (render_tlf), not the ggplot.
render_pk_display(
  p, "fig-mean-conc-semilog", out_dir, cfg, source_data = db_meta$source_file_path,
  title = sprintf("%s (%s) Concentration-Time Profile", str_to_title(stat), toupper(variability)),
  subtitle = sprintf("%s; semi-logarithmic scale%s", cfg$study$id,
                     if (is.na(sched$lloq)) "" else sprintf("; dashed line: LLOQ = %s %s", sched$lloq, cfg$units$conc))
)

nca_log_stop()

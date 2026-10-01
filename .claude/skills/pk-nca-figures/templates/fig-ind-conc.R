# Individual concentration-time profiles: ONE PAGE PER PARTICIPANT, linear and
# semi-logarithmic panels side by side, as one multi-page PDF in the same docorator shell
# as the tables (like the paginated tbl-conc-by-nominal-time). From the pk-nca-figures skill.
# Saves output/nca/v{{project_number}}/figures/fig-ind-conc.pdf (+ .RDS: list of plots, one per participant).

library(tidyverse)
library(patchwork)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-ind-conc", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
db_meta <- read_nca_db(project_number)
source(".posit/assistant/skills/pk-nca/scripts/nca_nominal.R")
source(".posit/assistant/skills/pk-nca-figures/scripts/nca_figures.R")

out_dir <- sprintf("output/nca/v%d/figures", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

lloq <- nominal_schedule(cfg, required = FALSE)$lloq
x_lab <- sprintf("Time after dose (%s)", cfg$units$time)
y_lab <- sprintf("Concentration (%s)", cfg$units$conc)
lloq_layer <- if (!is.na(lloq)) geom_hline(yintercept = lloq, linetype = "dashed", colour = "grey40")

ind_plot <- function(id) {
  d <- filter(cObsData, as.character(participant) == id)
  dose <- filter(doseData, as.character(participant) == id)
  lin <- ggplot(d, aes(time, cObs)) +
    lloq_layer + geom_line() + geom_point() +
    labs(x = x_lab, y = y_lab, subtitle = "Linear scale") + theme_pk()
  semilog <- ggplot(filter(d, cObs > 0), aes(time, cObs)) +
    lloq_layer + geom_line() + geom_point() + scale_y_log10() +
    labs(x = x_lab, y = y_lab, subtitle = "Semi-logarithmic scale") + theme_pk()
  # Page label only (identifies the page); the figure title is in the docorator header.
  (lin | semilog) + plot_annotation(
    title = sprintf("Participant %s; dose %s %s (%s)", id,
                    paste(signif(dose$dose, 3), collapse = ", "), cfg$units$dose,
                    paste(unique(dose$route), collapse = ", ")),
    caption = paste0("Actual sampling times. Concentrations of 0 are not shown on the log scale.",
                     if (!is.na(lloq)) sprintf(" Dashed line: LLOQ = %s %s.", lloq, cfg$units$conc) else "")
  )
}

plots <- lapply(participant_order(cObsData$participant), ind_plot)
names(plots) <- participant_order(cObsData$participant)

render_pk_display(
  plots, "fig-ind-conc", out_dir, cfg, source_data = db_meta$source_file_path,
  title = "Individual Concentration-Time Profiles",
  subtitle = sprintf("%s; linear and semi-logarithmic scale; one page per participant", cfg$study$id)
)

nca_log_stop()

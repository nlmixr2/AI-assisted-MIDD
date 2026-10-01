# Individual fits for the final model (checklist item 3): ONE PAGE PER PARTICIPANT, linear
# and semi-log panels -- observed (points), individual prediction (solid), population
# prediction (dashed) from augPred(); ETAs in the caption. The worst-fitting participants
# (highest mean |IWRES|) are flagged in the page label so they are reviewed first.
# Saves output/poppk/v{{project_number}}/figures/fig-individual-fits.pdf (+ .RDS: one plot per participant).

library(nlmixr2)
library(tidyverse)
library(patchwork)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-individual-fits", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), fits, runs, pkData -- no refit
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_figures.R")

out_dir <- tlf_out_dir("poppk", project_number)
u <- cfg$units

## EDIT: how many worst-fitting participants to flag -------------------------------
n_worst <- 3

fd <- as.data.frame(fit)
worst <- worst_fitting(fd, n_worst)
miwres <- tapply(abs(fd$IWRES), as.character(fd$ID), mean, na.rm = TRUE)
ap <- as.data.frame(augPred(fit)) |> mutate(id = as.character(id))   # id, time, ind (Population/Individual/Observed), values
etas <- fit$eta |> mutate(ID = as.character(ID))

ind_page <- function(i) {
  d <- filter(ap, id == i)
  panel <- function(log) {
    dd <- if (log) filter(d, values > 0) else d
    p <- ggplot(dd, aes(time, values)) +
      geom_line(data = filter(dd, ind == "Individual"), colour = "steelblue4") +
      geom_line(data = filter(dd, ind == "Population"), linetype = "dashed") +
      geom_point(data = filter(dd, ind == "Observed")) +
      labs(x = lab_unit("Time", u$time), y = lab_unit("Concentration", u$conc, log = log),
           subtitle = if (log) "Semi-logarithmic scale" else "Linear scale") + theme_pmx()
    if (log) p + scale_y_log10() else p
  }
  e <- filter(etas, ID == i) |> select(-ID)
  # Page label only (participant); the figure title is in the docorator header.
  (panel(FALSE) | panel(TRUE)) + plot_annotation(
    title = sprintf("Participant %s%s", i, if (i %in% worst) sprintf(" -- among the %d worst-fitting (mean |IWRES| = %.2f)", n_worst, miwres[[i]]) else ""),
    caption = paste0(paste(sprintf("%s = %.3f", names(e), unlist(e)), collapse = "; "),
                     ". Points: observed; solid: individual prediction; dashed: population prediction.")
  )
}

ids <- id_order(fd$ID)
plots <- setNames(lapply(ids, ind_page), ids)
render_poppk_display(plots, "fig-individual-fits", out_dir, cfg, source_data = db_meta$source_file_path,
                     title = sprintf("Individual Fits -- %s (Final Model)", final_run),
                     subtitle = sprintf("%s; one page per participant, worst-fitting flagged", cfg$study$id))

nca_log_stop()

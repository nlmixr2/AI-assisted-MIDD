# Convergence of the final model (checklist item 6): parameter history by iteration
# (nlmixr2plot::traceplot(); SAEM burn-in and estimation phases), standard TLF shell.
# A flat final phase indicates convergence. Methods without an iteration history get a page
# saying so, so the output always exists.
# Saves output/poppk/v{{project_number}}/figures/fig-traceplot.pdf (+ .RDS).

library(nlmixr2)
library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-traceplot", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), fits, runs, pkData -- no refit
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_figures.R")

out_dir <- tlf_out_dir("poppk", project_number)
u <- cfg$units

p <- if (!is.null(fit$parHist) && nrow(fit$parHist) > 1) {
  nlmixr2plot::traceplot(fit) + theme_pmx()
} else {
  ggplot() + annotate("text", x = 0, y = 0, label = sprintf("No iteration history stored for est = '%s'", fit$est)) +
    theme_void()
}

# Title and subtitle go in the docorator header (render_tlf), not the ggplot.
render_poppk_display(p, "fig-traceplot", out_dir, cfg, source_data = db_meta$source_file_path,
                     title = sprintf("Parameter History -- %s (Final Model, %s)", final_run, toupper(fit$est)),
                     subtitle = "Estimates by iteration; a flat final phase indicates convergence")

nca_log_stop()

# Goodness of fit for the final model (poppk-estimation references/diagnostics.md, checklist
# items 1-2), two pages in the standard TLF shell:
#   page 1 (linear): DV vs PRED, DV vs IPRED (identity + loess), CWRES vs TIME, CWRES vs PRED
#                    (reference lines at 0, +/-2 dotted, +/-3 dashed)
#   page 2 (log):    DV vs PRED and DV vs IPRED on log-log axes, CWRES normal QQ, |IWRES| vs IPRED
# Saves output/poppk/v{{project_number}}/figures/fig-gof.pdf (+ .RDS).

library(tidyverse)
library(patchwork)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-gof", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), fits, runs, pkData -- no refit
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_figures.R")

out_dir <- tlf_out_dir("poppk", project_number)
u <- cfg$units

fd <- as.data.frame(fit)
conc_lab <- function(what) lab_unit(what, u$conc)
loess_layer <- geom_smooth(method = "loess", formula = y ~ x, se = FALSE, colour = "firebrick", linewidth = 0.7)

p_identity <- function(x, xlab, log = FALSE) {
  d <- if (log) filter(fd, DV > 0, {{ x }} > 0) else fd
  p <- ggplot(d, aes({{ x }}, DV)) + geom_abline(linetype = "dashed") +
    geom_point(alpha = 0.5, size = 1.2) + loess_layer +
    labs(x = xlab, y = conc_lab("Observed")) + theme_pmx()
  if (log) p + scale_x_log10() + scale_y_log10() else p
}
p_resid <- function(x, xlab) {
  ggplot(fd, aes({{ x }}, CWRES)) +
    geom_hline(yintercept = 0) +
    geom_hline(yintercept = c(-2, 2), linetype = "dotted") +
    geom_hline(yintercept = c(-3, 3), linetype = "dashed", colour = "grey50") +
    geom_point(alpha = 0.5, size = 1.2) + loess_layer +
    labs(x = xlab, y = "CWRES") + theme_pmx()
}

page_linear <- (p_identity(PRED, conc_lab("Population prediction")) | p_identity(IPRED, conc_lab("Individual prediction"))) /
  (p_resid(TIME, lab_unit("Time", u$time)) | p_resid(PRED, conc_lab("Population prediction"))) +
  plot_annotation(title = "Linear scale; red: loess smooth; dotted/dashed: CWRES = +/-2 / +/-3")   # page label

qq <- ggplot(fd, aes(sample = CWRES)) + stat_qq(alpha = 0.5, size = 1.2) + stat_qq_line(colour = "firebrick") +
  labs(x = "Theoretical quantiles", y = "CWRES quantiles") + theme_pmx()
iwres <- ggplot(fd, aes(IPRED, abs(IWRES))) + geom_point(alpha = 0.5, size = 1.2) + loess_layer +
  labs(x = conc_lab("Individual prediction"), y = "|IWRES|") + theme_pmx()
page_log <- (p_identity(PRED, conc_lab("Population prediction"), log = TRUE) |
               p_identity(IPRED, conc_lab("Individual prediction"), log = TRUE)) / (qq | iwres) +
  plot_annotation(title = "Log-log observed vs predicted (zero values omitted); CWRES normal QQ; |IWRES| vs IPRED")   # page label

render_poppk_display(list(page_linear, page_log), "fig-gof", out_dir, cfg,
                     source_data = db_meta$source_file_path,
                     title = sprintf("Goodness of Fit -- %s (Final Model, %s)", final_run, toupper(fit$est)),
                     subtitle = sprintf("%s; linear scale, then log scale and residual diagnostics", cfg$study$id))

nca_log_stop()

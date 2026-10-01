# ggPMX diagnostics for the final model that the other figure templates do not draw, in the
# standard TLF shell, one topic per page:
#   NPDE vs time, vs PRED and normal QQ (NPDE stored in the fit by analysis-poppk.R,
#   tableControl(npde = TRUE); ggPMX's own addNpde() fails silently on a cached fit)
#   IWRES density and normal QQ
#   correlations of the random effects (candidate OMEGA blocks)
#   random effects by categorical covariate
# Plots are taken by name (ggPMX::plot_names() / get_plot()), so a page whose plots this fit
# cannot produce (e.g. one ETA: no correlation matrix; no categorical covariate) is skipped
# and the log says why. ggPMX's own VPC is disabled for nlmixr2 fits: see fig-vpc.R.
# Saves output/poppk/v{{project_number}}/figures/fig-pmx-diagnostics.pdf (+ .RDS).

library(nlmixr2)
library(tidyverse)
library(patchwork)
library(ggPMX)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-pmx-diagnostics", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), fits, runs, pkData -- no refit
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_figures.R")

out_dir <- tlf_out_dir("poppk", project_number)

## EDIT: covariates and pages ----------------------------------------------------------
# Baseline covariates (constant within participant); <= 5 distinct values -> categorical.
# Column names must match the data exactly, or ggPMX silently drops the covariate plots.
covariates <- baseline_covariates(pkData)
cats <- covariates[vapply(covariates, function(v) length(unique(pkData[[v]])) <= 5, logical(1))]
conts <- setdiff(covariates, cats)
# Page label = ggPMX plot names shown on that page (lower case, see plot_names(ctr)).
pmx_pages <- list(
  "Normalised prediction distribution errors (NPDE)" = c("npde_time", "npde_pred", "npde_qq"),
  "Individual weighted residuals: distribution" = c("iwres_dens", "iwres_qq"),
  "Correlations of random effects" = "eta_matrix",
  "Random effects by categorical covariate" = "eta_cats"
)

pmx_args <- list(fit)
if (length(conts)) pmx_args$conts <- conts
if (length(cats)) pmx_args$cats <- cats
# ggPMX/GGally draw to the current graphics device while building plots; with none open, R
# writes Rplots.pdf into the project root. A null device keeps those draws off disk.
invisible(grDevices::pdf(NULL))
ctr <- do.call(pmx_nlmixr, pmx_args)
nca_log_resume()   # pmx_nlmixr() resets the message sink; re-attach the run log
available <- plot_names(ctr)

# One ggPMX plot as a patchwork-ready panel in the TLF look. The ETA matrix is a GGally
# ggmatrix (not a ggplot), so it is wrapped as a grob.
pmx_panel <- function(name) {
  p <- tryCatch(get_plot(ctr, name), error = function(e) {
    message("ggPMX plot ", name, " not drawn: ", conditionMessage(e)); NULL
  })
  if (is.null(p)) return(NULL)
  if (inherits(p, "ggmatrix")) {
    return(wrap_elements(full = GGally::ggmatrix_gtable(p + theme(text = element_text(family = "serif")))))
  }
  if (is.list(p) && !inherits(p, "ggplot")) p <- wrap_plots(p)
  p & theme_tlf()
}

pages <- list()
for (label in names(pmx_pages)) {
  wanted <- pmx_pages[[label]]
  missing_plots <- setdiff(wanted, available)
  if (length(missing_plots)) message("Not available for this fit: ", paste(missing_plots, collapse = ", "))
  panels <- compact(lapply(intersect(wanted, available), pmx_panel))
  if (!length(panels)) {
    message("Page skipped: ", label)
    next
  }
  pages[[label]] <- wrap_plots(panels) + plot_annotation(title = label)   # page label
}
if (!length(pages)) stop("ggPMX produced none of the requested plots for this fit", call. = FALSE)

# Title and subtitle go in the docorator header (render_tlf), not the ggplot.
render_poppk_display(pages, "fig-pmx-diagnostics", out_dir, cfg, source_data = db_meta$source_file_path,
                     title = sprintf("Model Diagnostics (ggPMX) -- %s (Final Model)", final_run),
                     subtitle = sprintf("%s; covariates: %s", cfg$study$id,
                                        if (length(covariates)) paste(covariates, collapse = ", ") else "none"))

nca_log_stop()

# Shared ggplot building blocks for production figures (sourced by tlf_shell.R, so every
# fig-*.R that sources the shell has them). Same typography as the tables: 11 pt serif.
#
#   theme_tlf()                            theme_bw, 11 pt serif, legend at the bottom, no minor grid
#   out_dir <- tlf_out_dir("poppk", n)     output/poppk/v{n}/figures (created)
#   lab_unit("Concentration", u$conc)      "Concentration (mg/L)"; log = TRUE adds ", log scale"
#
# theme_pk() (pk-nca-figures) and theme_pmx() (poppk-estimation) are this theme.

library(ggplot2)

#' The figure theme of every TLF: theme_bw at `base_size` pt, serif, legend at the bottom,
#' no minor grid lines, bold page labels.
theme_tlf <- function(base_size = 11) {
  theme_bw(base_size = base_size, base_family = "serif") +
    theme(legend.position = "bottom", panel.grid.minor = element_blank(),
          plot.title = element_text(face = "bold"))
}

#' Output folder of a version's figures (or tables), created if needed.
tlf_out_dir <- function(type, project_number, kind = "figures") {
  d <- file.path("output", type, sprintf("v%d", as.integer(project_number)), kind)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

#' Axis label with its unit, e.g. lab_unit("Time after dose", u$time) -> "Time after dose (h)".
lab_unit <- function(what, unit, log = FALSE) {
  sprintf("%s (%s%s)", what, unit, if (log) ", log scale" else "")
}

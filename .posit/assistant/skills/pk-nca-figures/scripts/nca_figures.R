# Helpers for NCA figure scripts (script/nca/v{n}/fig-*.R) built from the pk-nca-figures
# templates. Source after project.R (for analysis_title()).
#
#   render_pk_display(p, "fig-mean-conc", out_dir, cfg)          # one page, docorator shell
#   render_pk_display(plot_list, "fig-ind-conc", out_dir, cfg)   # one page per list element
#
# The docorator shell is the shared TLF shell (pk-project scripts/tlf_shell.R), identical for
# tables and figures: header = analysis title + "Page x of y"; footer = "Source data: <file>"
# + script path + render date-time.
# Output: {out_dir}/{name}.pdf (RTF if TinyTeX is missing) plus {name}.RDS, the display
# object docorator saved -- ggplots are converted to page images (PNG) by docorator 0.7.0+ --
# recorded in the spec (display_rds) and reused by pk-nca-report (write_display_png()).

library(ggplot2)
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")

#' Render a ggplot, or a list of ggplots (one page each), in the standard TLF shell
#' (pk-project scripts/tlf_shell.R: header title + page, footer "Source data:" + script + time).
#'
#' @param source_data Path of the source data file (db_meta$source_file_path).
#' @param fig_dim Figure size on the page, c(height, width) in inches (docorator convention);
#'   default tlf_fig_dim (pk-project scripts/tlf_shell.R). Taller spills onto an extra, blank page.
#' @param title,subtitle Figure title and subtitle, placed in the docorator header (not the ggplot).
render_pk_display <- function(display, display_name, out_dir, cfg, type = "nca",
                              source_data = NULL, title = NULL, subtitle = NULL, fig_dim = tlf_fig_dim) {
  render_tlf(display, display_name, out_dir, cfg, type = type, source_data = source_data,
             title = title, subtitle = subtitle, fig_dim = fig_dim)
}

#' Subset of times at least `min_gap` (fraction of the range) apart, always keeping the first
#' and last -- for readable x-axis ticks and summary-table columns when times cluster early.
spaced_times <- function(times, min_gap = 0.08) {
  times <- sort(unique(times))
  if (length(times) <= 2) return(times)
  gap <- min_gap * diff(range(times))
  keep <- times[1]
  for (t in times[-1]) if (t - tail(keep, 1) >= gap) keep <- c(keep, t)
  last <- tail(times, 1)
  if (tail(keep, 1) != last) keep <- c(if (last - tail(keep, 1) < gap) head(keep, -1) else keep, last)
  keep
}

#' Participants in numeric ID order (character).
participant_order <- function(x) {
  ids <- unique(as.character(x))
  num <- suppressWarnings(as.numeric(ids))
  if (anyNA(num)) sort(ids) else ids[order(num)]
}

#' Legend handling for crane PK plots: hidden for a single group (crane otherwise draws a
#' redundant colour and "group" legend), untitled at the bottom for several groups.
pk_legend <- function(groups) {
  if (length(unique(groups)) <= 1) {
    theme(legend.position = "none")
  } else {
    list(labs(colour = NULL, shape = NULL, linetype = NULL, group = NULL),
         theme(legend.position = "bottom", legend.title = element_blank()))
  }
}

#' Shared look for PK figures (clean, print-friendly, legend at the bottom).
theme_pk <- theme_tlf   # the TLF figure theme (pk-project scripts/figure_helpers.R)

# The standard docorator "shell" for every production table and figure (TLF), so all
# outputs of the template look the same:
#
#   header: analysis title (left)                         Page x of y (right)
#                         <figure title> (centred; figures only)
#                        <figure subtitle> (centred; figures only)
#   footer: Source data: <file the analysis read>
#           <script that produced the output> (left)      render date-time (right)
#
#   render_tlf(display, "tbl-pk-parameters", out_dir, cfg, source_data = db_meta$source_file_path)
#
# `display` is a gt table, a gt_group / list of gt (one page each), a ggplot, or a list of
# ggplots (one page each). Output is 11 pt serif (tlf_fontsize, tlf_font_tex). Writes
# {out_dir}/{display_name}.pdf (RTF if TinyTeX is missing) and {display_name}.RDS -- the exact display object, recorded in the spec (display_rds)
# and reused by the reports. Source after project.R (for analysis_title()).
#
# Titles: a table's title and subtitle come from tfrmt (tfrmt(title =, subtitle =)); a figure's
# come from render_tlf(title =, subtitle =), which puts them in the docorator header. Never put
# them in the ggplot (labs(title/subtitle), plot_annotation()). The header is the same on every
# page, so a multi-page figure has one title; a page that needs identifying (participant,
# regimen, page type) gets one short in-plot label line (labs(title =)) and nothing more.
# Keep header text to plain words and numbers: put anything with LaTeX special characters
# (% & _ # $), such as "90% PI", in the plot caption instead.

library(docorator)
source(".posit/assistant/skills/pk-project/scripts/tfrmt_helpers.R")   # fs(), summary_ard(), ...
source(".posit/assistant/skills/pk-project/scripts/figure_helpers.R")  # theme_tlf(), lab_unit(), ...

# Typography of every TLF: 11 pt serif. Tables, headers and footers are LaTeX text (font from
# assets/tlf-serif.tex, passed to render_pdf(header_latex =)); figures are ggplots turned into
# images by docorator, so their text family is set on the plot (tlf_serif()).
tlf_fontsize <- 11L
tlf_font_tex <- ".posit/assistant/skills/pk-project/assets/tlf-serif.tex"
# Figure size on the page, c(height, width) in inches. 4.6 in tall fits a landscape page with
# the full header (analysis title, title, subtitle) and footer ("Source data:", script, time);
# docorator's own default of 5 in then spills the figure onto a second page, leaving the
# first one blank.
tlf_fig_dim <- c(4.6, 8)

#' Render a table or figure in the standard TLF shell.
#'
#' @param display gt / gt_group / ggplot, or a list of them (one per page).
#' @param display_name Output file name without extension -- the script name.
#' @param out_dir Output directory (output/{type}/v{n}/tables or figures).
#' @param cfg project_config() result.
#' @param type Analysis type for the header title ("nca", "poppk", "poppk-sim").
#' @param source_data Path of the source data file (e.g. db_meta$source_file_path from
#'   read_nca_db()); printed as "Source data: ..." in the footer. NULL omits the line.
#' @param title,subtitle Figure title and subtitle, centred header lines under the analysis
#'   title (same for every page). Leave NULL for tables: tfrmt already carries theirs.
#' @param fontsize Point size of the document (docorator accepts 10, 11 or 12).
#' @param fig_dim Figure size, c(height, width) in inches (tlf_fig_dim); ignored for tables.
#'   Keep the height at or below 4.6 in, or the figure spills onto an extra, blank page.
#' @param ... Passed to as_docorator().
render_tlf <- function(display, display_name, out_dir, cfg, type = "nca", source_data = NULL,
                       title = NULL, subtitle = NULL, fontsize = tlf_fontsize,
                       fig_dim = tlf_fig_dim, ...) {
  has_text <- function(x) !is.null(x) && length(x) == 1 && !is.na(x) && nzchar(x)
  header_rows <- list(fancyrow(left = analysis_title(type, cfg), right = doc_pagenum()))
  if (has_text(title)) header_rows <- c(header_rows, list(fancyrow(center = title)))
  if (has_text(subtitle)) header_rows <- c(header_rows, list(fancyrow(center = subtitle)))
  footer_rows <- list(fancyrow(left = doc_path(display_name, out_dir), right = doc_datetime()))
  if (!is.null(source_data) && length(source_data) && nzchar(source_data)) {
    footer_rows <- c(list(fancyrow(left = paste("Source data:", source_data))), footer_rows)
  }
  doc <- as_docorator(
    tlf_serif(display),
    display_name = display_name, display_loc = out_dir,
    header = do.call(fancyhead, header_rows),
    footer = do.call(fancyfoot, footer_rows),
    fontsize = fontsize,
    fig_dim = fig_dim,
    ...
  )
  if (requireNamespace("tinytex", quietly = TRUE) && tinytex::is_tinytex()) {
    pdf_args <- list(doc, display_loc = out_dir)
    if (tlf_has_header_latex()) {
      pdf_args$header_latex <- tlf_font_tex
    } else {
      message("docorator ", utils::packageVersion("docorator"), " has no render_pdf(header_latex =): ",
              "tables and headers keep its default typewriter font (update docorator for serif)")
    }
    do.call(render_pdf, pdf_args)
  } else {
    render_rtf(doc, display_loc = out_dir)
  }
  invisible(doc)
}

#' Serif text for ggplot displays (a ggplot, a patchwork, or a list of them); other displays
#' (gt tables, PNG paths) are returned unchanged.
tlf_serif <- function(display) {
  serif <- ggplot2::theme(text = ggplot2::element_text(family = "serif"))
  if (inherits(display, "patchwork")) return(display & serif)
  if (inherits(display, "ggplot")) return(display + serif)
  if (is.list(display) && !inherits(display, "gt_tbl") && length(display) &&
      all(vapply(display, function(x) inherits(x, "ggplot"), logical(1)))) {
    return(lapply(display, tlf_serif))
  }
  display
}

#' Does the installed docorator's PDF renderer take `header_latex` (the font file)?
tlf_has_header_latex <- function() {
  ns <- asNamespace("docorator")
  args <- names(formals(ns$render_pdf))
  if (exists("render_pdf_latex", envir = ns, inherits = FALSE)) args <- c(args, names(formals(ns$render_pdf_latex)))
  "header_latex" %in% args
}

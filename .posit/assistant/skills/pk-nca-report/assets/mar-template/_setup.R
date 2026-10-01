# Shared setup, sourced by the first chunk of every chapter. Quarto runs chapters from
# this MAR folder (execute-dir: project); data are read from the project root.
nca_version <- {{project_number}}L

root <- normalizePath(file.path("..", "..", "..", ".."))   # output/nca/v{n}/MAR -> project root
local({
  old <- setwd(root); on.exit(setwd(old))
  suppressPackageStartupMessages({
    source(".posit/assistant/skills/pk-project/scripts/project.R", local = globalenv())
    source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R", local = globalenv())
    source(".posit/assistant/skills/pk-nca-report/scripts/nca_report_helpers.R", local = globalenv())
    source(".posit/assistant/skills/pk-nca-figures/scripts/nca_figures.R", local = globalenv())   # participant_order()
    source(".posit/assistant/skills/pk-nca/scripts/nca_nominal.R", local = globalenv())           # nominal_time_source()
  })
  assign("cfg", project_config(), envir = globalenv())
  assign("db_meta", read_nca_db(nca_version, envir = globalenv(), verify_source = FALSE), envir = globalenv())
  assign("spec", yaml::read_yaml(sprintf("spec/nca/v%d.yaml", nca_version)), envir = globalenv())
  assign("qc_result", latest_qc_result(nca_version), envir = globalenv())
})

out_dir <- file.path(root, "output", "nca", sprintf("v%d", nca_version))
# Figures are referenced relative to the chapter file being rendered (Quarto resolves
# image paths from the chapter's folder, and reads absolute paths as project-relative).
# Use with knitr::include_graphics(fig_file("x.png"), rel_path = FALSE, error = FALSE).
fig_file <- function(name) {
  abs <- file.path(out_dir, "figures", name)
  if (!file.exists(abs)) stop("Figure not found: ", abs, call. = FALSE)
  chapter_dir <- dirname(normalizePath(knitr::current_input(dir = TRUE)))
  as.character(fs::path_rel(abs, start = chapter_dir))
}
u <- cfg$units
data_sum <- nca_data_summary(cObsData, doseData)
logs_dir <- file.path(out_dir, "logs")
qc_text <- if (is.na(qc_result$tests)) "not run" else
  sprintf("%d of %d checks passed (%s)", qc_result$tests - qc_result$failed, qc_result$tests, basename(qc_result$file))
log_table <- function() run_log_table(names(spec$script_hashes), logs_dir)
validation_report <- function() data_validation_report(logs_dir)

# QC'd displays of the version, reused verbatim: tables are the gt objects and figures the
# page images that docorator saved next to each PDF (.RDS), hash-checked against the spec.
fig_display <- function(name) nca_output_display(name, spec, root, "figures")
# Path (relative to the current chapter) of page `i` of a QC'd figure, written from its .RDS
# into MAR/_display/ -- the exact image in the QC'd PDF.
qc_figure <- function(name, i = 1, display = fig_display(name)) {
  f <- normalizePath(file.path("_display", sprintf("%s-%d.png", name, i)), mustWork = FALSE)
  write_display_png(display, f, i)
  as.character(fs::path_rel(f, start = dirname(normalizePath(knitr::current_input(dir = TRUE)))))
}

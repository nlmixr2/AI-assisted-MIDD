# Shared setup, sourced by the first chunk of every chapter. Quarto runs chapters from
# this MAR folder (execute-dir: project); data are read from the project root.
poppk_version <- {{project_number}}L

root <- normalizePath(file.path("..", "..", "..", ".."))   # output/poppk/v{n}/MAR -> project root
local({
  old <- setwd(root); on.exit(setwd(old))
  suppressPackageStartupMessages({
    source(".posit/assistant/skills/pk-project/scripts/project.R", local = globalenv())
    source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R", local = globalenv())
    # report helpers shared with pk-nca-report (display objects, logs, QC result, tables)
    source(".posit/assistant/skills/pk-nca-report/scripts/nca_report_helpers.R", local = globalenv())
    source(".posit/assistant/skills/poppk-report/scripts/poppk_report_helpers.R", local = globalenv())
  })
  assign("cfg", project_config(), envir = globalenv())
  # hash-verified read of the version's database (pkData, runs, final_run, ...): no refit
  assign("db_meta", read_poppk_db(poppk_version, envir = globalenv(), verify_source = FALSE), envir = globalenv())
  assign("spec", yaml::read_yaml(sprintf("spec/poppk/v%d.yaml", poppk_version)), envir = globalenv())
  assign("qc_result", latest_qc_result(poppk_version, output_dir = "output/poppk"), envir = globalenv())
})

out_dir <- file.path(root, "output", "poppk", sprintf("v%d", poppk_version))
u <- cfg$units
data_sum <- poppk_data_summary(pkData)
logs_dir <- file.path(out_dir, "logs")
qc_text <- if (is.na(qc_result$tests)) "not run" else
  sprintf("%d of %d checks passed (%s)", qc_result$tests - qc_result$failed, qc_result$tests, basename(qc_result$file))
log_table <- function() run_log_table(names(spec$script_hashes), logs_dir)
validation_report <- function() data_validation_report(logs_dir)

# QC'd displays of the version, reused verbatim: tables are the gt objects and figures the
# page images that docorator saved next to each PDF (.RDS), hash-checked against the spec.
table_display <- function(name) nca_output_display(name, spec, root, "tables")
fig_display <- function(name) nca_output_display(name, spec, root, "figures")
# Path (relative to the current chapter) of page `i` of a QC'd figure, written from its .RDS
# into MAR/_display/ -- the exact image in the QC'd PDF.
qc_figure <- function(name, i = 1, display = fig_display(name)) {
  f <- normalizePath(file.path("_display", sprintf("%s-%d.png", name, i)), mustWork = FALSE)
  write_display_png(display, f, i)
  as.character(fs::path_rel(f, start = dirname(normalizePath(knitr::current_input(dir = TRUE)))))
}

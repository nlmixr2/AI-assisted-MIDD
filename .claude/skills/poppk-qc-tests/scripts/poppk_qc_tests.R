# Helpers for per-version popPK QC-readiness tests (tests/poppk/v{project_number}/).
# Source this file, then:
#
#   create_poppk_qc_tests(project_number)   # writes tests/poppk/v{n}/test-poppk-qc.R from the template
#   run_poppk_qc_tests(project_number)      # runs tests/poppk/v{n}/, writes a JUnit report to
#                                     # output/poppk/v{n}/logs/qc-tests-{timestamp}.xml
#
# All paths are relative to the current working directory (the project root).

poppk_qc_template_path <- function() {
  ".posit/assistant/skills/poppk-qc-tests/assets/test-poppk-qc-template.R"
}

#' Write tests/poppk/v{project_number}/test-poppk-qc.R from the skill template.
#'
#' @param project_number Integer version number.
#' @param tests_dir Parent directory of versioned test directories. Defaults to "tests/poppk".
#' @param overwrite If FALSE (default), refuse to replace an existing test file --
#'   it may carry hand-added analysis-specific checks.
#' @return (Invisibly) the path written to.
create_poppk_qc_tests <- function(project_number, tests_dir = "tests/poppk", overwrite = FALSE) {
  pn <- as.integer(project_number)
  if (!dir.exists(file.path("script/poppk", sprintf("v%d", pn)))) {
    stop("Script directory not found: script/poppk/v", pn, call. = FALSE)
  }
  out_dir <- file.path(tests_dir, sprintf("v%d", pn))
  out_path <- file.path(out_dir, "test-poppk-qc.R")
  if (file.exists(out_path) && !overwrite) {
    stop(out_path, " already exists -- pass overwrite = TRUE to replace it.", call. = FALSE)
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  txt <- gsub("{{project_number}}", pn, readLines(poppk_qc_template_path(), warn = FALSE), fixed = TRUE)
  writeLines(txt, out_path)
  message("Wrote ", out_path)
  invisible(out_path)
}

#' Run a version's QC-readiness tests.
#'
#' Prints progress to the console and saves a JUnit XML report next to the
#' version's run logs, so the QC reviewer gets a record of which checks passed.
#'
#' @param project_number Integer version number.
#' @param tests_dir Parent directory of versioned test directories. Defaults to "tests/poppk".
#' @param output_dir Parent directory of versioned output directories. Defaults to "output/poppk".
#' @return (Invisibly) `TRUE` if every test passed; otherwise raises an error.
run_poppk_qc_tests <- function(project_number, tests_dir = "tests/poppk", output_dir = "output/poppk") {
  pn <- as.integer(project_number)
  test_path <- file.path(tests_dir, sprintf("v%d", pn))
  if (!dir.exists(test_path)) {
    stop("No tests for v", pn, " -- run create_poppk_qc_tests(", pn, ") first.", call. = FALSE)
  }
  log_dir <- file.path(output_dir, sprintf("v%d", pn), "logs")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  junit_path <- file.path(normalizePath(log_dir), sprintf("qc-tests-%s.xml", format(Sys.time(), "%Y%m%dT%H%M%S")))

  reporter <- testthat::MultiReporter$new(list(
    testthat::ProgressReporter$new(show_praise = FALSE),
    testthat::JunitReporter$new(file = junit_path)
  ))
  res <- as.data.frame(testthat::test_dir(test_path, reporter = reporter, stop_on_failure = FALSE))
  message("QC test report: ", junit_path)

  n_bad <- sum(res$failed) + sum(res$error)
  if (n_bad > 0) {
    stop("v", pn, " is NOT ready for QC: ", n_bad, " test(s) failed -- see ", junit_path, call. = FALSE)
  }
  message("v", pn, " is ready for QC: all ", nrow(res), " tests passed.")
  invisible(TRUE)
}

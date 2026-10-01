# QC-readiness tests for popPK version v{{project_number}}.
# Generated from the poppk-qc-tests skill's assets/test-poppk-qc-template.R by
# create_poppk_qc_tests({{project_number}}L) -- regenerate rather than hand-editing, and
# add any analysis-specific checks at the bottom (section 9).
#
# A version is "ready for QC" when every test here passes: all scripts ran to
# completion, the spec is complete and untampered, every script/data/database/output
# hash still matches the spec, the model trail in the spec matches the fits, and the
# final model passes its acceptance checks. Nothing here modifies the real bundle --
# negative controls work on temp copies.
#
# Run from the project root:
#   Rscript -e 'source(".posit/assistant/skills/poppk-qc-tests/scripts/poppk_qc_tests.R"); run_poppk_qc_tests({{project_number}}L)'

library(testthat)

withr::local_dir(here::here(), .local_envir = teardown_env())
suppressPackageStartupMessages(suppressWarnings({
  library(nlmixr2)
  source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
  source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")
  source(".posit/assistant/skills/poppk-estimation/scripts/poppk_checks.R")
}))

project_number <- {{project_number}}L
version <- sprintf("v%d", project_number)
script_dir <- file.path("script/poppk", version)
output_dir <- file.path("output/poppk", version)
spec_dir <- "spec/poppk"
spec_path <- file.path(spec_dir, paste0(version, ".yaml"))

## 1. Script directory structure ------------------------------------------------------

scripts <- sort(list.files(script_dir, pattern = "\\.R$"))

test_that("version directory has analysis, generate-spec, and at least one tbl/fig script", {
  expect_length(grep("^analysis-.*\\.R$", scripts), 1)
  expect_true("generate-spec.R" %in% scripts)
  expect_gt(length(grep("^(tbl|fig)-.*\\.R$", scripts)), 0)
})

test_that("every script refers only to this version (project_number and poppk/v{n}/ paths)", {
  for (s in scripts) {
    txt <- readLines(file.path(script_dir, s), warn = FALSE)
    pn <- as.integer(unlist(regmatches(txt, gregexpr("project_number (<-|=) \\K\\d+(?=L)", txt, perl = TRUE))))
    vdirs <- as.integer(unlist(regmatches(txt, gregexpr("(?<=poppk/v)\\d+(?=/)", txt, perl = TRUE))))
    expect_true(all(c(pn, vdirs) == project_number), label = s)
  }
})

test_that("every script logs to output/poppk via nca_log_start()/nca_log_stop()", {
  for (s in scripts) {
    txt <- paste(readLines(file.path(script_dir, s), warn = FALSE), collapse = "\n")
    expect_match(txt, sprintf("nca_log_start\\(\"%s\",[^)]*output_dir = \"output/poppk\"",
                              tools::file_path_sans_ext(s)), label = s)
    expect_match(txt, "nca_log_stop\\(\\)", label = s)
  }
})

## 2. Execution logs: every script ran to completion without errors -------------------

latest_log <- function(script) {
  logs <- sort(list.files(file.path(output_dir, "logs"),
                          pattern = sprintf("^%s-\\d{8}T\\d{6}\\.log$", script), full.names = TRUE))
  if (length(logs) == 0) NA_character_ else tail(logs, 1)
}

test_that("each script's latest log exists, ran to completion, and has no errors", {
  for (s in tools::file_path_sans_ext(scripts)) {
    log <- latest_log(s)
    expect_false(is.na(log), label = paste(s, "log exists"))
    if (is.na(log)) next
    txt <- readLines(log, warn = FALSE)
    expect_true(any(txt == sprintf("# project_number: %d", project_number)), label = paste(s, "log project_number"))
    expect_true(any(grepl("^# sessionInfo\\(\\):", txt)), label = paste(s, "reached nca_log_stop()"))
    expect_false(any(grepl("^Error", txt)), label = paste(s, "log has no errors"))
  }
})

## 3. Spec file: present, untampered, complete, awaiting QC ------------------------------

spec <- yaml::read_yaml(spec_path)

test_that("spec file matches its sidecar hash", {
  expect_true(verify_spec(project_number, spec_dir = spec_dir))
})

test_that("spec describes this version and has its semantic fields filled in", {
  expect_identical(as.integer(spec$project_number), project_number)
  expect_identical(spec$script_dir, script_dir)
  for (field in list(spec$description, spec$data$dataset, spec$report$title,
                     spec$data$source_file$path, spec$final_model$run_id,
                     spec$final_model$rationale)) {
    expect_true(is.character(field) && nzchar(field))
  }
  expect_gt(length(spec$models), 0)
  expect_true(all(c("conc", "time", "dose") %in% names(spec$data$units)))
})

test_that("QC status is pending or in review (not already signed off)", {
  expect_true(spec$qc$status %in% c("pending", "in_review"))
})

## 4. Provenance: scripts, source data, database vs the spec -------------------------------

test_that("spec lists exactly the scripts on disk, with matching hashes", {
  expect_setequal(names(spec$script_hashes), scripts)
  for (s in scripts) {
    expect_identical(hash_file(file.path(script_dir, s)), spec$script_hashes[[s]], label = s)
  }
})

test_that("source data file matches its recorded hash", {
  expect_true(file.exists(spec$data$source_file$path))
  expect_identical(hash_file(spec$data$source_file$path), spec$data$source_file$hash)
})

pp <- new.env()
db_meta <- read_poppk_db(project_number, envir = pp)   # errors if the blob fails verification

test_that("database payload_hash and source file match the spec", {
  expect_identical(db_meta$payload_hash, spec$data$poppk_db$payload_hash)
  expect_identical(db_meta$source_file_path, spec$data$source_file$path)
  expect_identical(db_meta$source_file_hash, spec$data$source_file$hash)
  expect_no_warning(read_poppk_db(project_number, envir = new.env()))   # no stale-data warning
})

test_that("model dataset hash matches the spec", {
  expect_identical(hash(pp$pkData), spec$data$hash$components$pkData)
})

## 5. Outputs: every table/figure exists, is non-empty, and matches the spec ---------------

test_that("every tbl-/fig- script has an output recorded in the spec", {
  recorded <- tools::file_path_sans_ext(basename(vapply(
    c(spec$outputs$tables, spec$outputs$figures), `[[`, "", "path")))
  expected <- tools::file_path_sans_ext(grep("^(tbl|fig)-", scripts, value = TRUE))
  expect_setequal(recorded, expected)
})

test_that("every output lives in this version's output directory and is non-empty", {
  for (entry in c(spec$outputs$tables, spec$outputs$figures)) {
    expect_true(startsWith(entry$path, paste0(output_dir, "/")), label = entry$path)
    expect_gt(file.size(entry$path), 0)
  }
})

test_that("every table and figure matches its recorded hash", {
  expect_true(verify_outputs(project_number, spec_dir = spec_dir))
})

## 6. Model trail: spec, database, and fits agree -------------------------------------------

test_that("spec's model trail matches the runs in the database", {
  spec_runs <- vapply(spec$models, `[[`, "", "run_id")
  expect_setequal(spec_runs, names(pp$fits))
  expect_setequal(pp$runs$run_id, names(pp$fits))
  for (m in spec$models) {
    fit <- pp$fits[[m$run_id]]
    expect_equal(m$objf, fit$objf, tolerance = 1e-4, label = paste(m$run_id, "objf"))
    expect_identical(m$model_hash, hash(deparse(as.function(fit$ui))), label = paste(m$run_id, "model code"))
  }
})

test_that("every run has a finite OFV, and dOFV is consistent with its parent", {
  expect_true(all(is.finite(pp$runs$objf)))
  has_parent <- !is.na(pp$runs$parent_run)
  expect_true(all(pp$runs$parent_run[has_parent] %in% pp$runs$run_id))
  expected <- pp$runs$objf - pp$runs$objf[match(pp$runs$parent_run, pp$runs$run_id)]
  expect_equal(pp$runs$delta_ofv, expected)
})

test_that("exactly one final model, the same in database and spec", {
  expect_identical(sum(pp$runs$final), 1L)
  expect_identical(pp$runs$run_id[pp$runs$final], pp$final_run)
  expect_identical(spec$final_model$run_id, pp$final_run)
  expect_identical(db_meta$final_run, pp$final_run)
})

## 7. Final model: data coverage and acceptance checks --------------------------------------

test_that("fit used every subject and observation in the dataset", {
  # observations as nlmixr2 counts them: EVID 0 and not MDV 1 (same rule as check_param_table())
  is_obs <- pp$pkData$EVID == 0 & (if ("MDV" %in% names(pp$pkData)) pp$pkData$MDV %in% 0 else TRUE)
  obs <- pp$pkData[is_obs, ]
  expect_setequal(as.character(unique(pp$fit$ID)), as.character(unique(pp$pkData$ID)))
  expect_equal(nrow(pp$fit), nrow(obs))
  expect_true(all(pp$pkData$AMT[pp$pkData$EVID != 0] > 0))
})

test_that("final model passes every acceptance check (no fail)", {
  checks <- acceptance_checks(pp$fit)
  expect_false(any(checks$status == "fail"),
               info = paste(checks$check[checks$status == "fail"], collapse = ", "))
})

test_that("spec's recorded acceptance checks and caveats match a recomputation", {
  checks <- acceptance_checks(pp$fit)
  recorded <- vapply(spec$final_model$acceptance_checks, `[[`, "", "status")
  names(recorded) <- vapply(spec$final_model$acceptance_checks, `[[`, "", "check")
  expect_identical(recorded[checks$check], setNames(checks$status, checks$check))
  caveats <- vapply(spec$diagnostics$caveats, `[[`, "", "check")
  expect_setequal(caveats, checks$check[checks$status == "warn"])
})

## 7b. nlmixr2save fit archives: present, unchanged, and loadable -------------------------

suppressPackageStartupMessages(source(".posit/assistant/skills/poppk-estimation/scripts/poppk_fits.R"))

test_that("every run has a fit archive, and archives match their recorded hashes", {
  archives <- spec$fit_archives
  if (is.null(archives)) skip("spec predates nlmixr2save fit archives")
  runs_archived <- vapply(Filter(function(a) a$kind == "fit archive", archives), `[[`, "", "run_id")
  expect_setequal(runs_archived, names(pp$fits))
  for (a in archives) {
    expect_true(file.exists(a$path), label = a$path)
    expect_identical(hash_file(a$path), a$hash, label = a$path)
  }
})

test_that("the final model's archive reloads with the same OFV and estimates, and a data-free copy exists", {
  if (is.null(spec$fit_archives)) skip("spec predates nlmixr2save fit archives")
  final_zip <- file.path(fit_dir(project_number), paste0(pp$final_run, ".zip"))
  shared_zip <- file.path(fit_dir(project_number), "shared", paste0(pp$final_run, "-noData.zip"))
  f <- suppressMessages(suppressWarnings(load_fit_archive(final_zip)))
  expect_equal(f$objf, pp$fit$objf, tolerance = 1e-6)
  expect_equal(f$theta, pp$fit$theta, tolerance = 1e-8)
  expect_true(file.exists(shared_zip))
  sh <- suppressMessages(suppressWarnings(load_fit_archive(shared_zip)))
  expect_null(sh$origData)
  expect_equal(sh$theta, pp$fit$theta, tolerance = 1e-8)
})

## 8. Negative controls: the checks above do catch tampering (temp copies only) -----------

test_that("an edited spec file fails verify_spec()", {
  tmp <- withr::local_tempdir()
  file.copy(c(spec_path, paste0(spec_path, ".hash")), tmp)
  cat("# tampered\n", file = file.path(tmp, basename(spec_path)), append = TRUE)
  expect_error(verify_spec(project_number, spec_dir = tmp), "does not match its recorded hash")
})

test_that("a modified or missing output file fails verify_outputs()", {
  tmp <- withr::local_tempdir()
  fig <- spec$outputs$figures[[1]]$path
  fig_copy <- file.path(tmp, basename(fig))
  file.copy(fig, fig_copy)
  write(as.raw(0), fig_copy, append = TRUE)

  tampered <- spec
  tampered$outputs$figures[[1]]$path <- fig_copy
  yaml::write_yaml(tampered, file.path(tmp, basename(spec_path)))
  expect_error(verify_outputs(project_number, spec_dir = tmp), "hash mismatch")

  tampered$outputs$figures[[1]]$path <- file.path(tmp, "does-not-exist.png")
  yaml::write_yaml(tampered, file.path(tmp, basename(spec_path)))
  expect_error(verify_outputs(project_number, spec_dir = tmp), "file missing")
})

test_that("a corrupted results blob fails read_poppk_db()", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, version, "db"), recursive = TRUE)
  file.copy(poppk_db_path(project_number), poppk_db_path(project_number, output_dir = tmp))

  con <- poppk_db_connect(project_number, output_dir = tmp)
  blob <- dbGetQuery(con, "SELECT payload_blob FROM poppk_meta")$payload_blob[[1]]
  blob[length(blob)] <- as.raw(bitwXor(as.integer(blob[length(blob)]), 1L))
  dbExecute(con, "UPDATE poppk_meta SET payload_blob = ? WHERE project_number = ?",
            params = list(list(blob), project_number))
  dbDisconnect(con, shutdown = TRUE)

  expect_error(read_poppk_db(project_number, output_dir = tmp, envir = new.env()),
               "failed hash verification")
})

## 9. Analysis-specific checks (add below) --------------------------------------------------

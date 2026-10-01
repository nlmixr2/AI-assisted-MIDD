# QC-readiness tests for NCA version v{{project_number}}.
# Generated from the pk-nca-qc-tests skill's assets/test-nca-qc-template.R by
# create_qc_tests({{project_number}}L) -- regenerate rather than hand-editing, and add
# any analysis-specific checks at the bottom (section 8).
#
# A version is "ready for QC" when every test here passes: all scripts ran to
# completion, the spec is complete and untampered, every script/data/database/output
# hash still matches the spec, and the NCA results are complete and plausible.
# Nothing here modifies the real bundle -- negative controls work on temp copies.
#
# Run from the project root:
#   Rscript -e 'source(".posit/assistant/skills/pk-nca-qc-tests/scripts/qc_tests.R"); run_qc_tests({{project_number}}L)'

library(testthat)

withr::local_dir(here::here(), .local_envir = teardown_env())
suppressPackageStartupMessages(suppressWarnings({   # "package built under R x.y" noise
  source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
  source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")
}))

project_number <- {{project_number}}L
version <- sprintf("v%d", project_number)
script_dir <- file.path("script/nca", version)
output_dir <- file.path("output/nca", version)
spec_path <- file.path("spec/nca", paste0(version, ".yaml"))

## 1. Script directory structure ------------------------------------------------------

scripts <- sort(list.files(script_dir, pattern = "\\.R$"))

test_that("version directory has analysis, generate-spec, and at least one tbl/fig script", {
  expect_length(grep("^analysis-.*\\.R$", scripts), 1)
  expect_true("generate-spec.R" %in% scripts)
  expect_gt(length(grep("^(tbl|fig)-.*\\.R$", scripts)), 0)
})

test_that("every script refers only to this version (project_number and v{n}/ paths)", {
  for (s in scripts) {
    txt <- readLines(file.path(script_dir, s), warn = FALSE)
    pn <- as.integer(unlist(regmatches(txt, gregexpr("project_number (<-|=) \\K\\d+(?=L)", txt, perl = TRUE))))
    vdirs <- as.integer(unlist(regmatches(txt, gregexpr("(?<=nca/v)\\d+(?=/)", txt, perl = TRUE))))
    expect_true(all(c(pn, vdirs) == project_number), label = s)
  }
})

test_that("every script is bookended by nca_log_start()/nca_log_stop()", {
  for (s in scripts) {
    txt <- readLines(file.path(script_dir, s), warn = FALSE)
    expect_true(any(grepl(sprintf("nca_log_start\\(\"%s\"", tools::file_path_sans_ext(s)), txt)), label = s)
    expect_true(any(grepl("nca_log_stop\\(\\)", txt)), label = s)
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
  expect_true(verify_spec(project_number))
})

test_that("spec describes this version and has its semantic fields filled in", {
  expect_identical(as.integer(spec$project_number), project_number)
  expect_identical(spec$script_dir, script_dir)
  for (field in list(spec$description, spec$data$dataset, spec$report$title,
                     spec$data$route, spec$data$source_file$path)) {
    expect_true(is.character(field) && nzchar(field))
  }
  expect_gt(length(spec$parameters$requested), 0)
  expect_setequal(names(spec$data$units), c("conc", "time", "dose", "amount"))
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

nca <- new.env()
db_meta <- read_nca_db(project_number, envir = nca)   # errors if the blob fails verification

test_that("database payload_hash and source file match the spec", {
  expect_identical(db_meta$payload_hash, spec$data$nca_db$payload_hash)
  expect_identical(db_meta$source_file_path, spec$data$source_file$path)
  expect_identical(db_meta$source_file_hash, spec$data$source_file$hash)
  expect_no_warning(read_nca_db(project_number, envir = new.env()))   # no stale-data warning
})

test_that("derived cObsData/doseData hashes match the spec", {
  expect_identical(hash(nca$cObsData), spec$data$hash$components$conc)
  expect_identical(hash(nca$doseData), spec$data$hash$components$dose)
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
  expect_true(verify_outputs(project_number))
})

## 6. NCA results: complete and plausible -------------------------------------------------

participants <- levels(droplevels(factor(nca$cObsData$participant)))
requested <- unlist(spec$parameters$requested)
res_inf <- subset(nca$ncaRes$result, end == Inf)

test_that("input data are well-formed", {
  expect_false(anyNA(nca$cObsData[c("participant", "time", "cObs")]))
  expect_true(all(nca$cObsData$cObs >= 0))
  expect_true(all(nca$doseData$dose > 0))
  expect_setequal(levels(droplevels(factor(nca$doseData$participant))), participants)
  expect_false(anyDuplicated(nca$cObsData[c("participant", "time")]) > 0)
})

test_that("every participant has every requested parameter, non-missing and finite", {
  expect_s3_class(nca$ncaRes, "PKNCAresults")
  for (p in requested) {
    vals <- res_inf[res_inf$PPTESTCD == p, ]
    expect_setequal(as.character(vals$participant), participants)
    expect_true(all(is.finite(vals$PPORRES)), label = paste(p, "finite"))
  }
  expect_equal(nrow(nca$res_wide), length(participants))
})

test_that("parameter values are physically plausible", {
  val <- function(p) res_inf$PPORRES[res_inf$PPTESTCD == p]
  for (p in intersect(requested, c("cmax", "half.life", "aucinf.obs", "auclast", "cl.obs", "vz.obs"))) {
    expect_true(all(val(p) > 0), label = p)
  }
  if ("tmax" %in% requested) {
    expect_true(all(val("tmax") >= 0 & val("tmax") <= max(nca$cObsData$time)))
  }
  if (all(c("cmax", "clast.obs") %in% requested)) {
    expect_true(all(val("clast.obs") <= val("cmax")))
  }
})

test_that("no results were silently excluded", {
  expect_true(all(is.na(res_inf$exclude) | res_inf$exclude == ""))
})

test_that("spec's flagged subjects equal the subjects with span ratio < 2", {
  flagged_db <- sort(as.character(nca$halflife_fit$participant[nca$halflife_fit$span.ratio < 2]))
  flagged_spec <- sort(as.character(vapply(spec$diagnostics$flagged_subjects, function(x) x$id, numeric(1))))
  expect_identical(flagged_spec, flagged_db)
})

## 7. Negative controls: the checks above do catch tampering (temp copies only) -----------

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

test_that("a corrupted results blob fails read_nca_db()", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, version, "db"), recursive = TRUE)
  file.copy(nca_db_path(project_number), nca_db_path(project_number, output_dir = tmp))

  con <- nca_db_connect(project_number, output_dir = tmp)
  blob <- dbGetQuery(con, "SELECT ncares_blob FROM nca_meta")$ncares_blob[[1]]
  blob[length(blob)] <- as.raw(bitwXor(as.integer(blob[length(blob)]), 1L))
  dbExecute(con, "UPDATE nca_meta SET ncares_blob = ? WHERE project_number = ?",
            params = list(list(blob), project_number))
  dbDisconnect(con, shutdown = TRUE)

  expect_error(read_nca_db(project_number, output_dir = tmp, envir = new.env()),
               "failed hash verification")
})

## 8. Analysis-specific checks (add below) --------------------------------------------------

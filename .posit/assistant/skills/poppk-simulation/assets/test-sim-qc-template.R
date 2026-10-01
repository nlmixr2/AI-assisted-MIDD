# QC-readiness tests for popPK simulation version v{{project_number}}.
# Generated from the poppk-simulation skill's assets/test-sim-qc-template.R by
# create_sim_qc_tests({{project_number}}L) -- regenerate rather than hand-editing, and
# add any analysis-specific checks at the bottom (section 8).
#
# A simulation version is "ready for QC" when every test here passes: all scripts ran
# to completion, the spec is complete and untampered, every hash matches, the model
# source (popPK fit or model file) is unchanged since the simulation, the stored
# results re-derive from the stored simulations, and re-simulating from the recorded
# seed reproduces them exactly. Nothing here modifies the real bundle.
#
# Run from the project root:
#   Rscript -e 'source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_qc_tests.R"); run_sim_qc_tests({{project_number}}L)'

library(testthat)

withr::local_dir(here::here(), .local_envir = teardown_env())
suppressPackageStartupMessages(suppressWarnings({
  library(nlmixr2)
  source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim.R")
  source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_db.R")
  source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")
}))

project_number <- {{project_number}}L
version <- sprintf("v%d", project_number)
script_dir <- file.path("script/poppk-sim", version)
output_dir <- file.path("output/poppk-sim", version)
spec_dir <- "spec/poppk-sim"
spec_path <- file.path(spec_dir, paste0(version, ".yaml"))

## 1. Script directory structure ------------------------------------------------------

scripts <- sort(list.files(script_dir, pattern = "\\.R$"))

test_that("version directory has analysis, generate-spec, and at least one tbl/fig script", {
  expect_length(grep("^analysis-.*\\.R$", scripts), 1)
  expect_true("generate-spec.R" %in% scripts)
  expect_gt(length(grep("^(tbl|fig)-.*\\.R$", scripts)), 0)
})

test_that("every script refers only to this version (project_number and poppk-sim/v{n}/ paths)", {
  for (s in scripts) {
    txt <- readLines(file.path(script_dir, s), warn = FALSE)
    pn <- as.integer(unlist(regmatches(txt, gregexpr("project_number (<-|=) \\K\\d+(?=L)", txt, perl = TRUE))))
    vdirs <- as.integer(unlist(regmatches(txt, gregexpr("(?<=poppk-sim/v)\\d+(?=/)", txt, perl = TRUE))))
    expect_true(all(c(pn, vdirs) == project_number), label = s)
  }
})

test_that("every script logs to output/poppk-sim via nca_log_start()/nca_log_stop()", {
  for (s in scripts) {
    txt <- paste(readLines(file.path(script_dir, s), warn = FALSE), collapse = "\n")
    expect_match(txt, sprintf("nca_log_start\\(\"%s\",[^)]*output_dir = \"output/poppk-sim\"",
                              tools::file_path_sans_ext(s)), label = s)
    expect_match(txt, "nca_log_stop\\(\\)", label = s)
  }
})

## 2. Execution logs ---------------------------------------------------------------------

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

## 3. Spec ---------------------------------------------------------------------------------

spec <- yaml::read_yaml(spec_path)

test_that("spec file matches its sidecar hash", {
  expect_true(verify_spec(project_number, spec_dir = spec_dir))
})

test_that("spec describes this version and has its semantic fields filled in", {
  expect_identical(as.integer(spec$project_number), project_number)
  expect_identical(spec$script_dir, script_dir)
  for (field in list(spec$description, spec$report$title, spec$source$type)) {
    expect_true(is.character(field) && nzchar(field))
  }
  expect_true(spec$source$type %in% c("poppk-estimation", "model-file", "fit-file"))
  expect_gt(length(spec$scenarios), 0)
  expect_true(is.numeric(spec$simulation$seed))
})

test_that("QC status is pending or in review (not already signed off)", {
  expect_true(spec$qc$status %in% c("pending", "in_review"))
})

## 4. Provenance: scripts, database, model source --------------------------------------------

test_that("spec lists exactly the scripts on disk, with matching hashes", {
  expect_setequal(names(spec$script_hashes), scripts)
  for (s in scripts) {
    expect_identical(hash_file(file.path(script_dir, s)), spec$script_hashes[[s]], label = s)
  }
})

sim <- new.env()
db_meta <- read_sim_db(project_number, envir = sim)   # errors if the blob fails verification

test_that("database payload_hash and settings match the spec", {
  expect_identical(db_meta$payload_hash, spec$data$sim_db$payload_hash)
  expect_identical(db_meta$seed, as.integer(spec$simulation$seed))
  expect_identical(db_meta$n_sub, as.integer(spec$simulation$n_sub))
  expect_identical(db_meta$n_stud, as.integer(spec$simulation$n_stud))
})

test_that("model source is unchanged since the simulation", {
  src <- spec$source
  if (src$type == "poppk-estimation") {
    # source popPK database still verifies and still holds the simulated model
    loaded <- load_sim_model(list(type = src$type, poppk_version = src$poppk_version, run_id = src$run_id))
    expect_identical(loaded$provenance$poppk_db$payload_hash, src$poppk_db$payload_hash)
    expect_identical(loaded$provenance$model_hash, src$model_hash)
    expect_identical(hash_file(src$poppk_spec$path), src$poppk_spec$hash)   # source spec not regenerated
  } else {
    expect_true(file.exists(src$path))
    expect_identical(hash_file(src$path), src$hash)
  }
})

test_that("stored scenario events match the spec", {
  for (sc in spec$scenarios) {
    expect_identical(hash(sim$events[sim$events$scenario == sc$name, ]), sc$events_hash, label = sc$name)
  }
})

## 5. Outputs --------------------------------------------------------------------------------

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

## 6. Results: complete, plausible, and re-derivable ------------------------------------------

n_expected <- sim$settings$nSub * sim$settings$nStud

test_that("every scenario has nSub x nStud subjects and finite, non-negative concentrations", {
  expect_setequal(levels(sim$sims$scenario), vapply(spec$scenarios, `[[`, "", "name"))
  per_sc <- tapply(sim$sims$sim.id, sim$sims$scenario, function(x) length(unique(x)))
  expect_true(all(per_sc == n_expected))
  v <- sim$sims[[sim$settings$var]]
  expect_true(all(is.finite(v)) && all(v >= 0))
})

test_that("stored metrics and summaries re-derive from the stored simulations", {
  met <- exposure_metrics(sim$sims, var = sim$settings$var, windows = sim$settings$windows)
  expect_equal(met, sim$metrics)
  expect_equal(summarise_exposure(met), sim$exposure_summary)
  expect_equal(summarise_profiles(sim$sims, var = sim$settings$var), sim$profiles)
})

test_that("spec's exposure summary matches the database", {
  rec <- do.call(rbind, lapply(spec$results$exposure_summary, as.data.frame))
  db <- sim$exposure_summary
  key <- paste(db$scenario, db$metric)
  rec <- rec[match(key, paste(rec$scenario, rec$metric)), ]
  expect_equal(unname(rec$median), unname(signif(db$median, 5)))
  expect_equal(unname(rec$p05), unname(signif(db$p05, 5)))
  expect_equal(unname(rec$p95), unname(signif(db$p95, 5)))
})

test_that("re-simulating the first scenario from its recorded seed reproduces it exactly", {
  src <- spec$source
  loaded <- if (src$type == "poppk-estimation") {
    load_sim_model(list(type = src$type, poppk_version = src$poppk_version, run_id = src$run_id))
  } else load_sim_model(list(type = src$type, path = src$path))
  first <- spec$scenarios[[1]]$name
  ev <- sim$events[sim$events$scenario == first, setdiff(names(sim$events), "scenario")]
  keep <- setdiff(names(sim$sims), c("scenario", "study", "id", "sim.id", "time"))
  resim <- suppressMessages(suppressWarnings(simulate_scenarios(
    loaded$model, setNames(list(ev), first), nSub = sim$settings$nSub,
    nStud = sim$settings$nStud, seed = as.integer(spec$scenarios[[1]]$seed), keep = keep)))
  stored <- sim$sims[sim$sims$scenario == first, ]
  expect_equal(as.data.frame(resim)[keep], as.data.frame(stored)[keep])
})

## 7. Negative controls (temp copies only) -----------------------------------------------------

test_that("an edited spec file fails verify_spec()", {
  tmp <- withr::local_tempdir()
  file.copy(c(spec_path, paste0(spec_path, ".hash")), tmp)
  cat("# tampered\n", file = file.path(tmp, basename(spec_path)), append = TRUE)
  expect_error(verify_spec(project_number, spec_dir = tmp), "does not match its recorded hash")
})

test_that("a modified output file fails verify_outputs()", {
  tmp <- withr::local_tempdir()
  fig <- spec$outputs$figures[[1]]$path
  fig_copy <- file.path(tmp, basename(fig))
  file.copy(fig, fig_copy)
  write(as.raw(0), fig_copy, append = TRUE)
  tampered <- spec
  tampered$outputs$figures[[1]]$path <- fig_copy
  yaml::write_yaml(tampered, file.path(tmp, basename(spec_path)))
  expect_error(verify_outputs(project_number, spec_dir = tmp), "hash mismatch")
})

test_that("a corrupted results blob fails read_sim_db()", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, version, "db"), recursive = TRUE)
  file.copy(sim_db_path(project_number), sim_db_path(project_number, output_dir = tmp))
  con <- sim_db_connect(project_number, output_dir = tmp)
  blob <- dbGetQuery(con, "SELECT payload_blob FROM sim_meta")$payload_blob[[1]]
  blob[length(blob)] <- as.raw(bitwXor(as.integer(blob[length(blob)]), 1L))
  dbExecute(con, "UPDATE sim_meta SET payload_blob = ? WHERE project_number = ?",
            params = list(list(blob), project_number))
  dbDisconnect(con, shutdown = TRUE)
  expect_error(read_sim_db(project_number, output_dir = tmp, envir = new.env()), "failed hash verification")
})

## 8. Analysis-specific checks (add below) -------------------------------------------------------

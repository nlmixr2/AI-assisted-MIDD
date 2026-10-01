# Project-level helpers for the pk-nca / poppk analysis template.
# Source this file from the project root (the folder holding project.yaml), then:
#
#   cfg <- project_config()                    # study ID, titles, units from project.yaml
#   new_version("poppk")                        # scaffold script/poppk/v{next}/ + tests from templates
#   new_version("poppk", from = 1L)             # ... or copy an existing version as the starting point
#   run_version("poppk", 2L)                    # run analysis -> fig/tbl -> generate-spec -> QC
#   run_qc("poppk", 2L)                         # QC-readiness suite only
#   project_status()                            # every version: spec, QC status, last QC result
#   query_project_db("SELECT * FROM versions")  # SQL across every version and type: output/project.duckdb
#   update_project_db()                         # rebuild it (run_version()/run_qc() do this after every run)
#   new_tlf("nca", 3L, "fig-cmax-by-weight", title = "...")            # custom figure/table from
#                                               # the request's placeholders, same TLF shell
#
# Analysis types and their folders:
#   nca        script/nca/v{n}/        output/nca/v{n}/        spec/nca/v{n}.yaml        tests/nca/v{n}/
#   poppk      script/poppk/v{n}/      output/poppk/v{n}/      spec/poppk/v{n}.yaml      tests/poppk/v{n}/
#   poppk-sim  script/poppk-sim/v{n}/  output/poppk-sim/v{n}/  spec/poppk-sim/v{n}.yaml  tests/poppk-sim/v{n}/
#
# All paths are relative to the working directory (the project root).

pk_skills_dir <- ".posit/assistant/skills"
source(file.path(pk_skills_dir, "pk-project", "scripts", "project_db.R"))   # update_project_db(), query_project_db()

# Templates per analysis type, in run order within each group. `{{project_number}}`
# in a template is replaced by the version number when the version is scaffolded.
pk_types <- list(
  nca = list(
    templates = c(
      "pk-nca/templates/analysis-nca.R",
      "pk-nca/templates/fig-halflife-diagnostics.R",
      "pk-nca-figures/templates/fig-mean-conc.R",
      "pk-nca-figures/templates/fig-mean-conc-semilog.R",
      "pk-nca-figures/templates/fig-ind-conc.R",
      "pk-nca-figures/templates/fig-lambdaz.R",
      "pk-nca-tables/templates/tbl-pk-parameters.R",
      "pk-nca-tables/templates/tbl-conc-by-nominal-time.R",
      "pk-nca-run-spec/templates/generate-spec.R"
    ),
    qc_helpers = "pk-nca-qc-tests/scripts/qc_tests.R",
    create_qc = "create_qc_tests", run_qc = "run_qc_tests"
  ),
  poppk = list(
    templates = c(
      "poppk-estimation/templates/analysis-poppk.R",
      "poppk-estimation/templates/fig-gof.R",
      "poppk-estimation/templates/fig-individual-fits.R",
      "poppk-estimation/templates/fig-vpc.R",
      "poppk-estimation/templates/fig-eta.R",
      "poppk-estimation/templates/fig-traceplot.R",
      "poppk-estimation/templates/fig-pmx-diagnostics.R",
      "poppk-estimation/templates/fig-model-diagram.R",
      "poppk-tables/templates/tbl-parameters.R",
      "poppk-tables/templates/tbl-model-comparison.R",
      "poppk-run-spec/templates/generate-spec.R"
    ),
    qc_helpers = "poppk-qc-tests/scripts/poppk_qc_tests.R",
    create_qc = "create_poppk_qc_tests", run_qc = "run_poppk_qc_tests"
  ),
  "poppk-sim" = list(
    templates = c(
      "poppk-simulation/templates/analysis-sim.R",
      "poppk-simulation/templates/fig-sim-profiles.R",
      "poppk-simulation/templates/fig-exposure.R",
      "poppk-simulation/templates/tbl-exposure-summary.R",
      "poppk-simulation/templates/generate-spec.R"
    ),
    qc_helpers = "poppk-simulation/scripts/poppk_sim_qc_tests.R",
    create_qc = "create_sim_qc_tests", run_qc = "run_sim_qc_tests"
  )
)

check_type <- function(type) {
  if (!type %in% names(pk_types)) {
    stop("type must be one of: ", paste(names(pk_types), collapse = ", "), call. = FALSE)
  }
  pk_types[[type]]
}

#' Read project.yaml (study ID, analysis titles, units, table header text).
#'
#' @param path Path to the config file. Defaults to "project.yaml" in the project root.
#' @return A list; `cfg$study$id`, `cfg$analyses$nca$title`, `cfg$units$conc`, ...
project_config <- function(path = "project.yaml") {
  if (!file.exists(path)) {
    stop("project.yaml not found in ", normalizePath("."), " -- copy ",
         file.path(pk_skills_dir, "pk-project/assets/project-template.yaml"),
         " to project.yaml and fill it in.", call. = FALSE)
  }
  cfg <- yaml::read_yaml(path)
  required <- list(c("study", "id"), c("units", "conc"), c("units", "time"), c("units", "dose"))
  for (r in required) {
    v <- cfg[[r[1]]][[r[2]]]
    if (is.null(v) || !nzchar(v) || grepl("^<.*>$", v)) {
      stop("project.yaml: '", paste(r, collapse = "."), "' is not set", call. = FALSE)
    }
  }
  cfg
}

#' Title for an analysis type (falls back to "<type> analysis for <study id>").
analysis_title <- function(type, cfg = project_config()) {
  t <- cfg$analyses[[type]]$title
  if (is.null(t) || !nzchar(t)) sprintf("%s analysis for %s", type, cfg$study$id) else t
}

#' Existing version numbers of an analysis type.
list_versions <- function(type) {
  check_type(type)
  d <- file.path("script", type)
  if (!dir.exists(d)) return(integer(0))
  sort(as.integer(sub("^v", "", list.files(d, pattern = "^v[0-9]+$"))))
}

#' Scaffold a new version: scripts from the skill templates (or from an existing
#' version), plus its QC-readiness test suite.
#'
#' @param type "nca", "poppk", or "poppk-sim".
#' @param n Version number; defaults to the next free one.
#' @param from Optional existing version to copy instead of the templates (its
#'   version number is rewritten in project_number lines and `{type}/v{from}/` paths).
#' @return (Invisibly) the new script directory.
new_version <- function(type, n = NULL, from = NULL) {
  spec <- check_type(type)
  n <- as.integer(n %||% (max(c(0L, list_versions(type))) + 1L))
  script_dir <- file.path("script", type, sprintf("v%d", n))
  if (dir.exists(script_dir)) stop(script_dir, " already exists", call. = FALSE)
  dir.create(script_dir, recursive = TRUE)

  if (is.null(from)) {
    for (tpl in spec$templates) {
      txt <- readLines(file.path(pk_skills_dir, tpl), warn = FALSE)
      writeLines(gsub("{{project_number}}", n, txt, fixed = TRUE),
                 file.path(script_dir, basename(tpl)))
    }
  } else {
    from_dir <- file.path("script", type, sprintf("v%d", as.integer(from)))
    if (!dir.exists(from_dir)) stop(from_dir, " not found", call. = FALSE)
    for (f in list.files(from_dir, pattern = "\\.R$", full.names = TRUE)) {
      txt <- readLines(f, warn = FALSE)
      txt <- gsub(sprintf("project_number (<-|=) %dL", as.integer(from)),
                  sprintf("project_number \\1 %dL", n), txt)
      txt <- gsub(sprintf("%s/v%d/", type, as.integer(from)), sprintf("%s/v%d/", type, n), txt, fixed = TRUE)
      writeLines(txt, file.path(script_dir, basename(f)))
    }
  }

  qc_env <- new.env()
  sys.source(file.path(pk_skills_dir, spec$qc_helpers), envir = qc_env)
  suppressMessages(get(spec$create_qc, envir = qc_env)(n))

  message("Created ", script_dir, " (", length(list.files(script_dir)), " scripts) and tests/",
          type, "/v", n, "/. Edit the blocks marked EDIT, then run_version(\"", type, "\", ", n, "L).")
  invisible(script_dir)
}

#' Run a whole version in order, each script in a fresh R session:
#' analysis-*.R -> fig-*.R / tbl-*.R -> generate-spec.R -> QC suite.
#'
#' @param qc Run the QC-readiness suite at the end (default TRUE).
#' @param only Optional character vector of script names to run (e.g. "fig-vpc.R").
run_version <- function(type, n, qc = TRUE, only = NULL) {
  spec <- check_type(type)
  script_dir <- file.path("script", type, sprintf("v%d", as.integer(n)))
  files <- list.files(script_dir, pattern = "\\.R$")
  first <- grep("^analysis-", files, value = TRUE)
  last <- intersect("generate-spec.R", files)
  ordered <- c(first, sort(setdiff(files, c(first, last))), last)   # extra scripts run too, before the spec
  if (!is.null(only)) ordered <- intersect(ordered, only)

  rscript <- file.path(R.home("bin"), "Rscript")
  for (f in ordered) {
    message("-- ", file.path(script_dir, f))
    status <- system2(rscript, file.path(script_dir, f), stdout = FALSE, stderr = FALSE)
    if (!identical(status, 0L)) {
      logs <- sort(list.files(file.path("output", type, sprintf("v%d", as.integer(n)), "logs"),
                              pattern = paste0("^", tools::file_path_sans_ext(f), "-"), full.names = TRUE))
      stop(f, " failed (exit ", status, "). Latest log: ",
           if (length(logs)) tail(logs, 1) else "none", call. = FALSE)
    }
  }
  if (qc && is.null(only)) run_qc(type, n) else refresh_project_db()   # run_qc() refreshes it too
  invisible(TRUE)
}

#' Run a version's QC-readiness suite (errors if it is not ready for QC).
run_qc <- function(type, n) {
  spec <- check_type(type)
  qc_env <- new.env()
  sys.source(file.path(pk_skills_dir, spec$qc_helpers), envir = qc_env)
  res <- get(spec$run_qc, envir = qc_env)(as.integer(n))
  refresh_project_db()   # output/project.duckdb: every version and run (scripts/project_db.R)
  res
}

#' One row per version of every analysis type: spec present, QC status in the
#' spec, and the result of the latest QC-test run (from its JUnit report).
project_status <- function() {
  rows <- list()
  for (type in names(pk_types)) {
    for (n in list_versions(type)) {
      spec_path <- file.path("spec", type, sprintf("v%d.yaml", n))
      qc_status <- if (file.exists(spec_path)) yaml::read_yaml(spec_path)$qc$status else NA_character_
      reports <- sort(list.files(file.path("output", type, sprintf("v%d", n), "logs"),
                                 pattern = "^qc-tests-.*\\.xml$", full.names = TRUE))
      last_qc <- if (length(reports)) {
        xml <- paste(readLines(tail(reports, 1), warn = FALSE), collapse = " ")
        num <- function(attr) sum(as.integer(regmatches(xml, gregexpr(sprintf('(?<=<testsuite )[^>]*?%s="\\K\\d+', attr), xml, perl = TRUE))[[1]]))
        tests <- num("tests"); bad <- num("failures") + num("errors")
        sprintf("%s (%d/%d passed, %s)", if (bad == 0) "ready" else "NOT ready", tests - bad, tests,
                sub("^qc-tests-(\\d{8})T.*", "\\1", basename(tail(reports, 1))))
      } else "not run"
      rows[[length(rows) + 1]] <- data.frame(type = type, version = n, spec = file.exists(spec_path),
                                             qc_status = qc_status, last_qc = last_qc)
    }
  }
  if (length(rows) == 0) {
    message("No versions yet -- start with new_version(\"nca\") or new_version(\"poppk\").")
    return(invisible(data.frame()))
  }
  do.call(rbind, rows)
}

# How each analysis type's scripts read their database, and what the footer's
# "Source data:" line shows (used by new_tlf()).
tlf_db_blocks <- list(
  nca = list(
    code = 'source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
db_meta <- read_nca_db(project_number)   # cObsData, doseData, ncaRes, res_wide, halflife_fit
source_data <- db_meta$source_file_path',
    objects = "cObsData (participant, time, cObs[, ntime]), doseData, ncaRes (PKNCA results; ncaRes$result long), res_wide (one row per participant), halflife_fit"
  ),
  poppk = list(
    code = 'source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), fits, runs, final_run, pkData
source_data <- db_meta$source_file_path',
    objects = "fit (final nlmixr2 fit; as.data.frame(fit), fit$eta, fit$parFixedDf), fits (all runs), runs (trail summary), final_run, pkData"
  ),
  "poppk-sim" = list(
    code = 'source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim.R")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_db.R")
read_sim_db(project_number)   # sims, metrics, exposure_summary, profiles, settings, scenario_info, source_provenance
source_data <- sim_source_data(source_provenance)',
    objects = "sims (simulated rows), metrics (per-subject exposure), exposure_summary, profiles (median/PI by time), settings, scenario_info, source_provenance"
  )
)

#' Scaffold a custom figure or table into a version, from the request's placeholders.
#'
#' Writes script/{type}/v{n}/{name}.R from pk-project/templates/custom-{figure,table}.R --
#' same TLF shell as every other output (render_tlf(), "Source data:" footer), reading the
#' version's database -- and registers its description in the version's generate-spec.R so
#' the spec describes it. Fill in the EDIT block (the plot, or the ARD and formats), then
#' run_version(type, n). Only for a version still in development: adding a script to a
#' version whose spec is under review invalidates it (use new_version(type, from = n)).
#'
#' @param name Output/script name; must start with "fig-" (figure) or "tbl-" (table).
#' @param title,subtitle Placeholders from the request (subtitle may be "").
#' @param footnotes Table footnotes (character vector); `caption` is the figure caption.
#' @param description One line for the spec (defaults to the title).
new_tlf <- function(type, n, name, title, subtitle = "", footnotes = character(),
                    caption = "", description = title) {
  check_type(type)
  kind <- if (startsWith(name, "fig-")) "figure" else if (startsWith(name, "tbl-")) "table" else
    stop("name must start with 'fig-' (figure) or 'tbl-' (table)", call. = FALSE)
  script_dir <- file.path("script", type, sprintf("v%d", as.integer(n)))
  if (!dir.exists(script_dir)) stop(script_dir, " not found", call. = FALSE)
  out <- file.path(script_dir, paste0(name, ".R"))
  if (file.exists(out)) stop(out, " already exists", call. = FALSE)
  if (file.exists(file.path("spec", type, sprintf("v%d.yaml", as.integer(n))))) {
    message("Note: ", type, " v", n, " already has a spec -- re-run the whole version (run_version) ",
            "so the spec and QC include the new output; if the spec is under review, use a new version instead.")
  }
  lit <- function(x) paste(deparse(x, width.cutoff = 500L), collapse = " ")
  values <- c(
    name = name, type = type, project_number = as.integer(n),
    description = gsub("\n", " ", description),
    title = lit(title), subtitle = lit(subtitle), caption = lit(caption),
    footnotes = lit(as.character(footnotes)),
    db_block = tlf_db_blocks[[type]]$code, objects = tlf_db_blocks[[type]]$objects
  )
  txt <- readLines(file.path(pk_skills_dir, "pk-project/templates", sprintf("custom-%s.R", kind)), warn = FALSE)
  for (k in names(values)) txt <- gsub(sprintf("{{%s}}", k), values[[k]], txt, fixed = TRUE)
  writeLines(txt, out)

  # register the description in generate-spec.R's output_descriptions
  gs <- file.path(script_dir, "generate-spec.R")
  if (file.exists(gs)) {
    g <- readLines(gs, warn = FALSE)
    i <- grep("^output_descriptions <- c\\($", g)[1]
    if (!is.na(i) && !any(grepl(sprintf('^  "%s" = ', name), g))) {
      g <- append(g, sprintf('  %s = %s,', lit(name), lit(gsub("\n", " ", description))), after = i)
      writeLines(g, gs)
    }
  }
  message("Created ", out, " (", kind, "). Fill in its EDIT block, then run_version(\"", type, "\", ", n, "L).")
  invisible(out)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

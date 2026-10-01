# Create and render the popPK outputs report of one popPK version -- all tables and figures,
# the model trail and final model as recorded in the spec, source files and provenance, and
# the code, in one PDF -- as a Quarto book in output/poppk/v{n}/MAR/ built on the ISoP
# pmx-report-template (https://github.com/isop-phmx/pmx-report-template, MIT; see
# assets/LICENSE-pmx-report-template). The popPK counterpart of pk-nca-report.
# Source this file from the project root, then:
#
#   create_poppk_report(2L)   # scaffold output/poppk/v2/MAR/
#   render_poppk_report(2L)   # verify the version is unchanged since QC, then quarto render
#                             # -> output/poppk/v2/MAR/report/<file>.pdf + MAR/report-provenance.yaml
#
# The report is "decoupled": it reads the version's database, spec and display objects and
# never refits, so what is reported is exactly what passed QC.

poppk_report_skill_dir <- ".posit/assistant/skills/poppk-report"

poppk_mar_dir <- function(project_number, output_dir = "output/poppk") {
  file.path(output_dir, sprintf("v%d", as.integer(project_number)), "MAR")
}

poppk_yaml_str <- function(x) {
  x <- paste(as.character(x), collapse = ", ")
  paste0('"', gsub('"', '\\\\"', x), '"')
}

#' Scaffold the report project for popPK version `project_number`.
#'
#' Cover-page metadata come from project.yaml's `report:` block (report_number, drug_name,
#' indication, sponsor, authors, reviewers, approvers, status, company); missing or
#' placeholder (<...>) entries become "TBD" and can also be edited in MAR/_quarto.yml.
#' `report.poppk_report_number` overrides `report_number` for this report (the NCA report
#' usually has its own number).
#'
#' @param overwrite If FALSE (default), refuse to replace an existing MAR/.
#' @return (Invisibly) the MAR directory.
create_poppk_report <- function(project_number, overwrite = FALSE) {
  pn <- as.integer(project_number)
  source(".posit/assistant/skills/pk-project/scripts/project.R", local = TRUE)
  cfg <- project_config()
  if (!file.exists(file.path("spec/poppk", sprintf("v%d.yaml", pn)))) {
    stop("spec/poppk/v", pn, ".yaml not found -- run the popPK version (run_version(\"poppk\", ", pn,
         "L)) before creating its report.", call. = FALSE)
  }
  dest <- poppk_mar_dir(pn)
  if (dir.exists(dest) && !overwrite) {
    stop(dest, " already exists (it may hold edits to this report) -- pass overwrite = TRUE to replace it.",
         call. = FALSE)
  }
  src <- file.path(poppk_report_skill_dir, "assets", "mar-template")
  files <- list.files(src, recursive = TRUE, all.files = TRUE)
  rep <- cfg$report %||% list()
  tbd <- function(x) if (is.null(x) || !length(x) || !nzchar(paste(x, collapse = "")) || grepl("^<.*>$", paste(x, collapse = ""))) "TBD" else x
  title <- sprintf("%s -- popPK v%d", analysis_title("poppk", cfg), pn)
  company <- tbd(rep$company)
  values <- c(
    project_number = pn,
    version_label = sprintf("popPK v%d", pn),
    book_title = poppk_yaml_str(title),
    output_file = sprintf("poppk-v%d-report", pn),
    report_number = poppk_yaml_str(tbd(rep$poppk_report_number %||% rep$report_number)),
    report_title = poppk_yaml_str(tbd(rep$poppk_title %||% title)),
    drug_name = poppk_yaml_str(tbd(rep$drug_name)),
    indication = poppk_yaml_str(tbd(rep$indication)),
    study_number = poppk_yaml_str(rep$study_number %||% cfg$study$id),
    sponsor = poppk_yaml_str(tbd(rep$sponsor)),
    author = poppk_yaml_str(tbd(rep$authors)),
    review = poppk_yaml_str(tbd(rep$reviewers)),
    approve = poppk_yaml_str(tbd(rep$approvers)),
    status = poppk_yaml_str(if (identical(tbd(rep$status), "TBD")) "DRAFT" else rep$status),
    copyright = poppk_yaml_str(sprintf(paste(
      "This is a %s document that contains confidential information. It is intended solely",
      "for the recipient and must not be disclosed to any other party. This material may be",
      "used only for evaluating or conducting clinical investigations; any other proposed use",
      "requires written consent from %s."), company, company))
  )
  for (f in files) {
    out <- file.path(dest, f)
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    if (grepl("\\.(qmd|yml|R)$", f)) {
      txt <- readLines(file.path(src, f), warn = FALSE)
      for (k in names(values)) txt <- gsub(sprintf("{{%s}}", k), values[[k]], txt, fixed = TRUE)
      writeLines(txt, out)
    } else {
      file.copy(file.path(src, f), out, overwrite = TRUE)
    }
  }
  message("Created ", dest, ". Check the cover metadata in _quarto.yml, then render_poppk_report(", pn, "L).")
  invisible(dest)
}

#' Verify the popPK version and render its report.
#'
#' Refuses to render unless: the spec matches its sidecar hash, every output matches its
#' recorded hash, and (if `require_qc`) the latest QC-suite run for the version passed.
#' Writes MAR/report-provenance.yaml recording what the PDF was built from.
#'
#' @return (Invisibly) the path of the rendered PDF.
render_poppk_report <- function(project_number, require_qc = TRUE, quarto = Sys.which("quarto")) {
  pn <- as.integer(project_number)
  dest <- poppk_mar_dir(pn)
  if (!dir.exists(dest)) stop(dest, " not found -- run create_poppk_report(", pn, "L) first.", call. = FALSE)
  if (!nzchar(quarto)) stop("Quarto CLI not found on PATH (https://quarto.org).", call. = FALSE)

  e <- new.env()
  sys.source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R", envir = e)
  sys.source(".posit/assistant/skills/pk-nca-report/scripts/nca_report_helpers.R", envir = e)
  e$verify_spec(pn, spec_dir = "spec/poppk")       # errors if the spec was edited
  e$verify_outputs(pn, spec_dir = "spec/poppk")    # errors if a table/figure changed since the spec
  qc <- e$latest_qc_result(pn, output_dir = "output/poppk")
  if (require_qc && (is.na(qc$tests) || qc$failed > 0)) {
    stop("popPK v", pn, " has no passing QC run (", if (is.na(qc$tests)) "never run" else
         sprintf("%d of %d checks failed", qc$failed, qc$tests),
         ") -- run run_qc(\"poppk\", ", pn, "L) first, or pass require_qc = FALSE for a draft.", call. = FALSE)
  }

  status <- system2(quarto, c("render", shQuote(dest)))
  if (!identical(status, 0L)) stop("quarto render failed (exit ", status, ")", call. = FALSE)
  pdf <- list.files(file.path(dest, "report"), pattern = "\\.pdf$", full.names = TRUE)
  pdf <- pdf[which.max(file.mtime(pdf))]

  spec_path <- file.path("spec/poppk", sprintf("v%d.yaml", pn))
  spec <- yaml::read_yaml(spec_path)
  yaml::write_yaml(list(
    rendered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    pdf = pdf, pdf_hash = rlang::hash_file(pdf),
    poppk_version = pn,
    spec = list(path = spec_path, hash = rlang::hash_file(spec_path), qc_status = spec$qc$status),
    poppk_db = list(path = spec$data$poppk_db$path, payload_hash = spec$data$poppk_db$payload_hash),
    final_model = list(run_id = spec$final_model$run_id, objf = spec$final_model$objf),
    qc_run = list(report = qc$file, tests = qc$tests, failed = qc$failed),
    quarto = system2(quarto, "--version", stdout = TRUE)
  ), file.path(dest, "report-provenance.yaml"))
  message("Rendered ", pdf)
  invisible(pdf)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

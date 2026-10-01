# Create and render the NCA outputs report of one NCA version -- all tables and figures,
# source files and provenance, and the code, in one PDF -- as a Quarto book in
# output/nca/v{n}/MAR/ built on the ISoP pmx-report-template
# (https://github.com/isop-phmx/pmx-report-template, MIT; see assets/LICENSE-pmx-report-template).
# Source this file from the project root, then:
#
#   create_nca_report(1L)   # scaffold output/nca/v1/MAR/ (_quarto.yml, index.qmd, sections/, engine/, ...)
#   render_nca_report(1L)   # verify the version is unchanged since QC, then quarto render
#                           # -> output/nca/v1/MAR/report/<file>.pdf + MAR/report-provenance.yaml
#
# The report is "decoupled": it reads the version's database, spec and figures and never
# re-runs PKNCA, so what is reported is exactly what passed QC.

nca_report_skill_dir <- ".posit/assistant/skills/pk-nca-report"

mar_dir <- function(project_number, output_dir = "output/nca") {
  file.path(output_dir, sprintf("v%d", as.integer(project_number)), "MAR")
}

yaml_str <- function(x) {
  x <- paste(as.character(x), collapse = ", ")
  paste0('"', gsub('"', '\\\\"', x), '"')
}

#' Scaffold the report project for NCA version `project_number`.
#'
#' Cover-page metadata come from project.yaml's `report:` block (report_number,
#' drug_name, indication, sponsor, authors, reviewers, approvers, status, company);
#' missing or placeholder (<...>) entries become "TBD" and can also be edited in MAR/_quarto.yml.
#'
#' @param overwrite If FALSE (default), refuse to replace an existing MAR/ (it may hold
#'   edits to this report's cover metadata or chapters).
#' @return (Invisibly) the MAR directory.
create_nca_report <- function(project_number, overwrite = FALSE) {
  pn <- as.integer(project_number)
  source(".posit/assistant/skills/pk-project/scripts/project.R", local = TRUE)
  cfg <- project_config()
  if (!file.exists(file.path("spec/nca", sprintf("v%d.yaml", pn)))) {
    stop("spec/nca/v", pn, ".yaml not found -- run the NCA version (run_version(\"nca\", ", pn,
         "L)) before creating its report.", call. = FALSE)
  }
  dest <- mar_dir(pn)
  if (dir.exists(dest) && !overwrite) {
    stop(dest, " already exists (it may hold edits to this report) -- pass overwrite = TRUE to replace it.",
         call. = FALSE)
  }
  src <- file.path(nca_report_skill_dir, "assets", "mar-template")
  files <- list.files(src, recursive = TRUE, all.files = TRUE)
  rep <- cfg$report %||% list()
  tbd <- function(x) if (is.null(x) || !length(x) || !nzchar(paste(x, collapse = "")) || grepl("^<.*>$", paste(x, collapse = ""))) "TBD" else x
  title <- sprintf("%s -- NCA v%d", analysis_title("nca", cfg), pn)
  company <- tbd(rep$company)
  values <- c(
    project_number = pn,
    version_label = sprintf("NCA v%d", pn),
    book_title = yaml_str(title),
    output_file = sprintf("nca-v%d-report", pn),
    report_number = yaml_str(tbd(rep$report_number)),
    report_title = yaml_str(tbd(rep$title %||% title)),
    drug_name = yaml_str(tbd(rep$drug_name)),
    indication = yaml_str(tbd(rep$indication)),
    study_number = yaml_str(rep$study_number %||% cfg$study$id),
    sponsor = yaml_str(tbd(rep$sponsor)),
    author = yaml_str(tbd(rep$authors)),
    review = yaml_str(tbd(rep$reviewers)),
    approve = yaml_str(tbd(rep$approvers)),
    status = yaml_str(if (identical(tbd(rep$status), "TBD")) "DRAFT" else rep$status),   # missing or <...> -> DRAFT
    copyright = yaml_str(sprintf(paste(
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
  message("Created ", dest, ". Check the cover metadata in _quarto.yml, then render_nca_report(", pn, "L).")
  invisible(dest)
}

#' Verify the NCA version and render its report.
#'
#' Refuses to render unless: the spec matches its sidecar hash, every output matches its
#' recorded hash, and (if `require_qc`) the latest QC-suite run for the version passed.
#' Writes MAR/report-provenance.yaml recording what the PDF was built from.
#'
#' @return (Invisibly) the path of the rendered PDF.
render_nca_report <- function(project_number, require_qc = TRUE, quarto = Sys.which("quarto")) {
  pn <- as.integer(project_number)
  dest <- mar_dir(pn)
  if (!dir.exists(dest)) stop(dest, " not found -- run create_nca_report(", pn, "L) first.", call. = FALSE)
  if (!nzchar(quarto)) stop("Quarto CLI not found on PATH (https://quarto.org).", call. = FALSE)

  e <- new.env()
  sys.source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R", envir = e)
  sys.source(file.path(nca_report_skill_dir, "scripts", "nca_report_helpers.R"), envir = e)
  e$verify_spec(pn)       # errors if the spec was edited
  e$verify_outputs(pn)    # errors if a table/figure changed since the spec
  qc <- e$latest_qc_result(pn)
  if (require_qc && (is.na(qc$tests) || qc$failed > 0)) {
    stop("NCA v", pn, " has no passing QC run (", if (is.na(qc$tests)) "never run" else
         sprintf("%d of %d checks failed", qc$failed, qc$tests),
         ") -- run run_qc(\"nca\", ", pn, "L) first, or pass require_qc = FALSE for a draft.", call. = FALSE)
  }

  status <- system2(quarto, c("render", shQuote(dest)))
  if (!identical(status, 0L)) stop("quarto render failed (exit ", status, ")", call. = FALSE)
  pdf <- list.files(file.path(dest, "report"), pattern = "\\.pdf$", full.names = TRUE)
  pdf <- pdf[which.max(file.mtime(pdf))]

  spec_path <- file.path("spec/nca", sprintf("v%d.yaml", pn))
  spec <- yaml::read_yaml(spec_path)
  yaml::write_yaml(list(
    rendered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    pdf = pdf, pdf_hash = rlang::hash_file(pdf),
    nca_version = pn,
    spec = list(path = spec_path, hash = rlang::hash_file(spec_path), qc_status = spec$qc$status),
    nca_db = list(path = spec$data$nca_db$path, payload_hash = spec$data$nca_db$payload_hash),
    qc_run = list(report = qc$file, tests = qc$tests, failed = qc$failed),
    quarto = system2(quarto, "--version", stdout = TRUE)
  ), file.path(dest, "report-provenance.yaml"))
  message("Rendered ", pdf)
  invisible(pdf)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

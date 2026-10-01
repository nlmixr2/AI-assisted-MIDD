# Helpers used inside the NCA report (output/nca/v{n}/MAR/*.qmd) to turn one QC'd
# NCA version into report content. Loaded by MAR/_setup.R; everything is read from the
# version's database (read_nca_db()), spec, and output files -- nothing is recomputed
# with PKNCA, so the report stays tied to the QC'd results ("decoupled" report).

library(dplyr)
library(tidyr)

#' Display names for PKNCA parameter codes (fallback: the code itself).
nca_param_names <- c(
  cmax = "Cmax", tmax = "Tmax", half.life = "Half-life", aucinf.obs = "AUCinf",
  aucinf.pred = "AUCinf,pred", auclast = "AUClast", clast.obs = "Clast", cl.obs = "CL/F",
  cl.pred = "CL/F,pred", vz.obs = "Vz/F", lambda.z = "Lambda z", ctrough = "Ctrough",
  cav = "Cav", cmin = "Cmin", tlast = "Tlast", mrt.obs = "MRT"
)

param_label <- function(code, unit = NA_character_) {
  unit <- rep_len(unit, length(code))
  nm <- ifelse(code %in% names(nca_param_names), nca_param_names[code], code)
  ifelse(is.na(unit) | unit %in% c("", "unitless"), nm, sprintf("%s (%s)", nm, unit))
}

#' Format to `digits` significant figures, keeping trailing zeros (15.0) and no trailing point.
sig <- function(x, digits = 3) {
  out <- rep(NA_character_, length(x))
  out[is.finite(x) & x == 0] <- "0"
  ok <- is.finite(x) & x != 0
  d <- pmax(0, digits - 1 - floor(log10(pmax(abs(x[ok]), 1e-12))))
  out[ok] <- mapply(function(v, n) formatC(v, format = "f", digits = n), signif(x[ok], digits), d)
  out
}

#' The gt object(s) a pk-nca-tables script rendered into its QC'd PDF.
#'
#' docorator saves the exact display object behind each output PDF as <name>.RDS. Reusing it
#' makes the report's tables and figures identical to the QC'd ones. The .RDS is checked
#' against the hash the spec records (outputs.*[].display_rds, written by generate-spec.R);
#' specs written before that field existed fall back to requiring the .RDS to come from the
#' same run as the PDF.
nca_table_display <- function(name, spec, root) nca_output_display(name, spec, root, "tables")

#' The display object(s) behind a QC'd output: "tables" (gt) or "figures" (ggplot, or a
#' list of ggplots for one-page-per-participant figures). Verified as for tables.
nca_output_display <- function(name, spec, root, kind = c("tables", "figures")) {
  kind <- match.arg(kind)
  entries <- Filter(function(e) identical(tools::file_path_sans_ext(basename(e$path)), name),
                    spec$outputs[[kind]])
  entry <- Find(function(e) !is.null(e$display_rds), entries) %||%
    Find(function(e) grepl("\\.(pdf|rtf)$", e$path), entries)
  if (is.null(entry)) stop("'", name, "' is not recorded as a docorator output in the spec's outputs.", kind,
                           call. = FALSE)
  pdf <- file.path(root, entry$path)
  rds <- file.path(root, entry$display_rds$path %||% paste0(tools::file_path_sans_ext(entry$path), ".RDS"))
  if (!file.exists(rds)) stop("Display object not found: ", rds, call. = FALSE)
  if (!is.null(entry$display_rds)) {
    if (!identical(rlang::hash_file(rds), entry$display_rds$hash)) {
      stop(rds, " does not match the hash recorded in the spec -- it changed after QC", call. = FALSE)
    }
  } else if (abs(as.numeric(difftime(file.mtime(rds), file.mtime(pdf), units = "secs"))) > 120) {
    stop(rds, " was not written in the same run as ", entry$path, " (spec predates display_rds hashes)",
         call. = FALSE)
  }
  readRDS(rds)$display
}

#' Write the i-th image of a QC'd docorator figure to a PNG file, pixel-identical to the
#' image placed in the QC'd PDF (docorator stores figures as rendered pixel arrays).
#'
#' @param display Figure display object from nca_output_display(): a docorator "PNG" object,
#'   or a list of them (one per page).
#' @return (Invisibly) `file`.
write_display_png <- function(display, file, i = 1) {
  img <- if (inherits(display, "PNG")) display else display[[i]]
  if (!inherits(img, "PNG")) stop("Expected a docorator PNG display object", call. = FALSE)
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  png::writePNG(img$png, file)
  invisible(file)
}

#' Is an output (by name) recorded in the spec? Lets report chapters include figures/tables
#' that only newer versions produce.
has_output <- function(name, spec) {
  paths <- c(vapply(spec$outputs$tables, `[[`, "", "path"), vapply(spec$outputs$figures, `[[`, "", "path"))
  name %in% tools::file_path_sans_ext(basename(paths))
}

## Legacy: used only by reports scaffolded from the earlier narrative template (e.g. the
## examples/abc-111 NCA v1/v3 MARs). The current template has no narrative text. ----------

#' One formatted cell of a pk-nca-tables table (as printed in the QC'd PDF).
#'
#' @param display gt_tbl from nca_table_display().
#' @param row Row label: a participant ID, "N", "Mean", "Median", or "Min, Max".
#' @param param Display name of the parameter column without its unit, e.g. "Cmax".
#' @return list(value = trimmed cell text, unit = unit from the column header).
table_cell <- function(display, row, param) {
  d <- display[["_data"]]
  cols <- names(d)[startsWith(names(d), paste0(param, " (")) | names(d) == param]
  if (!length(cols) || !row %in% d$row_id) return(list(value = NA_character_, unit = NA_character_))
  v <- trimws(gsub("\\s+", " ", d[[cols[1]]][d$row_id == row]))
  list(value = v, unit = sub("^.*\\((.*)\\)$", "\\1", if (grepl("\\(", cols[1])) cols[1] else "()"))
}

#' "mean (median; min, max) unit" for one parameter, quoting the table's own cells.
table_summary_phrase <- function(display, param) {
  mean <- table_cell(display, "Mean", param)
  if (is.na(mean$value)) return(NA_character_)
  med <- table_cell(display, "Median", param)$value
  rng <- gsub("^\\(\\s*|\\s*\\)$", "", table_cell(display, "Min, Max", param)$value)
  rng <- gsub(",\\s*", " to ", rng)
  md_escape(sprintf("%s %s (median %s, range %s)", mean$value, mean$unit, med, rng))
}

#' Escape Markdown emphasis characters in text quoted inline (units like h*mg/L).
md_escape <- function(x) gsub("([*_])", "\\\\\\1", x)

#' Print table display object(s) into the LaTeX report, unchanged in content.
#'
#' gt's LaTeX is a floating table with an unnumbered caption (the table's title and
#' subtitle). To keep it under its heading and in the List of Tables, the float is pinned
#' ([H]) and the first page's caption becomes the numbered caption (short entry = the gt
#' title), labelled `label` for cross-references (`Table\ \ref{<label>}` in the text).
#' Later pages of a paginated table keep an unnumbered "(continued)" caption.
print_table_display <- function(display, label) {
  gts <- if (inherits(display, "gt_tbl")) list(display) else display
  parts <- vapply(seq_along(gts), function(i) {
    g <- gts[[i]]
    tex <- as.character(gt::as_latex(g))
    # pin the float: gt emits \begin{table} with or without a placement option ([t], [!h], ...)
    tex <- sub("\\\\begin\\{table\\}(\\[[^]]*\\])?", "\\\\begin{table}[H]", tex)
    title <- gsub("[{}\\\\]", "", as.character(g[["_heading"]]$title %||% ""))
    if (i == 1) {
      tex <- sub("\\caption*{", sprintf("\\caption[%s]{", title), tex, fixed = TRUE)
      tex <- sub("\\end{table}", sprintf("\\label{%s}\n\\end{table}", label), tex, fixed = TRUE)
    } else {
      tex <- sub("\\caption*{", sprintf("\\caption*{\\textit{(continued)} "), tex, fixed = TRUE)
    }
    tex
  }, character(1))
  knitr::asis_output(paste(parts, collapse = "\n\n"))
}

#' Lambda-z regression table (all participants), flag column for span ratio < 2.
nca_lambdaz_table <- function(halflife_fit, span_min = 2, hl_unit = NULL) {
  halflife_fit |>
    arrange(as.numeric(as.character(participant))) |>
    transmute(
      `Participant ID` = participant,
      `Points (n)` = as.integer(lambda.z.n.points),
      `Adj. R²` = formatC(adj.r.squared, format = "f", digits = 3),
      `Span ratio` = formatC(span.ratio, format = "f", digits = 2),
      Half = sig(half.life),
      Flag = if_else(span.ratio < span_min, sprintf("span ratio < %g", span_min), "")
    ) |>
    rename_with(~ param_label("half.life", hl_unit %||% NA_character_), "Half")
}

#' Dataset summary numbers for the Data chapter.
nca_data_summary <- function(cObsData, doseData) {
  list(
    n_subjects = length(unique(cObsData$participant)),
    n_obs = nrow(cObsData),
    n_obs_zero = sum(cObsData$cObs == 0),
    n_doses = nrow(doseData),
    doses = sort(unique(doseData$dose)),
    routes = unique(doseData$route),
    time_range = range(cObsData$time)
  )
}

#' Result of the latest QC-suite run for this version (from its JUnit report).
latest_qc_result <- function(nca_version, output_dir = "output/nca") {
  reports <- sort(list.files(file.path(output_dir, sprintf("v%d", nca_version), "logs"),
                             pattern = "^qc-tests-.*\\.xml$", full.names = TRUE))
  if (!length(reports)) return(list(file = NA_character_, tests = NA_integer_, failed = NA_integer_))
  xml <- paste(readLines(tail(reports, 1), warn = FALSE), collapse = " ")
  num <- function(attr) sum(as.integer(regmatches(xml, gregexpr(
    sprintf('(?<=<testsuite )[^>]*?%s="\\K\\d+', attr), xml, perl = TRUE))[[1]]))
  list(file = tail(reports, 1), tests = num("tests"), failed = num("failures") + num("errors"))
}

#' Knit a data frame as a Markdown (pipe) table. Quarto adds the caption and number
#' from the chunk's `tbl-cap` and typesets it as a non-floating table, so it stays under its
#' heading (raw LaTeX tables from knitr ignore tbl-pos and float away).
report_table <- function(df, align = NULL) {
  knitr::kable(df, format = "pipe", align = align %||% c("l", rep("r", ncol(df) - 1)))
}

#' Output name (file name without extension) of a spec outputs entry.
output_name <- function(entry) tools::file_path_sans_ext(basename(entry$path))

#' Scripts in the order run_version() runs them: analysis, figures and tables, provenance record.
script_run_order <- function(files) {
  rank <- ifelse(startsWith(files, "analysis-"), 1L,
          ifelse(startsWith(files, "fig-") | startsWith(files, "tbl-"), 2L,
          ifelse(startsWith(files, "generate-spec"), 3L, 4L)))
  files[order(rank, files)]
}

#' Latest run log of each script, with the status from its run summary (pk-nca-logging).
run_log_table <- function(scripts, logs_dir) {
  rows <- lapply(script_run_order(scripts), function(s) {
    name <- tools::file_path_sans_ext(s)
    logs <- sort(list.files(logs_dir, pattern = sprintf("^%s-\\d{8}T\\d{6}\\.log$", name)))
    if (!length(logs)) return(tibble::tibble(Script = s, Log = "none", Status = "no log"))
    txt <- readLines(file.path(logs_dir, tail(logs, 1)), warn = FALSE)
    status <- sub("^# status: ", "", grep("^# status: ", txt, value = TRUE))
    if (!length(status)) {
      status <- if (any(grepl("^# sessionInfo\\(\\):", txt))) "completed (older log format)" else "incomplete"
    }
    tibble::tibble(Script = s, Log = tail(logs, 1), Status = status[1])
  })
  dplyr::bind_rows(rows)
}

#' Latest pk-data-validation HTML report of the version, with its hash, or a note if none.
data_validation_report <- function(logs_dir) {
  f <- sort(list.files(logs_dir, pattern = "^data-validation-.*\\.html$", full.names = TRUE))
  if (!length(f)) return("none (the version predates pk-data-validation)")
  sprintf("%s (hash %s)", basename(tail(f, 1)), rlang::hash_file(tail(f, 1)))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

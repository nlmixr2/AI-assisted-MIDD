# Inspect and validate a PK analysis dataset before NCA or popPK (pk-data-validation skill).
#
#   source(".posit/assistant/skills/pk-data-validation/scripts/pk_data_checks.R")
#   describe_pk_data(pkData)                      # facts to map columns from; nothing assumed
#   validate_pk_data(pkData, layout = "event",    # pointblank checks; stops on any failure
#                    cols = pk_cols(), report_dir = "output/nca/v1/logs")
#
# Requires: pointblank, dplyr. Both functions work on a plain data frame read from a file
# under data/ (read_csv(..., lazy = FALSE) |> as.data.frame(), so its hash is stable).

#' Column mapping for validate_pk_data(). Names are roles, values are the dataset's columns.
#' Set a role to NA when the dataset has no such column (e.g. cmt = NA).
#'
#' layout "event" (NONMEM/rxode2 records: dose and observation rows told apart by EVID) uses
#' id, time, dv, amt, evid and optionally cmt, mdv. layout "sample" (one row per sample, dose
#' in a column, no EVID) uses id, time, dv, dose.
pk_cols <- function(id = "ID", time = "TIME", dv = "DV", amt = "AMT", evid = "EVID",
                    cmt = "CMT", mdv = NA, dose = NA) {
  list(id = id, time = time, dv = dv, amt = amt, evid = evid, cmt = cmt, mdv = mdv, dose = dose)
}

#' Print the facts needed to map a dataset: columns (type, missing, distinct values),
#' subjects, record-type counts, time range, and columns that look like nominal time,
#' BLQ flags or LLOQ. Returns the column table invisibly. Makes no assumption about names.
describe_pk_data <- function(data, path = NULL) {
  stopifnot(is.data.frame(data))
  if (!is.null(path)) cat("File:", path, "\n")
  cat(sprintf("Rows: %d   Columns: %d\n\n", nrow(data), ncol(data)))

  col_tbl <- data.frame(
    column   = names(data),
    type     = vapply(data, \(x) class(x)[1], character(1)),
    n_na     = vapply(data, \(x) sum(is.na(x)), integer(1)),
    n_unique = vapply(data, \(x) length(unique(x)), integer(1)),
    example  = vapply(data, \(x) paste(utils::head(unique(x), 4), collapse = ", "), character(1)),
    row.names = NULL
  )
  print(col_tbl, right = FALSE)

  nm <- toupper(names(data))
  pick <- function(candidates) names(data)[match(candidates, nm, nomatch = 0)][1]
  id_col <- pick(c("ID", "USUBJID", "SUBJID", "SUBJECT"))
  if (!is.na(id_col)) cat(sprintf("\nSubjects (%s): %d\n", id_col, length(unique(data[[id_col]]))))

  count_by <- function(roles) {
    cols <- names(data)[match(roles, nm, nomatch = 0)]
    if (!length(cols)) return(invisible())
    cat("\nRecord counts by", paste(cols, collapse = " x "), ":\n")
    print(as.data.frame(dplyr::count(data, dplyr::across(dplyr::all_of(cols)))), row.names = FALSE)
  }
  count_by(c("EVID", "CMT"))   # which rows are doses / observations, into which compartment
  for (role in c("MDV", "DVID", "CENS", "BLQ")) count_by(role)

  time_col <- pick(c("TIME", "TAFD", "AFRLT", "ARRLT", "TAD"))
  if (!is.na(time_col) && is.numeric(data[[time_col]])) {
    cat(sprintf("\nTime (%s): %s to %s\n", time_col,
                format(min(data[[time_col]], na.rm = TRUE)), format(max(data[[time_col]], na.rm = TRUE))))
  }

  # Name-based hints, for non-standard names (e.g. WinNonlin WNLACTM / WNLNTM). A hint is
  # only a lead: confirm it against the values above, and with the user, before mapping.
  hints <- list(
    "subject"            = "^(ID|USUBJID|SUBJID|SUBJECT|SUBJ|PATID|PTID)$",
    "time (actual or nominal: check which)" = "TIME|TM$|ACTM|NTM|TPT|FRLT|RRLT|TAFD|^TAD$",
    "concentration / DV" = "CONC|^DV$|STRESN|^AVAL$|RESULT",
    "dose"               = "DOSE|^AMT$",
    "BLQ / LLOQ"         = "BLQ|BQL|LOQ|CENS|LIMIT",
    "group / analyte"    = "ARM|TRT|COHORT|GROUP|PERIOD|ANALYTE|TESTCD|PARAM"
  )
  cat("\nName-based hints (confirm before mapping):\n")
  for (role in names(hints)) {
    cols <- names(data)[grepl(hints[[role]], nm)]
    cat(sprintf("  %-38s %s\n", paste0(role, ":"), if (length(cols)) paste(cols, collapse = ", ") else "-"))
  }

  cat("\nNot in the file (ask the user or read project.yaml): units, route, whether dose",
      "is per kg, dosing time if there are no dose rows.\n")
  invisible(col_tbl)
}

#' Validate a PK dataset with pointblank. Every check must pass: on any failure it prints
#' the failing checks and stops, so the analysis never runs on data it has not confirmed.
#'
#' @param layout "event" (EVID-coded records) or "sample" (one row per sample, no EVID).
#' @param cols Column mapping from pk_cols().
#' @param covariates Covariate columns that must be present on every row (popPK models).
#' @param report_dir Folder for the HTML report (the version's logs/ folder); NULL for none.
#' @param label Report title, e.g. the data file name.
#' @return The interrogated pointblank agent, invisibly.
validate_pk_data <- function(data, layout = c("event", "sample"), cols = pk_cols(),
                             covariates = character(), report_dir = NULL, label = NULL) {
  layout <- match.arg(layout)
  stopifnot(is.data.frame(data))

  required <- switch(layout,
    event  = c("id", "time", "dv", "amt", "evid"),
    sample = c("id", "time", "dv", "dose")
  )
  unset <- required[vapply(cols[required], \(x) is.null(x) || is.na(x), logical(1))]
  if (length(unset)) {
    stop("Layout '", layout, "' needs a column for: ", paste(unset, collapse = ", "),
         ". Set it in pk_cols().", call. = FALSE)
  }
  mapped <- unlist(cols[!vapply(cols, \(x) is.null(x) || is.na(x), logical(1))])
  # Only the roles this layout uses must exist; unused defaults (e.g. amt for "sample") are ignored.
  optional <- if (layout == "event") c("cmt", "mdv") else character()
  used <- mapped[names(mapped) %in% c(required, optional)]
  missing_cols <- setdiff(c(used, covariates), names(data))
  if (length(missing_cols)) {
    stop("Columns not found: ", paste(missing_cols, collapse = ", "),
         ". The data has: ", paste(names(data), collapse = ", "),
         ". Fix the mapping in pk_cols() (run describe_pk_data() to see the columns).", call. = FALSE)
  }

  # Mapping errors above need no pointblank, so they are reported even where it is missing.
  if (!requireNamespace("pointblank", quietly = TRUE)) {
    stop("Package 'pointblank' is required: install.packages(\"pointblank\")", call. = FALSE)
  }
  agent <- pointblank::create_agent(tbl = data, tbl_name = label %||% "pk data",
                                    label = paste("PK data validation:", label %||% "", "-", layout))
  agent <- if (layout == "event") .pk_event_checks(agent, cols) else .pk_sample_checks(agent, cols)
  if (length(covariates)) {
    agent <- pointblank::col_vals_not_null(agent, columns = covariates,
                                           label = "Covariates present on every row")
  }
  agent <- pointblank::interrogate(agent)

  if (!is.null(report_dir)) {
    dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
    report <- file.path(report_dir, sprintf("data-validation-%s.html", format(Sys.time(), "%Y%m%dT%H%M%S")))
    pointblank::export_report(agent, filename = report)
    message("Data validation report: ", report)
  }

  x <- pointblank::get_agent_x_list(agent)
  labels <- agent$validation_set$label
  if (is.null(labels) || all(is.na(labels))) labels <- x$briefs
  failed <- which(is.na(x$n_failed) | x$n_failed > 0 | x$eval_error)
  cat(sprintf("Data validation: %d checks, %d failed\n", length(x$n_failed), length(failed)))
  if (length(failed)) {
    detail <- sprintf("  - step %d: %s (%s failing rows%s)", failed, labels[failed],
                      x$n_failed[failed], ifelse(x$eval_error[failed], ", evaluation error", ""))
    stop("Data validation failed:\n", paste(detail, collapse = "\n"),
         "\nFix the data or the mapping; do not drop or weaken a check without the user's agreement.",
         call. = FALSE)
  }
  invisible(agent)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# EVID-coded records: observations are EVID == 0 (and MDV == 0 when mapped), doses are
# EVID != 0 with AMT > 0. Dose EVID codes differ (1, 4, 101, ...), so none is assumed.
.pk_event_checks <- function(agent, cols) {
  id <- cols$id; time <- cols$time; dv <- cols$dv; amt <- cols$amt; evid <- cols$evid
  mdv <- cols$mdv; cmt <- cols$cmt

  is_obs  <- function(x) x[[evid]] == 0 & (if (is.na(mdv)) TRUE else x[[mdv]] %in% 0)
  is_dose <- function(x) x[[evid]] != 0 & !is.na(x[[amt]]) & x[[amt]] > 0
  obs_rows <- function(x) x[is_obs(x), , drop = FALSE]
  evid0_rows <- function(x) x[x[[evid]] == 0, , drop = FALSE]
  # Per-subject record counts (one row per subject) for the "every subject has ..." checks.
  per_subject <- function(x) {
    data.frame(id = x[[id]], dose = is_dose(x), obs = is_obs(x)) |>
      dplyr::group_by(id) |>
      dplyr::summarise(n_dose = sum(dose), n_obs = sum(obs), .groups = "drop")
  }
  # Time step from the previous record of the same subject, in file order (first record: 0).
  time_steps <- function(x) {
    x |>
      dplyr::group_by(.pk_id = .data[[id]]) |>
      dplyr::mutate(.dt = .data[[time]] - dplyr::lag(.data[[time]], default = dplyr::first(.data[[time]]))) |>
      dplyr::ungroup()
  }

  agent |>
    pointblank::col_is_numeric(columns = c(time, dv, amt, evid), label = "Numeric TIME, DV, AMT, EVID") |>
    pointblank::col_vals_not_null(columns = c(id, time, evid), label = "No missing ID, TIME, EVID") |>
    pointblank::col_vals_gte(columns = time, value = 0, label = "TIME >= 0") |>
    pointblank::col_vals_gte(columns = ".dt", value = 0, preconditions = time_steps,
                             label = "TIME non-decreasing within each subject (file order)") |>
    pointblank::col_vals_not_null(columns = dv, preconditions = obs_rows,
                                  label = "Observation rows have DV") |>
    pointblank::col_vals_gte(columns = dv, value = 0, na_pass = TRUE, preconditions = obs_rows,
                             label = "Observation DV >= 0") |>
    pointblank::col_vals_lte(columns = amt, value = 0, na_pass = TRUE, preconditions = evid0_rows,
                             label = "No dose amount on EVID 0 rows (AMT 0 or missing)") |>
    pointblank::col_vals_gt(columns = "n_dose", value = 0, preconditions = per_subject,
                            label = "Every subject has a dose record (EVID != 0, AMT > 0)") |>
    pointblank::col_vals_gt(columns = "n_obs", value = 0, preconditions = per_subject,
                            label = "Every subject has an observation") |>
    pointblank::rows_distinct(columns = if (is.na(cmt)) c(id, time, evid) else c(id, time, evid, cmt),
                              label = "No duplicate records (ID, TIME, EVID[, CMT])")
}

# One row per sample, dose in a column, no EVID (e.g. theophylline: Subject/Time/conc/Dose).
.pk_sample_checks <- function(agent, cols) {
  id <- cols$id; time <- cols$time; dv <- cols$dv; dose <- cols$dose
  agent |>
    pointblank::col_is_numeric(columns = c(time, dv, dose), label = "Numeric time, concentration, dose") |>
    pointblank::col_vals_not_null(columns = c(id, time, dose), label = "No missing ID, time, dose") |>
    pointblank::col_vals_gte(columns = time, value = 0, label = "Time >= 0") |>
    pointblank::col_vals_gte(columns = dv, value = 0, na_pass = TRUE, label = "Concentration >= 0") |>
    pointblank::col_vals_gt(columns = dose, value = 0, label = "Dose > 0") |>
    pointblank::col_vals_equal(columns = "n_dose_values", value = 1,
                               preconditions = function(x) {
                                 dplyr::summarise(dplyr::group_by(x, id = .data[[id]]),
                                                  n_dose_values = dplyr::n_distinct(.data[[dose]]),
                                                  .groups = "drop")
                               },
                               label = "One dose value per subject (single-dose layout)") |>
    pointblank::rows_distinct(columns = c(id, time), label = "No duplicate samples (ID, time)")
}

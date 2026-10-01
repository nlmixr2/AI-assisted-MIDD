# Helpers for writing, reading, and querying a population-PK results database
# backed by DuckDB -- one file per version, output/poppk/v{project_number}/db/poppk.duckdb,
# alongside that version's tables/, figures/ and logs/. Source this file from
# analysis-poppk.R, then:
#
#   write_poppk_db(project_number, pkDataPath, pkData, fits, runs, final_run)
#
# writes six tables (poppk_meta, poppk_runs, poppk_parameters, poppk_omega,
# poppk_eta, poppk_fitdata), each carrying a project_number column, plus a
# serialized copy of the exact R objects (payload_hash-verified) in poppk_meta so
# the nlmixr2 fit objects can be restored exactly. Every downstream tbl-*.R /
# fig-*.R / generate-spec.R script then loads them -- no refit needed -- with:
#
#   read_poppk_db(project_number)   # verifies the hash, then assigns pkData,
#                                    # fits, runs, final_run, final_rationale, and
#                                    # fit (= the final model's fit) into the caller's env
#
# Or query across versions with SQL (e.g. the OFV trail of every version):
#
#   query_poppk_db("SELECT project_number, run_id, objf FROM poppk_runs ORDER BY 1, 2")
#
# Mirrors the pk-nca-database skill's nca_db.R (same per-version file layout,
# idempotent writes, hash-before-SQL rule); see that file for the rationale.
#
# All paths are relative to the current working directory (the project root).

library(DBI)
library(duckdb)
library(rlang)
library(dplyr)
source(".posit/assistant/skills/pk-project/scripts/db_snapshot.R")   # git-friendly snapshot (Parquet + xz payload)

poppk_db_tables <- c("poppk_meta", "poppk_runs", "poppk_parameters", "poppk_omega",
                     "poppk_eta", "poppk_fitdata")

#' Path to a version's popPK DuckDB file.
poppk_db_path <- function(project_number, output_dir = "output/poppk") {
  file.path(output_dir, sprintf("v%d", as.integer(project_number)), "db", "poppk.duckdb")
}

#' Paths of existing per-version popPK DuckDB files, named by project number.
poppk_db_paths <- function(project_numbers = NULL, output_dir = "output/poppk") {
  if (is.null(project_numbers)) {
    version_dirs <- list.files(output_dir, pattern = "^v[0-9]+$")
    project_numbers <- sort(as.integer(sub("^v", "", version_dirs)))
  }
  paths <- vapply(project_numbers, poppk_db_path, character(1), output_dir = output_dir)
  names(paths) <- as.integer(project_numbers)
  for (pth in paths[!file.exists(paths)]) db_snapshot_restore(pth, "poppk_meta", "payload_blob")   # fresh clone
  paths[file.exists(paths)]
}

#' Open a connection to a version's popPK DuckDB file. Always pair with
#' `on.exit(dbDisconnect(con, shutdown = TRUE))` -- DuckDB locks its file.
poppk_db_connect <- function(project_number, output_dir = "output/poppk", read_only = FALSE) {
  path <- poppk_db_path(project_number, output_dir)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  dbConnect(duckdb::duckdb(), path, read_only = read_only)
}

ensure_poppk_db_schema <- function(con) {
  dbExecute(con, "CREATE TABLE IF NOT EXISTS poppk_meta (
    project_number INTEGER PRIMARY KEY, generated_at VARCHAR, r_version VARCHAR,
    nlmixr2_version VARCHAR, source_file_path VARCHAR, source_file_hash VARCHAR,
    final_run VARCHAR, payload_hash VARCHAR, payload_blob BLOB
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS poppk_runs (
    project_number INTEGER, run_id VARCHAR, parent_run VARCHAR, description VARCHAR,
    est VARCHAR, objf DOUBLE, aic DOUBLE, bic DOUBLE, n_id INTEGER, n_obs INTEGER,
    n_par INTEGER, delta_ofv DOUBLE, cov_ok BOOLEAN, final BOOLEAN
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS poppk_parameters (
    project_number INTEGER, run_id VARCHAR, parameter VARCHAR, label VARCHAR,
    estimate DOUBLE, se DOUBLE, rse DOUBLE, back_transformed DOUBLE,
    ci_lower DOUBLE, ci_upper DOUBLE, bsv_cv DOUBLE, shrink_sd DOUBLE
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS poppk_omega (
    project_number INTEGER, run_id VARCHAR, eta_row VARCHAR, eta_col VARCHAR, value DOUBLE
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS poppk_eta (
    project_number INTEGER, run_id VARCHAR, ID VARCHAR, eta VARCHAR, value DOUBLE
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS poppk_fitdata (
    project_number INTEGER, run_id VARCHAR, ID VARCHAR, TIME DOUBLE, DV DOUBLE,
    PRED DOUBLE, IPRED DOUBLE, RES DOUBLE, IRES DOUBLE, IWRES DOUBLE, CWRES DOUBLE
  )")
  invisible(TRUE)
}

#' Tidy one fit's parameter table (fixed effects + residual error).
poppk_parameter_rows <- function(fit, run_id) {
  pf <- fit$parFixedDf
  shrink_col <- intersect(c("Shrink(SD)%"), names(pf))
  tibble(
    run_id = run_id,
    parameter = rownames(pf),
    label = if (is.null(fit$parFixed$Parameter)) NA_character_ else as.character(fit$parFixed$Parameter),
    estimate = pf$Estimate, se = pf$SE, rse = pf$`%RSE`,
    back_transformed = pf$`Back-transformed`,
    ci_lower = pf$`CI Lower`, ci_upper = pf$`CI Upper`,
    bsv_cv = pf$`BSV(CV%)`,
    shrink_sd = if (length(shrink_col)) pf[[shrink_col]] else NA_real_
  )
}

#' Write this version's popPK fits to its DuckDB database.
#'
#' Idempotent per `project_number`: deletes that version's existing rows first.
#'
#' @param project_number Integer version number (matches script/poppk/v{n}/).
#' @param pkDataPath Path to the source data file analysis-poppk.R read (hashed).
#' @param pkData The data frame passed to `nlmixr2()`.
#' @param fits Named list of nlmixr2 fit objects (names are run IDs, e.g. "run001").
#' @param runs Run-summary data frame from `summarise_runs()` (poppk-estimation's
#'   scripts/poppk_checks.R): one row per run.
#' @param final_run Run ID of the selected final model (must be in `names(fits)`).
#' @param final_rationale Why `final_run` was selected (copied into the spec).
#' @param output_dir Parent directory of versioned output directories.
#' @return (Invisibly) a list: `db_path`, `project_number`, `payload_hash`.
write_poppk_db <- function(project_number, pkDataPath, pkData, fits, runs, final_run,
                            final_rationale = NA_character_, output_dir = "output/poppk") {
  if (!file.exists(pkDataPath)) stop("Source data file not found: ", pkDataPath, call. = FALSE)
  if (!final_run %in% names(fits)) stop("final_run '", final_run, "' is not in names(fits)", call. = FALSE)
  if (!setequal(runs$run_id, names(fits))) stop("runs$run_id and names(fits) differ", call. = FALSE)
  pn <- as.integer(project_number)

  # Hash the serialized bytes (not the R objects -- see nca_db.R for why), and keep
  # the blob so fits restore with full fidelity (vpcPlot(), rxSolve(), etc.).
  payload <- list(pkData = pkData, fits = fits, runs = runs, final_run = final_run,
                  final_rationale = final_rationale)
  blob <- serialize(payload, connection = NULL)
  payload_hash <- hash(blob)

  db_path <- poppk_db_path(pn, output_dir)
  con <- poppk_db_connect(pn, output_dir)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  ensure_poppk_db_schema(con)
  for (tbl in poppk_db_tables) {
    dbExecute(con, sprintf("DELETE FROM %s WHERE project_number = ?", tbl), params = list(pn))
  }

  dbExecute(con, "INSERT INTO poppk_meta VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      pn, format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      paste(R.version$major, R.version$minor, sep = "."),
      as.character(packageVersion("nlmixr2")),
      pkDataPath, hash_file(pkDataPath), final_run, payload_hash, list(blob)
    ))

  add_pn <- function(df) mutate(df, project_number = pn, .before = 1)

  dbWriteTable(con, "poppk_runs",
    runs |> select(run_id, parent_run, description, est, objf, aic, bic, n_id, n_obs,
                   n_par, delta_ofv, cov_ok, final) |> add_pn(), append = TRUE)

  for (run_id in names(fits)) {
    fit <- fits[[run_id]]
    dbWriteTable(con, "poppk_parameters", add_pn(poppk_parameter_rows(fit, run_id)), append = TRUE)

    om <- fit$omega
    if (!is.null(om)) {
      dbWriteTable(con, "poppk_omega", add_pn(tibble(
        run_id = run_id,
        eta_row = rep(rownames(om), times = ncol(om)),
        eta_col = rep(colnames(om), each = nrow(om)),
        value = as.vector(om)
      )), append = TRUE)
    }

    eta <- fit$eta
    if (!is.null(eta)) {
      eta_long <- tidyr::pivot_longer(eta, -ID, names_to = "eta", values_to = "value")
      dbWriteTable(con, "poppk_eta",
        add_pn(transmute(eta_long, run_id = run_id, ID = as.character(ID), eta, value)), append = TRUE)
    }

    fd <- as.data.frame(fit)
    keep <- c("TIME", "DV", "PRED", "IPRED", "RES", "IRES", "IWRES", "CWRES")
    for (k in setdiff(keep, names(fd))) fd[[k]] <- NA_real_
    dbWriteTable(con, "poppk_fitdata",
      add_pn(tibble(run_id = run_id, ID = as.character(fd$ID), !!!fd[keep])), append = TRUE)
  }

  # Committed snapshot (the .duckdb itself is not committed): Parquet tables + xz payload
  db_snapshot_write(con, db_path, "poppk_meta", "payload_blob")
  message("Wrote v", pn, " (", length(fits), " runs, final = ", final_run, ") to ", db_path)
  invisible(list(db_path = db_path, project_number = pn, payload_hash = payload_hash))
}

#' Read a version's popPK objects back from its DuckDB database, verify them,
#' and assign `pkData`, `fits`, `runs`, `final_run`, `final_rationale`, and `fit`
#' (the final model) into `envir`.
#'
#' Errors if the blob fails its hash check; warns (does not error) if the
#' recorded source data file has changed since the version was written.
#'
#' @return (Invisibly) the `poppk_meta` row (minus the blob) as a list.
read_poppk_db <- function(project_number, output_dir = "output/poppk",
                           envir = parent.frame(), verify_source = TRUE) {
  pn <- as.integer(project_number)
  db_path <- poppk_db_path(pn, output_dir)
  if (!file.exists(db_path)) db_snapshot_restore(db_path, "poppk_meta", "payload_blob")   # fresh clone
  if (!file.exists(db_path)) {
    stop("popPK database not found: ", db_path, " -- run script/poppk/v", pn,
         "/analysis-poppk.R first.", call. = FALSE)
  }
  con <- poppk_db_connect(pn, output_dir, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE))

  meta <- dbGetQuery(con, "SELECT * FROM poppk_meta WHERE project_number = ?", params = list(pn))
  if (nrow(meta) == 0) {
    stop("No version ", pn, " found in ", db_path, " -- run script/poppk/v", pn,
         "/analysis-poppk.R first.", call. = FALSE)
  }
  blob <- meta$payload_blob[[1]]
  if (!identical(hash(blob), meta$payload_hash)) {
    stop("popPK db entry for v", pn, " in ", db_path, " failed hash verification -- ",
         "corrupted or written outside write_poppk_db(); re-run analysis-poppk.R.", call. = FALSE)
  }
  payload <- unserialize(blob)

  if (verify_source && file.exists(meta$source_file_path) &&
      !identical(hash_file(meta$source_file_path), meta$source_file_hash)) {
    warning("Source data file ", meta$source_file_path, " has changed since v", pn,
            " was written at ", meta$generated_at, " -- results may be stale. ",
            "Re-run analysis-poppk.R to refit.", call. = FALSE)
  }

  payload$fit <- payload$fits[[payload$final_run]]
  list2env(payload, envir = envir)
  invisible(as.list(meta[, setdiff(names(meta), "payload_blob")]))
}

#' Run an ad-hoc SQL query across one or more versions' popPK databases (read-only).
#' Each table is exposed as a UNION ALL view across the attached versions;
#' a single version's table is reachable as e.g. `v1.poppk_runs`.
query_poppk_db <- function(sql, project_numbers = NULL, output_dir = "output/poppk") {
  paths <- poppk_db_paths(project_numbers, output_dir)
  if (length(paths) == 0) stop("No popPK databases found under ", output_dir, call. = FALSE)
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE))
  for (pn in names(paths)) {
    dbExecute(con, sprintf("ATTACH '%s' AS v%s (READ_ONLY)", paths[[pn]], pn))
  }
  for (tbl in setdiff(poppk_db_tables, "poppk_meta")) {
    dbExecute(con, sprintf("CREATE VIEW %s AS %s", tbl,
      paste(sprintf("SELECT * FROM v%s.%s", names(paths), tbl), collapse = " UNION ALL BY NAME ")))
  }
  dbExecute(con, sprintf("CREATE VIEW poppk_meta AS %s",
    paste(sprintf("SELECT * EXCLUDE (payload_blob) FROM v%s.poppk_meta", names(paths)),
          collapse = " UNION ALL BY NAME ")))
  dbGetQuery(con, sql)
}

#' Which versions have a popPK database, when they were written, and their final run.
list_poppk_db_versions <- function(output_dir = "output/poppk") {
  query_poppk_db("SELECT project_number, generated_at, nlmixr2_version, final_run,
                  source_file_path FROM poppk_meta ORDER BY project_number",
                 output_dir = output_dir)
}

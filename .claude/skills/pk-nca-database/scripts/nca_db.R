# Helpers for writing, reading, and querying an NCA results database backed by
# DuckDB -- one file per version, output/nca/v{project_number}/db/nca.duckdb,
# alongside that version's tables/, figures/ and logs/. Source this file from
# analysis-*.R, then:
#
#   write_nca_db(project_number, pkDataPath, cObsData, doseData, ncaRes,
#                res_wide, halflife_fit)
#
# writes six tables (nca_meta, nca_conc, nca_dose, nca_result, nca_res_wide,
# nca_halflife_fit), each carrying a project_number column, plus a serialized
# copy of the exact R objects (payload_hash-verified) in nca_meta so the
# original objects can be restored exactly. Every downstream tbl-*.R /
# fig-*.R / generate-spec.R script then loads them -- no PKNCA re-run needed --
# with:
#
#   read_nca_db(project_number)   # verifies the hash, then assigns
#                                  # cObsData/doseData/ncaRes/res_wide/
#                                  # halflife_fit into the caller's environment
#
# Or query across versions directly with SQL (e.g. from a TFL/report script,
# or from Python/another tool entirely -- the DuckDB files don't require R).
# query_nca_db() ATTACHes every version's file and exposes each table as a
# UNION ALL view, so SQL written against one table name spans all versions:
#
#   query_nca_db("SELECT project_number, participant, cmax, \"half.life\"
#                 FROM nca_res_wide ORDER BY project_number, participant")
#
# Why one file per version: every artifact a version produces lives under
# output/nca/v{n}/, so a version's outputs can be archived, shared, or deleted
# as a unit, and re-running one version never opens (or locks) another
# version's database. Every table still carries a project_number column, so
# the attached files combine cleanly for cross-version TFL comparisons. The
# serialized BLOB column preserves exact-fidelity R objects (factors, the full
# PKNCAresults object, etc.) for when SQL's flattened types aren't enough.
#
# All paths are relative to the current working directory (the project root).

library(DBI)
library(duckdb)
library(rlang)
library(dplyr)
source(".posit/assistant/skills/pk-project/scripts/db_snapshot.R")   # git-friendly snapshot (Parquet + xz payload)

nca_db_tables <- c("nca_meta", "nca_conc", "nca_dose", "nca_result", "nca_res_wide", "nca_halflife_fit")

#' Path to a version's NCA DuckDB file.
#' @param project_number Integer version number.
#' @param output_dir Parent directory of versioned output directories. Defaults
#'   to `"output/nca"`; the file is `{output_dir}/v{project_number}/db/nca.duckdb`.
nca_db_path <- function(project_number, output_dir = "output/nca") {
  file.path(output_dir, sprintf("v%d", as.integer(project_number)), "db", "nca.duckdb")
}

#' Paths of existing per-version NCA DuckDB files, named by project number.
#' @param project_numbers Integer versions to include, or `NULL` (default) for
#'   every `v{n}/db/nca.duckdb` found under `output_dir`.
#' @param output_dir Parent directory of versioned output directories.
nca_db_paths <- function(project_numbers = NULL, output_dir = "output/nca") {
  if (is.null(project_numbers)) {
    version_dirs <- list.files(output_dir, pattern = "^v[0-9]+$")
    project_numbers <- sort(as.integer(sub("^v", "", version_dirs)))
  }
  paths <- vapply(project_numbers, nca_db_path, character(1), output_dir = output_dir)
  names(paths) <- as.integer(project_numbers)
  for (pth in paths[!file.exists(paths)]) db_snapshot_restore(pth, "nca_meta", "ncares_blob")   # fresh clone
  paths[file.exists(paths)]
}

#' Open a connection to a version's NCA DuckDB file, creating its directory if needed.
#'
#' **Always pair with `on.exit(dbDisconnect(con, shutdown = TRUE))`** (or call
#' it explicitly when done) -- DuckDB locks its file while any connection is
#' open; a connection left open (or disconnected without `shutdown = TRUE`)
#' can leave the file locked for the next script/session.
#'
#' @param project_number Integer version number.
#' @param output_dir Parent directory of versioned output directories.
#' @param read_only If `TRUE`, open read-only (safe for concurrent readers;
#'   use for `read_nca_db()`). Defaults to `FALSE` (for `write_nca_db()`,
#'   which needs write access).
#' @return A `DBIConnection`.
nca_db_connect <- function(project_number, output_dir = "output/nca", read_only = FALSE) {
  path <- nca_db_path(project_number, output_dir)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  dbConnect(duckdb::duckdb(), path, read_only = read_only)
}

#' Create the NCA database's tables if they don't already exist.
#' @param con A writable `DBIConnection` (see `nca_db_connect()`).
ensure_nca_db_schema <- function(con) {
  dbExecute(con, "CREATE TABLE IF NOT EXISTS nca_meta (
    project_number INTEGER PRIMARY KEY,
    generated_at VARCHAR,
    r_version VARCHAR,
    pknca_version VARCHAR,
    source_file_path VARCHAR,
    source_file_hash VARCHAR,
    payload_hash VARCHAR,
    ncares_blob BLOB
  )")
  # nca_conc (participant/time/cObs + optional ntime from the source data) and nca_res_wide
  # (one column per requested PK parameter) take their columns from the data frames, so
  # they are created on first write (see write_nca_db()) rather than with a fixed schema.
  dbExecute(con, "CREATE TABLE IF NOT EXISTS nca_dose (
    project_number INTEGER, participant VARCHAR, time DOUBLE, dose DOUBLE,
    route VARCHAR, dur DOUBLE
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS nca_result (
    project_number INTEGER, participant VARCHAR, start DOUBLE, \"end\" DOUBLE,
    PPTESTCD VARCHAR, PPORRES DOUBLE, exclude VARCHAR
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS nca_halflife_fit (
    project_number INTEGER, participant VARCHAR, \"half.life\" DOUBLE,
    \"r.squared\" DOUBLE, \"adj.r.squared\" DOUBLE, \"span.ratio\" DOUBLE,
    \"lambda.z.n.points\" DOUBLE
  )")
  invisible(TRUE)
}

#' Write this version's NCA analysis objects to its DuckDB database.
#'
#' Idempotent per `project_number`: deletes that version's existing rows in
#' every table first, so re-running `analysis-*.R` for the same version
#' cleanly replaces its data rather than duplicating or appending to it.
#'
#' @param project_number Integer version number (matches the enclosing
#'   `script/nca/v{project_number}/` directory).
#' @param pkDataPath Path to the source data file `analysis-*.R` read from
#'   (e.g. `"data/pk-data.csv"`), for provenance -- hashed, not copied.
#' @param cObsData,doseData,ncaRes,res_wide,halflife_fit The analysis objects
#'   built by `analysis-*.R`'s Core Process steps.
#' @param output_dir Parent directory of versioned output directories.
#'   Defaults to `"output/nca"` (writes `output/nca/v{project_number}/db/nca.duckdb`).
#' @return (Invisibly) a list: `db_path`, `project_number`, `payload_hash`.
write_nca_db <- function(project_number, pkDataPath, cObsData, doseData, ncaRes,
                          res_wide, halflife_fit, output_dir = "output/nca") {
  if (!file.exists(pkDataPath)) {
    stop("Source data file not found: ", pkDataPath, call. = FALSE)
  }
  pn <- as.integer(project_number)

  # Hash the exact R objects (pre-SQL, since DuckDB round-tripping can change
  # types -- e.g. factor -> character) and keep a serialized copy so the
  # originals can be restored exactly regardless of what SQL's flattened
  # tables preserve.
  payload <- list(
    cObsData = cObsData, doseData = doseData, ncaRes = ncaRes,
    res_wide = res_wide, halflife_fit = halflife_fit
  )
  blob <- serialize(payload, connection = NULL)
  # Hash the serialized bytes, not the R objects: hash(payload) is not stable
  # across a serialize round-trip or across R sessions (ALTREP vectors get
  # expanded; the formula environments inside PKNCAconc/PKNCAdose are rebuilt
  # on unserialize), so an object-level hash could never be re-verified.
  payload_hash <- hash(blob)

  db_path <- nca_db_path(pn, output_dir)
  con <- nca_db_connect(pn, output_dir)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  ensure_nca_db_schema(con)

  dynamic_cols <- list(nca_conc = names(cObsData), nca_res_wide = names(res_wide))
  for (tbl in nca_db_tables) {
    if (!dbExistsTable(con, tbl)) next
    # a changed column set (e.g. ntime added, other parameters requested) means a new
    # table shape: recreate it (one database per version, so no other version is affected)
    if (tbl %in% names(dynamic_cols) &&
        !setequal(dbListFields(con, tbl), c("project_number", dynamic_cols[[tbl]]))) {
      dbRemoveTable(con, tbl)
      next
    }
    dbExecute(con, sprintf("DELETE FROM %s WHERE project_number = ?", tbl), params = list(pn))
  }

  dbExecute(
    con, "INSERT INTO nca_meta VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      pn, format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      paste(R.version$major, R.version$minor, sep = "."),
      as.character(packageVersion("PKNCA")),
      pkDataPath, hash_file(pkDataPath), payload_hash, list(blob)
    )
  )

  dbWriteTable(con, "nca_conc",
    cObsData |> mutate(project_number = pn, participant = as.character(participant), .before = 1),
    append = TRUE)
  dbWriteTable(con, "nca_dose",
    doseData |> mutate(project_number = pn, participant = as.character(participant), .before = 1),
    append = TRUE)
  dbWriteTable(con, "nca_result",
    ncaRes$result |>
      mutate(project_number = pn, participant = as.character(participant), .before = 1) |>
      select(project_number, participant, start, end, PPTESTCD, PPORRES, exclude),
    append = TRUE)
  dbWriteTable(con, "nca_res_wide",
    res_wide |> mutate(project_number = pn, participant = as.character(participant), .before = 1),
    append = TRUE)
  dbWriteTable(con, "nca_halflife_fit",
    halflife_fit |> mutate(project_number = pn, participant = as.character(participant), .before = 1),
    append = TRUE)

  # Committed snapshot (the .duckdb itself is not committed): Parquet tables + xz payload
  db_snapshot_write(con, db_path, "nca_meta", "ncares_blob")
  message("Wrote v", pn, " to ", db_path)
  invisible(list(db_path = db_path, project_number = pn, payload_hash = payload_hash))
}

#' Read a version's NCA objects back from the DuckDB database, verify them,
#' and assign them into an environment.
#'
#' Unserializes `nca_meta.ncares_blob` and verifies `payload_hash` against a
#' fresh `rlang::hash()` of the serialized blob before unserializing -- catches a
#' truncated/corrupted blob or one written outside `write_nca_db()`.
#' Optionally also re-hashes the recorded `source_file_path` and warns (does
#' not error) if it no longer matches -- the input data file may have
#' legitimately changed since this version was written, but that's worth
#' surfacing rather than silently using stale results.
#'
#' @param project_number Integer version number.
#' @param output_dir Parent directory of versioned output directories.
#'   Defaults to `"output/nca"` (reads `output/nca/v{project_number}/db/nca.duckdb`).
#' @param envir Environment to assign `cObsData`/`doseData`/`ncaRes`/
#'   `res_wide`/`halflife_fit` into. Defaults to the caller's environment, so
#'   `read_nca_db(1)` at the top of a script behaves like
#'   `source("script/nca/v1/analysis-nca.R")` did, without re-running PKNCA.
#' @param verify_source If `TRUE` (default), warn when the recorded source
#'   file hash no longer matches the file on disk.
#' @return (Invisibly) the `nca_meta` row for this version, as a list.
read_nca_db <- function(project_number, output_dir = "output/nca",
                         envir = parent.frame(), verify_source = TRUE) {
  pn <- as.integer(project_number)
  db_path <- nca_db_path(pn, output_dir)
  if (!file.exists(db_path)) db_snapshot_restore(db_path, "nca_meta", "ncares_blob")   # fresh clone
  if (!file.exists(db_path)) {
    stop(
      "NCA database not found: ", db_path, " -- run ",
      "script/nca/v", pn, "/analysis-nca.R first to build and write it.",
      call. = FALSE
    )
  }

  con <- nca_db_connect(pn, output_dir, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE))

  meta <- dbGetQuery(con, "SELECT * FROM nca_meta WHERE project_number = ?", params = list(pn))
  if (nrow(meta) == 0) {
    stop(
      "No version ", pn, " found in ", db_path, " -- run ",
      "script/nca/v", pn, "/analysis-nca.R first to build and write it.",
      call. = FALSE
    )
  }

  blob <- meta$ncares_blob[[1]]
  if (!identical(hash(blob), meta$payload_hash)) {
    stop(
      "NCA db entry for v", pn, " in ", db_path, " failed hash ",
      "verification -- its blob doesn't match payload_hash. It may be ",
      "corrupted or was written outside write_nca_db(); regenerate it via ",
      "analysis-nca.R.",
      call. = FALSE
    )
  }

  payload <- unserialize(blob)

  if (verify_source && file.exists(meta$source_file_path)) {
    if (!identical(hash_file(meta$source_file_path), meta$source_file_hash)) {
      warning(
        "Source data file ", meta$source_file_path, " has changed since v",
        pn, " was written at ", meta$generated_at, " -- results may be ",
        "stale. Re-run analysis-nca.R if you want them to reflect the ",
        "current file.",
        call. = FALSE
      )
    }
  }

  list2env(payload, envir = envir)
  invisible(as.list(meta[, setdiff(names(meta), "ncares_blob")]))
}

#' Run an ad-hoc SQL query across one or more versions' NCA databases (read-only).
#'
#' ATTACHes each version's `output/nca/v{n}/db/nca.duckdb` read-only into an
#' in-memory DuckDB session and exposes every table (`nca_meta`, `nca_conc`,
#' `nca_dose`, `nca_result`, `nca_res_wide`, `nca_halflife_fit`) as a
#' `UNION ALL` view across them, so cross-version queries/TFLs work without
#' restoring R objects via `read_nca_db()` -- e.g.
#' `query_nca_db("SELECT project_number, avg(cmax) FROM nca_res_wide GROUP BY project_number")`.
#' A single version's file is also reachable by its catalog alias, e.g.
#' `v1.nca_res_wide`.
#'
#' @param sql A SQL query string.
#' @param project_numbers Integer versions to include, or `NULL` (default)
#'   for every version with a database under `output_dir`.
#' @param output_dir Parent directory of versioned output directories.
#' @return A data frame of results.
query_nca_db <- function(sql, project_numbers = NULL, output_dir = "output/nca") {
  paths <- nca_db_paths(project_numbers, output_dir)
  if (length(paths) == 0) {
    stop("No NCA databases found under ", output_dir, "/v*/db/ -- run ",
         "analysis-nca.R for at least one version first.", call. = FALSE)
  }
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE))

  aliases <- paste0("v", names(paths))
  for (i in seq_along(paths)) {
    dbExecute(con, sprintf("ATTACH '%s' AS %s (READ_ONLY)", paths[[i]], aliases[[i]]))
  }
  for (tbl in nca_db_tables) {
    dbExecute(con, sprintf(
      "CREATE TEMP VIEW %s AS %s", tbl,
      paste(sprintf("SELECT * FROM %s.%s", aliases, tbl), collapse = " UNION ALL BY NAME ")
    ))
  }
  dbGetQuery(con, sql)
}

#' List every version with an NCA database under `output_dir`.
#' @param output_dir Parent directory of versioned output directories.
#' @return A data frame: `project_number`, `generated_at`, `pknca_version`,
#'   `source_file_path`, `payload_hash`.
list_nca_db_versions <- function(output_dir = "output/nca") {
  query_nca_db(
    "SELECT project_number, generated_at, pknca_version, source_file_path, payload_hash
     FROM nca_meta ORDER BY project_number",
    output_dir = output_dir
  )
}

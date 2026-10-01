# One project-wide DuckDB database of every version and every run: output/project.duckdb.
#
#   update_project_db()                          rebuild it now (run_version() and run_qc() do
#                                                this automatically after every run)
#   query_project_db("SELECT * FROM versions")   read-only SQL on it
#
# It is a derived, local catalogue, rebuilt in full from files that are committed or written by
# every run, so it can always be regenerated and never needs to be committed (*.duckdb is
# git-ignored):
#
#   <table> (nca_*, poppk_*, sim_*)   every results table of every version, read from the per-version
#                                     Parquet snapshots (output/{type}/v{n}/db/snapshot/*.parquet);
#                                     each row keeps project_number, and `filename` names its source
#   versions                          every version of every type: spec present, QC status, last QC result
#   script_runs                       every script execution, from the run logs' headers and summaries
#   catalog                           each table, its rows and versions, and when the file was built
#
# The per-version databases and specs stay the source of truth for provenance and QC: analysis,
# table, figure and report scripts never read the project database, so rebuilding it cannot change
# any version's hashes. The serialized R payloads (fits, PKNCA results) stay per version.
# Source after project.R (uses pk_types, list_versions(), project_status()).

project_db_path <- function(output_root = "output") file.path(output_root, "project.duckdb")

#' Every run log under output/{type}/v{n}/logs/: one row per script execution, from the log
#' header and run summary written by pk-nca-logging (older logs without a summary get
#' status "completed (older log format)" or "incomplete").
run_log_records <- function(output_root = "output") {
  logs <- Sys.glob(file.path(output_root, "*", "v*", "logs", "*.log"))
  if (!length(logs)) {
    return(data.frame(type = character(), project_number = integer(), script = character(),
                      started_at = character(), finished_at = character(), status = character(),
                      elapsed = character(), user = character(), git_commit = character(),
                      log_file = character()))
  }
  field <- function(txt, key) {
    v <- sub(sprintf("^# %s: ", key), "", grep(sprintf("^# %s: ", key), txt, value = TRUE))
    if (length(v)) v[1] else NA_character_
  }
  rows <- lapply(logs, function(f) {
    txt <- readLines(f, warn = FALSE, n = -1L)
    status <- field(txt, "status")
    if (is.na(status)) {
      status <- if (any(grepl("^# sessionInfo\\(\\):", txt))) "completed (older log format)" else "incomplete"
    }
    data.frame(
      type = basename(dirname(dirname(dirname(f)))),
      project_number = as.integer(sub("^v", "", basename(dirname(dirname(f))))),
      script = sub("-\\d{8}T\\d{6}\\.log$", "", basename(f)),
      started_at = field(txt, "started_at"), finished_at = field(txt, "finished_at"),
      status = status, elapsed = field(txt, "elapsed"), user = field(txt, "user"),
      git_commit = field(txt, "git_commit"), log_file = f
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$type, out$project_number, out$started_at, out$script), ]
}

#' Rebuild output/project.duckdb from every version's Parquet snapshot, project_status() and
#' the run logs. Built in a temporary file and moved into place, so a failed build never
#' leaves a half-written database. Returns the path invisibly.
update_project_db <- function(output_root = "output", path = project_db_path(output_root)) {
  for (p in c("DBI", "duckdb")) {
    if (!requireNamespace(p, quietly = TRUE)) stop("Package '", p, "' is required", call. = FALSE)
  }
  tmp <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), tmp)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
  sql_str <- function(x) paste0("'", gsub("'", "''", x), "'")

  files <- Sys.glob(file.path(output_root, "*", "v*", "db", "snapshot", "*.parquet"))
  tables <- sort(unique(tools::file_path_sans_ext(basename(files))))
  for (t in tables) {
    glob <- file.path(output_root, "*", "v*", "db", "snapshot", paste0(t, ".parquet"))
    DBI::dbExecute(con, sprintf(
      "CREATE TABLE \"%s\" AS SELECT * FROM read_parquet(%s, union_by_name = true, filename = true)",
      t, sql_str(glob)))
  }

  status <- project_status()
  if (!nrow(status)) status <- data.frame(type = character(), version = integer(), spec = logical(),
                                          qc_status = character(), last_qc = character())
  DBI::dbWriteTable(con, "versions", status, overwrite = TRUE)
  DBI::dbWriteTable(con, "script_runs", run_log_records(output_root), overwrite = TRUE)

  built <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  catalog <- do.call(rbind, lapply(c(tables, "versions", "script_runs"), function(t) {
    n <- DBI::dbGetQuery(con, sprintf("SELECT count(*) AS n FROM \"%s\"", t))$n
    v <- if (t %in% tables) DBI::dbGetQuery(con, sprintf(
      "SELECT count(DISTINCT project_number) AS v FROM \"%s\"", t))$v else NA_integer_
    data.frame(table_name = t, rows = as.integer(n), versions = as.integer(v), built_at = built)
  }))
  DBI::dbWriteTable(con, "catalog", catalog, overwrite = TRUE)
  DBI::dbDisconnect(con, shutdown = TRUE)

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(tmp, path, overwrite = TRUE)) {
    stop("Could not write ", path, " (is it open in another R session?)", call. = FALSE)
  }
  unlink(tmp)
  message("Project database updated: ", path, " (", length(tables), " results tables, ",
          nrow(status), " versions)")
  invisible(path)
}

#' Run read-only SQL on output/project.duckdb (built first if it does not exist yet).
#'
#' Example: query_project_db("SELECT project_number, run_id, objf FROM poppk_runs WHERE final")
query_project_db <- function(sql, output_root = "output", path = project_db_path(output_root)) {
  if (!file.exists(path)) update_project_db(output_root, path)
  con <- DBI::dbConnect(duckdb::duckdb(), path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbGetQuery(con, sql)
}

#' update_project_db() for run_version()/run_qc(): a failure (e.g. duckdb missing, or the file
#' open elsewhere) is reported but never fails the version.
refresh_project_db <- function(output_root = "output") {
  tryCatch(update_project_db(output_root),
           error = function(e) message("Project database not updated: ", conditionMessage(e)))
  invisible(NULL)
}

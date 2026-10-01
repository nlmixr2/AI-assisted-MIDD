# Helpers for a popPK simulation results database backed by DuckDB -- one file per
# version, output/poppk-sim/v{project_number}/db/sim.duckdb. Same design as the
# poppk-database / pk-nca-database skills (per-version file, idempotent writes,
# hash of the serialized payload, full-fidelity BLOB).
#
#   write_sim_db(project_number, source_provenance, settings, scenarios,
#                sims, metrics, exposure_summary, profiles)
#   read_sim_db(project_number)   # assigns source_provenance, settings, events,
#                                  # sims, metrics, exposure_summary, profiles
#   query_sim_db("SELECT * FROM sim_exposure_summary")
#
# SQL tables hold the summaries (sim_scenarios, sim_exposure, sim_exposure_summary,
# sim_profiles); the full simulated rows live only in the BLOB (they can be large).

library(DBI)
library(duckdb)
library(rlang)
library(dplyr)
source(".posit/assistant/skills/pk-project/scripts/db_snapshot.R")   # git-friendly snapshot (Parquet + xz payload)

sim_db_tables <- c("sim_meta", "sim_scenarios", "sim_exposure", "sim_exposure_summary", "sim_profiles")

sim_db_path <- function(project_number, output_dir = "output/poppk-sim") {
  file.path(output_dir, sprintf("v%d", as.integer(project_number)), "db", "sim.duckdb")
}

sim_db_paths <- function(project_numbers = NULL, output_dir = "output/poppk-sim") {
  if (is.null(project_numbers)) {
    project_numbers <- sort(as.integer(sub("^v", "", list.files(output_dir, pattern = "^v[0-9]+$"))))
  }
  paths <- vapply(project_numbers, sim_db_path, character(1), output_dir = output_dir)
  names(paths) <- as.integer(project_numbers)
  for (pth in paths[!file.exists(paths)]) db_snapshot_restore(pth, "sim_meta", "payload_blob")   # fresh clone
  paths[file.exists(paths)]
}

sim_db_connect <- function(project_number, output_dir = "output/poppk-sim", read_only = FALSE) {
  path <- sim_db_path(project_number, output_dir)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  dbConnect(duckdb::duckdb(), path, read_only = read_only)
}

ensure_sim_db_schema <- function(con) {
  dbExecute(con, "CREATE TABLE IF NOT EXISTS sim_meta (
    project_number INTEGER PRIMARY KEY, generated_at VARCHAR, r_version VARCHAR,
    rxode2_version VARCHAR, source_type VARCHAR, source_ref VARCHAR, source_hash VARCHAR,
    seed INTEGER, n_sub INTEGER, n_stud INTEGER, payload_hash VARCHAR, payload_blob BLOB
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS sim_scenarios (
    project_number INTEGER, scenario VARCHAR, description VARCHAR, seed INTEGER, n_rows INTEGER
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS sim_exposure (
    project_number INTEGER, scenario VARCHAR, study INTEGER, id INTEGER, \"sim.id\" INTEGER,
    cmax DOUBLE, tmax DOUBLE, cmin DOUBLE, auc DOUBLE, auc24 DOUBLE
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS sim_exposure_summary (
    project_number INTEGER, scenario VARCHAR, metric VARCHAR, n INTEGER,
    p05 DOUBLE, median DOUBLE, p95 DOUBLE
  )")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS sim_profiles (
    project_number INTEGER, scenario VARCHAR, time DOUBLE, p05 DOUBLE, median DOUBLE, p95 DOUBLE
  )")
  invisible(TRUE)
}

#' Write this simulation version to its DuckDB database (idempotent per version).
#'
#' @param source_provenance `load_sim_model()$provenance`.
#' @param settings list(seed, nSub, nStud, var, windows = data frame scenario/start/end, ...).
#' @param scenarios Named list of event tables; `scenario_info` gives descriptions.
#' @param scenario_info data frame: scenario, description.
#' @param sims,metrics,exposure_summary,profiles From poppk_sim.R helpers.
write_sim_db <- function(project_number, source_provenance, settings, scenarios, scenario_info,
                          sims, metrics, exposure_summary, profiles, output_dir = "output/poppk-sim") {
  pn <- as.integer(project_number)
  stopifnot(setequal(names(scenarios), scenario_info$scenario))
  events <- scenario_events_df(scenarios)
  payload <- list(source_provenance = source_provenance, settings = settings, events = events,
                  scenario_info = scenario_info, sims = sims, metrics = metrics,
                  exposure_summary = exposure_summary, profiles = profiles)
  blob <- serialize(payload, connection = NULL)
  payload_hash <- hash(blob)

  source_ref <- if (source_provenance$type == "poppk-estimation") {
    sprintf("poppk v%d %s", source_provenance$poppk_version, source_provenance$run_id)
  } else source_provenance$path
  source_hash <- if (source_provenance$type == "poppk-estimation") {
    source_provenance$poppk_db$payload_hash
  } else source_provenance$hash

  db_path <- sim_db_path(pn, output_dir)
  con <- sim_db_connect(pn, output_dir)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  ensure_sim_db_schema(con)
  for (tbl in sim_db_tables) {
    dbExecute(con, sprintf("DELETE FROM %s WHERE project_number = ?", tbl), params = list(pn))
  }

  dbExecute(con, "INSERT INTO sim_meta VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(pn, format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                  paste(R.version$major, R.version$minor, sep = "."),
                  as.character(packageVersion("rxode2")),
                  source_provenance$type, source_ref, source_hash,
                  as.integer(settings$seed), as.integer(settings$nSub), as.integer(settings$nStud),
                  payload_hash, list(blob)))

  add_pn <- function(df) mutate(df, project_number = pn, .before = 1)
  sc <- scenario_info |>
    mutate(seed = as.integer(settings$seed) + match(scenario, names(scenarios)) - 1L,
           n_rows = as.integer(table(sims$scenario)[scenario]))
  dbWriteTable(con, "sim_scenarios", add_pn(select(sc, scenario, description, seed, n_rows)), append = TRUE)
  dbWriteTable(con, "sim_exposure", add_pn(mutate(metrics, scenario = as.character(scenario))), append = TRUE)
  dbWriteTable(con, "sim_exposure_summary",
               add_pn(mutate(exposure_summary, scenario = as.character(scenario))), append = TRUE)
  dbWriteTable(con, "sim_profiles", add_pn(mutate(profiles, scenario = as.character(scenario))), append = TRUE)

  # Committed snapshot (the .duckdb itself is not committed): Parquet tables + xz payload
  db_snapshot_write(con, db_path, "sim_meta", "payload_blob")
  message("Wrote simulation v", pn, " (", length(scenarios), " scenarios, ",
          format(nrow(sims), big.mark = ","), " rows) to ", db_path)
  invisible(list(db_path = db_path, project_number = pn, payload_hash = payload_hash))
}

#' Read a simulation version back (hash-verified) into `envir`.
#' @return (Invisibly) the `sim_meta` row (minus the blob) as a list.
read_sim_db <- function(project_number, output_dir = "output/poppk-sim", envir = parent.frame()) {
  pn <- as.integer(project_number)
  db_path <- sim_db_path(pn, output_dir)
  if (!file.exists(db_path)) db_snapshot_restore(db_path, "sim_meta", "payload_blob")   # fresh clone
  if (!file.exists(db_path)) {
    stop("Simulation database not found: ", db_path, " -- run script/poppk-sim/v", pn,
         "/analysis-sim.R first.", call. = FALSE)
  }
  con <- sim_db_connect(pn, output_dir, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  meta <- dbGetQuery(con, "SELECT * FROM sim_meta WHERE project_number = ?", params = list(pn))
  if (nrow(meta) == 0) stop("No simulation version ", pn, " in ", db_path, call. = FALSE)
  blob <- meta$payload_blob[[1]]
  if (!identical(hash(blob), meta$payload_hash)) {
    stop("Simulation db entry for v", pn, " in ", db_path, " failed hash verification -- ",
         "re-run analysis-sim.R.", call. = FALSE)
  }
  list2env(unserialize(blob), envir = envir)
  invisible(as.list(meta[, setdiff(names(meta), "payload_blob")]))
}

#' Ad-hoc SQL across simulation versions (read-only; UNION ALL views per table).
query_sim_db <- function(sql, project_numbers = NULL, output_dir = "output/poppk-sim") {
  paths <- sim_db_paths(project_numbers, output_dir)
  if (length(paths) == 0) stop("No simulation databases under ", output_dir, call. = FALSE)
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE))
  for (pn in names(paths)) dbExecute(con, sprintf("ATTACH '%s' AS v%s (READ_ONLY)", paths[[pn]], pn))
  for (tbl in setdiff(sim_db_tables, "sim_meta")) {
    dbExecute(con, sprintf("CREATE VIEW %s AS %s", tbl,
      paste(sprintf("SELECT * FROM v%s.%s", names(paths), tbl), collapse = " UNION ALL BY NAME ")))
  }
  dbExecute(con, sprintf("CREATE VIEW sim_meta AS %s",
    paste(sprintf("SELECT * EXCLUDE (payload_blob) FROM v%s.sim_meta", names(paths)), collapse = " UNION ALL BY NAME ")))
  dbGetQuery(con, sql)
}

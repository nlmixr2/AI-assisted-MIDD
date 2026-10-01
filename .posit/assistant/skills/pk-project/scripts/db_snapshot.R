# Git-friendly snapshots of the per-version results databases (NCA, popPK, simulation).
#
# The DuckDB files (output/{type}/v{n}/db/*.duckdb) are a LOCAL working store and are not
# committed: they are large, binary, and grow on every rewrite. What is committed instead is a
# compact snapshot written next to them on every write:
#
#   output/{type}/v{n}/db/snapshot/<table>.parquet        every SQL table (zstd Parquet),
#                                                         readable anywhere (R, Python, DuckDB)
#   output/{type}/v{n}/db/snapshot/<meta>-payload.bin.xz  the exact serialized R objects
#                                                         (xz), which Parquet cannot hold
#
# On a fresh clone, read_*_db() finds no .duckdb and calls db_snapshot_restore(), which
# rebuilds it from the snapshot; the usual payload_hash check then proves the rebuilt payload
# is byte-identical to the one the analysis wrote.

library(DBI)
library(duckdb)

snapshot_dir <- function(db_path) file.path(dirname(db_path), "snapshot")

#' Write the snapshot of an open database connection (called by write_*_db()).
#'
#' @param con Open (writable) DBI connection to the version's DuckDB file.
#' @param db_path Path of that DuckDB file.
#' @param meta_table Name of the one-row-per-version meta table (e.g. "nca_meta").
#' @param blob_col Name of its serialized-payload BLOB column.
db_snapshot_write <- function(con, db_path, meta_table, blob_col) {
  dir <- snapshot_dir(db_path)
  unlink(dir, recursive = TRUE)
  dir.create(dir, recursive = TRUE)
  for (t in dbListTables(con)) {
    cols <- setdiff(dbListFields(con, t), blob_col)
    dbExecute(con, sprintf("COPY (SELECT %s FROM %s) TO '%s' (FORMAT parquet, COMPRESSION zstd)",
                           paste(sprintf('"%s"', cols), collapse = ", "), t,
                           file.path(dir, paste0(t, ".parquet"))))
  }
  blob <- dbGetQuery(con, sprintf("SELECT %s FROM %s", blob_col, meta_table))[[1]][[1]]
  writeBin(memCompress(blob, "xz"), file.path(dir, paste0(meta_table, "-payload.bin.xz")))
  invisible(dir)
}

#' Rebuild a version's DuckDB file from its committed snapshot (fresh clone).
#'
#' @return TRUE if rebuilt, FALSE if there is no snapshot.
db_snapshot_restore <- function(db_path, meta_table, blob_col) {
  dir <- snapshot_dir(db_path)
  payload_file <- file.path(dir, paste0(meta_table, "-payload.bin.xz"))
  if (!file.exists(payload_file)) return(FALSE)
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
  con <- dbConnect(duckdb::duckdb(), db_path)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  for (f in list.files(dir, pattern = "\\.parquet$", full.names = TRUE)) {
    t <- sub("\\.parquet$", "", basename(f))
    dbExecute(con, sprintf("CREATE TABLE %s AS SELECT * FROM read_parquet('%s')", t, f))
  }
  blob <- memDecompress(readBin(payload_file, "raw", file.size(payload_file)), "xz")
  dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s BLOB", meta_table, blob_col))
  dbExecute(con, sprintf("UPDATE %s SET %s = ?", meta_table, blob_col), params = list(list(blob)))
  message("Rebuilt ", db_path, " from its snapshot (", dir, ")")
  invisible(TRUE)
}

# `pk-nca-database`

Saves the results of an NCA version to a DuckDB database, one file per version, with a
content hash. Tables, figures, the spec and the report then read the results back instead of
re-running PKNCA.

## When it is used

- At the end of `analysis-nca.R`, right after the NCA objects are built, to write them.
- At the top of every `tbl-*.R`, `fig-*.R` and `generate-spec.R`, to read them back.
- When you ask about a "database", "db" or "duckdb", or how to avoid re-running the NCA for
  tables, figures or reports.
- When you want to compare results across versions with SQL.
- Not needed for a one-off, exploratory NCA that nothing downstream reuses.
- Neighbouring tasks: run the NCA itself with [pk-nca](pk-nca.md); record the database in
  the provenance record with [pk-nca-run-spec](pk-nca-run-spec.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `nca.duckdb` | `output/nca/v{n}/db/` | Six tables keyed by `project_number`: `nca_meta`, `nca_conc`, `nca_dose`, `nca_result`, `nca_res_wide`, `nca_halflife_fit`. Local working store, git-ignored. |
| `<table>.parquet` | `output/nca/v{n}/db/snapshot/` | Every SQL table as Parquet. Committed. |
| `nca_meta-payload.bin.xz` | `output/nca/v{n}/db/snapshot/` | The exact serialized R objects, xz-compressed. Committed. |
| `cObsData`, `doseData`, `ncaRes`, `res_wide`, `halflife_fit` | calling script's environment | Restored by `read_nca_db()` after the hash check. |
| metadata list | return value of `read_nca_db()` | The `nca_meta` row without the blob: `project_number`, `generated_at`, `r_version`, `pknca_version`, `source_file_path`, `source_file_hash`, `payload_hash`. |

`nca_meta` also holds `ncares_blob`, the serialized list of the five R objects. This is the
full-fidelity restore path: factors and the `PKNCAresults` object do not survive the flat
SQL tables unchanged.

## How to use it

You rarely call these functions by hand. `new_version("nca")` scaffolds scripts that
already do it.

1. Scaffold a version (pk-project). `analysis-nca.R` already ends with `write_nca_db()`:

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   new_version("nca")
   ```

2. The write call in `analysis-nca.R` looks like this:

   ```r
   source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
   write_nca_db(
     project_number = 1L, pkDataPath = pkDataPath,
     cObsData = cObsData, doseData = doseData, ncaRes = ncaRes,
     res_wide = res_wide, halflife_fit = halflife_fit
   )
   ```

3. Every downstream script reads the results back:

   ```r
   source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
   db_meta <- read_nca_db(1L)   # assigns cObsData, doseData, ncaRes, res_wide, halflife_fit
   ```

4. Query one or several versions with SQL, without restoring R objects:

   ```r
   query_nca_db("SELECT project_number, avg(cmax) AS mean_cmax
                 FROM nca_res_wide GROUP BY project_number ORDER BY project_number")
   list_nca_db_versions()      # which versions have a database, and when they were written
   ```

   Dotted parameter names need double quotes in SQL, for example `"half.life"`. A single
   version's table is also reachable as `v1.nca_res_wide`.

Typical prompts: "Save the v1 NCA results so the tables do not re-run PKNCA", "Compare Cmax
between NCA v1 and v2", "Which NCA versions have a database?".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `scripts/nca_db.R` | Source this file; it defines every function below. |
| `write_nca_db()` | Writes the five objects and the metadata row. Replaces that version's rows, so re-running is safe. Also writes the committed snapshot. |
| `read_nca_db()` | Verifies `payload_hash`, then assigns the objects. Returns the metadata invisibly. Rebuilds the `.duckdb` from the snapshot on a fresh clone. |
| `query_nca_db(sql, project_numbers = NULL)` | Attaches every version's file read-only and exposes each table as a `UNION ALL` view. |
| `list_nca_db_versions()` | Lists versions with `generated_at`, `pknca_version`, `source_file_path`, `payload_hash`. |
| `nca_db_path(n)` | Path of a version's file, `output/nca/v{n}/db/nca.duckdb`. |
| `references/schema.md` | Column list of every table. |

## Rules and checks

- One database file per version. Writing one version never opens another version's file.
- Writing is idempotent per version: `write_nca_db()` deletes that version's rows first.
- The hash is taken before SQL. `payload_hash` is computed on the serialized objects before
  they are written to tables; `read_nca_db()` checks it before assigning anything and stops
  on a mismatch.
- `read_nca_db()` warns (does not stop) when the source data file has changed since the
  write. The results may then be stale.
- Every connection is closed with `dbDisconnect(con, shutdown = TRUE)`. DuckDB locks its
  file while a connection is open.
- Only `analysis-nca.R` computes. Other scripts read with `read_nca_db()` (AGENTS.md).
- The spec records the database by `payload_hash`, not by file hash, because DuckDB
  rewrites the file on every connection.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `IO Error: Could not set lock on file` | A connection was left open (crashed script, another R session). Close other sessions. Delete a stray `.duckdb.wal` only after confirming no process holds the lock. |
| `NCA database not found` or `No version N found` | `write_nca_db()` never ran for that version. Run `analysis-nca.R` for it first. |
| Hash verification failed | The blob does not match `payload_hash` (corrupted file, or rows written outside `write_nca_db()`). Re-run `analysis-nca.R`. |
| Warning that the source data file has changed | The data file changed after the write. Re-run `analysis-nca.R` if the results should reflect it; under the project rules a data change means a new version. |

The skill was verified against `duckdb` 1.5.0 and `DBI` 1.2.3. Re-check the SQL syntax if
errors look like API drift.

## Related

- [pk-nca](pk-nca.md): produces the objects this skill stores.
- [pk-nca-tables](pk-nca-tables.md) and [pk-nca-figures](pk-nca-figures.md): read them back.
- [pk-nca-run-spec](pk-nca-run-spec.md): records the database entry as `data.nca_db`.
- [SKILL.md](../../.posit/assistant/skills/pk-nca-database/SKILL.md)
- [NCA workflow guide](../pk-nca/README.md)

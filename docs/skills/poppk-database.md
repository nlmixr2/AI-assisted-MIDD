# `poppk-database`

Saves a popPK version's nlmixr2 fits to one DuckDB database per version, tagged with a
content hash. Figure, table, spec and QC scripts read the fits back from it instead of
refitting. It is the popPK counterpart of [pk-nca-database](pk-nca-database.md).

## When it is used

- At the end of `analysis-poppk.R`, after the final model is selected (the
  [poppk-estimation](poppk-estimation.md) template already does this).
- At the top of every `tbl-*.R`, `fig-*.R` and `generate-spec.R` of a popPK version.
- You want fits saved for reuse, mention a "database", "db", "duckdb" or "saveFit", or ask how
  to avoid refitting for tables, figures or reports.
- For NCA results use [pk-nca-database](pk-nca-database.md). Simulation results are stored by
  [poppk-simulation](poppk-simulation.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `poppk.duckdb` | `output/poppk/v{n}/db/` | Local working store (git-ignored): six SQL tables plus the serialized R objects |
| `<table>.parquet` | `output/poppk/v{n}/db/snapshot/` | Every SQL table as zstd Parquet (committed) |
| `poppk_meta-payload.bin.xz` | `output/poppk/v{n}/db/snapshot/` | The exact serialized R objects, xz-compressed (committed) |
| `pkData`, `fits`, `runs`, `final_run`, `final_rationale`, `fit` | the calling R environment | Objects assigned by `read_poppk_db()`; `fit` is `fits[[final_run]]` |

The six tables, all keyed by `project_number` (and `run_id` except `poppk_meta`):

| Table | One row per |
|---|---|
| `poppk_meta` | version: timestamps, R and nlmixr2 versions, source file path and hash, final run, `payload_hash`, serialized payload |
| `poppk_runs` | run in the model-building trail: OFV, AIC, BIC, n, parameters, dOFV vs parent, covariance OK, final |
| `poppk_parameters` | THETAs and residual-error parameters per run, from `fit$parFixedDf` (no OMEGA rows; the parameter table in `poppk-tables` adds those) |
| `poppk_omega` | OMEGA matrix element per run |
| `poppk_eta` | individual ETA per run |
| `poppk_fitdata` | observation per run: `TIME`, `DV`, `PRED`, `IPRED`, `RES`, `IRES`, `IWRES`, `CWRES` (`NA` when not available for the method) |

The full column list is in [references/schema.md](../../.posit/assistant/skills/poppk-database/references/schema.md).

## How to use it

1. Write, at the end of `analysis-poppk.R`:

   ```r
   source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
   write_poppk_db(project_number, pkDataPath = pkDataPath, pkData = pkData,
                  fits = fits, runs = runs, final_run = final_run,
                  final_rationale = final_rationale)
   ```

   Re-running replaces that version's rows.
2. Read, at the top of every downstream script:

   ```r
   db_meta <- read_poppk_db(project_number)   # assigns pkData, fits, runs, final_run, final_rationale, fit
   ```

   The restored fits are full nlmixr2 objects: `vpcPlot()`, `augPred()` and `rxSolve()` work
   on them in a fresh session.
3. Query with SQL when you do not need the fit objects, for example across versions:

   ```r
   query_poppk_db("SELECT project_number, run_id, objf, delta_ofv, final FROM poppk_runs ORDER BY 1, 2")
   list_poppk_db_versions()
   ```

Typical prompts: "Show the OFV trail of every popPK version", "Which run is final in v2?",
"Make a new figure from the v1 fit without refitting".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `write_poppk_db(project_number, pkDataPath, pkData, fits, runs, final_run, final_rationale = NA_character_, output_dir = "output/poppk")` | Writes one version's fits, run summary and dataset; returns `db_path`, `project_number`, `payload_hash` |
| `read_poppk_db(project_number, output_dir = "output/poppk", envir = parent.frame(), verify_source = TRUE)` | Verifies the payload hash, assigns the objects, returns the `poppk_meta` row (without the blob) |
| `query_poppk_db(sql, project_numbers = NULL, output_dir = "output/poppk")` | Read-only SQL across versions; each table is a view over all versions, one version is `v1.poppk_runs` |
| `list_poppk_db_versions()` | Versions with a database, when written, nlmixr2 version, final run, source file |
| `poppk_db_path()`, `poppk_db_connect()` | Path of a version's file; open a connection (close it with `dbDisconnect(con, shutdown = TRUE)`) |
| `scripts/poppk_db.R` | All the helpers above |
| `db_snapshot_write()`, `db_snapshot_restore()` | Write and restore the committed snapshot (`pk-project/scripts/db_snapshot.R`) |

## Rules and checks

- Fit only in `analysis-poppk.R`. Every other script reads with `read_poppk_db()`.
- The payload (`pkData`, `fits`, `runs`, `final_run`, `final_rationale`) is serialized once and
  `payload_hash` is the hash of those bytes. The SQL tables are a flattened view only.
- `read_poppk_db()` stops if the payload fails its hash check, and warns if the source data
  file changed since the version was written.
- `write_poppk_db()` stops if the data file is missing, if `final_run` is not in
  `names(fits)`, or if `runs$run_id` and `names(fits)` differ.
- For SAEM fits, access `fit$objf` before writing so the OFV is stored in the object.
  `summarise_runs()` does this.
- One file per version. Writing v2 never opens v1's file.
- On a fresh clone there is no `.duckdb`. `read_poppk_db()` and `query_poppk_db()` rebuild it
  from the snapshot, and the payload hash check proves it matches what the analysis wrote.
- `generate-spec.R` records the database in the spec as `data.poppk_db`. A later
  `payload_hash` mismatch means `analysis-poppk.R` was re-run after the spec; QC fails until
  `generate-spec.R` is re-run.
- Size is about 2 MB per fit for small datasets. Keep exploratory runs out of the versioned
  trail.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Could not set lock on file` | A connection is open in another session. Close it |
| `No version N found in ...` | `analysis-poppk.R` never completed for that version. Run it |
| `... failed hash verification` | Corrupted file, or rows written outside `write_poppk_db()`. Re-run `analysis-poppk.R` |
| Warning `Source data file ... has changed` | The data changed after the fit. Refit as a new version if the change is intended |
| `runs$run_id and names(fits) differ` | `run_info` and `models` are out of sync in `analysis-poppk.R` |

Verified against duckdb 1.5.5, DBI 1.2.3 and nlmixr2 7.0.1.

## Related

- [poppk-estimation](poppk-estimation.md): fits the models and writes the database
- [poppk-tables](poppk-tables.md), [poppk-run-spec](poppk-run-spec.md), [poppk-qc-tests](poppk-qc-tests.md): read it
- [poppk-simulation](poppk-simulation.md): simulates from a version's stored fit
- [pk-nca-database](pk-nca-database.md): the NCA equivalent
- [SKILL.md](../../.posit/assistant/skills/poppk-database/SKILL.md)
- [PopPK workflow guide](../poppk/README.md)

---
name: poppk-database
description: Stores every nlmixr2 fit of a popPK version in a hash-verified DuckDB database, so tables, figures and QC reuse the fits without refitting. Use when saving, reading or querying popPK fits, or when the user mentions the popPK database or DuckDB.
---

# PopPK results database (DuckDB)

Companion to `poppk-estimation`; the popPK counterpart of `pk-nca-database` (same design,
same rules). `analysis-poppk.R` writes, everything downstream reads.

## Core Process

A canonical, verified-working copy of every function lives in
`file:///{skill_dir}/scripts/poppk_db.R` — source it rather than reimplementing.

1. **Write**, at the end of `analysis-poppk.R`, after the final model is selected:

```r
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
write_poppk_db(project_number, pkDataPath = pkDataPath, pkData = pkData,
               fits = fits, runs = runs, final_run = final_run, final_rationale = final_rationale)
```

   Idempotent per `project_number` — re-running replaces that version's rows.

2. **Read**, at the top of every `tbl-*.R`/`fig-*.R`/`generate-spec.R`:

```r
read_poppk_db(project_number)   # assigns pkData, fits, runs, final_run, final_rationale, fit (= fits[[final_run]])
```

   Verifies the payload hash before assigning anything; warns if the source data file
   changed since the version was written. The restored fits are full nlmixr2 objects —
   `vpcPlot()`, `augPred()`, `rxSolve()` work on them in a fresh session.

3. **Query with SQL** when full fit objects aren't needed — e.g. across versions:

```r
query_poppk_db("SELECT project_number, run_id, objf, delta_ofv, final FROM poppk_runs ORDER BY 1, 2")
# across every analysis type, with QC state and script runs: query_project_db() (pk-project)
list_poppk_db_versions()
```

## Schema

Six tables keyed by `project_number` (+ `run_id`): `poppk_meta` (one row per version:
timestamps, nlmixr2 version, source-file provenance, final run, payload hash, serialized
BLOB), `poppk_runs`, `poppk_parameters`, `poppk_omega`, `poppk_eta`, `poppk_fitdata`.
Full column list: `file:///{skill_dir}/references/schema.md`.


## Committed snapshot (the `.duckdb` file is not committed)

The `.duckdb` file is a **local working store**: it is binary, grows on every rewrite, and is
git-ignored. Every write also produces a compact snapshot next to it, which **is** committed:

- `db/snapshot/<table>.parquet`: every SQL table as zstd Parquet, readable without this project
  (R `arrow`/`duckdb`, Python `pandas`/`polars`, DuckDB CLI);
- `db/snapshot/<meta>-payload.bin.xz`: the exact serialized R objects, xz-compressed (Parquet
  cannot hold R objects such as the PKNCA results or nlmixr2 fits).

On a fresh clone, `read_*_db()` and `query_*_db()` find no `.duckdb` and rebuild it from the
snapshot (`db_snapshot_restore()`, `pk-project/scripts/db_snapshot.R`). The usual
`payload_hash` check then proves the rebuilt payload is byte-identical to what the analysis
wrote, so the spec, QC suites and reports work unchanged. In the ABC-111 example the committed
databases shrank from 186 MB of `.duckdb` to 15 MB of snapshots.

## Rules

- **Always close with `dbDisconnect(con, shutdown = TRUE)`** (the helpers do, via `on.exit()`) — DuckDB locks its file.
- **Hash the serialized bytes, before SQL.** The payload (`pkData`, `fits`, `runs`, `final_run`, `final_rationale`) is serialized once; `payload_hash` is the hash of those bytes, and the BLOB is the full-fidelity restore. SQL tables are a flattened, queryable view only.
- **Access `fit$objf` before writing** for SAEM fits (`summarise_runs()` does) so the OFV is computed and cached inside the stored object.
- One file per version (`output/poppk/v{n}/db/poppk.duckdb`): writing v2 never opens v1's file.
- Size: ~2 MB per fit for small datasets; a version with many large fits can reach hundreds of MB — keep exploratory runs out of the versioned trail.

## Linking to poppk-run-spec

`generate-spec.R` records the database as `data.poppk_db` (path, project_number,
generated_at, payload_hash) from `read_poppk_db()`'s return value. A `payload_hash`
mismatch later means `analysis-poppk.R` was re-run (or the file corrupted) after the spec
was written — the QC tests fail until `generate-spec.R` is re-run.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `Could not set lock on file` | a connection left open in another session; close it |
| "No version N found" | `analysis-poppk.R` never completed for that version |
| hash verification failed | corrupted file or rows written outside `write_poppk_db()`; re-run `analysis-poppk.R` |
| stale-source warning | the data file changed after the fit; refit as a new version if the change is intended |
| "runs$run_id and names(fits) differ" | `run_info` and `models` out of sync in `analysis-poppk.R` |

Verified against duckdb 1.5.5 / DBI 1.2.3 / nlmixr2 7.0.1.

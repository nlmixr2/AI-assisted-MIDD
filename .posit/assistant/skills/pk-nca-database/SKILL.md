---
name: pk-nca-database
description: Stores a version's NCA results in a hash-verified DuckDB database, so tables, figures and reports reuse them without re-running PKNCA. Use when saving, reading or querying NCA results, or when the user mentions the NCA database or DuckDB.
---

# NCA results database (DuckDB)

Companion to the `pk-nca` skill: takes the objects `analysis-*.R` builds
(`cObsData`, `doseData`, `ncaRes`, `res_wide`, `halflife_fit`) and writes them to a
per-version DuckDB file, `output/nca/v{project_number}/db/nca.duckdb`, alongside that
version's `tables/`, `figures/` and `logs/` (this project's version-number convention —
see `pk-nca`'s "Versioned run scripts & provenance"). Every table still carries a
`project_number` column, and `query_nca_db()` attaches all versions' files at once, so
versions stay joinable/comparable by SQL.

## When to use

Use this skill right after `analysis-*.R`'s Core Process (see `pk-nca`) produces
`ncaRes` and friends, so that:

- Downstream `tbl-*.R`/`fig-*.R` scripts (see `pk-nca-tables`) can load results
  instantly instead of re-running PKNCA.
- A report, TFL, or ad-hoc analysis can query results — across one or several
  versions — directly with SQL, without R at all if needed.
- `pk-nca-run-spec` can record the database (path, version, content hash) as part of
  that version's provenance record (see Linking to pk-nca-run-spec below).

### When NOT to use

For one-off, exploratory NCA where nothing downstream needs to reuse the results,
skip this — writing to the database is only worth it for a versioned, reusable
analysis (see `pk-nca`'s Versioned run scripts & provenance section for when that
threshold is crossed).

## Core Process

A canonical, verified-working copy of every function below lives in
`file:///{skill_dir}/scripts/nca_db.R` — source it rather than reimplementing.

1. **Write**, at the end of `analysis-*.R`, right after `halflife_fit` is built:

```r
source("{skill_dir}/scripts/nca_db.R")   # adjust the relative path to the skill directory

write_nca_db(
  project_number = 1L, pkDataPath = pkDataPath,
  cObsData = cObsData, doseData = doseData, ncaRes = ncaRes,
  res_wide = res_wide, halflife_fit = halflife_fit
)
```

   Writing is idempotent per `project_number` — re-running `analysis-*.R` for the
   same version cleanly replaces that version's rows rather than duplicating them.

2. **Read**, at the top of every `tbl-*.R`/`fig-*.R`/`generate-spec.R` script,
   *instead of* `source("script/nca/v{project_number}/analysis-nca.R")`:

```r
source("{skill_dir}/scripts/nca_db.R")
read_nca_db(1L)   # assigns cObsData/doseData/ncaRes/res_wide/halflife_fit into
                  # this script's environment -- no PKNCA re-run
```

   `read_nca_db()` verifies a content hash before assigning anything (see Rules
   below) and returns the `nca_meta` row (minus the blob) invisibly — capture it
   when you need the metadata itself (e.g. in `generate-spec.R`; see Linking to
   pk-nca-run-spec).

3. **Query directly with SQL** when full R objects aren't needed — e.g. a report
   comparing Cmax across versions:

```r
query_nca_db("SELECT project_number, avg(cmax) AS mean_cmax
              FROM nca_res_wide GROUP BY project_number ORDER BY project_number")
```

   `query_nca_db()` attaches every `output/nca/v*/db/nca.duckdb` it finds (or only
   `project_numbers = c(1, 2)`) and exposes each table as a `UNION ALL` view across
   them; a single version's table is also reachable as `v1.nca_res_wide`.
   `list_nca_db_versions()` is a shortcut for "which versions have a database, and
   when were they written."
   For one query across NCA, popPK and simulation versions together (plus QC state and
   every script run), use `query_project_db()` on `output/project.duckdb` (pk-project).

## Schema

See `file:///{skill_dir}/references/schema.md` for the full table-by-table column
list. Six tables, all keyed by `project_number`: `nca_meta` (one row per version:
timestamps, package version, source-file provenance, content hash, and a serialized
BLOB of the exact R objects), `nca_conc`, `nca_dose`, `nca_result` (long-format,
mirrors `ncaRes$result`), `nca_res_wide`, `nca_halflife_fit`.


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

- **Always pair a connection with `dbDisconnect(con, shutdown = TRUE)`** (every
  function in `scripts/nca_db.R` already does this via `on.exit()`) — DuckDB locks
  its file while a connection is open; a connection left open, or disconnected
  without `shutdown = TRUE`, can leave the file locked for the next script/session.
- **Hash before SQL, not after.** `write_nca_db()` computes `payload_hash` from the
  serialized bytes of the R objects *before* writing them to DuckDB tables, because round-tripping
  through SQL can change types (e.g. a factor becomes `VARCHAR`). The hash — and a
  full-fidelity restore — come from the serialized BLOB in `nca_meta`, not from
  re-hashing the flattened SQL tables.
  `read_nca_db()` verifies the BLOB's hash, then unserializes it, before assigning
  anything, and separately warns (does not error) if the recorded source data
  file's hash no longer matches what's on disk — a legitimate but worth-surfacing
  sign that results may be stale.
- **Writing is idempotent per version, not accumulating duplicates.**
  `write_nca_db()` deletes that `project_number`'s existing rows in every table
  before inserting — safe to re-run `analysis-*.R` after a fix.
- **Dotted PKNCA column names (`half.life`, `aucinf.obs`, ...) need no renaming** —
  DuckDB accepts them as quoted identifiers directly; `scripts/nca_db.R` already
  quotes them in its `CREATE TABLE` statements.

## Linking to pk-nca-run-spec

`generate-spec.R` should record this database as part of the version's provenance,
not just its rendered tables/figures. Capture `read_nca_db()`'s return value (or
`write_nca_db()`'s, if called in the same script) and add it to the spec's `data`
block as `data.nca_db`:

```r
db_meta <- read_nca_db(project_number)   # or reuse write_nca_db()'s return value

spec$data$nca_db <- list(
  path = nca_db_path(project_number),    # output/nca/v{project_number}/db/nca.duckdb
  project_number = db_meta$project_number,
  generated_at = db_meta$generated_at,
  payload_hash = db_meta$payload_hash
)
```

See the `pk-nca-run-spec` skill's `references/schema.md` for the full `data.nca_db`
field description and a worked example, and its Gotchas for what a `payload_hash`
mismatch implies (each version has its own database file under `output/nca/v{n}/db/`,
so a later version's write never opens or changes an earlier version's file).


## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `IO Error: Could not set lock on file` | A previous connection wasn't closed with `shutdown = TRUE` (e.g. a crashed script, or a connection held open in another R session). Close other sessions/connections; as a last resort, delete a stray `.duckdb.wal` file only after confirming no process holds the lock. |
| `read_nca_db()` errors: "No version N found" | `write_nca_db()` was never run for that `project_number` — run `analysis-nca.R` for that version first. |
| `read_nca_db()` errors: hash verification failed | The BLOB doesn't match `payload_hash` — corrupted file, or a row inserted outside `write_nca_db()`. Regenerate via `analysis-nca.R`. |
| `read_nca_db()` warns about a stale source file | Expected when `data/pk-data.csv` (or the version's source file) legitimately changed after this version was written — re-run `analysis-nca.R` if you want the database to reflect it. |
| `dbWriteTable()` fails on a dotted column name | Shouldn't happen — DuckDB auto-quotes; if it does, check the installed `duckdb` R package version against what this skill was verified with (see below). |

## References

- Skill reference: `scripts/nca_db.R` — canonical, verified-working
  `write_nca_db()`/`read_nca_db()`/`query_nca_db()`/`list_nca_db_versions()`; source
  rather than reimplementing.
- Skill reference: `references/schema.md` — full table-by-table column list.
- DuckDB R API: https://r.duckdb.org/ ; `?duckdb`, `?dbWriteTable`, `?dbGetQuery`
- Related project skills: `pk-nca` (produces the objects this skill persists),
  `pk-nca-tables` (its `tbl-*.R` templates should `read_nca_db()` rather than
  re-running the analysis), `pk-nca-run-spec` (records this database's provenance
  in a version's spec — see Linking to pk-nca-run-spec above).

Verified against `duckdb` 1.5.0 / `DBI` 1.2.3 — re-check `CREATE TABLE`/parameter-
binding syntax if errors look like API drift.

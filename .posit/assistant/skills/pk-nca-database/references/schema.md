# NCA DuckDB schema

`output/nca/v{project_number}/db/nca.duckdb` — one file per version, created by
`write_nca_db()`. Every table still carries a `project_number INTEGER` column, so
`query_nca_db()` can attach several versions' files and `UNION ALL` them into one
view per table for cross-version queries.

## `nca_meta` — one row per version

| Column | Type | Description |
|---|---|---|
| `project_number` | INTEGER (PK) | Version number. |
| `generated_at` | VARCHAR | ISO-8601 timestamp of `write_nca_db()`. |
| `r_version` | VARCHAR | R version the write ran under. |
| `pknca_version` | VARCHAR | Installed PKNCA version at write time. |
| `source_file_path` | VARCHAR | Path to the source data file `analysis-*.R` read (e.g. `data/pk-data.csv`). |
| `source_file_hash` | VARCHAR | `rlang::hash_file()` of that file at write time. |
| `payload_hash` | VARCHAR | `rlang::hash()` of the serialized bytes of the R objects (pre-SQL) — verified by `read_nca_db()` before use. |
| `ncares_blob` | BLOB | `serialize()`d list of `cObsData`, `doseData`, `ncaRes`, `res_wide`, `halflife_fit` — the exact-fidelity restore path (factors, the full `PKNCAresults` object, etc., none of which survive a round trip through the flattened SQL tables below unchanged). |

## `nca_conc` — mirrors `cObsData`

| Column | Type |
|---|---|
| `project_number` | INTEGER |
| `participant` | VARCHAR (a `factor` in R; flattened to text here) |
| `time` | DOUBLE |
| `cObs` | DOUBLE |

## `nca_dose` — mirrors `doseData`

| Column | Type |
|---|---|
| `project_number` | INTEGER |
| `participant` | VARCHAR |
| `time` | DOUBLE |
| `dose` | DOUBLE |
| `route` | VARCHAR |
| `dur` | DOUBLE |

## `nca_result` — mirrors `ncaRes$result` (long format)

| Column | Type | Notes |
|---|---|---|
| `project_number` | INTEGER | |
| `participant` | VARCHAR | |
| `start` | DOUBLE | Interval start. |
| `end` | DOUBLE | Interval end (quoted `"end"` in SQL — not actually reserved in DuckDB, but quoted defensively since `end` is easy to confuse with a keyword). |
| `PPTESTCD` | VARCHAR | Parameter code (e.g. `cmax`, `half.life`). |
| `PPORRES` | DOUBLE | Parameter value. |
| `exclude` | VARCHAR | Exclusion reason, if any (usually `NA`). |

Filter to `end = 'Infinity'` (DuckDB's textual representation once cast, or compare
via `end = 'inf'::DOUBLE`) to match the `pk-nca` skill's "filter to `end == Inf`"
convention when querying this table directly with SQL.

## `nca_res_wide` — mirrors `res_wide`

| Column | Type |
|---|---|
| `project_number` | INTEGER |
| `participant` | VARCHAR |
| `cmax` | DOUBLE |
| `tmax` | DOUBLE |
| `"half.life"` | DOUBLE |
| `"aucinf.obs"` | DOUBLE |
| `"clast.obs"` | DOUBLE |

Dotted column names need double quotes in SQL (`SELECT "half.life" FROM nca_res_wide`);
`dplyr`/`DBI` handle this automatically when queried from R (`` `half.life` `` or plain
`half.life` inside a `dplyr::select()`/`$` accessor both work once the result is a data
frame).

## `nca_halflife_fit` — mirrors `halflife_fit`

| Column | Type |
|---|---|
| `project_number` | INTEGER |
| `participant` | VARCHAR |
| `"half.life"` | DOUBLE |
| `"r.squared"` | DOUBLE |
| `"adj.r.squared"` | DOUBLE |
| `"span.ratio"` | DOUBLE |
| `"lambda.z.n.points"` | DOUBLE |

## Example cross-version query

```sql
SELECT project_number, participant, cmax, "half.life"
FROM nca_res_wide
WHERE "half.life" > 10
ORDER BY project_number, participant;
```

# PopPK database schema (`output/poppk/v{n}/db/poppk.duckdb`)

Every table carries `project_number`; all but `poppk_meta` carry `run_id`.

## `poppk_meta` — one row per version

| Column | Type | Description |
|---|---|---|
| `project_number` | INTEGER PK | version number |
| `generated_at` | VARCHAR | ISO timestamp of the write |
| `r_version`, `nlmixr2_version` | VARCHAR | software provenance |
| `source_file_path`, `source_file_hash` | VARCHAR | data file read by `analysis-poppk.R` and its `rlang::hash_file()` |
| `final_run` | VARCHAR | selected final model's run ID |
| `payload_hash` | VARCHAR | `rlang::hash()` of `payload_blob` |
| `payload_blob` | BLOB | `serialize(list(pkData, fits, runs, final_run, final_rationale))` |

## `poppk_runs` — one row per run (the model-building trail)

`run_id`, `parent_run`, `description`, `est`, `objf`, `aic`, `bic`, `n_id`, `n_obs`,
`n_par` (estimated THETAs + OMEGA elements), `delta_ofv` (vs parent), `cov_ok`
(covariance step succeeded and every structural SE present), `final`.

## `poppk_parameters` — one row per THETA per run (from `fit$parFixedDf`)

`run_id`, `parameter`, `label`, `estimate` (model scale), `se`, `rse`,
`back_transformed`, `ci_lower`, `ci_upper` (back-transformed), `bsv_cv`, `shrink_sd`.

## `poppk_omega` — full OMEGA matrix per run, long format

`run_id`, `eta_row`, `eta_col`, `value`.

## `poppk_eta` — individual ETAs per run, long format

`run_id`, `ID`, `eta`, `value`.

## `poppk_fitdata` — per-observation predictions/residuals per run

`run_id`, `ID`, `TIME`, `DV`, `PRED`, `IPRED`, `RES`, `IRES`, `IWRES`, `CWRES`
(`NA` when a column isn't available for that method).

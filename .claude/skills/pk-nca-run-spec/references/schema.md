# NCA run-spec YAML schema

Full field list for `spec/nca/v{project_number}.yaml`. Fields marked **(auto)** come
from `collect_run_metadata()`/`list_outputs()`/`collect_data_provenance()` in
`scripts/build_spec.R` — don't hand-author these. Fields marked **(fill in)** require
reading the scripts in `script/nca/v{project_number}/` (and their outputs) to populate
correctly.

## Contents

- Top-level provenance fields
- `data`
- `parameters`
- `diagnostics`
- `outputs`
- `qc`
- `report`
- Worked example

## Top-level provenance fields

| Field | Source | Description |
|---|---|---|
| `project_number` | auto | Integer identifying this script version (the `v{project_number}` directory under `script/nca/`). |
| `script_dir` | auto | Relative path to the version's script directory (e.g. `script/nca/v1`). |
| `scripts` | auto | Basenames of every `.R` file found in that directory (e.g. `analysis-nca.R`, `fig-halflife-diagnostics.R`, `fig-ind-conc.R`, `tbl-pk-parameters.R`, `tbl-conc-by-nominal-time.R`), sorted. |
| `script_hashes` | auto | Named map of script basename -> `rlang::hash_file()` of that individual file. |
| `scripts_combined_hash` | auto | Single `rlang::hash()` over `script_hashes`, so the whole directory's content can be fingerprinted in one value. |
| `generated_at` | auto | ISO-8601 timestamp of spec generation. |
| `r_version` | auto | R version the scripts were run under. |
| `packages` | auto | Named map of package -> installed version, detected from `library()`/`require()` calls across every script in the directory. |
| `description` | fill in | One or two sentences: what this version's pipeline does and on what data. |

## `data`

| Field | Description |
|---|---|
| `data.dataset` | Source dataset name (e.g. `"Theophylline PK data (data/pk-data.csv)"`). |
| `data.source_file` | auto (via `collect_data_provenance()`) | `{path, hash}` — the raw data file's path and `rlang::hash_file()` fingerprint at generation time, so a later check can confirm the exact bytes on disk haven't changed. Populate this whenever `analysis-*.R` reads its input from a file (the expected case — see the `pk-nca` skill's NCA Rules); it is independent of `data.hash` below, which fingerprints the *derived* in-memory objects instead. |
| `data.nca_db` | auto (via `pk-nca-database`'s `read_nca_db()`/`write_nca_db()`) | `{path, project_number, generated_at, payload_hash}` — where this version's results live (its own DuckDB file, `output/nca/v{project_number}/db/nca.duckdb`) and their content hash, so a later check can confirm they haven't changed. See the `pk-nca-database` skill's "Linking to pk-nca-run-spec" section and the Gotchas in SKILL.md. |
| `data.concentration_data` | Description of the concentration data object/columns (e.g. `"cObsData: participant, time, cObs"`). |
| `data.dose_data` | Description of the dose data object/columns. |
| `data.route` | Dosing route (e.g. `"extravascular"`). |
| `data.units` | Map: `conc`, `time`, `dose`, `amount` (as passed to `pknca_units_table()`). |
| `data.hash` | auto (via `hash_data()`) | `{combined, components}` — `rlang::hash()` fingerprint of the *derived* input data objects (e.g. the concentration and dose data frames built from `data.source_file`), so a later run can confirm those objects are unchanged. `components` is a named list mirroring the names passed to `hash_data(...)`. If this ever disagrees with a fresh re-derivation from `data.source_file` (same file hash, different `data.hash`), `analysis-*.R`'s own read/transform logic has changed or has a bug — investigate before trusting the run's results. |

## `parameters`

| Field | Description |
|---|---|
| `parameters.interval` | The NCA interval. Use the **string** `"Inf"` for an open-ended end (e.g. `{start: 0, end: "Inf"}`) — R's `yaml` package round-trips this as character, not numeric `Inf`; downstream code should compare `end == "Inf"` rather than expect a numeric value. |
| `parameters.requested` | List of PPTESTCD parameter codes requested (e.g. `[cmax, tmax, half.life, aucinf.obs, clast.obs]`). |

## `diagnostics`

| Field | Description |
|---|---|
| `diagnostics.flagged_subjects` | List of `{id, reason}` — subjects flagged by diagnostic checks (e.g. low λz span ratio from `pk-nca`'s `references/diagnostics.md`). Omit or leave empty if none. Use integer literals (`1L`, not `1`) for `id` when assembling the R list, otherwise they serialize with a trailing `.0`. |
| `diagnostics.notes` | Free-text notes on anything else worth QC's attention. |

## `outputs`

| Field | Description |
|---|---|
| `outputs.tables` | auto file list from `list_outputs(project_number)` — one entry per `tbl-*.R` script in `script/nca/v{project_number}/` that has a matching output file in `output/nca/v{project_number}/tables/` (matched by basename, e.g. `tbl-pk-parameters.R` -> `tbl-pk-parameters.pdf`; see the Gotchas below) — each entry is `{path, description, hash}`: `description` filled in once you know which file is which, `hash` is `rlang::hash_file()` of that file at spec-generation time (auto, via `annotate_outputs()`, same pattern as before). |
| `outputs.figures` | Same, for `fig-*.R` scripts and `output/nca/v{project_number}/figures/`. |

## `qc`

| Field | Description |
|---|---|
| `qc.status` | One of `pending`, `in_review`, `approved`, `rejected`. Default `pending` — do not set to `approved` unless the user explicitly provides sign-off. |
| `qc.reviewer` | `null` until assigned. |
| `qc.reviewed_date` | `null` until reviewed. |
| `qc.notes` | `null` or free text. |

## Consistency hashing

Scripts, data, output files, and the written spec file are all fingerprinted the same
way, with `rlang::hash()`/`hash_file()` (not `tools::md5sum()`), so provenance can be
cross-checked end to end:

- `script_hashes` / `scripts_combined_hash` — hash of each script file in the version
  directory, and one combined hash over all of them.
- `data.source_file.hash` — hash of the raw input data file on disk (e.g.
  `data/pk-data.csv`), via `collect_data_provenance()`.
- `data.hash` — hash of the *derived* in-memory input data objects `analysis-*.R` built
  from that file (`cObsData`/`doseData`), via `hash_data()`. Distinct from
  `data.source_file.hash` — a mismatch between a fresh file hash and this recorded
  value with an unchanged `data.source_file.hash` points to a bug in the script's own
  read/transform step, not a changed input file.
- `outputs.tables[].hash` / `outputs.figures[].hash` — hash of each individual output
  file (table/figure) at spec-generation time. Use `verify_outputs(project_number)` to
  re-hash every file listed in a spec and confirm none have changed since.
- `spec/nca/v{n}.yaml.hash` — a sidecar file (written by `write_spec()`) containing the
  hash of the just-written YAML, so a later copy of the spec can be checked for
  tampering/corruption independent of its own content. Use `verify_spec(project_number)`
  to check a spec file against its sidecar.

## Gotchas: versioned output directories

Output directories mirror script directories: `script/nca/v{n}/` writes only to
`output/nca/v{n}/tables/` and `output/nca/v{n}/figures/`. File names inside carry no
project-number suffix (the version lives in the directory). This means:

- `output/nca/v1/tables/tbl-pk-parameters.pdf` and
  `output/nca/v2/tables/tbl-pk-parameters.pdf` coexist; running v2 never touches v1's
  outputs, so v1's spec keeps describing files that are still on disk.
- A `verify_outputs(N)` hash mismatch therefore means version N's own output was edited
  or regenerated (e.g. its `tbl-*.R` re-run) after the spec was written — regenerate
  the spec or investigate; it is never an expected side effect of another version.
- A `tbl-*.R`/`fig-*.R` that saves to the old shared `output/nca/{tables,figures}/`
  path will be invisible to `list_outputs(N)` and silently omitted from the spec — fix
  the script's save path rather than working around it.
- The NCA results database follows the same rule: `output/nca/v{n}/db/nca.duckdb`.
  Logs go to `output/nca/v{n}/logs/`. Nothing a version produces belongs directly
  under `output/nca/`.

## `report`

| Field | Description |
|---|---|
| `report.title` | Suggested report title (e.g. `"NCA Report — Theophylline — v1"`). |
| `report.template` | Path to a report template if one exists, else `null`. |

## Worked example

```yaml
project_number: 1
script_dir: script/nca/v1
scripts:
  - analysis-nca.R
  - fig-halflife-diagnostics.R
  - tbl-conc-by-nominal-time.R
  - tbl-pk-parameters.R
script_hashes:
  analysis-nca.R: 6b1a5b9c8f7d2e...
  fig-halflife-diagnostics.R: 5b3a7d1c9e4f2a...
  tbl-conc-by-nominal-time.R: 2a7d5c9e1f4b8a...
  tbl-pk-parameters.R: 9c2e4f1a7b6d8e...
scripts_combined_hash: 4f9d2a1e7c3b6...
generated_at: '2026-09-27T17:40:00-0700'
r_version: '4.4.1'
packages:
  PKNCA: 0.12.1
  tidyverse: 2.0.0
  tfrmt: 0.4.0
  docorator: 0.7.0
description: >-
  Non-compartmental analysis of Theophylline single-dose oral PK data
  (data/pk-data.csv): Cmax, Tmax, AUCinf, half-life, and Clast per subject,
  with diagnostic figures and formatted PK-parameter and
  concentration-by-nominal-time tables.
data:
  dataset: Theophylline PK data (data/pk-data.csv)
  source_file:
    path: data/pk-data.csv
    hash: 2b7e4a9c1f6d8a3...
  nca_db:
    path: output/nca/v1/db/nca.duckdb
    project_number: 1
    generated_at: '2026-09-27T17:47:00-0700'
    payload_hash: 3f413a53f8a9b4e38bb830ebef197d6b
  concentration_data: 'cObsData: participant, time, cObs'
  dose_data: 'doseData: participant, time, dose, route, dur'
  route: extravascular
  units:
    conc: mg/L
    time: hr
    dose: mg
    amount: mg
  hash:
    combined: 4f9d2a1e7c3b6...
    components:
      conc: 1a2b3c4d5e6f7...
      dose: 7f6e5d4c3b2a1...
parameters:
  interval:
    start: 0
    end: Inf
  requested:
    - cmax
    - tmax
    - half.life
    - aucinf.obs
    - clast.obs
diagnostics:
  flagged_subjects:
    - id: 1
      reason: 'span.ratio 1.07 (< 2); half-life 14.3 h is an outlier vs. 6.3-9.3 h elsewhere'
    - id: 9
      reason: 'span.ratio 1.86 (< 2)'
    - id: 10
      reason: 'span.ratio 1.55 (< 2)'
  notes: null
outputs:
  tables:
    - path: output/nca/v1/tables/tbl-pk-parameters.pdf
      description: Individual PK parameters by Participant ID, with N/Mean/Median/Min-Max summary rows
      hash: 9c2e4f1a7b6d8e3...
    - path: output/nca/v1/tables/tbl-conc-by-nominal-time.pdf
      description: Concentrations by nominal postdose sample time, with N/Mean/Median/Min-Max/BLQ N/%BLQ summary rows
      hash: 2a7d5c9e1f4b8a6...
  figures:
    - path: output/nca/v1/figures/fig-halflife-diagnostics.pdf
      description: Half-life span-ratio vs. adjusted R-squared diagnostic plot
      hash: 3d8a6c2f9e1b7d4...
qc:
  status: pending
  reviewer: null
  reviewed_date: null
  notes: null
report:
  title: NCA Report — Theophylline — v1
  template: null
```

## `outputs.tables[].display_rds` (optional)

`{path, hash}` of the `gt` object that docorator saved next to a table's PDF
(`tbl-<name>.RDS`), recorded by `display_rds_entry()` in `scripts/build_spec.R`.
`verify_outputs()` checks it when present, and `pk-nca-report` prints this object so the
report's tables are identical to the QC'd ones. Specs written before this field existed
simply lack it.

---
name: pk-nca-run-spec
description: Writes the provenance record (spec) of an NCA version: hashes of its scripts, data, results database and outputs. Use when the user asks for a run spec, provenance or QC metadata for an NCA version.
---

# NCA run-spec YAML generator

For a versioned NCA script directory `script/nca/v{project_number}/` (one
`analysis-*.R` core pipeline, plus one `tbl-*.R` per table and one `fig-*.R` per
figure), produce `spec/nca/v{project_number}.yaml`: a single provenance record used
downstream to auto-generate reports and drive QC (which script version ran, on what
data, with what parameters, producing which outputs, at what QC status).

Naming convention: `project_number` is a positive integer distinguishing pipeline
versions (`script/nca/v1/`, `script/nca/v2/`, ...). One spec file per version — do not
overwrite a prior version's spec when a new version is created; each `project_number`
gets its own file. Outputs are versioned by directory the same way as scripts:
`script/nca/v{project_number}/` writes to `output/nca/v{project_number}/tables/tbl-*.pdf`
and `output/nca/v{project_number}/figures/fig-*.pdf` (file names carry no
project-number suffix — the version lives in the directory).

## Process

1. **Identify `project_number`** (ask the user if ambiguous) and confirm
   `script/nca/v{project_number}/` exists with at least one `.R` file in it.
2. **Collect deterministic metadata** by sourcing `scripts/build_spec.R` and calling
   `collect_run_metadata(project_number)` (hashes every `.R` file in that version's
   directory individually plus a combined hash, timestamp, R version, detected packages
   + installed versions across all scripts) and `list_outputs(project_number)` (resolves
   each `tbl-*.R`/`fig-*.R` script to its output file in
   `output/nca/v{project_number}/tables/`/`output/nca/v{project_number}/figures/` by
   basename match). These come from the filesystem/session
   directly — don't guess them.
3. **Hash the source data file** with `collect_data_provenance(path)` (e.g.
   `collect_data_provenance("data/pk-data.csv")`) — the expected case, since
   `analysis-*.R` should read its input from a file (see the `pk-nca` skill's NCA
   Rules). This records `data.source_file` (path + `rlang::hash_file()`) independent of
   `data.hash` (which fingerprints the *derived* `cObsData`/`doseData` objects via
   `hash_data()`); record both.
4. **Record the NCA results database entry** by sourcing the `pk-nca-database` skill's
   `scripts/nca_db.R` and calling `read_nca_db(project_number)` (or reusing
   `write_nca_db()`'s return value if `analysis-*.R` just ran in the same session) —
   `read_nca_db()` returns `{project_number, generated_at, r_version, pknca_version,
   source_file_path, source_file_hash, payload_hash}`, `write_nca_db()` returns
   `{db_path, project_number, payload_hash}`. Add these, plus `nca_db_path(project_number)`, as `data.nca_db` in
   the spec (see `references/schema.md`).
5. **Fill in semantic fields by reading the scripts**: dataset/description, dose route
   and units, requested PK parameters, and any diagnostic findings worth recording (e.g.
   flagged subjects from `pk-nca`'s `references/diagnostics.md` conventions). See
   `references/schema.md` for the full field list and an annotated example.
6. **Hash each output file** (`hash_file(path)` per table/figure) when assembling the
   `outputs` entries, so the spec records not just which files exist but a fingerprint
   of each one at generation time (see the pk-nca skill's run scripts'
   `annotate_outputs()` for the pattern).
7. **Merge and write**: assemble one list matching the schema and call
   `write_spec(spec, project_number)` to save `spec/nca/v{project_number}.yaml`, then
   `verify_spec(project_number)` and `verify_outputs(project_number)` to confirm the
   spec and its output files are internally consistent before considering the version
   complete.
8. **Create and run the QC-readiness tests** with the companion `pk-nca-qc-tests`
   skill (`create_qc_tests(project_number)` → `tests/nca/v{project_number}/test-nca-qc.R`,
   then `run_qc_tests(project_number)`). The version is ready for QC only when this
   passes; it re-checks everything this spec records, plus log cleanliness and NCA
   result completeness.
9. **Leave QC fields as placeholders** (`status: pending`, reviewer/date `null`) unless
   the user explicitly provides QC review information — this skill drafts the spec, it
   does not perform or fabricate QC sign-off.

## Reference

See `references/schema.md` for the complete YAML schema (field-by-field description)
and a fully worked example.

## Gotchas

- Re-running this skill for the same `project_number` overwrites that version's spec
  file — confirm with the user before regenerating an existing spec.
- **Outputs are versioned by directory.** Every `tbl-*.R`/`fig-*.R` in
  `script/nca/v{n}/` must save into `output/nca/v{n}/{tables,figures}/`, never into a
  shared `output/nca/{tables,figures}/` — otherwise v2 would overwrite v1's outputs and
  v1's spec would no longer describe anything on disk. Because versions don't share
  output paths, a `verify_outputs(n)` hash mismatch means version `n`'s own output was
  edited or regenerated after its spec was written — always worth investigating.
- `collect_run_metadata()` detects packages via `library()`/`require()` calls found
  across every script in the version directory; it cannot see packages loaded
  indirectly (e.g. via `::`). Add those manually to the `packages` field if relevant for
  QC/reproducibility.
- `list_outputs(project_number)` matches each `tbl-*.R`/`fig-*.R` script to an output
  file by basename (e.g. `tbl-pk-parameters.R` -> `tbl-pk-parameters.pdf`) — run the
  version's scripts first if you want the spec to reflect their latest outputs. A
  script with no matching output file yet is silently omitted, not an error.
- `verify_outputs(project_number)` re-hashes every file listed in the spec and errors if
  any hash doesn't match (or the file is missing) — run it after regenerating a spec,
  and re-run it later (e.g. before using a spec to drive a report) to catch a
  table/figure that was edited or regenerated since the spec was written.
- `collect_data_provenance(path)` errors if the file doesn't exist at that path — pass
  the same path `analysis-*.R` actually used to load the data (e.g. `"data/pk-data.csv"`),
  not a guessed one.
- **`data.nca_db` is checked by content hash, not file hash.** The NCA database lives
  with the version's other outputs, at `output/nca/v{n}/db/nca.duckdb`. DuckDB rewrites
  the file on every connection, so the spec records the `payload_hash` of the stored
  R objects rather than a file hash. A `data.nca_db.payload_hash` mismatch means
  `analysis-nca.R` was re-run for that version, or the database was corrupted, after
  the spec was written — always worth investigating.

# `pk-nca-run-spec`

Writes the provenance record of an NCA version, `spec/nca/v{n}.yaml`, with a sidecar hash
file. The spec says which scripts ran, on what data, with which parameters, producing which
outputs, and at what QC status. QC tests and the report are driven from it.

## When it is used

- When you ask to create, update or freeze a "spec", "run spec" or metadata file for an NCA
  version, or mention QC or report metadata for an NCA version.
- As the step after all `tbl-*.R` and `fig-*.R` scripts and before the QC suite.
- Neighbouring tasks: the QC-readiness tests are [pk-nca-qc-tests](pk-nca-qc-tests.md); the
  database entry it records comes from [pk-nca-database](pk-nca-database.md); the popPK
  equivalent is [poppk-run-spec](poppk-run-spec.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `v{n}.yaml` | `spec/nca/` | Script hashes, packages, source-data hash, derived-data hash, the `data.nca_db` entry, units, requested parameters, flagged subjects, hashed outputs, QC placeholders, report title. |
| `v{n}.yaml.hash` | `spec/nca/` | `rlang::hash_file()` of the YAML, so later changes to the spec can be detected. |

Main fields (full list in `references/schema.md`):

- Top level: `project_number`, `script_dir`, `scripts`, `script_hashes`,
  `scripts_combined_hash`, `generated_at`, `r_version`, `packages`, `description`.
- `data`: `dataset`, `source_file` (`path`, `hash`), `nca_db` (`path`, `project_number`,
  `generated_at`, `payload_hash`), `concentration_data`, `nominal_time`, `dose_data`,
  `route`, `units`, `hash` (`combined`, `components`).
- `parameters`: `interval` (end written as the string `"Inf"`), `requested`.
- `diagnostics`: `flagged_subjects` (subjects with span ratio < 2), `notes`.
- `outputs`: `tables` and `figures`, each entry with `path`, `description`, `hash` and,
  when a `.RDS` exists, `display_rds` (`path`, `hash`).
- `qc`: `status: pending`, `reviewer`, `reviewed_date`, `notes`.
- `report`: `title`, `template`.

## How to use it

1. `new_version("nca")` scaffolds `script/nca/v{n}/generate-spec.R` from the skill template.
2. Edit its `EDIT` block if needed: `description`, `dataset`, `dose_data`,
   `diagnostic_notes`. Everything else is collected automatically.
3. Run the version in order. `run_version()` runs `generate-spec.R` after every figure and
   table, then the QC suite:

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   run_version("nca", 1L)
   ```

   Or run the script alone, from the project root, after the other scripts:

   ```sh
   Rscript script/nca/v1/generate-spec.R
   ```

4. Check an existing spec later, for example before a report:

   ```r
   source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")
   verify_spec(1L)      # YAML matches its .hash sidecar
   verify_outputs(1L)   # every listed table and figure (and .RDS) matches its hash
   ```

5. A custom table or figure added with `new_tlf()` is registered in `generate-spec.R`'s
   `output_descriptions` automatically.

Typical prompts: "Generate the spec for NCA v1", "Is the v2 spec still valid?", "Why does
verify_outputs fail for v1?".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `templates/generate-spec.R` | Version script: collects metadata, assembles the spec, writes and verifies it. |
| `collect_run_metadata(n)` | Hashes every `.R` file in `script/nca/v{n}/`, plus a combined hash; R version; packages found in `library()`/`require()` calls. |
| `collect_data_provenance(path)` | Path and `hash_file()` of the raw data file. Errors if the file does not exist. |
| `hash_data(...)` | Hash of the derived objects (`conc = cObsData, dose = doseData`); arguments must be named. |
| `list_outputs(n)` | Finds each `tbl-*.R`/`fig-*.R` output in `output/nca/v{n}/tables/` or `figures/` by base name. |
| `display_rds_entry(path)` | `path` and hash of the `.RDS` next to an output, or `NULL`. |
| `write_spec(spec, n)` | Writes `spec/nca/v{n}.yaml` and its `.hash` sidecar. |
| `verify_spec(n)`, `verify_outputs(n)` | Check the spec against its sidecar, and each output against its recorded hash. |
| `read_nca_db()`, `nca_db_path()` | From pk-nca-database: the metadata for `data.nca_db`. |
| `references/schema.md`, `assets/spec-template.yaml` | Field-by-field description with a worked example; blank annotated scaffold. |

## Rules and checks

- One spec per version. Re-running `generate-spec.R` overwrites that version's spec, so
  confirm before regenerating an existing one. Never edit a version whose spec exists; a
  change means `new_version("nca", from = n)`.
- Never edit a spec by hand, and never set `qc.status: approved`; that is the reviewer's
  sign-off. The script leaves `status: pending` and the reviewer fields `null`.
- Keep the order: analysis, then figures and tables, then `generate-spec.R`, then QC.
  Re-running any earlier script afterwards makes `verify_outputs()` and QC fail until the
  spec is regenerated.
- Outputs are versioned by folder. Every script writes only into `output/nca/v{n}/`. A
  script that saves elsewhere is not found by `list_outputs()` and is silently left out.
- `data.nca_db` is checked by `payload_hash`, not by file hash, because DuckDB rewrites the
  file on every connection. A mismatch means `analysis-nca.R` was re-run, or the database
  was corrupted, after the spec was written.
- `data.source_file.hash` fingerprints the raw file; `data.hash` fingerprints the derived
  `cObsData`/`doseData`. Same file hash but a different `data.hash` points to a change or bug
  in the analysis script's read/transform step.
- The version is ready for QC only when its QC suite passes (`run_qc("nca", n)`).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `verify_outputs()`: hash mismatch | The output was edited or regenerated after the spec. Re-run the version with `run_version()` (in a version not yet under review), or investigate. |
| `verify_spec()`: spec does not match its recorded hash | The YAML was modified after generation. Regenerate it with `generate-spec.R`; do not edit it by hand. |
| A table or figure is missing from `outputs` | Its script has not run yet, or it saved outside `output/nca/v{n}/`, or the file name does not match the script name. Tables are looked up as `.pdf`/`.rtf`/`.docx`, figures as `.png`/`.jpg`/`.jpeg`/`.pdf`/`.rtf`. |
| `Source data file not found` | `collect_data_provenance()` was given a path that does not exist. Use the path the analysis read (the template uses `db_meta$source_file_path`). |
| A package is missing from `packages` | Only `library()`/`require()` calls are detected, not packages used through `::`. If it matters for QC, add it to the `packages` field in the list `generate-spec.R` assembles, not in the YAML. |

## Related

- [pk-nca-database](pk-nca-database.md), [pk-nca-qc-tests](pk-nca-qc-tests.md),
  [pk-nca-report](pk-nca-report.md), [pk-nca-tables](pk-nca-tables.md),
  [pk-nca-figures](pk-nca-figures.md), [pk-project](pk-project.md)
- [SKILL.md](../../.posit/assistant/skills/pk-nca-run-spec/SKILL.md)
- [NCA workflow guide](../pk-nca/README.md)

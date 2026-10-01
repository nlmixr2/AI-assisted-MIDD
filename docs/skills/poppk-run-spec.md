# `poppk-run-spec`

Writes the provenance record of a popPK version: `spec/poppk/v{n}.yaml` plus a `.hash`
sidecar. The spec holds the hashes, the model-building trail and the final model, and it is
what QC and reports check against.

## When it is used

- You ask to create, update or freeze a spec, run spec, provenance record or QC metadata for
  a popPK or nlmixr2 version.
- It runs as the last script of a popPK version (`generate-spec.R`), before the QC suite.
- Use neighbouring skills for other tasks:
  - the QC-readiness suite: [poppk-qc-tests](poppk-qc-tests.md);
  - NCA specs: [pk-nca-run-spec](pk-nca-run-spec.md);
  - simulation specs: [poppk-simulation](poppk-simulation.md), which has its own `generate-spec.R`.

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `v{n}.yaml` | `spec/poppk/` | Scripts and their hashes, R and package versions, source data and model-dataset hashes, the `poppk_db` entry, the model trail, fit archives, the final model, caveats, hashed outputs, QC placeholders |
| `v{n}.yaml.hash` | `spec/poppk/` | `rlang::hash_file()` of the YAML, used to detect edits |
| Run log | `output/poppk/v{n}/logs/` | Log of the `generate-spec` run |

Main blocks of the YAML (field list in `references/schema.md`):

- `data`: dataset name, `source_file` (path and hash), `poppk_db` (path, project number,
  generated time, payload hash), `model_data`, `units`, and `hash` of the model dataset.
- `models`: one entry per run: `run_id`, `parent_run`, `description`, `est`, `objf`,
  `delta_ofv`, `n_par`, `cov_ok`, `model_hash`.
- `fit_archives`: the nlmixr2save fit archives and their hashes.
- `final_model`: `run_id`, `est`, `objf`, `rationale`, `parameters` (estimate, RSE, BSV CV%)
  and `acceptance_checks` (check, status, detail).
- `diagnostics`: `caveats` (warn-level acceptance checks) and free-text `notes`.
- `outputs`: `tables` and `figures`, each with path, description, hash and, for tables,
  `display_rds`.
- `qc`: `status: pending`, reviewer and date empty. `report`: title.

## How to use it

1. `generate-spec.R` is scaffolded with the version by `new_version("poppk")`.
2. Edit only its `EDIT` block: `description`, `dataset`, `model_data` and
   `diagnostic_notes` (for example why a flagged %RSE or shrinkage is acceptable). Units and
   the report title come from `project.yaml`.
3. Set `final_rationale` in `analysis-poppk.R`. The spec reads it from the database, and it
   is required.
4. Run the whole version, so the spec is written after every analysis, figure and table
   script:

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   run_version("poppk", 1L)
   ```

   Or run the script alone after a stale script was re-run:

   ```sh
   Rscript script/poppk/v1/generate-spec.R
   ```

5. The script ends by checking what it wrote:

   ```r
   write_spec(spec, project_number, spec_dir = "spec/poppk")
   verify_spec(project_number, spec_dir = "spec/poppk")
   verify_outputs(project_number, spec_dir = "spec/poppk")
   ```

6. Run the QC suite ([poppk-qc-tests](poppk-qc-tests.md)). The version is ready for QC
   only when it passes.

Typical prompts: "Generate the spec for popPK v1", "Freeze popPK v2 for QC".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `templates/generate-spec.R` | The spec script scaffolded into `script/poppk/v{n}/` |
| `spec_models(runs, fits)` | `models` block: the trail, with a hash of each run's model code |
| `spec_final_model(fit, final_run, checks, rationale)` | `final_model` block: estimates and acceptance checks |
| `spec_caveats(checks)` | Warn-level acceptance checks, for `diagnostics.caveats` |
| `annotate_outputs(paths, descriptions)` | Output entries: path, description, hash, `display_rds` |
| `collect_run_metadata()`, `collect_data_provenance()`, `hash_data()`, `list_outputs()` | Shared helpers from `pk-nca-run-spec/scripts/build_spec.R`, called with the popPK folders |
| `write_spec()`, `verify_spec()`, `verify_outputs()` | Write the YAML and sidecar; check the sidecar hash and every output hash |
| `acceptance_checks(fit)` | From `poppk-estimation/scripts/poppk_checks.R` |
| `fit_archive_entries()`, `fit_dir()` | From `poppk-estimation/scripts/poppk_fits.R`; fill `fit_archives` |
| `references/schema.md` | Field-by-field description of the spec |

## Rules and checks

- Run `generate-spec.R` last. Re-running `analysis-poppk.R` or any `fig-`/`tbl-` script
  afterwards changes a hash, and QC fails until the spec is regenerated.
- A change to data, models or method means a new version (`new_version("poppk", from = n)`).
  Never edit a version whose spec exists.
- Never edit a spec by hand. `verify_spec()` compares it with its `.hash` sidecar.
- Leave `qc.status` as `pending`. This skill drafts provenance; it never signs off QC.
- `final_model.rationale` is required; the QC tests check it.
- The model-code hash is `rlang::hash(deparse(as.function(fit$ui)))`. It fingerprints what
  was fitted, however the script wrote the model.
- Regenerating overwrites `spec/poppk/v{n}.yaml`. Confirm with the user before regenerating
  a spec that is already in QC review.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "does not match its recorded hash" | The YAML was changed after it was written. Regenerate it with `generate-spec.R`; do not edit it |
| "Output file(s) inconsistent with spec" / "hash mismatch" | A table or figure script ran after the spec. Regenerate the spec |
| "popPK database not found" or "No version n found" | Run `analysis-poppk.R` first |
| QC fails on `final_model.rationale` | `final_rationale` is empty in `analysis-poppk.R`; set it and re-run the version |
| An output's `description` is `NA` in the spec | Add it to `output_descriptions` in `generate-spec.R` (`new_tlf()` does this for custom outputs) |

## Related

- [poppk-qc-tests](poppk-qc-tests.md), [poppk-estimation](poppk-estimation.md),
  [poppk-database](poppk-database.md), [poppk-tables](poppk-tables.md),
  [pk-nca-run-spec](pk-nca-run-spec.md), [pk-project](pk-project.md)
- Source: [SKILL.md](../../.posit/assistant/skills/poppk-run-spec/SKILL.md)
- Workflow guide: [Population PK workflow](../poppk/README.md)

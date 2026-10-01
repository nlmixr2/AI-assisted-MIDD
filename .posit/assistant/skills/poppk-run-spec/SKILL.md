---
name: poppk-run-spec
description: Writes the provenance record (spec) of a popPK version: model trail, final model and rationale, estimates, acceptance checks and hashes. Use when the user asks for a run spec, provenance or QC metadata for a popPK version.
---

# PopPK run-spec YAML generator

Companion to `poppk-estimation`; the popPK counterpart of `pk-nca-run-spec`. The generic
provenance helpers are **reused, not copied**: source `pk-nca-run-spec`'s
`scripts/build_spec.R` and point it at the popPK directories. The popPK-specific blocks come
from `file:///{skill_dir}/scripts/poppk_spec.R`.

## Core Process

A verified-working `generate-spec.R` lives in `file:///{skill_dir}/templates/generate-spec.R`
and is scaffolded into `script/poppk/v{n}/` by `new_version("poppk")` (pk-project). Only its
EDIT block (description, dataset, model-data text, notes) needs attention: units and the
report title come from `project.yaml`, and the final-model rationale from the database
(`final_rationale`, set in `analysis-poppk.R`).

1. Load the version (no refit) and helpers:

```r
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_checks.R")
source(".posit/assistant/skills/poppk-run-spec/scripts/poppk_spec.R")
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_fits.R")   # fit_dir(), fit_archive_entries()
db_meta <- read_poppk_db(project_number)
```

   The spec also records the version's nlmixr2save fit archives (`fit_archives =
   fit_archive_entries(fit_dir(project_number))`): every `.zip` under `fits/`, including the
   shared data-free copy, with its path, run ID, kind and hash.

2. Deterministic metadata — every call takes the popPK directories:

```r
meta      <- collect_run_metadata(project_number, script_dir = "script/poppk")
data_file <- collect_data_provenance(db_meta$source_file_path)
data_hash <- hash_data(pkData = pkData)
outputs   <- list_outputs(project_number, script_dir = "script/poppk", output_dir = "output/poppk")
```

3. popPK blocks: `spec_models(runs, fits)` (trail, with a hash of each run's model code),
   `spec_final_model(fit, final_run, checks, rationale)` (estimates + acceptance checks),
   `spec_caveats(checks)` (warn-level checks → `diagnostics.caveats`),
   `annotate_outputs(paths, descriptions)` (path, description, hash per output).
4. Write and verify:

```r
write_spec(spec, project_number, spec_dir = "spec/poppk")
verify_spec(project_number, spec_dir = "spec/poppk")
verify_outputs(project_number, spec_dir = "spec/poppk")
```

5. Create and run the QC-readiness tests with `poppk-qc-tests`
   (`create_poppk_qc_tests(n)`, `run_poppk_qc_tests(n)`). The version is ready for QC only
   when they pass.
6. Leave `qc` as `status: pending`, reviewer/date `null` — this skill drafts provenance; it
   never signs off QC.

## Schema

Field-by-field description: `file:///{skill_dir}/references/schema.md`.

## Gotchas

- Run `generate-spec.R` **last**: re-running `analysis-poppk.R` or any `fig-`/`tbl-` script afterwards changes a hash and the QC tests fail until the spec is regenerated.
- `final_model.rationale` is required (QC tests check it): set `final_rationale` in `analysis-poppk.R`; `generate-spec.R` reads it from the database.
- The model-code hash (`models[].model_hash`) is `rlang::hash(deparse(as.function(fit$ui)))` — it fingerprints what was actually fitted, independent of how the script expressed it (function vs piped edit).
- Regenerating overwrites `spec/poppk/v{n}.yaml` — confirm with the user before regenerating a spec that is already in QC review.

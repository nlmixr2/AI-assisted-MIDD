---
name: poppk-qc-tests
description: Creates and runs the QC-readiness test suite of a popPK version, checking logs, the spec, hashes, the model trail and the final model's acceptance checks. Use when the user asks whether a popPK version is ready for QC, or asks for QC tests.
---

# PopPK QC-readiness tests

Companion to `poppk-estimation`, `poppk-run-spec`, `poppk-database`; the popPK counterpart
of `pk-nca-qc-tests`. One suite per version:

```
tests/poppk/
  v1/test-poppk-qc.R
  v2/test-poppk-qc.R
```

A version is **ready for QC** only when its suite passes with zero failures.

## Core Process

Helpers: `file:///{skill_dir}/scripts/poppk_qc_tests.R`; test body:
`file:///{skill_dir}/assets/test-poppk-qc-template.R`. Generate from the template — don't
hand-write the suite.

1. **Prerequisites**: `analysis-poppk.R` → every `fig-*.R`/`tbl-*.R` → `generate-spec.R`
   have all run for the version.
2. **Generate** (once per version) — `new_version()` (pk-project) already does this when it
   scaffolds a version, so this is only needed for a version created by hand:

```r
source(".posit/assistant/skills/poppk-qc-tests/scripts/poppk_qc_tests.R")
create_poppk_qc_tests(1L)   # writes tests/poppk/v1/test-poppk-qc.R; won't overwrite without overwrite = TRUE
```

3. **Add analysis-specific checks** (optional) under section 9 — e.g. an expected
   covariate in the final model, a parameter within a literature range.
4. **Run** from the project root (or `run_qc(type, n)` / `run_version()` from pk-project):

```r
run_poppk_qc_tests(1L)
# Rscript -e 'source(".posit/assistant/skills/poppk-qc-tests/scripts/poppk_qc_tests.R"); run_poppk_qc_tests(1L)'
```

   Saves a JUnit report to `output/poppk/v{n}/logs/qc-tests-{timestamp}.xml` and errors
   with "NOT ready for QC" on any failure.
5. **On failure, fix the cause** (re-run the stale script, then `generate-spec.R`) — never
   edit the test or the spec to pass, never set `qc.status: approved`.

## What the template checks

| Section | Checks |
|---|---|
| 1. Structure | one `analysis-*.R`, a `generate-spec.R`, ≥1 `tbl-`/`fig-`; every `project_number` and `poppk/v{n}/` path points at this version; every script logs to `output/poppk` |
| 2. Logs | each script's latest log exists, has this `project_number`, reached `nca_log_stop()`, has no `Error` lines |
| 3. Spec | sidecar hash; `project_number`/`script_dir`; description, dataset, report title, final run, rationale, models, units filled; `qc.status` pending/in_review |
| 4. Provenance | spec lists exactly the scripts on disk with matching hashes; source data hash; DB payload/source hashes match the spec; no stale-data warning; model dataset hash |
| 5. Outputs | every `tbl-`/`fig-` has a recorded, non-empty output inside `output/poppk/v{n}/` matching its hash |
| 6. Model trail | spec runs = stored fits; each run's OFV and model-code hash match the fit; finite OFVs; parents exist; dOFV consistent; exactly one final model, same in DB and spec |
| 7b. Fit archives | every run has an nlmixr2save archive matching its recorded hash; the final model's archive reloads with the same OFV and THETAs; the data-free shared copy exists and has no `origData` (skipped for specs that predate archives) |
| 7. Final model | fit used every subject/observation; no acceptance check fails; spec's recorded checks and caveats equal a recomputation |
| 8. Negative controls | tampered spec, modified/missing output, corrupted DB blob each detected (temp copies only) |

## Gotchas

- **Tests dir is `tests/poppk/v{n}/`**, separate from NCA's suites, so version numbers of the two analysis types never collide.
- The suite loads the fits (`read_poppk_db()`) and recomputes acceptance checks — a few seconds per version; no refit.
- "model dataset hash matches the spec" failing means the data was read with a lazy `read_csv()` tibble — see `poppk-estimation` Rules.
- `create_poppk_qc_tests()` refuses to overwrite an existing suite (it may hold hand-added checks).

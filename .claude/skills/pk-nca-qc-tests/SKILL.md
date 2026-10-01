---
name: pk-nca-qc-tests
description: Creates and runs the QC-readiness test suite of an NCA version, checking run logs, the spec, hashes and the plausibility of results. Use when the user asks whether an NCA version is ready for QC, or asks for QC tests.
---

# NCA QC-readiness tests

Companion to `pk-nca`, `pk-nca-run-spec`, `pk-nca-database`, and `pk-nca-logging`.
Each NCA version `script/nca/v{n}/` gets its own test directory `tests/nca/v{n}/`, so
every version can be re-checked independently at any time (e.g. just before a QC
reviewer picks it up, or before a report is built from its spec):

```
tests/nca/
  v1/test-nca-qc.R
  v2/test-nca-qc.R
  ...
```

NCA and popPK suites live side by side (`tests/nca/v{n}/`, `tests/poppk/v{n}/`), so the
version numbers of the two analysis types never collide.

A version is **ready for QC** only when its suite passes with zero failures.

## Core Process

Helpers live in `file:///{skill_dir}/scripts/qc_tests.R`; the test body lives in
`file:///{skill_dir}/assets/test-nca-qc-template.R`. Don't hand-write the suite —
generate it from the template so every version is checked the same way.

1. **Prerequisites**: the version has been fully run — `analysis-nca.R`, every
   `tbl-*.R`/`fig-*.R`, then `generate-spec.R` (`spec/nca/v{n}.yaml` + `.hash` exist).
2. **Generate** the suite (once per version) — `new_version()` (pk-project) already does this when it
   scaffolds a version, so this is only needed for a version created by hand:

```r
source(".posit/assistant/skills/pk-nca-qc-tests/scripts/qc_tests.R")
create_qc_tests(2L)   # writes tests/nca/v2/test-nca-qc.R; refuses to overwrite unless overwrite = TRUE
```

3. **Add analysis-specific checks** (optional) under section 8 of the generated file
   — e.g. expected number of subjects, a known dose, a protocol-specified parameter.
4. **Run** it from the project root (or `run_qc("nca", n)` / `run_version()` from pk-project):

```r
run_qc_tests(2L)
# or: Rscript -e 'source(".posit/assistant/skills/pk-nca-qc-tests/scripts/qc_tests.R"); run_qc_tests(2L)'
```

   This prints progress, saves a JUnit XML report to
   `output/nca/v{n}/logs/qc-tests-{timestamp}.xml` (the record to hand the QC
   reviewer), and errors with "NOT ready for QC" if anything failed.
5. **Report** the result to the user. On failure, fix the cause (usually re-run the
   stale script, then `generate-spec.R`) — never edit the test or the spec to make it
   pass, and never set `qc.status` to `approved` (that's the reviewer's sign-off).

## What the template checks

| Section | Checks |
|---|---|
| 1. Structure | one `analysis-*.R`, a `generate-spec.R`, ≥1 `tbl-`/`fig-` script; every `project_number` and `nca/v{n}/` path in every script points at this version; every script is bookended by `nca_log_start()`/`nca_log_stop()` |
| 2. Execution logs | each script's latest log exists, has this `project_number`, reached `nca_log_stop()` (`# sessionInfo():`), and contains no `Error` lines |
| 3. Spec | sidecar hash verifies; `project_number`/`script_dir` match; description, dataset, report title, route, source path, requested parameters, and units are filled in; `qc.status` is `pending`/`in_review` |
| 4. Provenance | spec lists exactly the scripts on disk with matching hashes; source data hash matches; DB `payload_hash` and source-file hash match the spec; no stale-data warning; `cObsData`/`doseData` hashes match |
| 5. Outputs | every `tbl-`/`fig-` script has a recorded output, inside `output/nca/v{n}/`, non-empty, matching its hash |
| 6. Results | inputs well-formed (no NA, conc ≥ 0, dose > 0, dose per participant, no duplicate times); every participant has every requested parameter, finite; plausibility (positive Cmax/AUC/t½/CL/Vz, Tmax within sampling window, Clast ≤ Cmax); no excluded results; spec's flagged subjects = span ratio < 2 |
| 7. Negative controls | tampered spec, modified/missing output, and corrupted DB blob are each detected (temp copies only — the real bundle is never modified) |

## Gotchas

- **Order matters**: re-running any script after `generate-spec.R` changes a hash (or
  the DB payload), so the suite fails until `generate-spec.R` is re-run. That is the
  intended signal — the spec no longer describes what's on disk.
- **A failing "finite" check for `half.life`/`aucinf.obs`** usually means λz couldn't
  be estimated for a subject. Resolve it in the analysis (and document it in the spec's
  diagnostics) rather than loosening the test.
- `testthat::test_dir()` changes the working directory to `tests/nca/v{n}/`; the template
  resets it to the project root via `here::here()`, and `run_qc_tests()` writes the
  JUnit report to an absolute path for the same reason.
- `create_qc_tests()` won't overwrite an existing suite (it may hold hand-added
  checks); pass `overwrite = TRUE` only after copying those checks out.

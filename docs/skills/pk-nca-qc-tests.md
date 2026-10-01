# `pk-nca-qc-tests`

Creates and runs a testthat suite for one NCA version that says whether the version is ready
for QC. A version is ready for QC only when its suite passes with zero failures.

## When it is used

- You ask for QC tests, QC readiness, "is v2 ready for QC", or tests for an NCA version.
- As the last step of a version, after `generate-spec.R` has written the spec.
  `run_version("nca", n)` (`pk-project`) runs it for you at the end.
- Use [poppk-qc-tests](poppk-qc-tests.md) for a popPK version. Simulation versions have their
  own suite in [poppk-simulation](poppk-simulation.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `test-nca-qc.R` | `tests/nca/v{n}/` | The version's QC-readiness suite, generated from the skill template |
| `qc-tests-{timestamp}.xml` | `output/nca/v{n}/logs/` | JUnit report of each run: which checks passed. This is the record for the QC reviewer |

## How to use it

1. Run the whole version first: `analysis-nca.R`, every `tbl-*.R` and `fig-*.R`, then
   `generate-spec.R` (so `spec/nca/v{n}.yaml` and its `.hash` exist).
2. Generate the suite. `new_version("nca")` already does this, so you only need it for a
   version created by hand:

   ```r
   source(".posit/assistant/skills/pk-nca-qc-tests/scripts/qc_tests.R")
   create_qc_tests(2L)   # writes tests/nca/v2/test-nca-qc.R
   ```

3. Optional: add study-specific checks under section 8 of the generated file (for example
   the expected number of subjects, a known dose, or a protocol-specified parameter).
4. Run it from the project root:

   ```r
   run_qc_tests(2L)
   # or, through pk-project:
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   run_qc("nca", 2L)
   ```

   It prints progress, writes the JUnit report, and stops with "NOT ready for QC" if any
   test failed.
5. On failure, fix the cause (usually re-run the stale script, then `generate-spec.R`).

Typical prompts: "Is NCA v2 ready for QC?", "Run the QC tests for NCA v1", "Add a check that
v3 has 12 subjects".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `create_qc_tests(project_number, tests_dir = "tests/nca", overwrite = FALSE)` | Writes `tests/nca/v{n}/test-nca-qc.R` from the template. Refuses to replace an existing suite unless `overwrite = TRUE` |
| `run_qc_tests(project_number, tests_dir = "tests/nca", output_dir = "output/nca")` | Runs the suite, saves the JUnit report, errors if anything failed |
| `run_qc("nca", n)` | Same run, called from `pk-project` |
| `scripts/qc_tests.R` | The two helpers above |
| `assets/test-nca-qc-template.R` | The test body. `{{project_number}}` is replaced by the version number |

What the template checks:

| Section | Checks |
|---|---|
| 1. Structure | one `analysis-*.R`, a `generate-spec.R`, at least one `tbl-`/`fig-` script; every `project_number` and `nca/v{n}/` path points at this version; every script calls `nca_log_start("<script-name>"` and `nca_log_stop()` |
| 2. Execution logs | each script's latest log exists, has this `project_number`, reached `nca_log_stop()`, and has no `Error` lines |
| 3. Spec | sidecar hash verifies; `project_number` and `script_dir` match; description, dataset, report title, route, source path, requested parameters and units are filled in; `qc.status` is `pending` or `in_review` |
| 4. Provenance | spec lists exactly the scripts on disk, with matching hashes; source data hash matches; database `payload_hash` and source file match the spec; no stale-data warning; `cObsData`/`doseData` hashes match |
| 5. Outputs | every `tbl-`/`fig-` script has a recorded output inside `output/nca/v{n}/`, non-empty, matching its hash |
| 6. Results | inputs well formed (no NA, concentrations >= 0, doses > 0, a dose per participant, no duplicate times); every participant has every requested parameter, finite; plausible values (positive Cmax, AUC, half-life, CL, Vz; Tmax within the sampling window; Clast <= Cmax); no excluded results; the spec's flagged subjects are those with span ratio < 2 |
| 7. Negative controls | a tampered spec, a modified or missing output, and a corrupted database blob are each detected. These use temporary copies; the real files are never modified |

## Rules and checks

- Generate the suite from the template. Do not hand-write it, so every version is checked
  the same way.
- Never edit a test or the spec to make the suite pass. Fix the cause instead.
- Never set `qc.status` to `approved`. That is the QC reviewer's sign-off.
- Order matters. Re-running any script after `generate-spec.R` changes a hash (or the
  database payload), so the suite fails until `generate-spec.R` is re-run. This is the
  intended signal that the spec no longer describes what is on disk.
- `create_qc_tests()` will not overwrite a suite, because it may hold hand-added checks.
  Copy those checks out before using `overwrite = TRUE`.
- `testthat::test_dir()` changes the working directory. The template resets it to the
  project root with `here::here()`, and `run_qc_tests()` writes the report to an absolute
  path.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Hash checks fail after you re-ran a figure or table script | The spec is stale. Re-run `generate-spec.R`, then the suite (or re-run the whole version with `run_version()`) |
| "finite" check fails for `half.life` or `aucinf.obs` | Lambda z could not be estimated for a subject. Resolve it in the analysis and record it in the spec's diagnostics; do not loosen the test |
| `No tests for v{n} -- run create_qc_tests(n) first.` | The version has no suite. Run `create_qc_tests(n)` |
| `... already exists -- pass overwrite = TRUE to replace it.` | A suite already exists. Keep it, or copy out its hand-added checks before overwriting |
| Log checks fail ("reached nca_log_stop()", "no errors") | A script stopped early or logged an error. Read its latest log in `output/nca/v{n}/logs/` and re-run it |

## Related

- [pk-project](pk-project.md): `new_version()`, `run_version()`, `run_qc()`, `project_status()`
- [pk-nca-run-spec](pk-nca-run-spec.md): writes the spec the suite checks
- [pk-nca-database](pk-nca-database.md): the results database the suite reads
- [pk-nca-logging](pk-nca-logging.md): the run logs the suite checks
- [pk-nca-report](pk-nca-report.md): needs a passing QC run before it renders
- [SKILL.md](../../.posit/assistant/skills/pk-nca-qc-tests/SKILL.md)
- [NCA workflow guide](../pk-nca/README.md)

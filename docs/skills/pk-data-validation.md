# `pk-data-validation`

Inspects a PK dataset and validates its column mapping before NCA or popPK. Wrong columns,
dose codes and units are the commonest source of a wrong analysis. This skill replaces
guessing with two scripted steps: describe the file, then validate the mapping with
pointblank.

## When it is used

- Before mapping any new dataset in `data/`.
- In every `analysis-nca.R` and `analysis-poppk.R`: both templates already call it in
  their data `EDIT` block.
- When you mention data checks, data validation, data QC, pointblank, NONMEM-format data,
  EVID or CMT coding, or BLQ records.
- When an analysis fails on a column or coding problem.
- Mapping the validated columns to PKNCA objects is covered by [pk-nca](pk-nca.md); mapping
  them to an nlmixr2 model by `poppk-estimation`.

## What it produces

| File or object | Location | Contents |
|---|---|---|
| Printed description | console and the script's run log | column types, missing counts, example values, number of subjects, record counts by `EVID` x `CMT` (and `MDV`, `DVID`, `CENS`, `BLQ` when present), time range, name-based hints for nominal-time and BLQ/LLOQ columns |
| Printed result line | console and the run log | `Data validation: N checks, 0 failed` |
| Validation report | `output/{type}/v{n}/logs/data-validation-<timestamp>.html` | pointblank report of every check, with extracts of failing rows |
| pointblank agent | returned invisibly by `validate_pk_data()` | the interrogated agent |

## How to use it

1. Read the file from `data/`, the way the analysis template does:
   - popPK: `read_csv(pkDataPath, show_col_types = FALSE, lazy = FALSE) |> as.data.frame()`.
     The model dataset itself is hashed, and a lazy readr tibble hashes differently in
     every R session.
   - NCA: `read_csv(pkDataPath, show_col_types = FALSE)`. The spec hashes the file and the
     derived `cObsData`/`doseData`.
2. Describe it, and map columns from this output only:

```r
source(".posit/assistant/skills/pk-data-validation/scripts/pk_data_checks.R")
describe_pk_data(pkData, pkDataPath)
```

3. Pick the layout. **event**: dose and observation records told apart by `EVID`
   (NONMEM/rxode2 style). **sample**: one row per sample, dose in a column, no `EVID`
   (single-dose data only).
4. Confirm what the file cannot tell you: units, route of administration, whether a dose
   column is per kg, and the dosing time when there are no dose rows.
5. Validate. In a scaffolded version this is the `EDIT` block of the analysis script:

```r
validate_pk_data(pkData, layout = "event",
                 cols = pk_cols(id = "ID", time = "TIME", dv = "DV", amt = "AMT",
                                evid = "EVID", cmt = "CMT"),
                 covariates = c("WT"),                       # popPK: covariates in any model
                 report_dir = sprintf("output/%s/v%d/logs", "nca", project_number),
                 label = basename(pkDataPath))
```

   For the sample layout: `layout = "sample", cols = pk_cols(id = "Subject", time = "Time",
   dv = "conc", dose = "Dose")`. Set a role to `NA` when the dataset has no such column
   (for example `cmt = NA`).
6. Report the printed result line, the layout and the mapping used.

Typical prompts: "describe the dataset in data/", "which column is the dose?", "validate
the data for NCA v2", "why does the analysis fail on EVID?".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `describe_pk_data(data, path = NULL)` | prints the facts needed to map columns; returns the column table invisibly |
| `pk_cols(id, time, dv, amt, evid, cmt, mdv, dose)` | column mapping: names are roles, values are the dataset's columns |
| `validate_pk_data(data, layout, cols, covariates, report_dir, label)` | runs the pointblank checks; stops on any failure; writes the HTML report when `report_dir` is set |
| `scripts/pk_data_checks.R` | the two functions above; run them, do not rewrite them |
| `references/checks.md` | the check list and how to add study-specific checks |
| `references/data-layouts.md` | event and sample layouts, `EVID` codes, BLQ and missing values |

## Rules and checks

- Map columns only from `describe_pk_data()` output. If a role has no column, say so.
- Dose rows are `EVID != 0` with `AMT > 0`. Do not assume `EVID == 1`: rxode2-style data
  use 101, and 4 is reset-and-dose.
- Event layout checks: TIME, DV, AMT, EVID numeric; no missing ID, TIME, EVID; TIME >= 0;
  TIME non-decreasing within each subject (file order); observation rows (EVID 0, and
  MDV 0 when mapped) have DV, and DV >= 0; no dose amount on EVID 0 rows; every subject
  has a dose record and an observation; no duplicate (ID, TIME, EVID[, CMT]) rows.
- Sample layout checks: time, concentration, dose numeric; no missing ID, time, dose;
  time >= 0; concentration >= 0 (missing allowed); dose > 0; one dose value per subject;
  no duplicate (ID, time) rows.
- With `covariates =`, every listed covariate must be present on every row.
- Every check must pass; there is no failure threshold. Never drop, loosen or skip a check
  without the user's agreement. Add study-specific checks only with limits the user or
  protocol gave (see `references/checks.md`).
- Never edit the file under `data/`: it is the hashed source. A new or corrected data file
  is a new version (`new_version(type, from = n)`).
- Keep BLQ samples in the file. How they are handled is an analysis choice for the user.
- The HTML report is a log: the spec does not hash it, and it is never deleted.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Layout 'event' needs a column for: ...` | A required role is `NA` in `pk_cols()`. Map it, or use the other layout. |
| `Columns not found: ...` | The mapping names a column the data does not have. Run `describe_pk_data()` and fix `pk_cols()`. |
| `Package 'pointblank' is required` | `install.packages("pointblank")`. |
| `Data validation failed:` with a list of steps | Each line gives the check and the number of failing rows. Open the HTML report in `logs/` for the rows, or reproduce the step, e.g. `dplyr::filter(pkData, EVID == 0, is.na(DV))`. Fix the mapping, or tell the user what is wrong in the data. |
| "Every subject has a dose record" fails | Missing doses or a wrong EVID code; check the record counts from `describe_pk_data()`. |
| "Observation rows have DV" fails | Missing samples not flagged. If they are BLQ, the file needs a BLQ flag or `MDV = 1`; ask rather than impute. |

## Related

- [pk-nca](pk-nca.md), [pk-project](pk-project.md), [pk-nca-logging](pk-nca-logging.md)
- Source: [SKILL.md](../../.posit/assistant/skills/pk-data-validation/SKILL.md)
- Workflow guides: [NCA](../pk-nca/README.md), [popPK](../poppk/README.md)

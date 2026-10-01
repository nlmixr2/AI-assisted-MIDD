# Validation checks

Companion to [../SKILL.md](../SKILL.md). `validate_pk_data()` runs these pointblank
checks. Each must pass (no failure threshold), because one bad record can change an
individual's parameters.

## Event layout

| # | Check | Catches |
|---|---|---|
| 1 | TIME, DV, AMT, EVID numeric | text values, `"<LLOQ"` strings, bad import |
| 2 | ID, TIME, EVID not missing | incomplete records |
| 3 | TIME >= 0 | pre-dose times coded negative (ask how to handle) |
| 4 | TIME non-decreasing within subject, in file order | records out of time order, usually a merge or time-derivation error |
| 5 | Observation rows (EVID 0, MDV 0) have DV | missing samples not flagged |
| 6 | Observation DV >= 0 | sign errors, log-scale DV |
| 7 | AMT 0 or missing on EVID 0 rows | dose records miscoded as observations |
| 8 | Every subject has a dose record (EVID != 0, AMT > 0) | missing doses, wrong EVID code |
| 9 | Every subject has an observation | dose-only subjects |
| 10 | No duplicate (ID, TIME, EVID[, CMT]) rows | double-entered records |
| 11 | Covariates not missing (when `covariates =` given) | covariates that break an nlmixr2 fit |

## Sample layout

| # | Check |
|---|---|
| 1 | time, concentration, dose numeric |
| 2 | ID, time, dose not missing |
| 3 | time >= 0 |
| 4 | concentration >= 0 (missing allowed) |
| 5 | dose > 0 |
| 6 | one dose value per subject (single-dose layout) |
| 7 | no duplicate (ID, time) rows |

## Adding study-specific checks

`validate_pk_data()` returns the interrogated agent invisibly. For checks that depend
on the study (dose levels, sampling window, weight range), build them in the analysis
script's data `EDIT` block with the same pattern, using values the user gave:

```r
pointblank::create_agent(pkData, label = "Study-specific checks") |>
  pointblank::col_vals_in_set(columns = "AMT", set = c(0, 100, 200, 400)) |>   # protocol doses
  pointblank::col_vals_between(columns = "WT", left = 40, right = 150) |>      # user-supplied range
  pointblank::interrogate() |>
  pointblank::all_passed() |>
  stopifnot()
```

Never add a limit the user or protocol did not give.

## Reading a failure

The error lists each failing step with its label and number of failing rows. Open the
HTML report in `logs/` for the failing rows (the report shows extracts), or reproduce a
step directly, e.g. `dplyr::filter(pkData, EVID == 0, is.na(DV))`.

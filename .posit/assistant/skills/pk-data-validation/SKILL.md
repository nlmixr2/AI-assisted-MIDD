---
name: pk-data-validation
description: Inspects and validates PK datasets before NCA or popPK: describes the columns, EVID/CMT coding and BLQ records, then runs pointblank checks that stop on bad data. Use when mapping a new dataset, checking data quality, or when an analysis fails on a column or coding problem.
---

# Validating PK analysis data

Wrong columns, dose codes and units are the commonest source of a wrong analysis, and
they are exactly what a model is tempted to guess. This skill replaces the guess with
two scripted steps: **describe** the file, then **validate** the mapping with pointblank.
Both live in `scripts/pk_data_checks.R`. Run them; do not rewrite them.

Requires `pointblank` and `dplyr` (`install.packages("pointblank")`).

## Workflow

Copy this checklist and tick it off:

```
Data validation:
- [ ] 1. Read the file from data/ (lazy = FALSE, as.data.frame())
- [ ] 2. describe_pk_data(): map columns from its output
- [ ] 3. Confirm the mapping, units, route and per-kg dosing with the user
- [ ] 4. validate_pk_data(): every check passes
- [ ] 5. Report what was checked, quoting the printed result
```

**1. Read the file** from `data/` (never an in-memory object, so it can be hashed), the way
the analysis template does:

- **popPK** (`analysis-poppk.R`): `read_csv(pkDataPath, show_col_types = FALSE, lazy = FALSE) |> as.data.frame()`.
  Required there because the model dataset itself is hashed, and a lazy readr tibble
  hashes differently in every R session.
- **NCA** (`analysis-nca.R`): `read_csv(pkDataPath, show_col_types = FALSE)`, as in the
  template. The spec hashes the file and the derived `cObsData`/`doseData`, not `pkData`.

Both functions below accept either a tibble or a data frame.

**2. Describe it.** Map columns from this output, not from examples or memory:

```r
source(".posit/assistant/skills/pk-data-validation/scripts/pk_data_checks.R")
describe_pk_data(pkData, pkDataPath)
```

It prints each column's type, missing count and example values, the number of subjects,
record counts by `EVID` x `CMT` (and `MDV`, `DVID`, `CENS`, `BLQ` when present), the time
range, and any nominal-time or BLQ/LLOQ columns. Pick the layout:

- **event**: dose and observation records told apart by `EVID` (NONMEM/rxode2 style).
- **sample**: one row per sample, dose in a column, no `EVID` (e.g. theophylline).

Coding rules for both: [references/data-layouts.md](references/data-layouts.md).

**3. Ask for what the file cannot tell you.** Units, route of administration, whether a
dose column is per kg, and the dosing time when there are no dose rows come from the
user or `project.yaml`. Tell the user which column you mapped to each role.

**4. Validate.** Stops with the failing checks listed; writes
`logs/data-validation-<timestamp>.html`:

```r
validate_pk_data(pkData, layout = "event",
                 cols = pk_cols(id = "ID", time = "TIME", dv = "DV", amt = "AMT",
                                evid = "EVID", cmt = "CMT"),
                 covariates = c("WT"),                       # popPK: covariates in any model
                 report_dir = sprintf("output/%s/v%d/logs", "nca", project_number),
                 label = basename(pkDataPath))
```

For the sample layout: `layout = "sample", cols = pk_cols(id = "Subject", time = "Time",
dv = "conc", dose = "Dose")`. The check list and how to add study-specific checks:
[references/checks.md](references/checks.md).

If a check fails, fix the mapping, or tell the user what is wrong in the data. Never drop,
loosen or skip a check to get a pass without the user's agreement, and never edit the
file under `data/` (it is the hashed source).

**5. Report** the printed line (`Data validation: N checks, 0 failed`), the layout and
mapping used, and anything you asked the user to confirm.

## Where it runs

`templates/analysis-nca.R` (`pk-nca`) and `templates/analysis-poppk.R`
(`poppk-estimation`) call both functions in their data `EDIT` block, so every scaffolded
version validates its data before PKNCA or nlmixr2 runs. Mapping the validated columns to
PKNCA objects is covered by `pk-nca` (`references/pipeline.md`); to an nlmixr2 model by
`poppk-estimation`.

## Rules

- Map columns only from `describe_pk_data()` output. If a role has no column, say so.
- Dose rows are `EVID != 0` with `AMT > 0`. Do not assume `EVID == 1`: rxode2-style data
  use 101, and 4 is a reset-and-dose.
- A new or corrected data file is a new analysis version (`new_version(type, from = n)`).
- The HTML report is a log: it is not hashed by the spec and is never deleted.

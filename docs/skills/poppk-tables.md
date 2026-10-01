# `poppk-tables`

Builds the production tables of a popPK version: the final-model parameter table and the
model-development (OFV trail) table. It reads the fits from the version's database, so the
tables never refit a model, and it checks the parameter table against the model and the data.

## When it is used

- You ask for a popPK parameter table, or a summary of fixed effects, random effects or
  residual error.
- You ask for a model comparison, run log or model-development table.
- You want report-ready tables for an nlmixr2 analysis.
- Use neighbouring skills for other tasks:
  - fitting models and diagnostic figures: [poppk-estimation](poppk-estimation.md);
  - NCA tables: [pk-nca-tables](pk-nca-tables.md);
  - a custom table: `new_tlf()` from [pk-project](pk-project.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `tbl-parameters.pdf` | `output/poppk/v{n}/tables/` | Final-model parameters in three sections: fixed effects, random effects (with OMEGA correlations), residual unexplained variability |
| `tbl-model-comparison.pdf` | `output/poppk/v{n}/tables/` | One row per run: N par, OFV, dOFV, AIC, BIC, covariance step; `*` marks the final model |
| `tbl-*.RDS` | `output/poppk/v{n}/tables/` | The gt object behind each table; the spec records it as `display_rds` |
| Run logs | `output/poppk/v{n}/logs/` | One log per script run |

Tables are written as RTF instead of PDF when TinyTeX is not installed.

### The parameter table

`scripts/poppk_param_table.R` builds the rows in three sections that follow the model's
`ini({})` block:

1. **Fixed effects.** Every THETA that is not a residual-error parameter. Shows the
   back-transformed estimate, %RSE and 95% CI. A fixed THETA gets "(fixed)" and no RSE.
2. **Random effects (between-subject variability).** Every ETA: variance (omega^2), CV%
   and shrinkage (SD%), labelled "BSV on <THETA label>". An ETA with no mu-referenced THETA
   is labelled "BSV <eta name>" and has no CV%. Then every OMEGA-block correlation, labelled
   "Correlation: <label> ~ <label>".
3. **Residual unexplained variability.** Every residual-error parameter. An unlabelled one
   gets a label from its error type (for example "Additive residual SD").

Row labels come from `label()` in the model. A parameter without a label shows its model name.

## How to use it

1. The table scripts are scaffolded with the version. Run from the project root:

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   new_version("poppk")          # includes tbl-parameters.R and tbl-model-comparison.R
   ```

2. In `script/poppk/v{n}/tbl-parameters.R`, edit only the `EDIT` block (title and
   subtitle) if needed. Fix labels in the model's `ini({})`, not in the table script.
3. Run the whole version in order (analysis, figures and tables, spec, QC):

   ```r
   run_version("poppk", 1L)
   ```

   To run one table script only: `run_version("poppk", 1L, only = "tbl-parameters.R")`.
   Then regenerate the spec, because the table's hash has changed.
4. After changing `poppk_param_table.R`, run its scenario tests (no nlmixr2 needed):

   ```r
   testthat::test_file(".posit/assistant/skills/poppk-tables/tests/test-poppk-param-table.R")
   ```

   They cover: diagonal OMEGA with additive error; OMEGA block, combined error, fixed THETA
   and covariate THETA; an ETA without a mu-referenced THETA; fit/data mismatch; table/model
   mismatch; missing labels. They read `examples/abc-111/data/pk-data-2.csv`.

Typical prompts: "Make the parameter table for popPK v1", "Show the model-development table
with OFV and dOFV".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `templates/tbl-parameters.R` | Final-model parameter table script |
| `templates/tbl-model-comparison.R` | Model-development table script |
| `poppk_param_inputs(fit)` | Takes what the table needs from the fit (`iniDf`, `parFixedDf`, `omega`, mu-referencing, participant and observation counts) |
| `poppk_param_rows(inputs)` | Builds the long rows of the three sections |
| `check_param_table(rows, inputs, pkData)` | Stops unless the table matches the model and the data; returns the footnote text |
| `data_obs_rows(pkData)` | Marks observation records (EVID 0 and MDV 0) |
| `read_poppk_db()` | Loads `fit`, `fits`, `runs`, `final_run`, `pkData` (poppk-database) |
| `render_tlf()` | Renders the table in the shared TLF shell (pk-project) |
| `tests/test-poppk-param-table.R` | Scenario tests for the parameter table code |

## Rules and checks

- `check_param_table()` stops the script unless:
  - every THETA, ETA, OMEGA correlation and residual parameter appears exactly once;
  - fixed-effect estimates equal the fit's back-transformed estimates;
  - random-effect variances equal the fit's OMEGA diagonal;
  - participants and observations (EVID 0, MDV 0) equal those in the source data.
  The footnote states the agreed counts.
- Never edit the rows by hand to fix a mismatch. A mismatch means the fit, the database or
  the data file is not the one you think.
- Labels come from the model. Fix unlabelled rows in `ini({})`.
- Say what scale the numbers are on: estimates and CIs are back-transformed; %RSE is on the
  estimation scale. Keep that footnote.
- State the OFV type in the comparison table footnote. OFVs are comparable only when computed
  the same way.
- Build tables with tfrmt (long ARD and `body_plan()`) and render with `render_tlf()`. Never
  hand-build `as_docorator()`.
- Name outputs by basename only (`tbl-parameters.pdf`). The version is in the folder name.
- Every script is logged with `nca_log_start()` / `nca_log_stop()`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "Parameter table is not consistent with the source model/data" | The message lists each problem (missing, extra or duplicated parameter, differing estimates, participant or observation counts). Check which fit, database and data file were used |
| `--` in %RSE for residual rows | Expected for SAEM residual error (no SE computed). Say so in a footnote if it matters |
| Long labels wrap badly | Shorten run descriptions in `run_info`, or pass `gt::cols_width()` to the gt object before `render_tlf()` |
| `Can only handle one format per frmt_structure` | Use one `frmt` (or `frmt_combine` / `frmt_when`) per `frmt_structure()`; split into several |
| RTF instead of PDF | TinyTeX is not installed (`tinytex::install_tinytex()`) |
| Column labels missing or wrong | `parFixedDf` column names differ across nlmixr2 versions; check `names(fit$parFixedDf)` |

## Related

- [poppk-estimation](poppk-estimation.md), [poppk-database](poppk-database.md),
  [poppk-run-spec](poppk-run-spec.md), [poppk-qc-tests](poppk-qc-tests.md),
  [pk-nca-tables](pk-nca-tables.md), [pk-project](pk-project.md)
- Source: [SKILL.md](../../.posit/assistant/skills/poppk-tables/SKILL.md)
- Workflow guide: [Population PK workflow](../poppk/README.md)

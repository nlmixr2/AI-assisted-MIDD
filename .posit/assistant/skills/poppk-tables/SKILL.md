---
name: poppk-tables
description: Creates production popPK tables: the final-model parameter table (fixed effects, random effects, residual variability), checked against the model and data, and the model-development table. Use when the user asks for a popPK parameter table, a run comparison table or popPK TLF tables.
---

# PopPK tables (tfrmt + docorator)

Companion to `poppk-estimation` and `poppk-database`; the popPK counterpart of
`pk-nca-tables`, built the same way: long ARD data → `tfrmt()` body plan → `print_to_gt()` →
the shared TLF shell `render_tlf()` (`pk-project/scripts/tlf_shell.R`, 11 pt serif). The header
has the analysis title and page; the footer has "Source data:", the script path and the
date-time. The shell also loads the shared tfrmt helpers (`fs()`, `frmt_sig3()`,
`tlf_footnotes()`, ...; `pk-project/scripts/tfrmt_helpers.R`), which these templates use.
Each table is one `tbl-*.R` script in `script/poppk/v{n}/`, saving
`output/poppk/v{n}/tables/tbl-*.pdf` (RTF if TinyTeX is unavailable) plus `tbl-*.RDS`, the
gt object, which the spec records as `display_rds`.

## Templates

Verified-working; scaffolded into `script/poppk/v{n}/` by `new_version("poppk")` (pk-project).
Headers use `analysis_title("poppk")`, subtitles `project.yaml`'s study ID:

| Template | Output | Contents |
|---|---|---|
| `file:///{skill_dir}/templates/tbl-parameters.R` | `tbl-parameters.pdf` | final model in three sections mirroring `ini({})` (`scripts/poppk_param_table.R`): **Fixed effects** (every estimated THETA except residual error: back-transformed estimate, %RSE, 95% CI; "(fixed)" without RSE for fixed THETAs), **Random effects** (every ETA: omega², CV% and shrinkage, labelled "BSV on <THETA label>"; then every OMEGA-block correlation), **Residual unexplained variability** (every error parameter). Labels come from the model's `label()`. `check_param_table()` stops the script unless every parameter appears exactly once, estimates equal the fit's, and participants/observations equal the source data's; the footnote states the agreed counts |
| `file:///{skill_dir}/templates/tbl-model-comparison.R` | `tbl-model-comparison.pdf` | one row per run, labelled "runNNN[*] (base / from runMMM): description"; N par, OFV, dOFV (`--` for the base), AIC, BIC, covariance step (Yes/No via `frmt_when`); method in the subtitle |

**Consistency with the source model and data.** `poppk_param_inputs(fit)` takes only the
fit's own records (`iniDf`, `parFixedDf`, `omega`, `ui$muRefTable`, participants and
observations); `poppk_param_rows()` builds the rows from them; `check_param_table(rows,
inputs, pkData)` compares the table with the model (THETA, ETA, correlation and residual
parameters, each exactly once; estimates identical) and with the source data (participants;
observations = EVID 0 and MDV 0 rows). Never edit the rows by hand to fix a mismatch: the
mismatch means the fit, the database or the data file is not the one you think.

Scenario tests (no nlmixr2 needed; run after changing the table code):
`testthat::test_file(".posit/assistant/skills/poppk-tables/tests/test-poppk-param-table.R")`:
diagonal OMEGA with additive error; OMEGA block, combined error, fixed THETA and covariate
THETA; ETA without a mu-referenced THETA; fit/data mismatch; table/model mismatch; missing labels.

Both start with:

```r
source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- 1L
nca_log_start("tbl-parameters", project_number = project_number, output_dir = "output/poppk")
source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()             # titles, study ID, units
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit, fits, runs, final_run -- no refit
```

and end with:

```r
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")
render_tlf(gt_obj, "tbl-parameters", out_dir, cfg, type = "poppk", source_data = db_meta$source_file_path)
```

The parameter table is built by `scripts/poppk_param_table.R` from the final fit (fixed
effects, random effects and correlations, residual error) and checked by
`check_param_table()`. The `poppk_parameters` SQL table (`poppk_parameter_rows()` in
`poppk_db.R`) is a separate, queryable view of each run's `parFixedDf` rows (THETAs and
residual error only, no OMEGA rows).

## Rules

- **Labels come from the model.** Row labels are the `label()` text in `ini({})` (with units); fix unlabeled rows in the model, not in the table script.
- **Say what scale the numbers are on.** Estimates and CIs are back-transformed; %RSE is on the estimation (log) scale — keep the footnote.
- **State the OFV type** in the comparison table footnote (e.g. FOCEi approximation from SAEM + CWRES), since OFVs are only comparable when computed the same way.
- **tfrmt, like the NCA tables.** Build a long ARD (one row per label × statistic), format with a `body_plan()` (`frmt_when()` for significant figures, `frmt_combine()` for CIs, `missing = "--"`), and put free text in the row label, since tfrmt values are numeric.
- **One shell.** Render with `render_tlf()`, never a hand-built `as_docorator()`, so the header and footer (including "Source data:") match every other table and figure.
- Output files are named by basename only (`tbl-parameters.pdf`) — the version lives in the directory, so `list_outputs()` / the QC tests can map script → output.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| Residual/other rows show `--` for %RSE | expected for SAEM residual error (no SE computed); say so in a footnote if it matters |
| Long labels wrap badly | shorten run descriptions in `run_info`, or pass `gt::cols_width()` to the gt object before `render_tlf()` |
| `Can only handle one format per frmt_structure` | one `frmt` (or `frmt_combine`/`frmt_when`) per `frmt_structure()`; split into several structures |
| RTF instead of PDF | TinyTeX not installed (`tinytex::install_tinytex()`) |
| Column labels missing / wrong | `parFixedDf` column names differ across nlmixr2 versions — check `names(fit$parFixedDf)` |

# `poppk-estimation`

Runs a versioned population PK analysis with nlmixr2: a model-building trail with an OFV
trail, acceptance checks on the final model, and diagnostic figures in the shared TLF shell.
It exists so that every popPK fit is logged, stored, reproducible and ready for QC.

## When it is used

- You ask to fit a popPK or PKPD model, run `nlmixr2()`, or mention SAEM/FOCEi, THETA/OMEGA,
  `$parFixed`, shrinkage, VPC, NPDE, a model diagram, `bootstrapFit()` or `profileLlp()`.
- You ask which estimation method to use.
- Use [pk-nca](pk-nca.md) for non-compartmental analysis.
- Use [poppk-simulation](poppk-simulation.md) to simulate from a fit or from a model file.
- Tables come from [poppk-tables](poppk-tables.md); the spec from
  [poppk-run-spec](poppk-run-spec.md); the QC suite from [poppk-qc-tests](poppk-qc-tests.md).
- NONMEM/Monolix/PKNCA backends through babelmixr2 are not covered by these skills.

## What it produces

| File or object | Location | Contents |
|---|---|---|
| Version scripts | `script/poppk/v{n}/` | `analysis-poppk.R`, the seven `fig-*.R` below, `tbl-parameters.R`, `tbl-model-comparison.R`, `generate-spec.R` |
| Results database | `output/poppk/v{n}/db/poppk.duckdb` (+ `db/snapshot/`) | every fit of the trail, the run summary, the final run and its rationale, the dataset ([poppk-database](poppk-database.md)) |
| Fit archives | `output/poppk/v{n}/fits/runNNN.zip` | nlmixr2save cache and portable `saveFit()` archive of each run |
| Shareable fit | `output/poppk/v{n}/fits/shared/<final_run>-noData.zip` | the final fit without subject data |
| Figures | `output/poppk/v{n}/figures/fig-*.pdf` (+ `.RDS`) | diagnostics in the TLF shell (RTF instead of PDF without TinyTeX); the `.RDS` is the exact display object |
| Logs | `output/poppk/v{n}/logs/` | one run log per script, the data-validation HTML report, QC reports |

### Diagnostic figures

Every figure reads the database (no refit) and shows the final model.

| Template | Content |
|---|---|
| `fig-gof.R` | Two pages. Page 1, linear: DV vs PRED, DV vs IPRED (identity line and loess), CWRES vs TIME, CWRES vs PRED (lines at 0, ±2 dotted, ±3 dashed). Page 2: DV vs PRED and DV vs IPRED on log-log axes (zero values omitted), CWRES normal QQ, \|IWRES\| vs IPRED |
| `fig-individual-fits.R` | One page per participant, linear and semi-log panels: observed (points), individual prediction (solid), population prediction (dashed) from `augPred()`; ETAs in the caption. The `n_worst` worst-fitting participants (highest mean \|IWRES\|, default 3) are flagged in the page label |
| `fig-eta.R` | Page 1: histogram with density and normal QQ plot per ETA, SD shrinkage in the panel labels. Page 2 (when the data have baseline covariates): ETA vs each baseline covariate with a loess smooth |
| `fig-vpc.R` | A collection of VPCs, one per page: standard, prediction-corrected and dose-normalized, each against time after first dose and time after dose, each on linear and log y. Standard and prediction-corrected VPCs use `nlmixr2plot::vpcPlot()` / `vpcPlotTad()`; the dose-normalized VPC is computed from one `nlmixr2est::vpcSim()` simulation. Same seed and replicates for all; n, seed and binning in the header subtitle. Time-after-dose pages are skipped when every participant has one dose |
| `fig-traceplot.R` | One page: parameter history by iteration (`nlmixr2plot::traceplot()`). A flat final phase indicates convergence. Methods without an iteration history get a page saying so |
| `fig-pmx-diagnostics.R` | ggPMX (`pmx_nlmixr()`), one topic per page, only what the other figures lack: NPDE vs time, vs PRED and QQ; IWRES density and QQ; random-effect correlations (candidate OMEGA blocks); random effects by categorical covariate. Pages the fit cannot produce are skipped, with a log message |
| `fig-model-diagram.R` | The final model's compartment diagram, drawn from its differential equations by `nlmixr2plot::modelDiagram()`; dosing compartments (from the data) have a heavy border, arrows are labelled with the model terms; the `modelGraph()` nodes and edges go to the log. `modelDiagram()` is new in nlmixr2plot and needs a development version; with an nlmixr2plot that lacks it, the script draws a placeholder page saying the diagram was not drawn, and the version still runs |

Keep `fig_dim` at the shell default `tlf_fig_dim` (`c(4.6, 8)`); a taller figure, including
docorator's own default of 5 in, spills onto an extra blank page.

## How to use it

1. Scaffold a version (or copy an existing one) with [pk-project](pk-project.md):

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   new_version("poppk")              # script/poppk/v{next}/ + tests/poppk/v{next}/
   new_version("poppk", from = 1L)   # or start from v1's trail
   ```

2. Edit the blocks marked `EDIT` in `analysis-poppk.R`:
   - **data**: `pkDataPath`, the column names in `pk_cols()`, and `covariates` used in any model;
   - **models and `run_info`**: a base `run001`, then each child run as a piped edit of its
     parent, with `parent_run` and a description;
   - **method**: `EST` and the control (same for every run);
   - **`final_run` and `final_rationale`**: your decision, copied into the spec.

   A child run looks like this:

   ```r
   run002 <- run001 |>
     model(cl <- exp(tcl + eta.cl + wt_cl * log(WT / 70))) |>
     ini(wt_cl <- 0.75, wt_cl = label("WT exponent on CL/F"))
   ```

3. Optional `EDIT` blocks in the figures: `n_worst` (individual fits), `covariates` (ETA and
   ggPMX figures), VPC types, axes, `n_sim`, `bins`, `seed` (VPC), `show_terms` (diagram).
4. Run the version in order and check its QC suite:

   ```r
   run_version("poppk", 2L)   # analysis -> figures/tables -> generate-spec -> QC suite
   project_status()
   ```

Typical prompts: "Fit a one-compartment model to data/pk-data.csv", "Add a WT effect on CL/F
as a new run", "Which estimation method should I use?", "Show me the VPCs for v2".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `templates/analysis-poppk.R` | Verified pipeline: load and validate data, model trail, fit, compare, acceptance checks, write database, share final fit |
| `templates/fig-*.R` | The seven diagnostic figures above |
| `fit_runs(models, pkData, est, control, table, dir)` | Fits every run with the nlmixr2save cache; returns `fits` and `restored` (`scripts/poppk_fits.R`) |
| `fit_dir(project_number)` | `output/poppk/v{n}/fits` |
| `share_fit(run_id, dir, refitted)` | Writes `fits/shared/<run>-noData.zip` |
| `load_fit_archive(path)` | Loads a fit archive safely from a temporary copy |
| `summarise_runs(fits, run_info)` | One row per run: OFV, AIC, BIC, dOFV and parameter change vs parent, covariance OK (`scripts/poppk_checks.R`) |
| `acceptance_checks(fit, max_rse = 50, max_shrink = 30)` | pass / warn / fail per check |
| `render_poppk_display()`, `theme_pmx()`, `baseline_covariates()`, `worst_fitting()` | Figure helpers (`scripts/poppk_figures.R`) |
| `add_last_dose()`, `vpc_summary()`, `vpc_quantile_plot()` | Dose-normalized VPC helpers |
| `references/` | `estimation-methods.md`, `model-building.md`, `priors.md`, `diagnostics.md` |

### Acceptance checks

| Check | Fails or warns when |
|---|---|
| `ofv_finite` | fail: OFV not finite |
| `covariance_step` | fail: `fit$cov` missing |
| `structural_se_present` | fail: a structural THETA has no SE |
| `theta_not_on_bound` | fail: a THETA sits on its `ini()` bound |
| `structural_rse` | warn: structural %RSE > 50 |
| `eta_shrinkage` | warn: ETA SD shrinkage > 30% |
| `bsv_range` | warn: BSV CV% < 1 or > 100 |
| `residual_error_positive` | fail: a residual-error estimate <= 0 |

A fail stops `analysis-poppk.R` and the QC tests. A warn is recorded as a caveat in the spec
by `generate-spec.R`.

## Rules and checks

- Read the data from a file under `data/` with `read_csv(..., lazy = FALSE) |> as.data.frame()`,
  so its hash is the same in every R session. Validate it first ([pk-data-validation](pk-data-validation.md)).
- Fit only in `analysis-poppk.R`. Every other script starts with `read_poppk_db(project_number)`.
- Fix every seed: `saemControl(seed = )` and the VPC `seed`.
- Use the same estimation method and OFV type for every run in one version. With SAEM,
  `tableControl(cwres = TRUE, npde = TRUE)` adds a FOCEi OFV so runs are comparable, and stores NPDE
  (a fit restored from the nlmixr2save cache cannot add it later).
- Add one ETA or covariate per run, as a new `runNNN` with its `parent_run`. Never edit an
  earlier run in place.
- For nested models, dOFV < -3.84 for one added parameter is about p < 0.05.
- `label()` every THETA with its units. Use log scale for fixed effects (`tcl <- log(2.7)`).
- Do not report SAEM output without confirming SEs exist and inspecting the diagnostics.
- A change to the trail, data or method is a new version. Never edit a version whose spec exists.
- Every script is bookended by `nca_log_start("<script-name>", project_number = n, output_dir = "output/poppk")` and `nca_log_stop()`.
- Fit cache: an unchanged run is restored from `fits/<run>.zip` instead of refitted (the log
  says "restored from cache (unchanged)"). To force a refit, delete that zip. Never edit a zip.
  Use the helpers rather than raw `:=` or `loadFit()`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `parameter not found` at compile | A symbol is not in `ini({})`, not a compartment and not in the data |
| SAEM OFV swings or runs forever | Initial values off scale (missing `log()`), or a covariate missing on some rows |
| FOCEi Hessian or covariance failure | Over-parameterized OMEGA, ETA variance near zero, identifiability. Drop or fix ETAs, try `foceiControl(outerOpt = "nlminb")` or `preconditionFit()` |
| SEs `NA` in `$parFixed` | Covariance step failed. `setCov(fit, "analytic")` (no refit), bootstrap or profile |
| "needs to be a mixed effect model" | Wrong method family for the model (pooled vs mixed effects) |
| `vpcPlot` / `augPred` empty or flat | Residual line missing, `dvid` mismatch, or `CMT` in the data does not match `d/dt(name)` |
| QC test "model dataset hash matches the spec" fails | Data read without `lazy = FALSE` / `as.data.frame()` |
| Model diagram page says "not drawn" | The installed nlmixr2plot has no `modelDiagram()`. Install a newer nlmixr2plot |
| `This nlmixr2plot has no vpcPlotTad()` | Update nlmixr2plot, or drop `"tad"` from `x_axes` in `fig-vpc.R` |

The skill was verified with nlmixr2 7.0.1, nlmixr2est 5.0.2, rxode2 5.1.6 and nlmixr2plot 5.0.0.

## Related

- [poppk-database](poppk-database.md), [poppk-tables](poppk-tables.md), [poppk-run-spec](poppk-run-spec.md), [poppk-qc-tests](poppk-qc-tests.md)
- [poppk-simulation](poppk-simulation.md), [pk-data-validation](pk-data-validation.md), [pk-nca-logging](pk-nca-logging.md), [pk-project](pk-project.md)
- [SKILL.md](../../.posit/assistant/skills/poppk-estimation/SKILL.md)
- [PopPK workflow guide](../poppk/README.md)

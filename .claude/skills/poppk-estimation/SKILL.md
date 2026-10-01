---
name: poppk-estimation
description: Fits population PK models with nlmixr2: step-by-step model building with an OFV trail, estimation method choice (SAEM, FOCEi and others), acceptance checks, and diagnostics such as GOF plots, VPCs, NPDE and model diagrams. Use when the user asks to fit or build a popPK or PKPD model, compare runs, or check model diagnostics.
---

# Population PK estimation with nlmixr2

Adapted from the nlmixr2llm `estimation` skill
(<https://github.com/mattfidler/nlmixr2llm/tree/merge-john-harrold/inst/skills/estimation>),
restructured to follow this project's `pk-nca` conventions: a versioned script directory,
a results database, logged runs, a provenance spec, formatted tables, and QC tests.

## Overview

A complete estimation task has four parts:

1. **Model function** — `function() { ini({...}); model({...}) }` (the rxode2 language plus initial estimates and a residual-error line).
2. **Dataset** — NONMEM-style `ID / TIME / EVID / AMT / CMT / DV` (+ covariates, `DVID`, `CENS` / `LIMIT`), read from a file under `data/`.
3. **Fit** — `nlmixr2(model, data, est = "...", control = ...Control(...))`, one per run in the model-building trail.
4. **Inspection** — `print(fit)`, `fit$parFixed`, `fit$omega`, the acceptance checks, and diagnostics before anything is reported.

Do not stop until the final model has converged, passed its acceptance checks, and been inspected.

### When NOT to use

- Non-compartmental analysis → `pk-nca`.
- Simulation (from a fit of this skill, or from a model file) → `poppk-simulation`; NONMEM/Monolix/PKNCA backends via babelmixr2 are not covered by these skills.

## Core Process

**Scaffold, don't retype** (companion skill `pk-project`):

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
new_version("poppk")              # script/poppk/v{next}/ + tests/poppk/v{next}/ from templates/
new_version("poppk", from = 1L)   # ... or start from an existing version's trail
# edit the blocks marked EDIT (data, models + run_info, method, final_run + final_rationale), then:
run_version("poppk", 2L)          # analysis -> figures/tables -> generate-spec -> QC suite
```

The canonical, verified-working version of steps 1–6 is
`file:///{skill_dir}/templates/analysis-poppk.R`; units and titles come from `project.yaml`.
The worked example `examples/abc-111/script/poppk/v1/` shows a two-run trail
(1-cmt base → WT on CL/F). The steps below explain each block.

1. **Import libraries and start the log** (`pk-nca-logging`, pointed at `output/poppk`):

```r
library(nlmixr2)
library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- 1L
nca_log_start("analysis-poppk", project_number = project_number, output_dir = "output/poppk")
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_checks.R")
```

2. **Read, describe and validate the dataset** with the `pk-data-validation` skill; never
   guess column or compartment names. Read with `lazy = FALSE` and convert to a plain
   `data.frame` (see Rules) so its hash is reproducible, and pass every covariate used in
   any model to `covariates =`:

```r
pkDataPath <- file.path("data", "pk-data-2.csv")
pkData <- read_csv(pkDataPath, show_col_types = FALSE, lazy = FALSE) |> as.data.frame()
source(".posit/assistant/skills/pk-data-validation/scripts/pk_data_checks.R")
describe_pk_data(pkData, pkDataPath)   # EVID x CMT counts: which rows dose / observe, where
validate_pk_data(pkData, layout = "event", cols = pk_cols(cmt = "CMT"), covariates = "WT",
                 report_dir = sprintf("output/poppk/v%d/logs", project_number))
```

   `CMT` values must match the model's `d/dt()` compartments (dose into depot, observe
   central).

3. **Write the model-building trail**: a base model function, then each candidate as a
   *piped edit* of its parent, plus a `run_info` table recording parent and intent:

```r
run001 <- function() {
  ini({
    tka <- log(1.5); label("Ka (1/h)")
    tcl <- log(2.7); label("CL/F (L/h)")
    tv  <- log(30);  label("V/F (L)")
    eta.ka ~ 0.6; eta.cl ~ 0.3; eta.v ~ 0.1
    add.sd <- 0.7;   label("Additive residual SD (mg/L)")
  })
  model({
    ka <- exp(tka + eta.ka); cl <- exp(tcl + eta.cl); v <- exp(tv + eta.v)
    d/dt(depot)  <- -ka * depot
    d/dt(center) <-  ka * depot - cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}
run002 <- run001 |>
  model(cl <- exp(tcl + eta.cl + wt_cl * log(WT / 70))) |>
  ini(wt_cl <- 0.75, wt_cl = label("WT exponent on CL/F"))

run_info <- tribble(
  ~run_id,  ~parent_run, ~description,
  "run001", NA,          "1-cmt, first-order absorption, BSV on Ka/CL/V, additive error",
  "run002", "run001",    "run001 + power WT effect on CL/F (centred at 70 kg)"
)
models <- list(run001 = run001, run002 = run002)
```

4. **Fit every run** with the same method and control, `print = 0`, a fixed `seed`, and
   CWRES in the table (SAEM computes no OFV during the fit; CWRES adds the FOCEi OFV so every
   run's OFV is comparable):

```r
fit_res <- fit_runs(models, pkData, est = "saem",          # scripts/poppk_fits.R
                    control = saemControl(print = 0, seed = 1234),
                    table = tableControl(cwres = TRUE, npde = TRUE),   # NPDE stored in the fit
                    dir = fit_dir(project_number))          # nlmixr2save cache: unchanged runs are restored
fits <- fit_res$fits
```

5. **Compare runs, select the final model, and run the acceptance checks**:

```r
runs <- summarise_runs(fits, run_info)       # OFV, dOFV vs parent, AIC, BIC, cov_ok per run
final_run <- "run001"                         # analyst decision
final_rationale <- "run002 WT effect not supported (dOFV = -0.62, 1 parameter)"   # copied into the spec
runs$final <- runs$run_id == final_run
fit <- fits[[final_run]]
checks <- acceptance_checks(fit)             # pass / warn / fail
if (any(checks$status == "fail")) stop("Final model fails acceptance checks")
```

6. **Persist** to the results database (`poppk-database`), write the shareable data-free copy of the final model, and stop the log:

```r
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
write_poppk_db(project_number, pkDataPath = pkDataPath, pkData = pkData,
               fits = fits, runs = runs, final_run = final_run, final_rationale = final_rationale)
share_fit(final_run, fit_dir(project_number), refitted = !fit_res$restored[[final_run]])  # fits/shared/<run>-noData.zip
nca_log_stop()
```

## Authoring rules

1. **Hand `nlmixr2()` the function itself**, not `model()`; it instantiates internally.
2. **Log / logit scale for fixed effects.** `tcl <- log(2.72)` in `ini`, `cl <- exp(tcl + eta.cl)` in `model`. Use `logit()` / `expit()` for (0, 1) parameters, or `logit(x, low, hi)` / `expit(x, low, hi)` for (low, hi) bounds. Forgetting `log()` is the most common cause of a fit that wanders.
3. **`label()` every THETA** (with units) so `$parFixed`, `tbl-parameters`, and reports are readable.
4. **Random effects** use `~` with a starting *variance*: `eta.cl ~ 0.3`. Correlated ETAs: `eta.cl + eta.v ~ c(0.3, 0.01, 0.1)` (lower-triangle order).
5. **Residual error** ends `model({})`: `cp ~ add(add.sd)`, `prop(prop.sd)`, `add(add.sd) + prop(prop.sd)`, `lnorm(lnorm.sd)`; transforms and heavier tails via `add(add.sd) + boxCox(lambda)` or `add(add.sd) + dt(df)`; a fully custom likelihood via `ll(cp) ~ <log-likelihood expression>` (FOCEi family or SAEM). Multi-endpoint: one line per endpoint bound with `| endpointName` (a bare name matching the `CMT` / `DVID` value).
6. **Bounds / fixed values.** `tcl <- log(c(0, 2.7, 100))` gives lower / initial / upper; `tv <- fixed(log(31.5))` fixes a THETA.
7. **Pick `est=` deliberately** (see table) and always pass the matching control (`saemControl()`, `foceiControl()`, `foceControl()`, `foControl()`, `laplaceControl()`, `agqControl()`, `nlmeControl()`) with `print = 0` and a `seed` in scripts.
8. **Closed-form PK** can use `linCmt()` in place of the ODEs (`linCmt() ~ add(add.sd)`), which is faster for 1–3 compartment linear models.
9. **The model decides the family:** no etas needs a pooled method (`focei`, `nlm`, `nlminb`, `bobyqa`, ...). Full list, variants, and covariance tokens: `references/estimation-methods.md`.
10. **Priors** in `ini({})` work with the FOCEi family, `laplace`/`agq`, `imp`/`impmap`/`qrpem`, `posthoc`, and nlmixr2bayes; other methods refuse them. See `references/priors.md`.

## Estimation methods

| `est=` | Use for |
|---|---|
| `"saem"` | Best when the model has **many** etas; tolerant of poor initials. Computes SEs by default (`covMethod` in `saemControl()`); check they are present. No OFV during the fit: `fit$objf` (Gaussian quadrature) or `tableControl(cwres = TRUE)` / `addCwres(fit)` (FOCEi) adds one — use the same one for every run you compare. |
| `"focei"` | Best when the model has **few** etas. Gradient-based with Hessian SEs; more sensitive to initials and stiffness. Common pattern: SAEM first, then FOCEi from the SAEM estimates. |
| `"foce"`, `"fo"`, `"foi"` | Variants without interaction / first-order; legacy comparison. |
| `"laplace"`, `"agq"` | More accurate likelihoods (`agqControl(nAGQ=)`); only with few ETAs. |
| `"nlme"` | Wraps R's `nlme`; simple closed-form models. |
| `"posthoc"` | Freeze THETA/OMEGA, compute ETAs for (new) data. |
| `"imp"`, `"qrpem"`, `"npag"`, `"vae"`, pooled `"nlm"`/`"bobyqa"`/..., Bayesian `"nuts"` | see `references/estimation-methods.md` / `references/priors.md` |
| `"nonmem"`, `"monolix"`, `"pknca"`, `"nlmer"`, `"saemix"` | babelmixr2 — not covered by these skills; see the babelmixr2 package documentation. |

`nlmixr2est::nlmixr2AllEstType()` lists everything registered, grouped by category.

## Model building

Start simple, add one thing at a time, keep the OFV trail — every candidate is a new
`runNNN` in `models`/`run_info` with its `parent_run`, never an in-place edit of an
earlier run.

- Model piping (`ini()` / `model()` on a function, UI, or fit) is the idiomatic way to derive a child run; it preserves the rest of the model.
- `nlmixr2lib` supplies starting models and edits: `readModelDb("PK_2cmt_des") |> addEta("cl") |> addResErr("propSd")`.
- Nested models: dOFV < −3.84 for one added parameter ≈ p < 0.05 (`runs$delta_ofv`, `runs$delta_par`). Non-nested: AIC/BIC. Only compare OFVs computed the same way.
- Standard errors: `fit$parFixed` shows SE / %RSE; if missing, `setCov(fit, "analytic")` (no refit), `nlmixr2extra::preconditionFit(fit)`, `bootstrapFit()`, or `profileLlp()`. Details in `references/model-building.md`.
- Record the selection decision in `final_rationale` next to `final_run` — it is stored in the database and copied into the spec's `final_model.rationale`.

## Inspecting a fit

| Accessor | Contents |
|---|---|
| `print(fit)` | population estimates, BSV, shrinkage, OFV, timing |
| `fit$parFixed` / `fit$parFixedDf` | formatted / numeric table: estimate, SE, %RSE, back-transformed value, BSV%, shrinkage |
| `fit$omega`, `fit$cov` | BSV variance-covariance; fixed-effect covariance |
| `fit$objf`, `fit$objDf` | OFV / −2LL, AIC, BIC |
| `fit$shrink`, `fit$eta` | shrinkage per ETA; per-ID ETAs |
| `fit$parHist`, `nlmixr2plot::traceplot(fit)` | iteration history (SAEM / FOCEi) |
| `as.data.frame(fit)` | per-row `PRED`, `IPRED`, `IWRES`, `CWRES`, `ETA*` |

### Acceptance checks

`acceptance_checks(fit)` (`scripts/poppk_checks.R`) encodes what must hold before a model is
reported. **fail** blocks reporting (and the QC tests); **warn** must be recorded as a caveat
in the spec (`diagnostics.caveats`, done automatically by `generate-spec.R`).

| Check | Fail / warn when |
|---|---|
| `ofv_finite` | fail: OFV not finite |
| `covariance_step` | fail: `fit$cov` missing |
| `structural_se_present` | fail: a structural THETA has no SE |
| `theta_not_on_bound` | fail: a THETA sits on its `ini()` bound |
| `structural_rse` | warn: structural %RSE > 50 |
| `eta_shrinkage` | warn: ETA SD shrinkage > 30% |
| `bsv_range` | warn: BSV CV% < 1 or > 100 |
| `residual_error_positive` | fail: a residual-error estimate ≤ 0 |

## Diagnostics

Always produce these for the final model before reporting. They follow the diagnostics
checklist in `references/diagnostics.md`. Each template reads the database (no refit) and
renders in the shared TLF shell (`render_tlf()`: analysis title and page header, then the
figure's `title`/`subtitle` as centred header lines, never in the ggplot; "Source data:",
script and date-time footer; 11 pt serif) through `scripts/poppk_figures.R`, using the shared
figure helpers (`theme_pmx()` = `theme_tlf()`, `tlf_out_dir()`, `lab_unit()`;
`pk-project/scripts/figure_helpers.R`):

| Template | Checklist item | Pages |
|---|---|---|
| `templates/fig-gof.R` | 1 Structure, 2 Residuals | 2: linear (DV vs PRED/IPRED, CWRES vs TIME/PRED with ±2/±3 lines); log-log DV vs PRED/IPRED, CWRES QQ, \|IWRES\| vs IPRED |
| `templates/fig-individual-fits.R` | 3 Individuals | one per participant: linear and semi-log, observed/IPRED/PRED, ETAs in the caption; the `n_worst` worst-fitting (mean \|IWRES\|) flagged in the page label |
| `templates/fig-eta.R` | 4 Random effects | 2: ETA histograms and QQ with SD shrinkage; ETA vs baseline covariates (auto-detected with `baseline_covariates()`, EDIT to choose) |
| `templates/fig-vpc.R` | 5 Predictive check | a collection of VPCs, one per page: standard, prediction-corrected and dose-normalized × time after first dose and time after dose × linear and log y (TAD pages skipped when every participant has one dose); same seed and n for all; n, seed and binning in the header subtitle |
| `templates/fig-traceplot.R` | 6 Convergence | 1: parameter history by iteration (`nlmixr2plot::traceplot()`) |
| `templates/fig-model-diagram.R` | Model structure | the final model's compartment diagram from its differential equations (`nlmixr2plot::modelDiagram(engine = "ggplot2", labels = TRUE)`; dosing compartments from the data); `modelGraph()` nodes and edges in the log. A placeholder page if the installed nlmixr2plot has no `modelDiagram()` |
| `templates/fig-pmx-diagnostics.R` | 2, 4 Residuals, random effects | ggPMX (`pmx_nlmixr()`), one topic per page, only what the other figures lack: NPDE vs time, vs PRED and QQ; IWRES density and QQ; random-effect correlations (OMEGA-block candidates); random effects by categorical covariate. Pages whose plots the fit cannot produce are skipped, with a log message |

Keep `fig_dim` at the shell default `tlf_fig_dim` (`c(4.6, 8)`, pk-project `scripts/tlf_shell.R`):
with a title, subtitle and "Source data:" footer, a taller figure (including docorator's own
default of 5 in) spills onto an extra, blank page.

## Versioned run scripts & provenance

Same layout as `pk-nca`, under `poppk/`:

```
script/poppk/v{project_number}/
  analysis-poppk.R          # Core Process 1-6: data -> model trail -> fits -> checks -> write_poppk_db()
  fig-gof.R                 # read_poppk_db(); saves output/poppk/v{n}/figures/fig-gof.pdf (+ .RDS)
  fig-individual-fits.R     # ... figures/fig-individual-fits.pdf (one page per participant)
  fig-eta.R                 # ... figures/fig-eta.pdf
  fig-vpc.R                 # ... figures/fig-vpc.pdf
  fig-traceplot.R           # ... figures/fig-traceplot.pdf
  fig-pmx-diagnostics.R     # ... figures/fig-pmx-diagnostics.pdf (ggPMX)
  fig-model-diagram.R       # ... figures/fig-model-diagram.pdf
  tbl-parameters.R          # poppk-tables; saves output/poppk/v{n}/tables/tbl-parameters.pdf
  tbl-model-comparison.R    # poppk-tables; saves output/poppk/v{n}/tables/tbl-model-comparison.pdf
  generate-spec.R           # poppk-run-spec; writes spec/poppk/v{n}.yaml (+ .hash)

tests/poppk/v{project_number}/
  test-poppk-qc.R           # QC-readiness suite (poppk-qc-tests)

output/poppk/v{project_number}/
  figures/fig-*.pdf, fig-*.RDS
  tables/tbl-*.pdf
  logs/*.log, logs/qc-tests-*.xml
  db/poppk.duckdb           # all fits of this version (poppk-database)
```

**Simulating from a fit** (new regimens, exposure predictions) is a separate, versioned
analysis in `script/poppk-sim/v{m}/` — see `poppk-simulation`. It reads this version's fit
from the database (`sim_source <- list(type = "poppk-estimation", poppk_version = n)`) and
records its payload hash and spec hash, so a later refit of popPK v{n} is detected.

**Run order for a version:** `analysis-poppk.R` → every `fig-*.R`/`tbl-*.R` →
`generate-spec.R` → `run_poppk_qc_tests(n)`. The version is ready for QC only when the QC
suite passes. A change to the model trail, data, or method is a **new version**
(`v{n+1}`), never an edit of a version whose spec has been written.

Every script logs via `nca_log_start("<script name>", project_number = project_number,
output_dir = "output/poppk")` … `nca_log_stop()` (companion skill `pk-nca-logging`).

## Fit cache and archives (nlmixr2save)

`analysis-poppk.R` fits the trail with `fit_runs()` (`scripts/poppk_fits.R`), which uses
[nlmixr2save](https://nlmixr2.github.io/nlmixr2save/):

- **Cache.** Each run is fitted as `runNNN := nlmixr2(runNNN, ...)` and saved as
  `output/poppk/v{n}/fits/runNNN.zip`. On a re-run, an unchanged run is **restored instead
  of refitted**; the log says "restored from cache (unchanged)". The cache key covers the
  model, method, control/table options and the estimation-relevant data columns, so any real
  change refits. A cache hit leaves the zip byte-identical, so the spec's hash stays valid.
- **Portable archives.** The zips are `saveFit()` bundles (R + CSV, not binary
  serialization) that record the nlmixr2est/rxode2 versions. They complement the database
  blob, are listed with hashes in the spec (`fit_archives`), and QC checks that the final
  one reloads with the same OFV and estimates.
- **Shareable copy.** `share_fit()` writes `fits/shared/<final_run>-noData.zip`
  (`nlmixr2saveShare()`): the final fit without subject data, for sharing outside the project.
  It still simulates (`poppk-simulation` source type `fit-file`).
- **Force a refit.** Delete `fits/<run>.zip`. Never edit the zips.
- **Pitfalls handled by the helpers** (keep using them rather than raw `:=`/`loadFit()`):
  - `loadFit()` only finds bare names in the working directory, and cleans up `<run>*` files
    there. `load_fit_archive()` therefore loads from a temporary copy, and shared copies
    live in `fits/shared/`.
  - `:=` resets the message sink, which would silently stop the run log;
    `with_message_sink()` restores it.
  - rlang also exports `:=`, so the helpers call it as ``nlmixr2save::`:=` ``.

## Rules

- Always read the dataset from a file under `data/` (hashed for provenance), with `read_csv(..., lazy = FALSE) |> as.data.frame()`. A raw `read_csv()` tibble carries lazy ALTREP columns and a `problems` pointer, so its hash changes in every R session and the spec's data hash can never be re-verified.
- Fit in `analysis-poppk.R` only; every `fig-*.R`/`tbl-*.R`/`generate-spec.R` starts with `read_poppk_db(project_number)` (assigns `pkData`, `fits`, `runs`, `final_run`, `final_rationale`, `fit`) — never refit downstream.
- Fixed `seed` in every stochastic step (`saemControl(seed = )`, `set.seed()` before `vpcPlot()`), so a re-run reproduces the same estimates and figures.
- Same estimation method and OFV type across all runs in one version's trail.
- Don't report SAEM output without confirming SEs exist and diagnostics were inspected.
- Don't add several ETAs / covariates in one run; you lose the OFV trail.
- Don't deliver pseudocode or a model that never ran.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `parameter not found` at compile | symbol not in `ini({})`, not a compartment, not in the data |
| SAEM OFV swings wildly / runs forever | initials off-scale (missing `log()`), or a covariate column missing for some rows |
| FOCEi Hessian / covariance failure | over-parameterized OMEGA, ETA variance near zero, identifiability; drop or fix ETAs, `foceiControl(outerOpt = "nlminb")`, or `preconditionFit()` |
| SEs `NA` in `$parFixed` | covariance step failed; `setCov(fit, "analytic")` / `"sa"` (no refit), bootstrap, or profile |
| "needs to be a mixed effect model" / "can only have population estimates" | wrong method family (rule 9) |
| Parameter sits on its bound | not really estimated; rethink the structure or bounds |
| BSV% near 0 or > 100% | ETA unsupported by data; remove it |
| `vpcPlot` / `augPred` empty or flat | residual line missing, `dvid` mismatch, or `CMT` in data does not map to `d/dt(name)` |
| Fit "converges" but IPRED misses the data | dosing compartment or units wrong in the data |
| ggPMX figure has no NPDE page | the fit has no NPDE column: fit with `tableControl(cwres = TRUE, npde = TRUE)`. `addNpde()` on a fit reloaded by nlmixr2save fails ("parameter(s) are required for solving"), and ggPMX swallows that error |
| ggPMX `pmx_nlmixr()`: "Incompatible join types: x.ID (factor) and i.ID (integer)" | a fit reloaded by nlmixr2save has an integer `ID`; get fits from `fit_runs()` / `load_fit_archive()` (they apply `restore_fit_id()`), or call `restore_fit_id(fit)` |
| QC test "model dataset hash matches the spec" fails | data read without `lazy = FALSE` / `as.data.frame()` (see Rules) |

## References

- `templates/analysis-poppk.R` — verified Core Process, scaffolded by `new_version("poppk")`.
- `scripts/poppk_checks.R` — `summarise_runs()`, `acceptance_checks()`.
- `templates/fig-*.R` — verified GOF / individual-fit / VPC figures.
- `references/estimation-methods.md` — every `est=`, variants, covariance tokens.
- `references/model-building.md` — piping, nlmixr2lib, nested comparison, SEs/CIs, shrinkage, BLQ, multi-endpoint.
- `references/priors.md` — penalized (MAP) and Bayesian fits.
- `references/diagnostics.md` — how to read the diagnostic figures.
- Companion skills: `pk-data-validation`, `poppk-database`, `poppk-tables`, `poppk-run-spec`, `poppk-qc-tests`, `poppk-simulation`, `pk-nca-logging`.
- nlmixr2 vignettes: `running_nlmixr.Rmd`, `residualErrors.Rmd`, `addingCovariances.Rmd`, `multiple-endpoints.Rmd`, `censoring.Rmd`, `modelPiping.Rmd`.

Verified with nlmixr2 7.0.1 / nlmixr2est 5.0.2 / rxode2 5.1.6 / nlmixr2plot 5.2.0 (`modelDiagram()`
needs nlmixr2plot >= 5.2.0 and ggtibble; with 5.0.0 `fig-model-diagram.R` draws a placeholder page).

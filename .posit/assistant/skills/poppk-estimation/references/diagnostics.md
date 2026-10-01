# PopPK diagnostics — what to produce and how to read it

Produce these for the final model of every version, from the database (no refit).
Verified templates, scaffolded by `new_version("poppk")`, cover the checklist below:
`templates/fig-gof.R` (items 1–2), `templates/fig-individual-fits.R` (3),
`templates/fig-eta.R` (4), `templates/fig-vpc.R` (5), `templates/fig-traceplot.R` (6).

## 1. Goodness-of-fit panel

Four panels from `as.data.frame(fit)`:

| Panel | Looks right when | Suggests |
|---|---|---|
| DV vs PRED | scatter around the identity line, loess on it | loess bending away → structural misspecification (absorption, compartments, nonlinearity) |
| DV vs IPRED | tight around identity | wide scatter → residual error model too small or wrong type; systematic bias → structure |
| CWRES vs TIME | centred on 0, mostly within ±2, no trend | trend in early times → absorption model (lag, transit, zero-order); late times → elimination / extra compartment |
| CWRES vs PRED | centred on 0, constant spread | funnel shape → switch additive ↔ proportional / combined error |

Requires CWRES: fit with `tableControl(cwres = TRUE)` or call `addCwres(fit)` before saving.

## 2. Individual fits

`augPred(fit)` gives, per subject, `Observed`, `Individual` (IPRED on a fine grid), and
`Population` (PRED) curves. Look for subjects whose IPRED misses Cmax or the terminal phase —
with low ETA shrinkage this points at structure; with high shrinkage IPRED collapses toward
PRED and the plot is less informative.

## 3. Visual predictive check

`templates/fig-vpc.R` draws a set of VPCs with one seed and one `n`, one per page:

| Type | How | Use it for |
|---|---|---|
| Standard | `nlmixr2plot::vpcPlot()` | homogeneous dosing and design |
| Prediction-corrected (pcVPC) | `vpcPlot(pred_corr = TRUE)` | different doses, covariates or designs across participants: removes the variability they explain |
| Dose-normalized | observed and simulated concentrations divided by the most recent dose (`add_last_dose()`, `vpc_summary()`; one `nlmixr2est::vpcSim()`) | dose proportionality: with linear PK all dose groups overlay |

Each on two x-axes: **time after first dose** (`vpcPlot()`), showing accumulation over the
whole profile, and **time after dose** (`vpcPlotTad()`), which overlays every dosing interval
(skipped when every participant has one dose, since it equals time after first dose); and
on linear and log y (the log scale shows the terminal phase and low concentrations).

Reading: the observed 5th/50th/95th percentile lines should fall inside the shaded 95%
intervals of the simulated percentiles. Median outside → structural bias; outer percentiles
outside → BSV or residual variability mis-estimated. A standard VPC that fails where the
pcVPC passes points at dose or design heterogeneity rather than model misfit. Values ≤ 0
are dropped from log-scale pages.

## Other diagnostics (add as extra `fig-*.R` when relevant)

- ETA vs covariates (`fit$eta` joined to baseline covariates) — drives covariate model building.
- ETA distributions / correlations (`pairs(fit$eta[-1])`) — candidate OMEGA blocks.
- Parameter history `nlmixr2plot::traceplot(fit)` — SAEM convergence (flat second phase).
- Bootstrap (`bootstrapFit()`) and likelihood profiles (`profileLlp()`) for reportable CIs — see `model-building.md`.

## Diagnostics checklist

Cover these before declaring a model adequate, and say which you looked at:

1. **Structure**: DV vs PRED and IPRED, linear and log scales; points around the identity line without trend.
2. **Residuals**: CWRES (or NPDE) vs time and PRED; centred on zero, |CWRES| mostly < 3, no fan/trend. The template stores both at fit time (`tableControl(cwres = TRUE, npde = TRUE)`); SAEM fits don't compute CWRES by default, and `addNpde()` fails on a fit reloaded from the nlmixr2save cache.
3. **Individuals**: sample of subjects including the worst-fitting ones.
4. **Random effects**: ETA histograms/QQ and ETA-vs-covariate plots; report shrinkage; treat ETA conclusions as weak where shrinkage > ~30%.
5. **Predictive check**: VPC (prediction-corrected when doses vary), appropriate binning; state `n`, binning, and whether prediction-corrected.
6. **Convergence and precision**: flat final-phase traceplot; SEs present; nothing on a bound.

## Publication-quality GOF with xpose

```r
library(xpose.nlmixr2)
xpdb <- xpose_data_nlmixr2(fit)           # adds CWRES if missing (warns — expected)
dv_vs_ipred(xpdb); res_vs_idv(xpdb, res = "CWRES")
ind_plots(xpdb, page = 1); eta_distrib(xpdb); prm_vs_iteration(xpdb)
```

## ggPMX (`templates/fig-pmx-diagnostics.R`)

The template builds one controller and takes plots by name, so only plots the fit can
produce are drawn:

```r
ctr <- ggPMX::pmx_nlmixr(fit, conts = c("WT"), cats = c("SEX"))   # NPDE from the fit (tableControl(npde = TRUE))
plot_names(ctr)                    # what this controller can draw
get_plot(ctr, "npde_time")         # one plot by name (ggplot; "eta_matrix" is a GGally ggmatrix)
```

It adds what the other figures lack: NPDE vs time, vs PRED and QQ (read like CWRES, but
simulation-based, so valid for any model), IWRES density and QQ, random-effect correlations
(|r| > 0.5 suggests an OMEGA block) and random effects by categorical covariate. GOF,
individual fits, ETA distributions and ETA vs continuous covariates stay in the other
templates, in the shared TLF style.

Notes: ggPMX disables its VPC for nlmixr2 fits (use `fig-vpc.R`). Pass `conts=`/`cats=` with
exact data column names or covariate plots go missing. `pmx_report()` writes its own
Word/HTML report outside the TLF shell and spec: don't use it for deliverables.

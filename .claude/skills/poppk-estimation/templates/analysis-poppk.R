# Population PK core pipeline -- v{{project_number}}.
# Generated from the poppk-estimation skill's templates/analysis-poppk.R by new_version("poppk").
# Edit the blocks marked EDIT; the rest is the verified standard pipeline.
# Fits the model-building trail, summarises every run, runs the acceptance checks on
# the final model, and writes everything to output/poppk/v{{project_number}}/db/poppk.duckdb
# (poppk-database); downstream tbl-*.R / fig-*.R scripts read_poppk_db() instead of refitting.

library(nlmixr2)
library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("analysis-poppk", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_checks.R")
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_fits.R")   # nlmixr2save cache + archives

## 1. Load data -- EDIT: data file and dataset checks -------------------------------
nca_log_section("1. Load data")
# lazy = FALSE + as.data.frame(): drops readr's ALTREP columns and `problems` pointer,
# which otherwise make the dataset's hash differ in every R session.

pkDataPath <- "data/pk-data.csv"
pkData <- read_csv(pkDataPath, show_col_types = FALSE, lazy = FALSE) |> as.data.frame()

# Describe, then validate (pk-data-validation): stops the script if any check fails.
source(".posit/assistant/skills/pk-data-validation/scripts/pk_data_checks.R")
describe_pk_data(pkData, pkDataPath)
validate_pk_data(
  pkData,
  layout = "event",
  cols = pk_cols(id = "ID", time = "TIME", dv = "DV", amt = "AMT", evid = "EVID",
                 cmt = "CMT"),                        # EDIT: the file's column names
  covariates = character(),                           # EDIT: covariates used in any model, e.g. "WT"
  report_dir = sprintf("output/poppk/v%d/logs", project_number),
  label = basename(pkDataPath)
)

## 2. Model-building trail -- EDIT: models, run_info ---------------------------------
nca_log_section("2. Model-building trail")
# One function per base model; each child run is a piped edit of its parent.
# label() every THETA with its units (cfg$units: dose, time, conc).

run001 <- function() {
  ini({
    tka <- log(1);  label("Ka (1/h)")
    tcl <- log(3);  label("CL/F (L/h)")
    tv  <- log(30); label("V/F (L)")
    eta.ka ~ 0.3
    eta.cl ~ 0.3
    eta.v  ~ 0.1
    add.sd <- 0.5;  label("Additive residual SD")
  })
  model({
    ka <- exp(tka + eta.ka)
    cl <- exp(tcl + eta.cl)
    v  <- exp(tv  + eta.v)
    d/dt(depot)  <- -ka * depot
    d/dt(center) <-  ka * depot - cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}

# Example child run (add one change at a time):
# run002 <- run001 |>
#   model(cl <- exp(tcl + eta.cl + wt_cl * log(WT / 70))) |>
#   ini(wt_cl <- 0.75, wt_cl = label("WT exponent on CL/F"))

run_info <- tribble(
  ~run_id,  ~parent_run, ~description,
  "run001", NA,          "1-cmt, first-order absorption, BSV on Ka/CL/V, additive error"
)
models <- list(run001 = run001)

## 3. Fit every run -- EDIT: method (same for every run in the trail) ----------------------
nca_log_section("3. Fit every run")
# nlmixr2save `:=` cache: each run is saved as output/poppk/v{n}/fits/<run>.zip and, on a
# re-run, restored instead of refitted when its model, method, options and estimation data
# are unchanged (any real change refits). The zips are also the portable fit archives.

EST <- "saem"
fit_res <- fit_runs(models, pkData, est = EST,
                    control = saemControl(print = 0, seed = 1234),
                    table = tableControl(cwres = TRUE, npde = TRUE),
                    dir = fit_dir(project_number))
fits <- fit_res$fits
print(fit_res$restored)   # TRUE = restored from the nlmixr2save cache

## 4. Compare runs and select the final model -- EDIT: final_run and rationale -------------
nca_log_section("4. Compare runs and select the final model")
# SAEM computes no OFV during the fit; tableControl(cwres = TRUE) adds the FOCEi
# approximation, so every run's OFV is on the same footing. npde = TRUE stores NPDE in the
# fit: a fit reloaded from the nlmixr2save cache cannot add it later (addNpde() fails), and
# fig-pmx-diagnostics.R needs it. dOFV < -3.84 for 1 added
# parameter ~ p < 0.05.

runs <- summarise_runs(fits, run_info)
print(select(runs, run_id, parent_run, objf, delta_ofv, delta_par, aic, bic, cov_ok))

final_run <- "run001"
final_rationale <- "Base model; no alternative runs yet."
runs$final <- runs$run_id == final_run

## 5. Inspect the final model and run acceptance checks -------------------------------
nca_log_section("5. Inspect the final model and run acceptance checks")

fit <- fits[[final_run]]
print(fit)
print(fit$parFixed)
checks <- acceptance_checks(fit)
print(checks)
if (any(checks$status == "fail")) {
  stop("Final model ", final_run, " fails acceptance checks -- see above.")
}

## 6. Persist to the popPK results database -------------------------------------------
nca_log_section("6. Persist to the popPK results database")

source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
write_poppk_db(
  project_number = project_number, pkDataPath = pkDataPath, pkData = pkData,
  fits = fits, runs = runs, final_run = final_run, final_rationale = final_rationale
)

## 7. Shareable copy of the final model (no subject data; nlmixr2saveShare) ---------------
nca_log_section("7. Shareable copy of the final model (no subject data; nlmixr2saveShare)")
share_fit(final_run, fit_dir(project_number), refitted = !fit_res$restored[[final_run]])   # fits/shared/<final_run>-noData.zip

nca_log_stop()

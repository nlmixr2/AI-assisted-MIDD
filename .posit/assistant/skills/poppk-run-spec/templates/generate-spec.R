# Provenance record (poppk-run-spec): writes spec/poppk/v{{project_number}}.yaml (+ .hash)
# from this version's scripts, source data, popPK results database, model trail,
# acceptance checks, and outputs. Run after analysis-poppk.R and every tbl-*.R / fig-*.R.

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("generate-spec", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()

source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_checks.R")
source(".posit/assistant/skills/poppk-run-spec/scripts/poppk_spec.R")
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_fits.R")

db_meta <- read_poppk_db(project_number)

## Deterministic metadata (shared pk-nca-run-spec helpers, pointed at poppk dirs) ----

meta <- collect_run_metadata(project_number, script_dir = "script/poppk")
data_file <- collect_data_provenance(db_meta$source_file_path)
data_hash <- hash_data(pkData = pkData)
outputs <- list_outputs(project_number, script_dir = "script/poppk", output_dir = "output/poppk")

output_descriptions <- c(
  "tbl-parameters" = "Final-model parameter estimates with %RSE, 95% CI, BSV and shrinkage",
  "tbl-model-comparison" = "Model-building trail: OFV, dOFV vs parent, AIC/BIC, covariance status",
  "fig-gof" = "Goodness of fit, linear and log-log pages (DV vs PRED/IPRED, CWRES vs TIME/PRED, CWRES QQ, |IWRES| vs IPRED), final model",
  "fig-individual-fits" = "Individual observed, IPRED and PRED profiles, linear and semi-log, one page per participant, worst-fitting flagged",
  "fig-vpc" = "Visual predictive checks, final model: standard, prediction-corrected and dose-normalized; time after first dose and time after dose; linear and log scale",
  "fig-eta" = "ETA distributions and QQ plots with shrinkage; ETA vs baseline covariates, final model",
  "fig-traceplot" = "Parameter history by iteration (convergence), final model",
  "fig-model-diagram" = "Compartment diagram of the final model (nlmixr2plot::modelDiagram())",
  "fig-pmx-diagnostics" = "ggPMX diagnostics, final model: NPDE, IWRES distribution, random-effect correlations, random effects by categorical covariate"
)

## EDIT: description, dataset, diagnostic notes ------------------------------------------

description <- paste(
  analysis_title("poppk", cfg), "-- population PK model development with nlmixr2",
  sprintf("(%s, %d subjects; %d runs, final model %s).", db_meta$source_file_path,
          length(unique(pkData$ID)), nrow(runs), final_run)
)
dataset <- sprintf("%s PK data (%s)", cfg$study$id, db_meta$source_file_path)
model_data <- "pkData: NONMEM-style ID/TIME/DV/AMT/EVID/CMT (+ covariates)"
diagnostic_notes <- NULL   # free text, e.g. why a flagged %RSE or shrinkage is acceptable

## Model trail, final model, acceptance checks --------------------------------------

checks <- acceptance_checks(fit)

spec <- c(
  meta,
  list(
    description = description,
    data = list(
      dataset = dataset,
      source_file = data_file,
      poppk_db = list(
        path = poppk_db_path(project_number),
        project_number = db_meta$project_number,
        generated_at = db_meta$generated_at,
        payload_hash = db_meta$payload_hash
      ),
      model_data = model_data,
      units = list(conc = cfg$units$conc, time = cfg$units$time, dose = cfg$units$dose),
      hash = data_hash
    ),
    models = spec_models(runs, fits),
    # nlmixr2save fit archives (cache + portable copies) and the shareable final model
    fit_archives = fit_archive_entries(fit_dir(project_number)),
    final_model = spec_final_model(fit, final_run, checks, rationale = final_rationale),
    diagnostics = list(
      caveats = spec_caveats(checks),
      notes = diagnostic_notes
    ),
    outputs = list(
      tables = annotate_outputs(outputs$tables, output_descriptions),
      figures = annotate_outputs(outputs$figures, output_descriptions)
    ),
    qc = list(status = "pending", reviewer = NULL, reviewed_date = NULL, notes = NULL),
    report = list(title = sprintf("%s -- v%d", analysis_title("poppk", cfg), project_number), template = NULL)
  )
)

write_spec(spec, project_number, spec_dir = "spec/poppk")
verify_spec(project_number, spec_dir = "spec/poppk")
verify_outputs(project_number, spec_dir = "spec/poppk")
cat("Spec and outputs verified for popPK v", project_number, "\n", sep = "")

nca_log_stop()

# Provenance record for popPK v1 (poppk-run-spec): writes spec/poppk/v1.yaml (+ .hash)
# from this version's scripts, source data, popPK results database, model trail,
# acceptance checks, and outputs. Run after analysis-poppk.R and every tbl-*.R / fig-*.R.

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- 1L
nca_log_start("generate-spec", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_checks.R")
source(".posit/assistant/skills/poppk-run-spec/scripts/poppk_spec.R")

db_meta <- read_poppk_db(project_number)

## Deterministic metadata (shared pk-nca-run-spec helpers, pointed at poppk dirs) ----

meta <- collect_run_metadata(project_number, script_dir = "script/poppk")
data_file <- collect_data_provenance(db_meta$source_file_path)
data_hash <- hash_data(pkData = pkData)
outputs <- list_outputs(project_number, script_dir = "script/poppk", output_dir = "output/poppk")

output_descriptions <- c(
  "tbl-parameters" = "Final-model parameter estimates with %RSE, 95% CI, BSV and shrinkage",
  "tbl-model-comparison" = "Model-building trail: OFV, dOFV vs parent, AIC/BIC, covariance status",
  "fig-gof" = "Goodness-of-fit panel (DV vs PRED/IPRED, CWRES vs TIME/PRED), final model",
  "fig-individual-fits" = "Individual observed, IPRED and PRED profiles, final model",
  "fig-vpc" = "Visual predictive checks, final model: standard, prediction-corrected and dose-normalized; time after first dose and time after dose; linear and log scale"
)

## Model trail, final model, acceptance checks --------------------------------------

checks <- acceptance_checks(fit)

spec <- c(
  meta,
  list(
    description = paste(
      "PopPK Analysis for ABC-111: population PK model development for single-dose",
      "oral data (data/pk-data-2.csv, 12 subjects) with nlmixr2 SAEM; base",
      "one-compartment model and a body-weight covariate model on CL/F."
    ),
    data = list(
      dataset = "ABC-111 PK data (data/pk-data-2.csv)",
      source_file = data_file,
      poppk_db = list(
        path = poppk_db_path(project_number),
        project_number = db_meta$project_number,
        generated_at = db_meta$generated_at,
        payload_hash = db_meta$payload_hash
      ),
      model_data = "pkData: NONMEM-style ID/TIME/DV/AMT/EVID/CMT/WT (EVID 101 = dose to depot)",
      route = "extravascular",
      units = list(conc = "mg/L", time = "h", dose = "mg"),
      hash = data_hash
    ),
    models = spec_models(runs, fits),
    final_model = spec_final_model(fit, final_run, checks,
      rationale = "run002 WT effect on CL/F not supported (dOFV = -0.62 for 1 parameter, p ~ 0.43)"),
    diagnostics = list(
      caveats = spec_caveats(checks),
      notes = "Ka %RSE 43% and BSV on Ka 71% CV reflect sparse early absorption sampling."
    ),
    outputs = list(
      tables = annotate_outputs(outputs$tables, output_descriptions),
      figures = annotate_outputs(outputs$figures, output_descriptions)
    ),
    qc = list(status = "pending", reviewer = NULL, reviewed_date = NULL, notes = NULL),
    report = list(title = "PopPK Analysis for ABC-111", template = NULL)
  )
)

write_spec(spec, project_number, spec_dir = "spec/poppk")
verify_spec(project_number, spec_dir = "spec/poppk")
verify_outputs(project_number, spec_dir = "spec/poppk")
cat("Spec and outputs verified for popPK v", project_number, "\n", sep = "")

nca_log_stop()

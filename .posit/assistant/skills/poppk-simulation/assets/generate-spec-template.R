# Provenance record for popPK simulation v1 (poppk-simulation): writes
# spec/poppk-sim/v1.yaml (+ .hash) from this version's scripts, model source,
# simulation settings, scenarios, results database, exposure summary, and outputs.
# Run after analysis-sim.R and every tbl-*.R / fig-*.R.

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- 1L
nca_log_start("generate-spec", project_number = project_number, output_dir = "output/poppk-sim")

source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim.R")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_db.R")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_spec.R")
source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")
source(".posit/assistant/skills/poppk-run-spec/scripts/poppk_spec.R")

db_meta <- read_sim_db(project_number)

meta <- collect_run_metadata(project_number, script_dir = "script/poppk-sim")
outputs <- list_outputs(project_number, script_dir = "script/poppk-sim", output_dir = "output/poppk-sim")

output_descriptions <- c(
  "tbl-exposure-summary" = "Steady-state Cmax, Cmin, AUC0-24 and Tmax by regimen: median [5th, 95th percentile]",
  "fig-sim-profiles" = "Simulated concentration-time profiles: median and 90% PI by regimen",
  "fig-exposure" = "Steady-state Cmax, Cmin, AUC0-24 distributions by regimen"
)

spec <- c(
  meta,
  list(
    description = paste(
      "PopPK Simulation for ABC-111: steady-state exposure of three oral regimens",
      "(320 mg q12h, 480 mg q12h, 640 mg q24h for 7 days) simulated from the final",
      "popPK model (v1, run001) with parameter uncertainty."
    ),
    source = spec_sim_source(source_provenance),
    simulation = spec_sim_settings(settings),
    scenarios = spec_scenarios(scenario_info, events, settings),
    data = list(
      sim_db = list(path = sim_db_path(project_number), project_number = db_meta$project_number,
                    generated_at = db_meta$generated_at, payload_hash = db_meta$payload_hash),
      units = list(conc = "mg/L", time = "h", dose = "mg")
    ),
    results = list(exposure_summary = spec_exposure(exposure_summary)),
    diagnostics = list(
      caveats = if (!identical(source_provenance$spec$qc_status, "approved")) {
        list(list(check = "source_qc_status",
                  detail = sprintf("source popPK v%d spec QC status is '%s'; simulation results are provisional until it is approved",
                                   source_provenance$poppk_version, source_provenance$spec$qc_status)))
      } else list(),
      notes = "640 mg q24h matches 320 mg q12h AUC0-24,ss with ~50% higher Cmax,ss and ~40% lower Cmin,ss."
    ),
    outputs = list(
      tables = annotate_outputs(outputs$tables, output_descriptions),
      figures = annotate_outputs(outputs$figures, output_descriptions)
    ),
    qc = list(status = "pending", reviewer = NULL, reviewed_date = NULL, notes = NULL),
    report = list(title = "PopPK Simulation for ABC-111", template = NULL)
  )
)

write_spec(spec, project_number, spec_dir = "spec/poppk-sim")
verify_spec(project_number, spec_dir = "spec/poppk-sim")
verify_outputs(project_number, spec_dir = "spec/poppk-sim")
cat("Spec and outputs verified for popPK simulation v", project_number, "\n", sep = "")

nca_log_stop()

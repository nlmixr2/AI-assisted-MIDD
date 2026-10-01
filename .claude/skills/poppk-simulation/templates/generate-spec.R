# Provenance record (poppk-simulation): writes
# spec/poppk-sim/v{{project_number}}.yaml (+ .hash) from this version's scripts, model source,
# simulation settings, scenarios, results database, exposure summary, and outputs.
# Run after analysis-sim.R and every tbl-*.R / fig-*.R.

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("generate-spec", project_number = project_number, output_dir = "output/poppk-sim")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()

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
  "fig-sim-profiles" = "Simulated concentration-time profiles, median and 90% PI: all regimens overlaid, then one page per regimen",
  "fig-exposure" = "Steady-state Cmax, Cmin, AUC0-24 distributions by regimen (boxplots)"
)

## EDIT: description and notes -------------------------------------------------------------

src_label <- if (source_provenance$type == "poppk-estimation") {
  sprintf("popPK v%d %s", source_provenance$poppk_version, source_provenance$run_id)
} else source_provenance$path
description <- paste(
  analysis_title("poppk-sim", cfg), "-- steady-state exposure of",
  sprintf("%d regimens (%s) simulated from %s,", nrow(scenario_info),
          paste(scenario_info$scenario, collapse = ", "), src_label),
  sprintf("%d subjects x %d studies per regimen.", settings$nSub, settings$nStud)
)
notes <- NULL   # free text, e.g. the main comparison the simulation was run for

## Assemble and write ---------------------------------------------------------------------

caveats <- list()
if (source_provenance$type == "poppk-estimation" &&
    !identical(source_provenance$spec$qc_status, "approved")) {
  caveats <- list(list(check = "source_qc_status",
    detail = sprintf("source popPK v%d spec QC status is '%s'; simulation results are provisional until it is approved",
                     source_provenance$poppk_version, source_provenance$spec$qc_status)))
}
if (source_provenance$type == "fit-file") {
  caveats <- list(list(check = "fit_file_source",
    detail = sprintf("model and estimates come from the nlmixr2save fit archive %s (not a fit in this project)%s",
                     source_provenance$path,
                     if (isTRUE(source_provenance$has_covariance)) "" else "; it has no covariance, so no parameter uncertainty")))
}
if (source_provenance$type == "model-file") {
  caveats <- list(list(check = "model_file_source",
    detail = sprintf("parameters come from %s (not a fit in this project); see its header for their origin",
                     source_provenance$path)))
}

spec <- c(
  meta,
  list(
    description = description,
    source = spec_sim_source(source_provenance),
    simulation = spec_sim_settings(settings),
    scenarios = spec_scenarios(scenario_info, events, settings),
    data = list(
      sim_db = list(path = sim_db_path(project_number), project_number = db_meta$project_number,
                    generated_at = db_meta$generated_at, payload_hash = db_meta$payload_hash),
      units = list(conc = cfg$units$conc, time = cfg$units$time, dose = cfg$units$dose)
    ),
    results = list(exposure_summary = spec_exposure(exposure_summary)),
    diagnostics = list(caveats = caveats, notes = notes),
    outputs = list(
      tables = annotate_outputs(outputs$tables, output_descriptions),
      figures = annotate_outputs(outputs$figures, output_descriptions)
    ),
    qc = list(status = "pending", reviewer = NULL, reviewed_date = NULL, notes = NULL),
    report = list(title = sprintf("%s -- v%d", analysis_title("poppk-sim", cfg), project_number), template = NULL)
  )
)

write_spec(spec, project_number, spec_dir = "spec/poppk-sim")
verify_spec(project_number, spec_dir = "spec/poppk-sim")
verify_outputs(project_number, spec_dir = "spec/poppk-sim")
cat("Spec and outputs verified for popPK simulation v", project_number, "\n", sep = "")

nca_log_stop()

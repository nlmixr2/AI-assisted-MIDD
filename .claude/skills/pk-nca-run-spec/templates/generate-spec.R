# Provenance record (pk-nca-run-spec): writes spec/nca/v{{project_number}}.yaml (+ .hash)
# from this version's scripts, source data, NCA results database, and outputs.
# Run after analysis-nca.R and every tbl-*.R / fig-*.R script.

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("generate-spec", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-nca/scripts/nca_nominal.R")

source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
source(".posit/assistant/skills/pk-nca-run-spec/scripts/build_spec.R")

db_meta <- read_nca_db(project_number)

## Deterministic metadata ---------------------------------------------------------

meta <- collect_run_metadata(project_number)
data_file <- collect_data_provenance(db_meta$source_file_path)
data_hash <- hash_data(conc = cObsData, dose = doseData)
outputs <- list_outputs(project_number)

output_descriptions <- c(
  "tbl-pk-parameters" = "Individual PK parameters by Participant ID, with N/Mean/Median/Min-Max summary rows",
  "tbl-conc-by-nominal-time" = "Concentrations by nominal postdose sample time, with N/Mean/Median/Min-Max/BLQ N/%BLQ summary rows",
  "fig-halflife-diagnostics" = "Half-life span-ratio vs. adjusted R-squared diagnostic plot",
  "fig-mean-conc" = "Mean (SD) concentration-time profile by nominal time, linear scale, with n/mean/SD table (crane)",
  "fig-mean-conc-semilog" = "Mean (SD) concentration-time profile by nominal time, semi-logarithmic scale (crane)",
  "fig-ind-conc" = "Individual concentration-time profiles, linear and semi-log, one page per participant",
  "fig-lambdaz" = "Terminal-phase (lambda z) regression per participant, semi-log, regression line in red, one page per participant"
)

annotate_outputs <- function(paths) {
  lapply(paths, function(p) {
    entry <- list(
      path = p,
      description = unname(output_descriptions[tools::file_path_sans_ext(basename(p))]),
      hash = hash_file(p)
    )
    entry$display_rds <- display_rds_entry(p)   # gt object behind a table, reused by pk-nca-report
    entry
  })
}

## Diagnostics: subjects with lambda-z span ratio < 2 ------------------------------

flagged <- halflife_fit |>
  filter(span.ratio < 2) |>
  arrange(as.integer(as.character(participant)))

flagged_subjects <- pmap(flagged, function(participant, span.ratio, half.life, lambda.z.n.points, ...) {
  list(
    id = as.integer(as.character(participant)),
    reason = sprintf("span.ratio %.2f (< 2); half-life %.1f h from %d terminal points",
                     span.ratio, half.life, as.integer(lambda.z.n.points))
  )
})

## Assemble and write ---------------------------------------------------------------

## EDIT: description, dataset, dose derivation, diagnostic notes --------------------------

description <- paste(
  "Non-compartmental analysis of", cfg$study$id, "PK data",
  sprintf("(%s, %d subjects):", db_meta$source_file_path, nrow(res_wide)),
  "requested PK parameters per subject, with diagnostic figures and formatted",
  "PK-parameter and concentration-by-nominal-time tables."
)
dataset <- sprintf("%s PK data (%s)", cfg$study$id, db_meta$source_file_path)
dose_data <- "doseData: participant, time, dose (= AMT, EVID != 0 rows), route, dur"
diagnostic_notes <- "Half-life for flagged subjects (and derived AUCinf) should be interpreted with caution."

## Assemble and write ---------------------------------------------------------------------

spec <- c(
  meta,
  list(
    description = description,
    data = list(
      dataset = dataset,
      source_file = data_file,
      nca_db = list(
        path = nca_db_path(project_number),
        project_number = db_meta$project_number,
        generated_at = db_meta$generated_at,
        payload_hash = db_meta$payload_hash
      ),
      concentration_data = sprintf("cObsData: %s", paste(names(cObsData), collapse = ", ")),
      nominal_time = nominal_time_source(cObsData),
      dose_data = dose_data,
      route = unique(doseData$route),
      units = list(conc = cfg$units$conc, time = cfg$units$time, dose = cfg$units$dose,
                   amount = cfg$units$dose),
      hash = data_hash
    ),
    parameters = list(
      interval = list(start = 0L, end = "Inf"),
      requested = as.list(setdiff(names(res_wide), "participant"))
    ),
    diagnostics = list(
      flagged_subjects = flagged_subjects,
      notes = diagnostic_notes
    ),
    outputs = list(
      tables = annotate_outputs(outputs$tables),
      figures = annotate_outputs(outputs$figures)
    ),
    qc = list(status = "pending", reviewer = NULL, reviewed_date = NULL, notes = NULL),
    report = list(title = sprintf("%s -- v%d", analysis_title("nca", cfg), project_number), template = NULL)
  )
)

write_spec(spec, project_number)
verify_spec(project_number)
verify_outputs(project_number)
cat("Spec and outputs verified for v", project_number, "\n", sep = "")

nca_log_stop()

# NCA core pipeline -- v{{project_number}}.
# Generated from the pk-nca skill's templates/analysis-nca.R by new_version("nca").
# Edit the blocks marked EDIT; the rest is the verified standard pipeline.
# Ends by writing results to output/nca/v{{project_number}}/db/nca.duckdb (pk-nca-database);
# downstream tbl-*.R / fig-*.R scripts read_nca_db() instead of re-running PKNCA.

library(PKNCA)
library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("analysis-nca", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()

## 1. Load data -- EDIT: data file ------------------------------------------------
nca_log_section("1. Load data")

pkDataPath <- "data/pk-data.csv"   # relative path, recorded for provenance
pkData <- read_csv(pkDataPath, show_col_types = FALSE)

# Describe, then validate the column mapping (pk-data-validation). Map columns from the
# describe output, never by guessing; validation stops the script if any check fails.
source(".posit/assistant/skills/pk-data-validation/scripts/pk_data_checks.R")
describe_pk_data(pkData, pkDataPath)
validate_pk_data(
  pkData,
  layout = "event",                                   # EDIT: "event" (EVID) or "sample"
  cols = pk_cols(id = "ID", time = "TIME", dv = "DV", amt = "AMT", evid = "EVID",
                 cmt = NA),                           # EDIT: the file's column names
  report_dir = sprintf("output/nca/v%d/logs", project_number),
  label = basename(pkDataPath)
)

## 2. Build concentration and dose data -- EDIT: column mapping -----------------------
nca_log_section("2. Build concentration and dose data")
# Standardize to participant/time/cObs and participant/time/dose/route/dur.
# Event layout shown (observations EVID == 0, doses EVID != 0 and AMT > 0; coding in
# pk-data-validation references/data-layouts.md). For the sample layout (no EVID, one
# dose row per subject), see the pk-nca skill's references/pipeline.md, step 3.

cObsData <- pkData |>
  filter(EVID == 0) |>
  transmute(participant = factor(ID, levels = sort(unique(ID))), time = TIME, cObs = DV)

# Nominal time -- EDIT if needed. A nominal-time column in the data (CDISC NFRLT/NRRLT, NTIME,
# ...) is carried as `ntime` and used by every nominal-time table and figure (pk-nca
# scripts/nca_nominal.R). Set to a column name, or NA to use project.yaml's
# sampling.nominal_times instead. For multiple-dose data choose NFRLT vs NRRLT deliberately.
source(".posit/assistant/skills/pk-nca/scripts/nca_nominal.R")
NOMINAL_TIME_COL <- detect_nominal_time_col(pkData)
if (!is.na(NOMINAL_TIME_COL)) {
  message("Nominal time from data column ", NOMINAL_TIME_COL)
  cObsData$ntime <- pkData[[NOMINAL_TIME_COL]][pkData$EVID == 0]
  attr(cObsData, "nominal_time_col") <- NOMINAL_TIME_COL
}

doseData <- pkData |>
  filter(EVID != 0, AMT > 0) |>
  transmute(
    participant = factor(ID, levels = sort(unique(ID))),
    time = TIME,
    dose = AMT,                 # total dose amount
    route = "extravascular",    # EDIT: or "intravascular"
    dur = NA_real_
  )

## 3. Build PKNCAconc / PKNCAdose objects -------------------------------------------
nca_log_section("3. Build PKNCAconc / PKNCAdose objects")

objConc <- PKNCAconc(cObsData, cObs ~ time | participant)
objDose <- PKNCAdose(doseData, dose ~ time | participant)

## 4. Units (project.yaml) ----------------------------------------------------------
nca_log_section("4. Units (project.yaml)")

pkUnits <- pknca_units_table(concu = cfg$units$conc, timeu = cfg$units$time,
                             doseu = cfg$units$dose, amountu = cfg$units$dose)

## 5. Intervals and parameters -- EDIT: requested parameters -------------------------
nca_log_section("5. Intervals and parameters")

intervalData <- tibble(
  start = 0, end = Inf,
  cmax = TRUE, tmax = TRUE, half.life = TRUE, aucinf.obs = TRUE, clast.obs = TRUE
)
invisible(check.interval.specification(intervalData))

ncaObj <- PKNCAdata(objConc, objDose, intervals = intervalData, units = pkUnits)

## 6. Run NCA ------------------------------------------------------------------------
nca_log_section("6. Run NCA")

ncaRes <- pk.nca(ncaObj)

## 7. Summarize requested parameters (0-Inf interval) ----------------------------------
nca_log_section("7. Summarize requested parameters (0-Inf interval)")

requested <- setdiff(names(intervalData)[vapply(intervalData, isTRUE, logical(1))], c("start", "end"))
res_wide <- ncaRes$result |>
  filter(end == Inf, PPTESTCD %in% requested) |>
  select(participant, PPTESTCD, PPORRES) |>
  pivot_wider(names_from = PPTESTCD, values_from = PPORRES)

print(res_wide, n = Inf)
print(summary(ncaRes))

## 8. Terminal-phase (lambda z) regression diagnostics -----------------------------------
nca_log_section("8. Terminal-phase (lambda z) regression diagnostics")

halflife_fit <- ncaRes$result |>
  filter(end == Inf, PPTESTCD %in% c("half.life", "r.squared", "adj.r.squared",
                                      "span.ratio", "lambda.z.n.points")) |>
  select(participant, PPTESTCD, PPORRES) |>
  pivot_wider(names_from = PPTESTCD, values_from = PPORRES)

print(halflife_fit, n = Inf)
cat("\nSubjects with span.ratio < 2:\n")
print(filter(halflife_fit, span.ratio < 2), n = Inf)

## 9. Persist to the NCA results database ----------------------------------------------
nca_log_section("9. Persist to the NCA results database")

source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
write_nca_db(
  project_number = project_number, pkDataPath = pkDataPath,
  cObsData = cObsData, doseData = doseData, ncaRes = ncaRes,
  res_wide = res_wide, halflife_fit = halflife_fit
)

nca_log_stop()

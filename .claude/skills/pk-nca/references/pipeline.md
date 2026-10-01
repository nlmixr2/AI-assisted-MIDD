# NCA pipeline, step by step

Companion to [SKILL.md](../SKILL.md) (Core Process). This page explains each step of
`templates/analysis-nca.R`, the verified pipeline scaffolded by `new_version("nca")`.
The snippets illustrate the steps. They are not code to paste: when a snippet and the
template disagree, the template wins. Edit only the template's `EDIT` blocks.

Related pages (load them from the Reference files table in SKILL.md): `diagnostics.md`
(λz figures), `versioned-layout.md` (where the script lives and what reads its results),
`troubleshooting.md` (errors and API drift).

## Contents

- Steps 1-8
  - 1 Import libraries
  - 2 Read, describe and validate the dataset
  - 3 Split into observations (`cObsData`) and doses (`doseData`): sample layout (no EVID), event layout (EVID)
  - 4 Build `PKNCAconc` / `PKNCAdose`
  - 5 Units from `project.yaml`
  - 6 Intervals and requested parameters
  - 7 `PKNCAdata()` and `pk.nca()`
  - 8 λz regression-fit summary (`halflife_fit`)
- Summarizing results (`res_wide`, geometric means, `PPTESTCD`/`PPORRES`)

## Steps 1-8

1. Import libraries:

```r
library(PKNCA)
library(tidyverse)
```

2. Read the dataset from a path, then describe and validate it with the
   `pk-data-validation` skill before building the objects (the template does both). Always load from a file under `data/` (not `data(...)`/an in-memory
   object) so the run has a concrete file to hash for provenance (see `versioned-layout.md`). The snippets below use the worked example's data
   (`examples/abc-111/data/pk-data.csv`: theophylline, columns `Subject`, `Wt`, `Dose`,
   `Time`, `conc`, no `EVID` flag). A new study's `data/` holds its own file, whose
   columns you must map from `describe_pk_data()` output (Grounding checks in [SKILL.md](../SKILL.md)).

```r
DATA_DIR_PATH <- here::here("data/")
DATA_NAME <- "pk-data.csv"

pkData <- read_csv(fs::path(DATA_DIR_PATH, DATA_NAME))
```

3. Split data into observations and doses, standardized to `participant`, `time`,
   `cObs` (observations) and `participant`, `time`, `dose` (dosing), regardless of the
   source dataset's own column names. This keeps the `PKNCAconc`/`PKNCAdose` formulas
   and downstream code consistent across datasets, even when the source already has
   clean names (e.g. `Subject`/`Time`/`conc` in `pk-data.csv`) — rename to the
   convention below rather than keeping the native names.

**Datasets without an `EVID` flag** (e.g. `pk-data.csv`, single-dose designs where dose
info lives in separate columns): build `doseData` from one row per subject at the dosing
time instead of filtering `EVID`, derive total dose from whatever columns encode it,
and still rename to the `participant`/`time`/`cObs`/`dose` convention. In the example
below, `Dose * Wt` and `time = 0` are true **only for the theophylline example** (dose
in mg/kg, single dose at time 0). Confirm both with the user for any other dataset:

```r
cObsData <- pkData |>
  transmute(participant = factor(Subject), time = Time, cObs = conc)

doseData <- pkData |>
  distinct(Subject, Wt, Dose) |>
  transmute(
    participant = factor(Subject),
    time = 0,
    dose = Dose * Wt,   # Dose is mg/kg here; total amount in mg
    route = "extravascular",
    dur = NA_real_
  )
```

**Datasets with an `EVID` flag** (event layout: observations are `EVID == 0` rows, doses
`EVID != 0` rows with `AMT > 0`; the codes vary, see `pk-data-validation`
`references/data-layouts.md`):

```r
cObsData <- pkData |>
  filter(EVID == 0) |>
  transmute(participant = factor(ID), time = TIME, cObs = DV)

doseData <- pkData |>
  filter(EVID != 0, AMT > 0) |>
  transmute(
    participant = factor(ID), time = TIME, dose = AMT,
    route = "extravascular", dur = NA_real_
  )
```

4. Build `PKNCAconc` / `PKNCAdose`.

```r
objConc <- PKNCAconc(cObsData, cObs ~ time | participant)
objDose <- PKNCAdose(doseData, dose ~ time | participant)
```

5. Define units for time, dose, amount, and concentration.

```r
source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()   # units come from project.yaml, never typed in
pkUnits <- pknca_units_table(concu = cfg$units$conc, timeu = cfg$units$time,
                             doseu = cfg$units$dose, amountu = cfg$units$dose)
```

6. Define intervals and request parameters as boolean columns. There is no
   `interval_add_param()` function in current PKNCA (0.12.1) — build the intervals
   tibble directly with `TRUE`/`FALSE` parameter columns.

```r
intervalData <- tibble(
  start = 0, end = Inf,
  cmax = TRUE, tmax = TRUE, half.life = TRUE, aucinf.obs = TRUE, clast.obs = TRUE
)
check.interval.specification(intervalData)
```

7. Assemble `PKNCAdata` and run `pk.nca()`; capture warnings (they flag λz fit problems).

```r
ncaObj <- PKNCAdata(objConc, objDose, intervals = intervalData, units = pkUnits)
ncaRes <- pk.nca(ncaObj)
```

8. Build the λz regression-fit summary and ask the user if it looks OK (see
   `diagnostics.md` for the accompanying figures):

```r
halflife_fit <- ncaRes$result |>
  filter(end == Inf, PPTESTCD %in% c("half.life", "r.squared", "adj.r.squared",
                                      "span.ratio", "lambda.z.n.points")) |>
  select(participant, PPTESTCD, PPORRES) |>
  pivot_wider(names_from = PPTESTCD, values_from = PPORRES)
```

## Summarizing results

```r
res_wide <- ncaRes$result |>          # columns: participant, start, end, PPTESTCD, PPORRES, exclude
  filter(end == Inf) |>
  select(participant, PPTESTCD, PPORRES) |>
  pivot_wider(names_from = PPTESTCD, values_from = PPORRES)

# Summarize only parameters you requested in intervalData (cl.obs/vz.obs are not in the
# default request; add them there first, or this errors).
res_wide |> summarise(across(c(cmax, half.life, aucinf.obs),
                              list(geo_mean = ~ exp(mean(log(.x)))),
                              .names = "{.col}"))
```

Column names in `ncaRes$result` are `PPTESTCD`/`PPORRES` (not `PPTESTCODE`).

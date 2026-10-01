# PK dataset layouts and coding

Companion to [../SKILL.md](../SKILL.md). Confirm the layout with `describe_pk_data()`;
never infer it from a file name.

## Event layout (NONMEM / rxode2 records)

One row per event. Common columns (names vary; map them with `pk_cols()`):

| Role | Usual names | Meaning |
|---|---|---|
| id | `ID`, `USUBJID` | subject |
| time | `TIME`, `TAFD`, `AFRLT` | actual time since first dose (NCA and popPK use actual time) |
| dv | `DV` | observed concentration (observation rows) |
| amt | `AMT` | dose amount (dose rows); 0 or missing on observations |
| evid | `EVID` | record type, see below |
| cmt | `CMT` | compartment the dose goes into or the observation comes from |
| mdv | `MDV` | 1 = DV not used (dose rows, excluded samples) |
| — | `DVID` | which output (parent, metabolite, PD) when there are several |
| — | `CENS`, `LIMIT`, `BLQ` | BLQ handling: censored flag and limit |
| — | `NFRLT`, `NRRLT`, `NTIME` | nominal time (tables and figures only) |
| — | `II`, `ADDL`, `SS`, `RATE`, `DUR` | repeated, steady-state and infusion dosing |

`EVID` codes:

| EVID | Record |
|---|---|
| 0 | observation |
| 1 | dose (NONMEM) |
| 2 | other event (e.g. covariate change), not a dose or observation |
| 3 | reset |
| 4 | reset and dose |
| 101 | dose (rxode2 classic coding, e.g. `examples/abc-111/data/pk-data-2.csv`) |

So observations are `EVID == 0` (and `MDV == 0` if present) and doses are `EVID != 0`
with `AMT > 0`. `CMT` numbering is dataset-specific: for popPK it must match the model's
`d/dt()` compartments (dose into depot, observe central). Check `count(pkData, EVID, CMT)`.

## Sample layout (one row per sample, no EVID)

Each row is a concentration; dose information is in columns repeated on every row
(e.g. theophylline `examples/abc-111/data/pk-data.csv`: `Subject`, `Wt`, `Dose`, `Time`,
`conc`, with `Dose` in mg/kg). The dosing time and whether dose is per kg are **not** in
the file: ask. The NCA dose data frame is built as one row per subject (`pk-nca`,
`references/pipeline.md`). This layout supports single-dose data only; convert
multiple-dose data to the event layout.

## BLQ and missing values

- Keep BLQ samples in the file; how they are handled (set to 0 before tmax, excluded,
  censored in popPK) is an analysis choice for the user, recorded in the version.
- A missing `DV` on an observation row fails validation. If it is a BLQ sample, the file
  needs a BLQ flag or `MDV = 1`; ask rather than impute.

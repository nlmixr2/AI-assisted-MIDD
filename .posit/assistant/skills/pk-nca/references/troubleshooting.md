# Troubleshooting PKNCA runs

Companion to [SKILL.md](../SKILL.md). Check the symptom here before changing code, and
check the installed API before writing any function or argument the template does not
already use (Grounding checks in SKILL.md).

| Symptom | Likely cause |
|---|---|
| `unused argument` in `pknca_units_table` | API drift — installed signature is `pknca_units_table(concu, doseu, amountu, timeu, concu_pref, doseu_pref, amountu_pref, timeu_pref, conversions)`; check `?pknca_units_table` |
| `object 'PPTESTCODE' not found` | column is `PPTESTCD` in current PKNCA |
| No `cl.obs`/`vz.obs` in results | interval parameters not requested (add `cl.obs = TRUE` to `intervalData` in the EDIT block) |
| λz warnings for a subject | too few terminal points or curved terminal phase; check `span.ratio` and `lambda.z.n.points` |
| Duplicate interval rows in summary | filter `end == Inf` (or select the intended interval) |
| `Found column named route, using it...` | informational — dose data frame column names are auto-detected |
| CL/F or Vz/F units shown unsimplified (e.g. `mg/(h*mg/L)`) | PKNCA derives units without simplification; pass preferred units, e.g. `pknca_units_table(..., amountu_pref =, concu_pref =)` or a `conversions` table, in the `EDIT` units step |
| `object 'interval_add_param' not found` | API drift — that function doesn't exist in PKNCA 0.12.1; build the `intervals` tibble with boolean parameter columns directly (see `pipeline.md` step 6) |

Backward compatibility is not guaranteed before PKNCA 1.0 — verify function signatures (`?pknca_units_table`, `?PKNCAdata`) against the installed version when errors look like API drift.

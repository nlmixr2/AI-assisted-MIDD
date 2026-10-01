# Terminal-phase (λz) diagnostics

Companion to [SKILL.md](../SKILL.md) (Diagnostics). Look at these before reporting
half-life or any parameter derived from it (`aucinf.obs`, `cl.obs`, `vz.obs`). All are PDFs
in the shared TLF shell (`render_tlf()`), scaffolded by `new_version("nca")`, and read the
version's database (`read_nca_db()`); none re-runs PKNCA. `halflife_fit` is built in step 8
of `analysis-nca.R` (`pipeline.md`).

| Figure | Template | Shows |
|---|---|---|
| `fig-halflife-diagnostics.pdf` | `pk-nca/templates/fig-halflife-diagnostics.R` | span ratio vs adjusted R² for all participants, dashed line at the threshold |
| `fig-lambdaz.pdf` | `pk-nca-figures/templates/fig-lambdaz.R` | one page per participant: points used in the regression and PKNCA's fitted line |
| `fig-ind-conc.pdf` | `pk-nca-figures/templates/fig-ind-conc.R` | one page per participant: linear and semi-log profiles |

## Reading them

- **Semi-log profiles** (`fig-ind-conc`, right panel): the terminal phase should look
  roughly log-linear where λz was fit. Curvature, shoulders or a short terminal window
  are red flags even when the regression statistics look fine. Concentrations of 0
  (e.g. pre-dose) cannot be shown on a log axis and are dropped from that panel.
- **Span ratio vs adjusted R²** (`fig-halflife-diagnostics`): a high adjusted R² alone does
  not make a half-life trustworthy, because a straight line fits any narrow window.
  Points left of the dashed line (span ratio < 2, the commonly used minimum; set as
  `span_min` in the `EDIT` block, the same value as in `fig-lambdaz.R`) have a terminal
  window short relative to the half-life.
- **Per-participant regressions** (`fig-lambdaz`): check which points PKNCA used for each
  flagged participant, and whether the red line follows the terminal phase.

## What to do with flagged participants

List them exactly as `analysis-nca.R` prints them ("Subjects with span.ratio < 2") and
ask the user whether to accept the fits or revise them in a new version. Do not drop
them from summary statistics, or change the λz window, without being asked. The spec
records them in `diagnostics.flagged_subjects`.

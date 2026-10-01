# `pk-nca-figures`

Builds the production NCA figures of a version: mean concentration-time profiles, individual
profiles and terminal-phase regression plots. They use the same 11 pt serif TLF shell as the
tables, and the same nominal times as the concentration table, so figures and tables agree.

## When it is used

- When you ask for NCA or PK plots, mean or individual concentration plots, spaghetti
  plots, lambda z or half-life plots, or TLF figures for an NCA version.
- When you add a custom figure to an NCA version (scaffold it with `new_tlf()`, see
  [pk-project](pk-project.md)).
- Neighbouring tasks: the span-ratio vs adjusted R-squared figure
  (`fig-halflife-diagnostics`) comes with [pk-nca](pk-nca.md); tables are
  [pk-nca-tables](pk-nca-tables.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `fig-mean-conc.pdf` | `output/nca/v{n}/figures/` | Mean (SD) by nominal time, linear scale, numeric time axis, LLOQ line, with an n / mean / SD table under the plot at selected times. |
| `fig-mean-conc-semilog.pdf` | `output/nca/v{n}/figures/` | The same statistic on a semi-log scale, LLOQ line. |
| `fig-ind-conc.pdf` | `output/nca/v{n}/figures/` | One page per participant: linear and semi-log panels; participant, dose and route in the page label. |
| `fig-lambdaz.pdf` | `output/nca/v{n}/figures/` | One page per participant: terminal-phase regression on a semi-log scale, points used in the regression filled, regression line in red. Lambda z, half-life, adj. R-squared, span ratio and points in the caption. Span ratio below the threshold is flagged in the page label. |
| `fig-<name>.RDS` | `output/nca/v{n}/figures/` | The display object saved next to each PDF. The spec records its hash (`display_rds`) and the report reuses it. |

Without TinyTeX the figures are written as RTF instead of PDF. No NCA figure in this skill
is a PNG.

## How to use it

1. Scaffold the version. The four figure scripts are copied into `script/nca/v{n}/`:

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   new_version("nca")
   ```

2. Set the sampling schedule in `project.yaml`, unless the data carry a nominal-time column
   (`ntime`, mapped in `analysis-nca.R` as `NOMINAL_TIME_COL`), which then wins:

   ```yaml
   sampling:
     nominal_times: [0, 0.25, 0.5, 1, 2, 3.5, 5, 7, 9, 12, 24]
     lloq: 0.1          # optional
   ```

3. Edit only the `EDIT` blocks:
   - `fig-mean-conc.R`: grouping (`group`), `stat`, `variability`, `table_times` (`NULL` =
     times at least 8% of the range apart, first and last always kept).
   - `fig-mean-conc-semilog.R`: the same grouping, `stat` and `variability`. Keep the two
     blocks identical. For dose groups, join `doseData` and set `group` (example in the block).
   - `fig-lambdaz.R`: `span_min` (default `2`), the span-ratio threshold for the flag.
4. Run the whole version, so the spec and QC are refreshed after the figures:

   ```r
   run_version("nca", 1L)
   ```

5. For an extra figure, scaffold it in the same shell:

   ```r
   new_tlf("nca", 1L, "fig-cmax-by-weight", title = "...", caption = "...")
   ```

Typical prompts: "Make mean concentration plots by dose group for NCA v2", "Show the
individual profiles", "Plot the lambda z regression for each participant".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `templates/fig-mean-conc.R`, `templates/fig-mean-conc-semilog.R` | Mean profiles with `crane::gg_pkc_lineplot()`; the linear one adds `crane::annotate_pkc_df()`. |
| `templates/fig-ind-conc.R` | Individual profiles, one page per participant (patchwork). |
| `templates/fig-lambdaz.R` | Terminal-phase regression per participant. The line is PKNCA's own fit rebuilt from the stored results (`clast.pred`, `lambda.z`, `lambda.z.time.first`/`last`), not a refit. |
| `render_pk_display(p, name, out_dir, cfg, source_data =, title =, subtitle =)` | `render_tlf()` for figures. `p` is a ggplot, or a list of ggplots for one page each. Title and subtitle go in the docorator header. |
| `spaced_times(times, min_gap = 0.08)` | Timepoints far enough apart for ticks and the summary table. |
| `pk_legend()` | Hides crane's redundant legend when there is a single group. |
| `participant_order()`, `theme_pk()` | Numeric participant order; the shared figure theme (`theme_tlf()`: theme_bw, 11 pt serif). |
| `assign_nominal_time()`, `nominal_schedule()` | `pk-nca/scripts/nca_nominal.R`: the single nominal-time definition, shared with the concentration table. |

## Rules and checks

- Figures read results with `read_nca_db()`; they never re-run PKNCA.
- Titles and subtitles go to `render_pk_display(title =, subtitle =)`, never to
  `labs(title/subtitle)` or `plot_annotation()`. A one-page-per-participant figure only
  carries a short page label in the plot.
- Every deliverable figure goes through the shared shell; never `ggsave()`.
- One nominal-time definition. With a data column, every value must be on the
  `project.yaml` schedule when one is set. Without it, samples are matched by rank when every
  participant has one sample per nominal time, otherwise to the nearest time with a warning.
- Same rounding as the table: `annotate_pkc_df(digits = c(0, 1, 1))` matches the
  concentration table's `frmt("xx.x")`. Change both together.
- Use the numeric nominal time (`ntime`) for the mean plots. A factor axis spaces 0.25 h and
  12 h equally and distorts the profile.
- On the log scale, zero means and lower error bounds at or below zero cannot be drawn; the
  semi-log caption says so.
- Re-running a figure after `generate-spec.R` makes QC fail until the spec is regenerated.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `sampling.nominal_times is not set ... and the data have no nominal-time column` | Add the `sampling:` block, or map the data's nominal-time column in `analysis-nca.R` (`NOMINAL_TIME_COL`). |
| `Nominal times in the data not in project.yaml sampling.nominal_times` | The data column and the schedule disagree. Fix the schedule, or remove it to use the data's times. |
| Warning "matching each sample to the nearest nominal time" | Participants have different numbers of samples. Check the schedule and duplicate records. |
| Two legends | Single group without `pk_legend()`. |
| Crowded x ticks on the semi-log plot | Keep `scale_x_continuous(breaks = scales::breaks_pretty(8))`. |
| Figure missing from the spec | `list_outputs()` only finds `.png`/`.jpg`/`.jpeg`/`.pdf`/`.rtf` files named after the script. |
| `could not find function "gg_pkc_lineplot"` | Install crane (tested with 0.3.2). |

Verified with crane 0.3.2, docorator 0.7.0, patchwork 1.3.2 and ggplot2 4.0.1.

## Related

- [pk-nca](pk-nca.md), [pk-nca-database](pk-nca-database.md),
  [pk-nca-tables](pk-nca-tables.md), [pk-nca-run-spec](pk-nca-run-spec.md),
  [pk-nca-report](pk-nca-report.md), [pk-project](pk-project.md)
- [SKILL.md](../../.posit/assistant/skills/pk-nca-figures/SKILL.md)
- [NCA workflow guide](../pk-nca/README.md)

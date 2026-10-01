---
name: pk-nca-figures
description: Creates production NCA figures: mean and individual concentration-time plots, and terminal-phase (lambda z) regression and half-life diagnostics. Use when the user asks for PK plots, mean or individual profiles, spaghetti plots or half-life plots from an NCA.
---

# NCA figures (crane + docorator)

Companion to `pk-nca` and `pk-nca-tables`. Each figure is one `fig-*.R` script in
`script/nca/v{n}/`, scaffolded by `new_version("nca")` (pk-project) from
`file:///{skill_dir}/templates/`, and rendered with **the same docorator shell as the
tables**: analysis title and "Page x of y" in the header, script path and date-time in the
footer. The shell is the shared `render_tlf()` (`pk-project/scripts/tlf_shell.R`): header with analysis title and page, then the **figure title and subtitle** as centred lines (passed as `title =`/`subtitle =`, the counterpart of `tfrmt(title =, subtitle =)` for tables; never `labs(title/subtitle)` or `plot_annotation()`); footer with **"Source data: <file>"** (from `read_nca_db()`'s metadata), script path and date-time. Text is **11 pt serif**: `theme_pk()` uses `base_size = 11` and `render_tlf()` sets the plot text family to serif (`tlf_serif()`), matching the tables. The header is the same on every page, so one-page-per-participant figures carry only a short page label in the plot ("Participant 3 ..."). Every script reads the version's database (`read_nca_db()`) and never re-runs PKNCA.

| Template | Output | Contents |
|---|---|---|
| `templates/fig-mean-conc.R` | `fig-mean-conc.pdf` (+ `.RDS`) | `crane::gg_pkc_lineplot()` mean (SD) by nominal time, linear scale, **numeric time axis** (true spacing), LLOQ line; `crane::annotate_pkc_df()` n / mean / SD table at selected timepoints (`table_times`, default: automatically spaced) |
| `templates/fig-mean-conc-semilog.R` | `fig-mean-conc-semilog.pdf` (+ `.RDS`) | the same statistic on a semi-log scale, actual spacing of the nominal times, LLOQ line |
| `templates/fig-ind-conc.R` | `fig-ind-conc.pdf` (+ `.RDS`) | **one page per participant**: linear and semi-log panels (patchwork), participant, dose and route in the page label, LLOQ line; paginated like `tbl-conc-by-nominal-time` |
| `templates/fig-lambdaz.R` | `fig-lambdaz.pdf` (+ `.RDS`) | **one page per participant**: terminal-phase regression on a semi-log scale, points used in the regression filled, **regression line in red**. The line is PKNCA's own fit rebuilt from the stored results (`clast.pred`, `lambda.z`, `lambda.z.time.first/last`), not a refit. λz, t½, adj. R², span ratio and points in the caption; span ratio < 2 flagged in the page label |

`pk-nca` adds one more figure in the same shell, `fig-halflife-diagnostics.pdf` (span ratio
vs adjusted R-squared, all participants). Every NCA figure is a PDF (RTF without TinyTeX)
plus its `.RDS`; none is a PNG.

Helpers: `file:///{skill_dir}/scripts/nca_figures.R`
- `render_pk_display(p, name, out_dir, cfg, source_data =, title =, subtitle =)`: `render_tlf()`
  for figures. `p` is a ggplot, or a list of ggplots for one page each; `title`/`subtitle`
  are the figure's, placed in the docorator header.
- `spaced_times(times, min_gap = 0.08)`: timepoints at least 8% of the range apart (first and
  last always kept), for the mean plot's ticks and summary-table columns.
- `pk_legend()`: hides crane's redundant legend when there is a single group.
- `participant_order()`, `theme_pk()` (the shared `theme_tlf()`: theme_bw, 11 pt serif; `pk-project/scripts/figure_helpers.R`).

## Consistency rules

- **One nominal-time definition.** If the source data have a nominal-time column (CDISC
  `NFRLT`/`NRRLT`, `NTIME`, ...), `analysis-nca.R` carries it as `ntime` and it wins. The
  `project.yaml` schedule is then optional, and if present every data value must be on it.
  Otherwise the schedule and LLOQ live in `project.yaml`:

  ```yaml
  sampling:
    nominal_times: [0, 0.25, 0.5, 1, 2, 3.5, 5, 7, 9, 12, 24]
    nominal_labels: [Predose, "0.25", "0.5", "1", "2", "3.5", "5", "7", "9", "12", "24"]  # optional
    lloq: 0.1                                                                           # optional
  ```

  Every nominal-time output (`fig-mean-conc*.R`, `tbl-conc-by-nominal-time.R`) assigns times
  with `assign_nominal_time()` (`pk-nca/scripts/nca_nominal.R`). Samples are matched by rank
  when every participant has one sample per nominal time, and to the nearest time otherwise,
  with a warning. So the figure's n and mean at each timepoint equal the table's N and Mean.
- **Same rounding as the table.** `annotate_pkc_df(digits = c(0, 1, 1))` matches
  `tbl-conc-by-nominal-time`'s `frmt("xx.x")`. Change both together.
- **Same grouping in both mean plots.** `fig-mean-conc.R` and `fig-mean-conc-semilog.R` each
  have the same EDIT block (grouping, `stat`, `variability`); keep them identical. For dose
  groups, join `doseData` and set `group` (example in the EDIT block).
- **The report reuses the QC'd images.** docorator stores each figure in its `.RDS` as the
  rendered pixel array. `generate-spec.R` records the `.RDS` hash (`display_rds`), and
  `pk-nca-report` writes those arrays back to PNG. Report figures are therefore
  pixel-identical to the QC'd PDFs, with individual plots one participant per page.

## crane notes (0.3.2)

- `gg_pkc_lineplot(data, time_var, analyte_var, group, stat = c("mean", "median"), variability = c("sd", "se", "ci", "iqr", "none"), conf_level, log_y, lloq)` returns a ggplot. Use the **numeric** nominal time (`ntime`) so the axis is spaced in real time; a factor axis spaces 0.25 h and 12 h equally, which distorts the profile. To keep the summary table readable, give `annotate_pkc_df()` only the rows at `table_times` and set `scale_x_continuous(breaks = table_times)`. crane's message recommending a factor time applies only to decimal formatting in its table.
- `annotate_pkc_df(gg_plt, data, time_var, analyte_var, group, summary_stats = c("n", "mean", "sd"), digits, text_size, rel_height_plot)` returns a ggplot with the summary table below it. Pass the variables as strings when the plot was built with a factor time.
- On the log scale, zero means and lower error bounds at or below zero can't be drawn; the semi-log caption says so.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `project.yaml: sampling.nominal_times is not set ... and the data have no nominal-time column` | add the `sampling:` block, or map the data's nominal-time column in `analysis-nca.R` (`NOMINAL_TIME_COL`) |
| `Nominal times in the data not in project.yaml sampling.nominal_times: ...` | the data column and the schedule disagree; fix the schedule (or remove it to use the data's times) |
| `... record(s) have no nominal time in the data` | missing values in the nominal-time column (e.g. unscheduled samples); decide how to handle them in `analysis-nca.R` |
| Warning "matching each sample to the nearest nominal time" | participants have different numbers of samples; check the schedule, and whether duplicates are reported |
| Mean points not connected (log: "Each group consists of only one observation") | factor time axis without `aes(group = group)` |
| Two legends | single group without `pk_legend()` |
| Crowded x ticks on the semi-log plot | keep `scale_x_continuous(breaks = scales::breaks_pretty(8))` |
| Figure missing from the spec | `list_outputs()` recognises figure `.png`/`.jpg`/`.jpeg`/`.pdf`/`.rtf` named after the script |
| `could not find function "gg_pkc_lineplot"` | `install.packages("crane")` (tested 0.3.2) |

Verified with crane 0.3.2, docorator 0.7.0, patchwork 1.3.2, ggplot2 4.0.1.

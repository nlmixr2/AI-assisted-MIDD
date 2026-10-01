# `pk-nca-tables`

Builds the production NCA tables of a version with tfrmt and docorator: individual PK
parameters, and concentrations by nominal sample time. Every table uses the same 11 pt serif
TLF shell as the figures, so all outputs of the template look the same.

## When it is used

- After an NCA has run ([pk-nca](pk-nca.md)), when you want a PK parameter table, a
  concentration table, a TLF table or a presentation-ready table.
- When you ask how to format NCA results with tfrmt.
- When you add a custom table to an NCA version (scaffold it with `new_tlf()`, see
  [pk-project](pk-project.md)).
- Neighbouring tasks: figures are [pk-nca-figures](pk-nca-figures.md); the PDF report that
  collects the tables is [pk-nca-report](pk-nca-report.md).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| `tbl-pk-parameters.pdf` | `output/nca/v{n}/tables/` | One row per participant (numeric ID order), one column per requested PK parameter with its unit, then N, Mean, Median and Min, Max rows. |
| `tbl-conc-by-nominal-time.pdf` | `output/nca/v{n}/tables/` | One row per participant, one column per nominal sample time under a "Nominal Postdose Sample Time" span header, then N, Mean, Median, Min, Max, BLQ N and %BLQ rows. Four time columns per page. |
| `tbl-<name>.RDS` | `output/nca/v{n}/tables/` | The rendered `gt` object saved next to each PDF. The spec records its hash (`display_rds`) and the report prints it. |

Without TinyTeX the tables are written as RTF instead of PDF.

## How to use it

1. Scaffold the version. Both table scripts are copied into `script/nca/v{n}/`:

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   new_version("nca")
   ```

2. Edit only the `EDIT` blocks:
   - `tbl-pk-parameters.R`: `subtitle`, `display_names` (column names per PPTESTCD code),
     `param_digits` (default `tmax = 2`) and `default_digits` (default `1`). The digits
     apply to a parameter's participant rows and to its Mean, Median and Min, Max rows.
   - `tbl-conc-by-nominal-time.R`: `times_per_page` (default `4`).
3. Set the nominal times and the LLOQ in `project.yaml` under `sampling:` (`nominal_times`,
   optional `nominal_labels`, optional `lloq`), unless the data carry a nominal-time column
   (`ntime`), which then wins.
4. Run the whole version, so the spec and QC are refreshed after the tables:

   ```r
   run_version("nca", 1L)
   ```

5. For an extra table, scaffold it in the same shell:

   ```r
   new_tlf("nca", 1L, "tbl-auc-by-dose", title = "...", footnotes = c("..."))
   ```

Typical prompts: "Make the PK parameter table for NCA v2", "Show half-life with two
decimals", "Add a table of AUC by dose group", "Why does the concentration table show
BLQ?".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `templates/tbl-pk-parameters.R` | Individual PK-parameter table. Column labels come from `display_names` plus the unit PKNCA attaches (`PPORRESU`). |
| `templates/tbl-conc-by-nominal-time.R` | Concentration table by nominal time, paginated, with BLQ counts. |
| `read_nca_db()` | Loads `cObsData`, `ncaRes`, `res_wide` from the database; no PKNCA re-run. |
| `render_tlf()` | The shared shell (`pk-project/scripts/tlf_shell.R`): header with analysis title and page number, footer with "Source data:", script path and date-time. |
| `summary_ard()` | N, Mean, Median, Min and Max per group in long format, plus extra statistics (for example `BLQ_N = sum(blq)`). |
| `fs()`, `frmt_dp()`, `frmt_min_max()`, `frmt_sig3()` | Short forms of `frmt_structure()` and common number formats. |
| `per_param_body_plan()` | Body plan with one precision per parameter column. |
| `stat_row_label()`, `add_row_order()`, `participant_levels()` | Min/Max on one row, explicit row order for tfrmt, numeric participant order. |
| `tlf_footnotes()` | Footnote plan from strings; a named note marks that row label. |
| `assign_nominal_time()`, `nominal_schedule()` | `pk-nca/scripts/nca_nominal.R`: the single definition of nominal times, shared with the mean figures. |
| `references/tfrmt-guide.md` | tfrmt concepts behind the helpers, and a gotchas table. |
| `assets/table-config-template.yaml` | Optional template for shared labels and footnote text; copy it into the project, do not point scripts at the skill folder. |

## Rules and checks

- Tables read results with `read_nca_db()`; only `analysis-nca.R` runs PKNCA.
- No hard-coded study values. Title parts, study ID and units come from `project.yaml`.
- Every table goes through `render_tlf()`; never `ggsave()` or a hand-built
  `as_docorator()`.
- Output file names carry no version suffix; the version lives in the folder
  `output/nca/v{n}/tables/`.
- Nominal times come from `assign_nominal_time()`, so the table's N and Mean at each time
  equal the mean figure's n and mean. BLQ means a concentration of 0, or below
  `sampling.lloq` when it is set.
- Keep the `.RDS` next to each PDF. `generate-spec.R` hashes it and the report reuses it.
- Re-running a table after `generate-spec.R` makes QC fail until the spec is regenerated.
  Use `run_version()` to keep the order.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Column 'x' doesn't exist` or `Must group by variables found in .data` | One data column was passed to two of `tfrmt()`'s `label`/`column`/`param`/`value` roles. Give each role its own column. |
| Rows in the wrong order | tfrmt does not sort by factor levels. Use `add_row_order()` and `sorting_cols = row_ord`. |
| Summary rows duplicated, extra column visible | An extra column (for example `PPTESTCD`) was kept after `pivot_longer()`. Use `transmute()` to keep only the mapped columns. |
| `render_pdf()` fails or hangs; RTF written instead of PDF | No LaTeX. Check `tinytex::is_tinytex()`; install with `tinytex::install_tinytex()`. |
| Message that docorator has no `render_pdf(header_latex =)` | The installed docorator is older than the development version; tables keep its default typewriter font instead of serif. |

Verified against tfrmt 0.4.0 and docorator 0.7.0. If errors look like API drift, re-check
the function signatures (`?tfrmt`, `?as_docorator`).

## Related

- [pk-nca](pk-nca.md), [pk-nca-database](pk-nca-database.md),
  [pk-nca-figures](pk-nca-figures.md), [pk-nca-run-spec](pk-nca-run-spec.md),
  [pk-nca-report](pk-nca-report.md), [pk-project](pk-project.md)
- [SKILL.md](../../.posit/assistant/skills/pk-nca-tables/SKILL.md)
- [NCA workflow guide](../pk-nca/README.md)

# tfrmt/docorator concepts behind the table templates

Background for `templates/tbl-pk-parameters.R` and `templates/tbl-conc-by-nominal-time.R`.
Read this when adapting those templates or debugging unexpected `tfrmt` output. The
templates use the shared helpers in `pk-project/scripts/tfrmt_helpers.R` (sourced with the
TLF shell); each section below names the helper that implements it.

## Contents

- Mapping roles: label / column / param / value
- Row order: sorting_cols
- Two kinds of body_plan rules: label_val vs param_val
- Span (two-level) column headers
- Combining two stats into one row
- Percent formatting
- Footnotes for abbreviations
- Column-count pagination
- Gotchas

## Mapping roles: label / column / param / value

`tfrmt()`'s `label`, `column`, `param`, and `value` arguments must each reference a
**distinct column name** in the data, even when two of them logically hold the same
content (e.g. a row-label column and a formatting-lookup column both derived from the
same source code). Reusing one column for two roles causes `tfrmt` to silently drop it
while processing the first role, then fail on the second with a misleading
`Column 'x' doesn't exist` error. Always create a separate (even if duplicate-valued)
column per role — both templates do this (e.g. `row_id` vs `stat_type`).

## Row order: sorting_cols

`tfrmt` does **not** sort rows by an R factor's `levels()` automatically. Pass an
explicit integer `sorting_cols` column (e.g. `row_ord = as.integer(row_id)`, where
`row_id`'s factor levels are already in the desired display order) — otherwise rows
follow the input data's original (often arbitrary) order. Helper: `add_row_order(ard, levels)`
sets `row_id`'s levels and adds `row_ord`; drop it from the table with `col_plan(..., -row_ord)`.

## Two kinds of body_plan rules: label_val vs param_val

Both templates stack per-subject rows and summary-statistic rows (N, Mean, Median,
Min/Max, ...) into one row-label factor, so two independent matching mechanisms coexist
in `body_plan()`'s `frmt_structure()` calls:

- **By `label_val`**: matches a specific row label exactly (e.g.
  `frmt_structure(label_val = "N", frmt("xx"))` formats the N row as an integer,
  regardless of column).
- **By `param_val`**: pass a named `frmt()`/`frmt_when()`/`frmt_combine()` in the `...`,
  keyed by the `param` column's value (e.g. `tmax = frmt("xx.xx")` gives Tmax two
  decimals). This only affects rows whose `param` value matches — summary rows use
  `param` values like `"N"`/`"Mean"`, so a `tmax =` rule never touches them.

Helper: `fs(frmt, label =)` writes either kind (`fs(frmt("xx"), label = "N")`,
`fs(tmax = frmt_dp(2))`); `per_param_body_plan()` builds the full per-parameter plan.

## Span (two-level) column headers

Pass `column = c(span_col, sub_col)` to `tfrmt()`, where `span_col` is a constant string
(e.g. `"Nominal Postdose Sample Time"`) repeated on every row and `sub_col` holds the
individual column labels. The first level renders as a spanning header above the second.

## Combining two stats into one row

To display `"(min, max)"` as a single cell: give both stats the same `label` value (e.g.
`"Min, Max"`) but distinct `param` values (`"Min"`, `"Max"`), then target that
`label_val` in `body_plan()` with
`frmt_combine("({Min}, {Max})", Min = frmt("xx.x"), Max = frmt("xx.x"))`. Helpers:
`stat_row_label()` maps Min and Max onto the "Min, Max" row; `frmt_min_max(1)` is the combine.

## Percent formatting

`frmt()` templates accept literal characters alongside the `x` placeholders, e.g.
`frmt("xx.x%")`.

## Footnotes for abbreviations

Use `footnote_plan()` with one `footnote_structure()` per abbreviation, anchored via
`label_val` (e.g. explain `N`, `BLQ`, `%BLQ`, `Min, Max` where each first appears as a
row label). Helper: `tlf_footnotes(N = "N = ...", "general note")`.

## Column-count pagination

`tfrmt` has no built-in "max columns per page" option. Manually chunk the
column-defining variable (e.g. 4 nominal times at a time) and call `print_to_gt()` once
per chunk; bundle the resulting `gt` objects with `do.call(gt::gt_group, list_of_tables)`
so `docorator`/`render_pdf()` produces one multi-page document with the stub column
repeated on every page.

## Nominal-time derivation (concentration table)

`assign_nominal_time()` (`pk-nca/scripts/nca_nominal.R`) is the single definition, shared
with the mean-concentration figures. A nominal-time column in the data (`ntime`, carried by
`analysis-nca.R`) wins; every value must then be on the `project.yaml` schedule when one
is set. Without that column, times come from the schedule: matched by **rank** when every
participant has one sample per nominal time (the k-th sample gets the k-th time), otherwise
to the nearest nominal time with a warning. Nearest-value matching alone can double-book a
nominal time for one subject while leaving another empty.

## Gotchas

| Symptom | Likely cause |
|---|---|
| `Column 'param' doesn't exist` / `Must group by variables found in .data` | The same data column was passed to two of `tfrmt()`'s `label`/`column`/`param`/`value` arguments. Give each role its own (even if duplicate-content) column. |
| Bare column name silently ignored, tfrmt uses an unrelated value | The column name collides with one of `tfrmt()`'s own argument names (e.g. a data column literally called `param`). Quote it as a string (`param = "param"`) or rename the column. |
| Nothing prints when you type `tbl` at the console | `print_to_gt()` returns a `gt_tbl`; render with `gt::gtsave()` to view outside a notebook/Positron plot pane. |
| `render_pdf()` fails or hangs | No LaTeX distribution installed. Check `tinytex::is_tinytex()`, install via `tinytex::install_tinytex()`, or use `render_rtf()` instead. |
| Rows print in factor-creation order, not the intended display order | `tfrmt` doesn't sort by an R factor's `levels()` automatically. Add an explicit integer `sorting_cols` column matching the desired order. |
| Summary-statistic rows appear duplicated, with an extra unwanted column visible | An identifying column (e.g. `PPTESTCD`) was carried through via `mutate()` after `pivot_longer()` instead of dropped. Use `transmute()` (or explicit `select()`) to keep only the columns mapped to `label`/`column`/`param`/`value` — any extra column is treated by `tfrmt` as an added grouping key. |

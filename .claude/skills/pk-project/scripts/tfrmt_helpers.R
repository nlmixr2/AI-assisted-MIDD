# Shared tfrmt building blocks for production tables (sourced by tlf_shell.R, so every tbl-*.R
# that sources the shell has them). They remove the boilerplate each table would otherwise
# repeat; the table's own choices (rows, columns, statistics, digits, footnotes) stay in its
# EDIT blocks.
#
#   fs(frmt_dp(1))                              frmt_structure(group_val/label_val = ".default", ...)
#   fs(frmt("xx"), label = "N")                 ... for one row label
#   frmt_dp(2) / frmt_sig3() / frmt_min_max(1)  "xx.xx" / 3 significant figures / "(min, max)"
#   summary_ard(d, value, by = col)             N, Mean, Median, Min, Max per group, long format
#   stat_row_label(stat_type)                   "Min"/"Max" -> "Min, Max" row
#   add_row_order(ard, levels)                  row_id factor + row_ord sort key for tfrmt
#   participant_levels(ids)                     participant IDs in numeric order
#   per_param_body_plan(params, digits)         body plan with one precision per parameter column
#   tlf_footnotes("general", N = "N = ...")      footnote_plan(); a name = the row label it marks

library(tfrmt)

#' frmt() with `digits` decimals ("xx" for 0).
frmt_dp <- function(digits, ...) frmt(if (digits <= 0) "xx" else paste0("xx.", strrep("x", digits)), ...)

#' Three significant figures (estimates of very different magnitudes in one column).
frmt_sig3 <- function() {
  frmt_when(">=100" ~ frmt("xxx"), ">=10" ~ frmt("xx.x"), ">=1" ~ frmt("x.xx"), TRUE ~ frmt("x.xxx"))
}

#' "(min, max)" from two statistics, both with `digits` decimals.
frmt_min_max <- function(digits, min = "Min", max = "Max") {
  do.call(frmt_combine, c(list(sprintf("({%s}, {%s})", min, max)),
                          stats::setNames(list(frmt_dp(digits), frmt_dp(digits)), c(min, max))))
}

#' frmt_structure() for every group; `label` restricts it to one row label.
fs <- function(..., label = ".default", group = ".default") {
  frmt_structure(group_val = group, label_val = label, ...)
}

#' Participant IDs in numeric order when they are numbers, otherwise alphabetical (character).
participant_levels <- function(x) {
  ids <- unique(as.character(x))
  num <- suppressWarnings(as.numeric(ids))
  if (anyNA(num)) sort(ids) else ids[order(num)]
}

#' N, Mean, Median, Min and Max of `value` for each `by` group, plus any extra statistics
#' given in `...` (e.g. BLQ_N = sum(blq)), as long rows: by, stat_type, value.
summary_ard <- function(data, value, by, ...) {
  data |>
    dplyr::summarise(N = dplyr::n(), Mean = mean({{ value }}), Median = stats::median({{ value }}),
                     Min = min({{ value }}), Max = max({{ value }}), ..., .by = {{ by }}) |>
    tidyr::pivot_longer(!{{ by }}, names_to = "stat_type", values_to = "value")
}

#' Row label of a summary statistic: Min and Max share the "Min, Max" row; `labels` renames others.
stat_row_label <- function(stat_type, labels = c()) {
  labels <- c(Min = "Min, Max", Max = "Min, Max", labels)
  ifelse(stat_type %in% names(labels), labels[stat_type], stat_type)
}

#' Make `row_id` a factor with `levels` and add `row_ord`, the explicit sort key tfrmt needs
#' (it does not sort by factor levels alone). Drop it from the table with col_plan(-row_ord).
add_row_order <- function(ard, levels) {
  ard$row_id <- factor(as.character(ard$row_id), levels = levels)
  ard$row_ord <- as.integer(ard$row_id)
  ard
}

#' Body plan for a table with one column per parameter (param = parameter code on the
#' participant rows, "<code><sep><stat>" on the summary rows): each parameter's rows, Mean,
#' Median and (Min, Max) share its number of decimals (`digits`, named by parameter code;
#' others use `default`); N is an integer.
per_param_body_plan <- function(params, digits = c(), default = 1, stats = c("Mean", "Median"),
                                n_label = "N", min_max_label = "Min, Max", sep = "__") {
  dp <- function(p) if (p %in% names(digits)) digits[[p]] else default
  one <- function(label, param, fmt) do.call(fs, c(stats::setNames(list(fmt), param), list(label = label)))
  do.call(body_plan, c(
    list(fs(frmt_dp(default))),
    lapply(params, function(p) one(".default", p, frmt_dp(dp(p)))),
    unlist(lapply(params, function(p) lapply(stats, function(st) one(st, paste0(p, sep, st), frmt_dp(dp(p))))),
           recursive = FALSE),
    list(fs(frmt("xx"), label = n_label)),
    lapply(params, function(p) fs(frmt_min_max(dp(p), paste0(p, sep, "Min"), paste0(p, sep, "Max")),
                                  label = min_max_label))
  ))
}

#' footnote_plan() from strings: an unnamed footnote applies to the table, a named one marks
#' that row label (e.g. N = "N = number of subjects"). NULL when there are none.
tlf_footnotes <- function(...) {
  notes <- unlist(list(...))
  if (!length(notes)) return(NULL)
  rows <- names(notes) %||% rep("", length(notes))
  do.call(footnote_plan, unname(Map(function(text, row) {
    if (nzchar(row)) footnote_structure(text, label_val = row) else footnote_structure(text)
  }, notes, rows)))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

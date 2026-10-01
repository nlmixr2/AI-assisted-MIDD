# Nominal (protocol) sample times -- one definition shared by every NCA output that works
# by nominal time (tbl-conc-by-nominal-time.R, fig-mean-conc*.R), so tables and figures
# always agree on which sample belongs to which timepoint.
#
# Two sources, in order of preference:
#
# 1. A nominal-time column in the source data (e.g. CDISC ADPC NFRLT / NRRLT, or NTIME),
#    carried into cObsData as `ntime` by analysis-nca.R (see detect_nominal_time_col()).
#    It is part of the hash-verified NCA database, so every output uses the protocol's own
#    assignment. If project.yaml also has a schedule, every data value must be on it.
# 2. Otherwise, the schedule in project.yaml, matched to actual times:
#
#   sampling:
#     nominal_times: [0, 0.25, 0.5, 1, 2, 3.5, 5, 7, 9, 12, 24]   # in units$time
#     nominal_labels: [Predose, "0.25", "0.5", "1", "2", "3.5", "5", "7", "9", "12", "24"]  # optional
#     lloq: 0.1                                                    # optional, in units$conc
#
#   sched <- nominal_schedule(cfg, required = !"ntime" %in% names(cObsData))
#   conc  <- assign_nominal_time(cObsData, sched)   # + ntime (numeric), ntime_label (factor)

#' Common nominal-time column names, in order of preference (CDISC ADPC first).
nominal_time_candidates <- c("NFRLT", "NRRLT", "NTIME", "NOMTIME", "NTPD", "TNOM")

#' The source data's nominal-time column, or NA if there is none.
#'
#' Checks `nominal_time_candidates` case-insensitively and returns the first match (its
#' actual spelling). For multiple-dose data, NRRLT (relative to the reference/last dose) and
#' NFRLT (relative to the first dose) differ -- choose deliberately in analysis-nca.R.
detect_nominal_time_col <- function(data) {
  hit <- names(data)[match(tolower(nominal_time_candidates), tolower(names(data)))]
  hit <- hit[!is.na(hit)]
  if (length(hit)) hit[1] else NA_character_
}

#' Sampling schedule from project.yaml.
#'
#' @param required If TRUE (default), error when the schedule is not set. Pass FALSE when
#'   the data carry nominal times (`ntime` in cObsData): the schedule is then optional and,
#'   if given, only supplies labels and a consistency check.
#' @return list(times, labels, lloq); times/labels are NULL when not set and not required.
nominal_schedule <- function(cfg, required = TRUE) {
  s <- cfg$sampling
  times <- suppressWarnings(as.numeric(unlist(s$nominal_times)))
  lloq <- suppressWarnings(as.numeric(s$lloq %||% NA_real_))
  lloq <- if (length(lloq)) lloq else NA_real_
  if (!length(times) || anyNA(times)) {
    if (required) {
      stop("project.yaml: sampling.nominal_times is not set (list of nominal sample times in ",
           cfg$units$time, "), and the data have no nominal-time column", call. = FALSE)
    }
    return(list(times = NULL, labels = NULL, lloq = lloq))
  }
  labels <- if (length(s$nominal_labels)) as.character(unlist(s$nominal_labels)) else
    ifelse(times == 0, "Predose", format(times, trim = TRUE, drop0trailing = TRUE))
  if (length(labels) != length(times)) {
    stop("project.yaml: sampling.nominal_labels must have one label per nominal time", call. = FALSE)
  }
  list(times = times, labels = labels, lloq = lloq)
}

#' Add nominal time (ntime) and its label (ntime_label, a factor in time order).
#'
#' - If cObsData already has `ntime` (from the source data), it is used as is. With a
#'   schedule, every value must be one of the schedule's times (error listing the others)
#'   and the schedule's labels are used; without one, labels are the formatted times.
#' - Otherwise times come from the schedule: matched by rank when every participant has one
#'   sample per nominal time, else to the nearest nominal time (with a warning).
assign_nominal_time <- function(cObsData, sched) {
  d <- cObsData[order(cObsData$participant, cObsData$time), ]
  fmt <- function(t) ifelse(t == 0, "Predose", format(t, trim = TRUE, drop0trailing = TRUE))

  if ("ntime" %in% names(d)) {
    if (anyNA(d$ntime)) stop(sum(is.na(d$ntime)), " concentration record(s) have no nominal time in the data",
                             call. = FALSE)
    if (length(sched$times)) {
      off <- setdiff(unique(d$ntime), sched$times)
      if (length(off)) {
        stop("Nominal times in the data not in project.yaml sampling.nominal_times: ",
             paste(sort(off), collapse = ", "), call. = FALSE)
      }
      d$ntime_label <- factor(sched$labels[match(d$ntime, sched$times)],
                              levels = sched$labels[sched$times %in% d$ntime])
    } else {
      lv <- sort(unique(d$ntime))
      d$ntime_label <- factor(fmt(d$ntime), levels = fmt(lv))
    }
    return(d)
  }

  if (!length(sched$times)) stop("No nominal times: neither an ntime column nor a schedule", call. = FALSE)
  n_per <- table(d$participant)
  if (all(n_per == length(sched$times))) {
    idx <- ave(seq_len(nrow(d)), d$participant, FUN = seq_along)
  } else {
    warning("Participants do not all have ", length(sched$times), " samples; matching each ",
            "sample to the nearest nominal time.", call. = FALSE)
    idx <- vapply(d$time, function(t) which.min(abs(sched$times - t)), integer(1))
    dup <- duplicated(data.frame(d$participant, idx))
    if (any(dup)) warning(sum(dup), " sample(s) share a nominal time with another sample of ",
                          "the same participant.", call. = FALSE)
  }
  d$ntime <- sched$times[idx]
  d$ntime_label <- factor(sched$labels[idx], levels = sched$labels)
  d
}

#' Where this version's nominal times come from (for the spec and the report).
nominal_time_source <- function(cObsData) {
  col <- attr(cObsData, "nominal_time_col")
  if ("ntime" %in% names(cObsData)) {
    sprintf("source data column %s", if (is.null(col)) "(ntime)" else col)
  } else {
    "project.yaml sampling.nominal_times, matched to actual times"
  }
}

`%||%` <- function(x, y) if (is.null(x)) y else x

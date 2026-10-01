# Helpers for logging an NCA script's run to a timestamped file under
# output/nca/v{project_number}/logs/, and for checking session hygiene at the top of a script
# as a safer drop-in replacement for rm(list = ls()) (see
# https://blog.djnavarro.net/posts/2026-01-06_sessioncheck/). Source this
# file, then bookend a script's body with:
#
#   nca_log_start("analysis-nca", project_number = 1L)
#   nca_log_section("1. Load data")     # optional timed step marker
#   ... rest of the script ...
#   nca_log_stop()
#
# nca_log_start() writes a framed header (script, project_number, analysis, script file,
# user -- from whoami::username() --, start time, R version, git commit),
# runs sessioncheck::sessioncheck() if the package is installed (warns by
# default -- see sessioncheck_action -- rather than silently wiping the
# environment the way rm(list = ls()) does) and records its findings, then
# diverts stdout (split so it still prints to the console) and messages/
# warnings into the log file for the rest of the script. nca_log_stop()
# appends a run summary (status, finish time, elapsed time, output files the run wrote)
# and sessionInfo() (package versions matter for reproducibility), then restores normal
# output. If the script errors, an options(error =) handler writes the same summary with
# status FAILED and restores output.
#
# Log files are timestamped, not overwritten on re-run -- unlike
# output/nca/v{n}/{tables,figures}, a log is a historical record of one execution,
# not "the current state" of an artifact. One version can accumulate many log
# files across repeated runs; that's intentional.
#
# All paths are relative to the current working directory (the project root).

#' Start logging an NCA script's run to a timestamped file.
#'
#' @param script_name Short identifier for the script (e.g. `"analysis-nca"`,
#'   `"tbl-pk-parameters"`) -- becomes part of the log file name.
#' @param project_number Integer version number (matches the enclosing
#'   `script/nca/v{project_number}/` directory).
#' @param output_dir Parent directory of versioned output directories. Defaults
#'   to `"output/nca"`; logs are written to `{output_dir}/v{project_number}/logs/`,
#'   alongside that version's tables and figures.
#' @param sessioncheck_action One of `"warn"` (default), `"error"`, or
#'   `"message"`/`"none"` (see `?sessioncheck::sessioncheck`) -- what to do if
#'   the session looks contaminated (unexpected objects/packages already
#'   present). `"warn"` logs the finding and continues; use `"error"` for a
#'   stricter QC/CI context where a contaminated session should stop the run.
#'   Ignored (with a note written to the log) if the `sessioncheck` package
#'   isn't installed.
#' @return (Invisibly) the path to the log file.
nca_log_start <- function(script_name, project_number, output_dir = "output/nca",
                           sessioncheck_action = "warn") {
  project_number <- as.integer(project_number)
  version_out <- file.path(output_dir, sprintf("v%d", project_number))
  version_dir <- file.path(version_out, "logs")
  dir.create(version_dir, recursive = TRUE, showWarnings = FALSE)
  started <- Sys.time()
  log_path <- file.path(version_dir, sprintf("%s-%s.log", script_name, format(started, "%Y%m%dT%H%M%S")))
  con <- file(log_path, open = "wt")

  # Who ran it: whoami::username() checks LOGNAME/USER/USERNAME, then the
  # `whoami` command; fall back to the OS login (noted in the log) if the
  # package isn't installed.
  user <- if (requireNamespace("whoami", quietly = TRUE)) {
    whoami::username(fallback = Sys.info()[["user"]])
  } else {
    paste(Sys.info()[["user"]], "(whoami not installed -- OS login)")
  }
  type <- basename(output_dir)
  script_file <- file.path("script", type, sprintf("v%d", project_number), paste0(script_name, ".R"))

  # The header keys `# project_number: N` and the later `# sessionInfo():` line are read by the
  # QC suites (pk-nca-qc-tests, poppk-qc-tests, poppk-simulation): keep them verbatim.
  writeLines(c(
    .nca_log_rule("="),
    sprintf("#  %s run log  |  %s  |  v%d", .nca_log_type_label(type), script_name, project_number),
    .nca_log_rule("="),
    .nca_log_kv("script", script_name),
    .nca_log_kv("project_number", project_number),
    .nca_log_kv("analysis", type),
    .nca_log_kv("script_file", if (file.exists(script_file)) script_file else paste(script_file, "(not found)")),
    .nca_log_kv("user", user),
    .nca_log_kv("started_at", format(started, "%Y-%m-%dT%H:%M:%S%z")),
    .nca_log_kv("r_version", paste(R.version$major, R.version$minor, sep = ".")),
    .nca_log_kv("git_commit", .nca_log_git()),
    "#"
  ), con)

  writeLines(.nca_log_heading("Session check"), con)
  if (requireNamespace("sessioncheck", quietly = TRUE)) {
    chk <- withCallingHandlers(
      sessioncheck::sessioncheck(action = sessioncheck_action),
      warning = function(w) invokeRestart("muffleWarning")
    )
    chk_df <- as.data.frame(chk)
    flagged <- chk_df[chk_df$status, ]
    if (nrow(flagged) == 0) {
      writeLines("#   clean session", con)
    } else {
      # One line per kind; it includes what the script itself loaded before nca_log_start().
      for (kind in unique(flagged$type)) {
        writeLines(strwrap(paste(flagged$entity[flagged$type == kind], collapse = ", "),
                           width = 92, initial = sprintf("#   %-10s ", paste0(kind, ":")),
                           prefix = sprintf("#   %-10s ", "")), con)
      }
      writeLines("#   (includes what the script loaded before nca_log_start())", con)
    }
  } else {
    writeLines("#   skipped: sessioncheck not installed (install.packages(\"sessioncheck\") recommended)", con)
  }
  writeLines(c("#", .nca_log_heading("Output")), con)

  sink(con, split = TRUE, type = "output")
  sink(con, type = "message")
  options(
    nca_log.con = con,                  # remembered so nca_log_resume() can re-attach it
    nca_log.started = started,
    nca_log.out_dir = version_out,
    nca_log.files_before = .nca_log_snapshot(version_out),
    nca_log.error_handler = getOption("error"),
    # On an error the script stops before nca_log_stop(): close the log with a FAILED summary.
    error = function() .nca_log_footer(status = "FAILED (stopped on the error above)", session_info = FALSE)
  )

  invisible(log_path)
}

#' Start a titled, timed step in the log (e.g. `nca_log_section("1. Load data")`).
#'
#' Prints a rule with the step title, the clock time and the time since `nca_log_start()`, so a
#' long log can be scanned by step. Harmless (prints to the console) when no log is active.
nca_log_section <- function(title) {
  started <- getOption("nca_log.started")
  when <- format(Sys.time(), "%H:%M:%S")
  if (!is.null(started)) when <- sprintf("%s (+%s)", when, .nca_log_elapsed(started))
  cat("\n", .nca_log_heading(title, right = when), "\n\n", sep = "")
  invisible(NULL)
}

#' Re-attach the log's message sink if something reset it.
#'
#' Some packages reset R's message sink while running (seen with rxode2 model piping and
#' nlmixr2save's `:=` / loadFit()). Messages, warnings and errors then silently stop reaching
#' the log for the rest of the script. Call this after such steps; it does nothing when the
#' sink is intact or no log is active.
#'
#' @return (Invisibly) TRUE if the sink was re-attached.
nca_log_resume <- function() {
  con <- getOption("nca_log.con")
  if (is.null(con) || !isOpen(con) || sink.number(type = "message") != 2L) return(invisible(FALSE))
  sink(con, type = "message")
  invisible(TRUE)
}

#' Stop logging (pair with `nca_log_start()`), appending `sessionInfo()`.
#'
#' Safe to call even if no log is currently active (checks `sink.number()`
#' first) -- e.g. if a script errored before reaching its own
#' `nca_log_start()` call.
#'
#' @return (Invisibly) `TRUE`.
nca_log_stop <- function() {
  .nca_log_footer(status = "completed", session_info = TRUE)
  invisible(TRUE)
}

## Internal helpers --------------------------------------------------------------------

.nca_log_width <- 88L

.nca_log_rule <- function(char = "-") paste0("# ", strrep(char, .nca_log_width - 2L))

.nca_log_kv <- function(key, value) sprintf("# %s: %s", key, value)

# "# -- Title ------------------------------ right"
.nca_log_heading <- function(title, right = "") {
  left <- sprintf("# -- %s ", title)
  right <- if (nzchar(right)) paste0(" ", right) else ""
  paste0(left, strrep("-", max(3L, .nca_log_width - nchar(left) - nchar(right))), right)
}

.nca_log_type_label <- function(type) {
  switch(type, nca = "NCA", poppk = "PopPK", `poppk-sim` = "Simulation", toupper(type))
}

.nca_log_git <- function() {
  out <- tryCatch(suppressWarnings(system2("git", c("rev-parse", "--short", "HEAD"),
                                           stdout = TRUE, stderr = FALSE)),
                  error = function(e) character())
  if (!length(out) || !is.null(attr(out, "status"))) return("not a git repository")
  dirty <- tryCatch(suppressWarnings(system2("git", c("status", "--porcelain", "--untracked-files=no"),
                                             stdout = TRUE, stderr = FALSE)),
                    error = function(e) character())
  paste0(out[1], if (length(dirty)) " (with uncommitted changes)" else "")
}

.nca_log_elapsed <- function(started) {
  secs <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  if (secs < 60) sprintf("%.1f s", secs) else sprintf("%d min %02d s", secs %/% 60, round(secs %% 60))
}

# Modification times of the version's output files (logs excluded), to report what a run wrote.
.nca_log_snapshot <- function(dir) {
  files <- list.files(dir, recursive = TRUE, full.names = TRUE)
  files <- files[!startsWith(files, file.path(dir, "logs"))]
  stats::setNames(file.mtime(files), files)
}

.nca_log_footer <- function(status, session_info) {
  started <- getOption("nca_log.started")
  out_dir <- getOption("nca_log.out_dir")
  if (!is.null(started) && sink.number(type = "output") > 0) {
    before <- getOption("nca_log.files_before")
    after <- .nca_log_snapshot(out_dir)
    written <- names(after)[is.na(before[names(after)]) | after > before[names(after)]]
    cat("\n", .nca_log_heading("Run summary"), "\n", sep = "")
    cat(.nca_log_kv("status", status), "\n", sep = "")
    cat(.nca_log_kv("finished_at", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), "\n", sep = "")
    cat(.nca_log_kv("elapsed", .nca_log_elapsed(started)), "\n", sep = "")
    cat(.nca_log_kv("files_written", if (length(written)) length(written) else "none"), "\n", sep = "")
    if (length(written)) cat(paste0("#   ", sort(written), "\n"), sep = "")
    if (session_info) {
      cat("#\n# sessionInfo():\n")
      print(utils::sessionInfo())
    }
    cat(.nca_log_rule("="), "\n", sep = "")
  }
  con <- getOption("nca_log.con")
  if (!is.null(started)) {
    # restore the error handler saved by nca_log_start() -- only while a log is active, so a
    # redundant nca_log_stop() does not clear a handler set after the log ended
    options(error = getOption("nca_log.error_handler"))
  }
  options(nca_log.con = NULL, nca_log.started = NULL, nca_log.out_dir = NULL,
          nca_log.files_before = NULL, nca_log.error_handler = NULL)
  if (sink.number(type = "message") > 0) sink(type = "message")
  if (sink.number(type = "output") > 0) sink()
  if (!is.null(con) && isOpen(con)) close(con)
  invisible(TRUE)
}

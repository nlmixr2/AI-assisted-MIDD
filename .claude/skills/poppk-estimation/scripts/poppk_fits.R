# Fit caching and portable fit archives with nlmixr2save
# (https://nlmixr2.github.io/nlmixr2save/). Source from analysis-poppk.R, then:
#
#   res <- fit_runs(models, pkData, est = "saem", control = saemControl(print = 0, seed = 1234),
#                   table = tableControl(cwres = TRUE, npde = TRUE), dir = fit_dir(project_number))
#   fits <- res$fits            # named list of fits; res$restored says which came from the cache
#   share_fit(final_run, dir)   # final model without subject data -> fits/shared/<run>-noData.zip
#
# How it works:
# - Each run is fitted with nlmixr2save's `:=` operator: `run001 := nlmixr2(run001, ...)`.
#   The result is saved as output/poppk/v{n}/fits/run001.zip (saveFit(): text + csv, records
#   the nlmixr2est/rxode2 versions). On a re-run the cached fit is RESTORED instead of refitted
#   when the model, method, control/table options and the estimation-relevant data columns are
#   unchanged -- any real change refits. A cache hit leaves the zip byte-identical, so its hash
#   in the spec stays valid.
# - The zips double as portable fit archives, readable without R's binary serialization
#   (complementing the hash-verified database blob), and are hashed in the spec and QC.
# - share_fit() writes fits/shared/<run>-noData.zip (nlmixr2saveShare()): the fit without origData,
#   for sharing outside the project; it still simulates (poppk-simulation "fit-file" source).
#
# Force a refit: delete output/poppk/v{n}/fits/<run>.zip (or set options(nlmixr2save.check)
# as documented by nlmixr2save). Never edit a zip by hand.

library(nlmixr2)
library(nlmixr2save)

#' Evaluate `expr` with the run log's message sink attached before and after.
#'
#' nlmixr2save's `:=` / loadFit() (and rxode2 model piping) reset R's message sink, which
#' silently stops nca_log_start()'s capture of messages and warnings for the rest of the
#' script. nca_log_resume() (pk-nca-logging) re-attaches the log's connection, so every
#' run stays fully logged.
with_message_sink <- function(expr) {
  resume <- function() if (exists("nca_log_resume", mode = "function")) nca_log_resume()
  resume()   # re-attach first, in case an earlier step (e.g. rxode2 model piping) reset it
  on.exit(resume(), add = TRUE)
  force(expr)
}

#' Restore the fit's ID column to a factor, as nlmixr2() returns it.
#'
#' A fit saved and reloaded by nlmixr2save (`:=` cache, loadFit()) comes back with an integer
#' ID, because the archive stores the fit data as CSV. Downstream code that joins the fit's ID
#' with ID-derived factors then fails, e.g. ggPMX's pmx_nlmixr() (data.table: "Incompatible
#' join types: x.ID (factor) and i.ID (integer)"). Estimates and OFV are unaffected.
restore_fit_id <- function(fit) {
  ids <- fit[["ID"]]
  if (is.null(ids) || is.factor(ids)) return(fit)
  fit[["ID"]] <- factor(ids, levels = sort(unique(ids)))
  fit
}

#' Directory holding a version's fit cache/archives.
fit_dir <- function(project_number, output_dir = "output/poppk") {
  file.path(output_dir, sprintf("v%d", as.integer(project_number)), "fits")
}

#' Fit every run with the nlmixr2save `:=` cache.
#'
#' @param models Named list of model functions (names = run IDs, e.g. "run001").
#' @param pkData The estimation dataset.
#' @param est,control,table Passed to nlmixr2() for every run (same for the whole trail).
#' @param dir Cache/archive directory (fit_dir(project_number)).
#' @return list(fits = named list of fits, restored = named logical: TRUE if loaded from cache).
fit_runs <- function(models, pkData, est, control, table = tableControl(), dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  old <- options(nlmixr2save.dir = dir, nlmixr2save.prefix = "")
  on.exit(options(old))
  env <- new.env(parent = globalenv())
  env$pkData <- pkData
  restored <- setNames(logical(length(models)), names(models))
  if (exists("nca_log_resume", mode = "function")) nca_log_resume()
  for (id in names(models)) {
    assign(id, models[[id]], envir = env)
    # nlmixr2save's `:=`, namespace-qualified (rlang/data.table also export `:=`)
    call <- bquote(nlmixr2save::`:=`(.(as.name(id)), nlmixr2(.(as.name(id)), pkData, est = .(est),
                                                             control = .(control), table = .(table))))
    message("Fitting ", id, " (nlmixr2save cache: ", file.path(dir, paste0(id, ".zip")), ")")
    with_message_sink(eval(call, envir = env))
    restored[[id]] <- isTRUE(nlmixr2save::.assignRestore())
    message(id, if (restored[[id]]) ": restored from cache (unchanged)" else ": fitted and saved")
  }
  list(fits = lapply(mget(names(models), envir = env), restore_fit_id), restored = restored)
}

#' Write a shareable copy of a cached fit without the original data (<run>-noData.zip).
#'
#' Only (re)written when the fit was refitted or the copy is missing: nlmixr2saveShare()
#' produces a new zip each time, which would change its hash although nothing changed.
#' @param refitted TRUE when the run was fitted in this session (fit_runs()$restored is FALSE).
#' @return Path of the zip.
share_fit <- function(run_id, dir, refitted = TRUE) {
  # Kept in fits/shared/, NOT next to the cache: restoring <run> from the `:=` cache unpacks
  # and cleans up files named <run>* in the cache folder, which would delete <run>-noData.zip.
  shared_dir <- file.path(dir, "shared")
  out <- file.path(shared_dir, paste0(run_id, "-noData.zip"))
  if (refitted || !file.exists(out)) {
    dir.create(shared_dir, recursive = TRUE, showWarnings = FALSE)
    old <- options(nlmixr2save.dir = dir, nlmixr2save.prefix = "")
    on.exit(options(old))
    with_message_sink(nlmixr2saveShare(run_id))
    file.rename(file.path(dir, paste0(run_id, "-noData.zip")), out)
  }
  out
}

#' Load a fit archive written by saveFit()/`:=`/nlmixr2saveShare() from any directory
#' (nlmixr2 must be attached for the restore -- this file attaches it).
load_fit_archive <- function(path) {
  if (!file.exists(path)) stop("Fit archive not found: ", path, call. = FALSE)
  # Load from a private temporary copy: loadFit() only finds bare names in the working
  # directory, and it unpacks the zip there and cleans up files sharing the fit's name --
  # which, in the archive folder, would delete e.g. run001-noData.zip next to run001.zip.
  tmp <- tempfile("fit-archive-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  file.copy(path, tmp)
  restore_fit_id(with_message_sink(withr::with_options(list(nlmixr2save.dir = NULL, nlmixr2save.prefix = ""),
    withr::with_dir(tmp, loadFit(sub("\\.zip$", "", basename(path)))))))
}

#' Spec entries for a version's fit archives: run fits and shared copies, with hashes.
fit_archive_entries <- function(dir) {
  zips <- sort(list.files(dir, pattern = "\\.zip$", full.names = TRUE, recursive = TRUE))
  lapply(zips, function(z) {
    base <- sub("\\.zip$", "", basename(z))
    list(path = z,
         run_id = sub("-noData(-noFit)?$", "", base),
         kind = if (grepl("-noData", base)) "shared (no subject data)" else "fit archive",
         hash = rlang::hash_file(z))
  })
}

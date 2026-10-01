# Helpers for building an NCA run-spec YAML (spec/nca/v{project_number}.yaml)
# that describes a versioned script directory, script/nca/v{project_number}/,
# containing one analysis-*.R (core PKNCA pipeline) plus one tbl-*.R per table
# and one fig-*.R per figure. Source this file, then:
#
#   meta      <- collect_run_metadata(project_number)         # hashes every .R in that version's dir
#   data_file <- collect_data_provenance("data/pk-data.csv")  # raw source-file hash
#   data_hash <- hash_data(conc = cObsData, dose = doseData)  # derived-object hash
#   outputs   <- list_outputs(project_number)                 # this version's output/nca/v{n}/{tables,figures} files
#   spec      <- c(meta, list(data_hash = data_hash, outputs = outputs), <fields you
#                fill in by reading the scripts -- see references/schema.md>)
#   write_spec(spec, project_number)
#   verify_spec(project_number); verify_outputs(project_number)
#
# Directory/naming convention this file assumes:
#   script/nca/v{project_number}/analysis-*.R   -- core pipeline, sourced by every tbl-/fig- script
#   script/nca/v{project_number}/tbl-<name>.R   -- one table each, e.g. tbl-pk-parameters.R
#   script/nca/v{project_number}/fig-<name>.R   -- one figure each, e.g. fig-halflife-diagnostics.R
#   output/nca/v{project_number}/tables/tbl-<name>.{pdf,rtf,docx} -- output of tbl-<name>.R
#   output/nca/v{project_number}/figures/fig-<name>.{pdf,rtf,png,jpg,jpeg} -- output of fig-<name>.R
#
# Output directories mirror the script directories: script/nca/v{n}/ writes
# only into output/nca/v{n}/, so one version's run never overwrites another
# version's tables/figures. Output file names themselves do NOT carry a
# project-number suffix -- the version lives in the directory, not the file
# name. list_outputs()/verify_outputs() below resolve and check "this version's"
# outputs by matching each tbl-/fig- script in script/nca/v{n}/ to its expected
# output file by basename inside output/nca/v{n}/.
#
# Each `outputs.tables`/`outputs.figures` entry should also carry a `hash` field
# (rlang::hash_file() of that specific file, set when the entry is assembled --
# see the pk-nca skill's run scripts' `annotate_outputs()` for the pattern), so
# verify_outputs() can later confirm a table/figure hasn't changed since spec
# generation.
#
# All hashing uses rlang::hash()/hash_file() (a fast xxhash-based digest) rather than
# tools::md5sum(), so the scripts, the input data file, the derived data objects, and
# the written spec file can all be fingerprinted the same way and cross-checked for
# consistency.
#
# All paths are relative to the current working directory (the project root).

library(yaml)
library(rlang)

#' Collect deterministic metadata about a versioned NCA script directory.
#'
#' Hashes every `.R` file in `script/nca/v{project_number}/` (typically one
#' `analysis-*.R` plus one `tbl-*.R` per table and one `fig-*.R` per figure) --
#' individually and combined -- rather than a single script file, since the
#' pipeline is now split across multiple files per version.
#'
#' @param project_number Integer or numeric version number; scripts must exist
#'   under `file.path(script_dir, sprintf("v%d", project_number))`.
#' @param script_dir Parent directory of versioned script directories.
#'   Defaults to "script/nca".
#' @return A named list: `project_number`, `script_dir` (the version's
#'   directory), `scripts` (basenames of every `.R` file found, sorted),
#'   `script_hashes` (named list of basename -> `rlang::hash_file()`),
#'   `scripts_combined_hash` (single hash over all `script_hashes`),
#'   `generated_at`, `r_version`, `packages` (named list of package ->
#'   installed version, detected via `library()`/`require()` calls across
#'   every script in the directory).
collect_run_metadata <- function(project_number, script_dir = "script/nca") {
  version_dir <- file.path(script_dir, sprintf("v%d", as.integer(project_number)))
  if (!dir.exists(version_dir)) {
    stop("Script directory not found: ", version_dir, call. = FALSE)
  }
  script_files <- sort(list.files(version_dir, pattern = "\\.R$", full.names = TRUE))
  if (length(script_files) == 0) {
    stop("No .R scripts found in ", version_dir, call. = FALSE)
  }

  lines <- unlist(lapply(script_files, readLines, warn = FALSE))
  pkg_matches <- regmatches(
    lines,
    regexpr("(?<=^library\\(|^require\\()[A-Za-z0-9_.]+", trimws(lines), perl = TRUE)
  )
  pkgs <- sort(unique(unlist(pkg_matches)))
  pkg_versions <- lapply(pkgs, function(p) {
    tryCatch(as.character(packageVersion(p)), error = function(e) NA_character_)
  })
  names(pkg_versions) <- pkgs

  script_hashes <- lapply(script_files, hash_file)
  names(script_hashes) <- basename(script_files)

  list(
    project_number = as.integer(project_number),
    script_dir = version_dir,
    scripts = as.list(basename(script_files)),
    script_hashes = script_hashes,
    scripts_combined_hash = hash(script_hashes),
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    packages = pkg_versions
  )
}

#' Fingerprint the input data objects a run depends on.
#'
#' Hashes each object with `rlang::hash()` (stable across sessions for the same
#' object content) plus a combined hash over all of them together, so the spec can
#' later be used to confirm the exact input data a run used hasn't changed.
#'
#' Complements `collect_data_provenance()`: this hashes the *derived* in-memory
#' objects the script built from the raw file (e.g. `cObsData`/`doseData` after
#' filtering/renaming); `collect_data_provenance()` hashes the raw file itself.
#' Record both when the spec was built from a file on disk -- they can diverge
#' if the data-wrangling step between file and objects has a bug.
#'
#' @param ... Named data objects (e.g. `conc = cObsData, dose = doseData`).
#' @return A named list: `combined` (single hash over all objects) and `components`
#'   (named list of per-object hashes, using the names supplied in `...`).
hash_data <- function(...) {
  objs <- list(...)
  if (is.null(names(objs)) || any(names(objs) == "")) {
    stop("hash_data() requires all arguments to be named.", call. = FALSE)
  }
  list(
    combined = hash(objs),
    components = lapply(objs, hash)
  )
}

#' Fingerprint the raw source data file a run reads from disk.
#'
#' Use this whenever the run's `analysis-*.R` script loads its input via a file
#' path (the expected case -- see the pk-nca skill's NCA Rules and
#' references/pipeline.md). Hashing the file itself (not just the data frame built from it)
#' lets a later check confirm the exact bytes on disk haven't changed,
#' independent of whether the script's own read/transform logic is re-run.
#'
#' @param path Path to the source data file (e.g. `"data/pk-data.csv"`),
#'   relative to the project root.
#' @return A named list: `path` (as supplied) and `hash` (`rlang::hash_file()`
#'   of the file's current contents).
collect_data_provenance <- function(path) {
  if (!file.exists(path)) {
    stop("Source data file not found: ", path, call. = FALSE)
  }
  list(path = path, hash = hash_file(path))
}

#' List this version's table and figure output files (for the outputs field).
#'
#' Resolves each `tbl-*.R`/`fig-*.R` script found in
#' `script/nca/v{project_number}/` to its expected output file by basename
#' match in `output/nca/v{project_number}/tables/` and
#' `output/nca/v{project_number}/figures/` (trying `.pdf`/`.rtf`/`.docx` for
#' tables and `.png`/`.jpg`/`.jpeg`/`.pdf`/`.rtf` for figures -- docorator figures are PDF/RTF). A script with no
#' matching output file yet (not run) is silently omitted, not an error --
#' re-run the script first if you expect its output in the list.
#'
#' @param project_number Integer version number.
#' @param script_dir Parent directory of versioned script directories.
#'   Defaults to "script/nca".
#' @param output_dir Parent directory of versioned output directories.
#'   Defaults to "output/nca"; tables and figures are looked up in
#'   `{output_dir}/v{project_number}/tables` and `.../figures`.
#' @return A named list with `tables` and `figures` character vectors of file paths.
list_outputs <- function(project_number, script_dir = "script/nca",
                          output_dir = "output/nca") {
  version_dir <- file.path(script_dir, sprintf("v%d", as.integer(project_number)))
  version_out <- file.path(output_dir, sprintf("v%d", as.integer(project_number)))
  tables_dir <- file.path(version_out, "tables")
  figures_dir <- file.path(version_out, "figures")
  if (!dir.exists(version_dir)) {
    stop("Script directory not found: ", version_dir, call. = FALSE)
  }

  resolve <- function(script_names, out_dir, exts) {
    unlist(lapply(script_names, function(s) {
      base <- tools::file_path_sans_ext(s)
      candidates <- file.path(out_dir, paste0(base, ".", exts))
      candidates[file.exists(candidates)]
    }))
  }

  tbl_scripts <- list.files(version_dir, pattern = "^tbl-.*\\.R$")
  fig_scripts <- list.files(version_dir, pattern = "^fig-.*\\.R$")

  list(
    tables = resolve(tbl_scripts, tables_dir, c("pdf", "rtf", "docx")),
    figures = resolve(fig_scripts, figures_dir, c("png", "jpg", "jpeg", "pdf", "rtf"))
  )
}

#' Companion display object of a docorator output (tbl-x.pdf -> tbl-x.RDS), as a spec entry.
#'
#' docorator saves the exact gt object it rendered next to the PDF/RTF. Reports reuse it
#' (pk-nca-report) so their tables are identical to the QC'd ones; recording its hash
#' lets verify_outputs() and the report confirm it is the object behind the PDF.
#'
#' @return list(path, hash), or NULL when there is no companion .RDS.
display_rds_entry <- function(path) {
  rds <- paste0(tools::file_path_sans_ext(path), ".RDS")
  if (!file.exists(rds)) return(NULL)
  list(path = rds, hash = hash_file(rds))
}

#' Write an assembled spec list to spec/nca/v{project_number}.yaml.
#'
#' Also writes a sidecar `<out_path>.hash` file containing `rlang::hash_file()` of
#' the just-written YAML, so a later copy of the spec (e.g. attached to a report or
#' QC package) can be checked for tampering/corruption independent of its own
#' content -- the hash lives outside the file it describes, so it can't be
#' circularly self-referential.
#'
#' @param spec A named list matching the schema in references/schema.md.
#' @param project_number Integer version number (determines the output filename).
#' @param spec_dir Output directory. Defaults to "spec/nca".
#' @return (Invisibly) the path written to.
write_spec <- function(spec, project_number, spec_dir = "spec/nca") {
  dir.create(spec_dir, showWarnings = FALSE, recursive = TRUE)
  out_path <- file.path(spec_dir, sprintf("v%d.yaml", as.integer(project_number)))
  writeLines(as.yaml(spec), out_path)

  hash_path <- paste0(out_path, ".hash")
  writeLines(hash_file(out_path), hash_path)

  message("Wrote ", out_path, " (+ ", hash_path, ")")
  invisible(out_path)
}

#' Verify a written spec file against its sidecar hash.
#'
#' @param project_number Integer version number.
#' @param spec_dir Output directory. Defaults to "spec/nca".
#' @return TRUE (invisibly) if the hash matches; otherwise raises an error.
verify_spec <- function(project_number, spec_dir = "spec/nca") {
  out_path <- file.path(spec_dir, sprintf("v%d.yaml", as.integer(project_number)))
  hash_path <- paste0(out_path, ".hash")
  if (!file.exists(out_path) || !file.exists(hash_path)) {
    stop("Spec or hash file missing for project ", project_number, call. = FALSE)
  }
  recorded <- readLines(hash_path, warn = FALSE)
  current <- hash_file(out_path)
  if (!identical(recorded, current)) {
    stop(
      "Spec file ", out_path, " does not match its recorded hash -- ",
      "it may have been modified after generation.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Verify a version's output files (tables/figures) against the hashes recorded
#' in its spec.
#'
#' Reads `spec/nca/v{project_number}.yaml` and re-hashes every file listed
#' under `outputs.tables`/`outputs.figures` with `rlang::hash_file()`, comparing
#' against the `hash` field recorded for that entry (written by the calling
#' script's `annotate_outputs()` -- see the pk-nca skill's run scripts).
#' Reports every mismatch or missing file rather than stopping at the first
#' one. Because each version writes only into its own output/nca/v{n}/
#' directory, a mismatch means this version's own output was edited,
#' corrupted, or regenerated (e.g. its tbl-/fig- script was re-run after the
#' spec was written) -- a real signal that the spec no longer reflects what's
#' on disk.
#'
#' @param project_number Integer version number.
#' @param spec_dir Directory containing the spec file. Defaults to "spec/nca".
#' @return TRUE (invisibly) if every output file's hash matches; otherwise raises
#'   an error listing the mismatched/missing files.
verify_outputs <- function(project_number, spec_dir = "spec/nca") {
  spec_path <- file.path(spec_dir, sprintf("v%d.yaml", as.integer(project_number)))
  if (!file.exists(spec_path)) {
    stop("Spec file not found: ", spec_path, call. = FALSE)
  }
  spec <- yaml::read_yaml(spec_path)
  entries <- c(spec$outputs$tables, spec$outputs$figures)

  problems <- character(0)
  for (entry in entries) {
    if (is.null(entry$hash)) {
      problems <- c(problems, sprintf("%s: no hash recorded in spec", entry$path))
    } else if (!file.exists(entry$path)) {
      problems <- c(problems, sprintf("%s: file missing", entry$path))
    } else if (!identical(hash_file(entry$path), entry$hash)) {
      problems <- c(problems, sprintf(
        "%s: hash mismatch (changed since spec generation -- edited, or regenerated by re-running this version's script)",
        entry$path
      ))
    }
    rds <- entry$display_rds   # optional: the gt object behind a table (see display_rds_entry())
    if (!is.null(rds)) {
      if (!file.exists(rds$path)) {
        problems <- c(problems, sprintf("%s: file missing", rds$path))
      } else if (!identical(hash_file(rds$path), rds$hash)) {
        problems <- c(problems, sprintf("%s: hash mismatch (changed since spec generation)", rds$path))
      }
    }
  }

  if (length(problems) > 0) {
    stop(
      "Output file(s) inconsistent with spec for project ", project_number, ":\n  ",
      paste(problems, collapse = "\n  "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

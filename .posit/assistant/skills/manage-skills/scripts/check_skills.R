# Consistency check of the analysis skills (manage-skills).
#
# Base R only, so it runs before any analysis package is installed:
#
#   Rscript .posit/assistant/skills/manage-skills/scripts/check_skills.R
#   source(".posit/assistant/skills/manage-skills/scripts/check_skills.R"); check_skills()
#
# Run from the project root (the folder with project.yaml). Prints one line per finding and
# returns the findings invisibly; Rscript exits with status 1 when any check fails.

#' Check every skill under `skills_dir` and its registration in the repository.
#'
#' @param skills_dir Folder holding one folder per skill.
#' @param root Project root: `AGENTS.md` and `docs/skills/`.
#' @return data.frame(skill, check, status = "pass"/"warn"/"fail", detail), invisibly.
check_skills <- function(skills_dir = ".posit/assistant/skills", root = ".") {
  stopifnot(dir.exists(skills_dir))
  skill_files <- Sys.glob(file.path(skills_dir, "*", "SKILL.md"))
  # skills in deeper folders are not discovered by the assistant
  deep_skills <- setdiff(list.files(skills_dir, pattern = "^SKILL\\.md$", recursive = TRUE),
                    file.path(basename(dirname(skill_files)), "SKILL.md"))
  out <- list()
  add <- function(skill, check, ok, detail = "", level = "fail") {
    out[[length(out) + 1L]] <<- data.frame(
      skill = skill, check = check,
      status = if (isTRUE(ok)) "pass" else level,
      detail = if (isTRUE(ok)) "" else detail, stringsAsFactors = FALSE
    )
  }
  read_txt <- function(p) if (file.exists(p)) readLines(p, warn = FALSE) else character()

  skills_readme <- paste(read_txt(file.path(skills_dir, "README.md")), collapse = "\n")
  docs_index    <- paste(read_txt(file.path(root, "docs/skills/README.md")), collapse = "\n")
  agents        <- paste(read_txt(file.path(root, "AGENTS.md")), collapse = "\n")
  names_seen    <- character()

  for (f in skill_files) {
    dir  <- dirname(f)
    slug <- basename(dir)
    lines <- read_txt(f)

    ## 1. Frontmatter ---------------------------------------------------------------
    fm_end <- if (length(lines) && lines[1] == "---") which(lines == "---")[2] else NA
    add(slug, "frontmatter present", !is.na(fm_end), "SKILL.md must start with a --- block")
    if (is.na(fm_end)) next
    fm <- lines[2:(fm_end - 1L)]
    field <- function(key) {
      hit <- grep(paste0("^", key, ":"), fm, value = TRUE)
      if (length(hit)) trimws(sub(paste0("^", key, ":"), "", hit[1])) else NA_character_
    }
    name <- field("name")
    desc <- gsub('^"|"$', "", field("description"))
    names_seen <- c(names_seen, name)

    add(slug, "name matches folder", identical(name, slug),
        sprintf("name '%s' vs folder '%s'", name, slug))
    add(slug, "name format", !is.na(name) && grepl("^[a-z0-9-]{1,64}$", name) &&
          !grepl("anthropic|claude", name),
        "lowercase letters, digits and hyphens, <= 64 chars, no 'anthropic'/'claude'")
    add(slug, "description present", !is.na(desc) && nzchar(desc),
        "description: one line, what the skill does and when to use it")
    if (!is.na(desc)) {
      add(slug, "description length", nchar(desc) <= 1024,
          sprintf("%d chars (max 1024)", nchar(desc)))
      add(slug, "description has no XML", !grepl("[<>]", desc), "remove < and >")
      add(slug, "description says when", grepl("Use when", desc, fixed = TRUE),
          "end with 'Use when ...'", level = "warn")
      add(slug, "description third person",
          !grepl("^(I|You|We)\\b|\\b(I can|you can|we can)\\b", desc),
          "write 'Creates ...', not 'I/You can ...'", level = "warn")
      add(slug, "description concise", nchar(desc) <= 400,
          sprintf("%d chars; keep it to what + when (usage belongs in the body)", nchar(desc)),
          level = "warn")
    }

    ## 2. Body ------------------------------------------------------------------------
    body <- lines[-seq_len(fm_end)]
    add(slug, "SKILL.md under 500 lines", length(lines) <= 500,
        sprintf("%d lines: move detail to references/", length(lines)), level = "warn")

    # file:///{skill_dir}/... and relative [..](path) links resolve inside the skill
    txt <- paste(body, collapse = "\n")
    own <- regmatches(txt, gregexpr("file:///\\{skill_dir\\}/[^) `'\"]+", txt))[[1]]
    own <- sub("^file:///\\{skill_dir\\}/", "", own)
    rel <- regmatches(txt, gregexpr("\\]\\((?!https?:|#|mailto:)[^)#]+", txt, perl = TRUE))[[1]]
    rel <- sub("^\\]\\(", "", rel)
    missing <- unique(c(own, rel)[!file.exists(file.path(dir, c(own, rel)))])
    add(slug, "own paths exist", !length(missing), paste(missing, collapse = ", "))

    # `other-skill/scripts/x.R` style references to sibling skills
    sib <- regmatches(txt, gregexpr(
      "`[a-z0-9-]+/(scripts|templates|assets|references)/[^` ]+`", txt))[[1]]
    sib <- unique(gsub("`", "", sib))
    sib <- sib[!file.exists(file.path(dir, sib))]           # not the skill's own folder
    gone <- sib[!file.exists(file.path(skills_dir, sib))]
    add(slug, "sibling paths exist", !length(gone), paste(gone, collapse = ", "))

    # every reference file is linked from SKILL.md (one level deep)
    refs <- list.files(file.path(dir, "references"), pattern = "\\.md$")
    orphan <- refs[!vapply(refs, function(r) grepl(r, txt, fixed = TRUE), logical(1))]
    add(slug, "references linked from SKILL.md", !length(orphan),
        paste(orphan, collapse = ", "), level = "warn")
    nested <- unlist(lapply(file.path(dir, "references", refs), function(r) {
      t <- paste(read_txt(r), collapse = "\n")
      if (grepl("\\]\\((\\./)?[a-z0-9_-]+\\.md\\)", t)) basename(r)
    }))
    add(slug, "references one level deep", !length(nested),
        paste("links to other reference files:", paste(nested, collapse = ", ")), level = "warn")

    ## 3. Code parses and source() targets exist -------------------------------------
    r_files <- list.files(dir, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
    bad_parse <- character()
    bad_src <- character()
    for (r in r_files) {
      code <- read_txt(r)
      # templates carry {{placeholders}}; substitute before parsing
      code_p <- gsub("\\{\\{[a-z_]+\\}\\}", "1", code)
      if (inherits(try(parse(text = code_p, keep.source = FALSE), silent = TRUE), "try-error"))
        bad_parse <- c(bad_parse, sub(paste0(dir, "/"), "", r, fixed = TRUE))
      src <- regmatches(code, regexpr('\\.posit/assistant/skills/[^"\']+\\.R', code))
      src <- src[!file.exists(file.path(skills_dir, sub(".posit/assistant/skills/", "", src,
                                                          fixed = TRUE)))]
      bad_src <- c(bad_src, src)
    }
    add(slug, "R files parse", !length(bad_parse), paste(bad_parse, collapse = ", "))
    add(slug, "sourced skill scripts exist", !length(bad_src),
        paste(unique(bad_src), collapse = ", "))

    ## 4. Registration in the repository ---------------------------------------------
    link <- sprintf("%s/SKILL.md", slug)
    add(slug, "listed in skills README", grepl(link, skills_readme, fixed = TRUE),
        sprintf("add a row linking %s to %s/README.md", link, skills_dir))
    add(slug, "docs page exists", file.exists(file.path(root, "docs/skills", paste0(slug, ".md"))),
        sprintf("create docs/skills/%s.md", slug))
    add(slug, "listed in docs/skills/README.md",
        grepl(sprintf("(%s.md)", slug), docs_index, fixed = TRUE),
        "add a row to docs/skills/README.md")
    add(slug, "mentioned in AGENTS.md", grepl(sprintf("`%s`", slug), agents, fixed = TRUE),
        "not in AGENTS.md; fine for a helper skill, add a row if users ask for it directly",
        level = "warn")
  }

  ## 5. Across skills -----------------------------------------------------------------
  add("(all)", "skills one folder deep", !length(deep_skills),
      paste("not discovered:", paste(deep_skills, collapse = ", ")))
  dup <- unique(names_seen[duplicated(names_seen)])
  add("(all)", "names unique", !length(dup), paste(dup, collapse = ", "))

  project_r <- file.path(skills_dir, "pk-project/scripts/project.R")
  if (file.exists(project_r)) {
    code <- read_txt(project_r)
    tpl <- unlist(regmatches(code, gregexpr('"[a-z0-9-]+/templates/[^"]+"', code)))
    tpl <- unique(gsub('"', "", tpl))
    gone <- tpl[!file.exists(file.path(skills_dir, tpl))]
    add("(all)", "new_version() templates exist", !length(gone), paste(gone, collapse = ", "))
  }

  res <- do.call(rbind, out)
  shown <- res[res$status != "pass", , drop = FALSE]
  cat(sprintf("Checked %d skills: %d pass, %d warn, %d fail\n", length(skill_files),
              sum(res$status == "pass"), sum(res$status == "warn"), sum(res$status == "fail")))
  if (nrow(shown)) {
    for (i in seq_len(nrow(shown)))
      cat(sprintf("  %-4s %-20s %-34s %s\n", toupper(shown$status[i]), shown$skill[i],
                  shown$check[i], shown$detail[i]))
  }
  invisible(res)
}

if (sys.nframe() == 0L) {
  res <- check_skills()
  if (any(res$status == "fail")) quit(status = 1L)
}

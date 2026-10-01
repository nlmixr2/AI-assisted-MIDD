---
name: pk-nca-logging
description: Writes a timestamped run log for every analysis script, with a session check, step timings and a pass/fail run summary. Use when the user asks for run logs, why a script failed, reproducibility checks, or session hygiene (sessioncheck, rm(list = ls())).
---

# NCA run logging and session hygiene

Companion to the `pk-nca` skill (and its `pk-nca-database`/`pk-nca-tables`/
`pk-nca-run-spec` companions): bookends every `script/nca/v{project_number}/*.R`
script with a session-hygiene check and a captured log of its execution, replacing
the old, unsafe habit of starting a script with `rm(list = ls())`.

## Why not `rm(list = ls())`

`rm(list = ls())` at the top of a script is meant to simulate a fresh session, but it
only clears global-environment objects — it does nothing about attached packages,
which is the more common source of a script silently depending on session state it
shouldn't. Worse, it "fixes" contamination silently rather than telling you it found
any. See [Danielle Navarro's *Some thoughts on checking the R
session*](https://blog.djnavarro.net/posts/2026-01-06_sessioncheck/) for the full
argument (and the origin of the `sessioncheck` package this skill uses).

`sessioncheck::sessioncheck()` is the safer alternative this skill embeds: it
inspects global-environment objects *and* attached packages *and* attached
environments, reports what it finds, and — critically — does not attempt to silently
clean anything up. Responsibility for deciding what to do about a contaminated
session stays with the human.

## Also used by the popPK skills

The `poppk-*` skills (`poppk-estimation`, `poppk-tables`, `poppk-run-spec`, `poppk-simulation`)
reuse these same helpers; they pass `output_dir = "output/poppk"` (or `"output/poppk-sim"`
for simulations) so logs land in `output/poppk{,-sim}/v{project_number}/logs/`:

```r
nca_log_start("analysis-poppk", project_number = 1L, output_dir = "output/poppk")
```

## Core Process

A canonical, verified-working copy of both functions lives in
`file:///{skill_dir}/scripts/nca_log.R` — source it rather than reimplementing.

1. Install `sessioncheck` and `whoami` if not already available
   (`install.packages(c("sessioncheck", "whoami"))` — both on CRAN). The logging still
   works without them (with a note in the log): without `sessioncheck` the
   session-hygiene check is skipped; without `whoami` the log's `# user:` line falls
   back to the OS login name.

2. **Bookend every script** — `analysis-nca.R`, each `tbl-*.R`/`fig-*.R`, and
   `generate-spec.R` — with a start/stop pair, as the very first and very last lines
   of the script (library() calls go *before* `nca_log_start()`, since library-loading
   messages are worth capturing too):

```r
library(tidyverse)
# ... other library() calls ...

source("{pk-nca-logging skill dir}/scripts/nca_log.R")
nca_log_start("analysis-nca", project_number = 1L)

## 1. Load data ------------------------------------------------------------------
nca_log_section("1. Load data")      # optional: a timed step marker in the log
## ... rest of the script's steps ...

nca_log_stop()
```

   The analysis templates (`analysis-nca.R`, `analysis-poppk.R`, `analysis-sim.R`) already
   call `nca_log_section()` under each numbered step.

3. **Read a log after a run** to review what happened without re-running anything:
   `output/{type}/v{project_number}/logs/{script_name}-{timestamp}.log`, one file per
   execution (timestamped, never overwritten). Layout:

```
# ======================================================================================
#  NCA run log  |  analysis-nca  |  v1
# ======================================================================================
# script: analysis-nca
# project_number: 1
# analysis: nca
# script_file: script/nca/v1/analysis-nca.R
# user: mutaz
# started_at: 2026-09-29T00:14:10+0000
# r_version: 4.5.0
# git_commit: 5c906a4
#
# -- Session check ---------------------------------------------------------------------
#   package:   PKNCA, tidyverse, ...
#   (includes what the script loaded before nca_log_start())
#
# -- Output ----------------------------------------------------------------------------

# -- 1. Load data ---------------------------------------------------- 00:14:10 (+0.3 s)

... everything the script printed, messages, warnings ...

# -- Run summary -----------------------------------------------------------------------
# status: completed                       (or: FAILED (stopped on the error above))
# finished_at: 2026-09-29T00:14:12+0000
# elapsed: 2.1 s
# files_written: 1
#   output/nca/v1/db/nca.duckdb
#
# sessionInfo():
... sessionInfo() (completed runs only) ...
# ======================================================================================
```

   `files_written` lists the version's output files (logs excluded) that the run created or
   modified. The QC suites read `# project_number: N`, require `# sessionInfo():` (the run
   reached `nca_log_stop()`) and fail on any line starting with `Error`: keep those lines
   verbatim if you change the format.

## Rules

- **`nca_log_start()` first, before any analysis code** (but after `library()` calls)
  — everything after it is captured; anything before it (besides the library-loading
  messages, which are useful to see even before the log starts printing to console)
  is not.
- **Always call `nca_log_stop()`** as the script's last line. If the script stops on an
  error, `nca_log_start()`'s error handler (`options(error =)`) closes the log instead: it
  writes the run summary with `status: FAILED (stopped on the error above)`, restores the
  sinks and the previous error handler. `nca_log_stop()` is safe to call redundantly.
- **Logs are timestamped and accumulate — they are not the same kind of output as
  tables/figures.** `output/nca/v{n}/tables/tbl-*.pdf` is the current state of that
  version's table and is replaced when its script is re-run; a log file in
  `output/nca/v{n}/logs/` is a record of one specific execution and is never
  overwritten by a later run.
- **`sessioncheck_action` defaults to `"warn"`** (log the finding, keep running) —
  appropriate for iterative analysis work. Pass `sessioncheck_action = "error"` in a
  stricter QC/CI context where a contaminated session should stop the run outright.
- **Messages/warnings are captured to the file, not the console, while a log is
  active** (a `sink(type = "message")` limitation — unlike the output stream, the
  message stream has no `split =` option). This is expected: review them in the log
  file afterward rather than expecting to see them scroll by live.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| Later, unrelated console commands are silently appearing in an old log file | A prior script neither reached `nca_log_stop()` nor errored (e.g. it was interrupted, or `options(error =)` was replaced after `nca_log_start()`). Call `nca_log_stop()` manually to restore normal output. |
| Run summary says `FAILED` | The script stopped on the error printed just above it; fix the cause and re-run the script (and anything after it in the version's order). |
| `sessioncheck` findings list is huge / not useful | Expected in an interactive session with lots of exploratory objects/packages loaded — the check is most informative when each script is run in its own fresh `Rscript` invocation, which is the intended usage for versioned pipeline scripts. |
| No sessioncheck section in the log, just a "not installed" note | `install.packages("sessioncheck")` (CRAN). |
| Log file contains a warning printed twice, oddly formatted | Don't also let `sessioncheck()`'s own base `warning()` propagate uncaught if you're customizing this pattern — `nca_log_start()` already muffles it and reports findings in its own cleaner format; re-implementations should do the same (see `scripts/nca_log.R`). |

## References

- Skill reference: `scripts/nca_log.R` — canonical, verified-working
  `nca_log_start()`/`nca_log_section()`/`nca_log_stop()`; source rather than reimplementing.
- sessioncheck package site: https://sessioncheck.djnavarro.net/
- whoami package (`username()` for the log header's `# user:` line):
  https://github.com/r-lib/whoami
- Origin/rationale: https://blog.djnavarro.net/posts/2026-01-06_sessioncheck/
- `?sessioncheck::sessioncheck`, `?base::sink` (especially the `split=`/`type=`
  arguments this skill relies on)
- Related project skills: `pk-nca` (the scripts this skill bookends),
  `pk-nca-database`, `pk-nca-tables`, `pk-nca-run-spec`.

Verified against `sessioncheck` 0.1 (CRAN) — re-check `sessioncheck()`'s `action=`
values and return-object structure if errors look like API drift; the package's own
author has flagged it as new/seeking feedback as of this writing.

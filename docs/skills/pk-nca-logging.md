# `pk-nca-logging`

Writes a log file for every run of a versioned script, and checks the R session at the
start instead of wiping it with `rm(list = ls())`. Despite its name, it serves NCA, popPK
and simulation scripts alike.

## When it is used

- Every versioned script is bookended by it: `analysis-*.R`, `fig-*.R`, `tbl-*.R` and
  `generate-spec.R`, for the `nca`, `poppk` and `poppk-sim` types. The templates already
  contain the calls.
- When you ask for a run log, an execution log or a reproducibility check.
- When you ask why a script failed.
- When you mention sessioncheck, `rm(list = ls())` or session hygiene.
- To run a whole version in order, use [pk-project](pk-project.md) (`run_version()`); it
  names the latest log of a script that fails.

## What it produces

| File or object | Location | Contents |
|---|---|---|
| Run log | `output/{type}/v{n}/logs/{script_name}-{timestamp}.log` | one file per execution, never overwritten |
| Log header | top of the log | script, `project_number`, analysis type, script file, user, start time, R version, git commit (marked "with uncommitted changes" when the tree is dirty) |
| Session check | "Session check" section | what `sessioncheck::sessioncheck()` found (objects, packages, environments), or "clean session" |
| Step markers | "Output" section | one rule per `nca_log_section()` call, with clock time and time since start |
| Script output | "Output" section | everything the script printed, plus messages and warnings |
| Run summary | end of the log | `status` (`completed`, or `FAILED (stopped on the error above)`), `finished_at`, `elapsed`, `files_written` (the version's output files, logs excluded, that the run created or changed), and `sessionInfo()` for completed runs |

## How to use it

1. Install the two optional packages (both on CRAN). Logging still works without them,
   with a note in the log: without `sessioncheck` the session check is skipped; without
   `whoami` the `# user:` line falls back to the OS login name.

```r
install.packages(c("sessioncheck", "whoami"))
```

2. Bookend each script. `library()` calls come before `nca_log_start()`; `nca_log_stop()`
   is the last line. The first argument is the script's file name without `.R`:

```r
library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- 1L
nca_log_start("analysis-nca", project_number = project_number)

nca_log_section("1. Load data")      # optional timed step marker
# ... the script's steps ...

nca_log_stop()
```

3. For popPK and simulation scripts, pass the output folder of the type:

```r
nca_log_start("analysis-poppk", project_number = 1L, output_dir = "output/poppk")
nca_log_start("analysis-sim", project_number = 1L, output_dir = "output/poppk-sim")
```

4. After a run, read the newest log in `output/{type}/v{n}/logs/` instead of re-running.

Typical prompts: "why did analysis-nca.R fail in v2?", "show me the run log of the
tables", "which package versions did v1 use?".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `nca_log_start(script_name, project_number, output_dir = "output/nca", sessioncheck_action = "warn")` | opens the log, writes the header, runs the session check, sends output and messages to the log; returns the log path invisibly |
| `nca_log_section(title)` | timed step marker; prints to the console when no log is active |
| `nca_log_resume()` | re-attaches the message sink when a package reset it (seen with rxode2 model piping and nlmixr2save's `:=` / `loadFit()`); does nothing when the sink is intact |
| `nca_log_stop()` | writes the run summary and `sessionInfo()`, restores normal output; safe to call when no log is active |
| `scripts/nca_log.R` | the canonical copy of these functions; source it, do not reimplement |

## Rules and checks

- `nca_log_start()` goes first, before any analysis code, but after the `library()` calls.
  Anything before it is not captured.
- Always end with `nca_log_stop()`. If the script stops on an error, the handler that
  `nca_log_start()` sets through `options(error =)` closes the log with
  `status: FAILED (stopped on the error above)` and restores the previous handler.
- `sessioncheck_action` defaults to `"warn"`: the finding is logged and the run continues.
  Pass `sessioncheck_action = "error"` where a contaminated session should stop the run.
- While a log is active, output still prints to the console, but messages and warnings
  go only to the log file. Read them in the log afterwards.
- Logs are append-only history. A re-run writes a new log; tables and figures, in
  contrast, are replaced.
- Automatic checks: the QC suites read `# project_number: N`, require `# sessionInfo():`
  (the run reached `nca_log_stop()`) and fail on any log line starting with `Error`. Keep
  these lines verbatim if you change the format.
- Sessioncheck findings are most useful when each script runs in its own fresh `Rscript`
  session, which is what `run_version()` does.
- The skill was verified against `sessioncheck` 0.1. The package is new; if errors look
  like API drift, re-check `sessioncheck()`'s `action =` values and return object.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Later, unrelated console commands appear in an old log file | A previous script neither reached `nca_log_stop()` nor errored (e.g. it was interrupted, or `options(error =)` was replaced after `nca_log_start()`). Call `nca_log_stop()` by hand. |
| Run summary says `FAILED` | The script stopped on the error printed just above it. Fix the cause and re-run the script and everything after it in the version's order. |
| The sessioncheck findings list is huge | Expected in an interactive session with many objects and packages. Run the script in a fresh `Rscript` session. |
| No session check in the log, only a "not installed" note | `install.packages("sessioncheck")`. |
| Messages stop appearing in the log part-way through | A package reset the message sink. Call `nca_log_resume()` after that step. |

## Related

- [pk-project](pk-project.md), [pk-nca](pk-nca.md), [pk-data-validation](pk-data-validation.md)
- [pk-nca-qc-tests](pk-nca-qc-tests.md), [pk-nca-run-spec](pk-nca-run-spec.md)
- Source: [SKILL.md](../../.posit/assistant/skills/pk-nca-logging/SKILL.md)
- Workflow guides: [NCA](../pk-nca/README.md), [popPK](../poppk/README.md)

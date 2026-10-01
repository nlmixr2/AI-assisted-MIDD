# PK analysis template (NCA · popPK · simulation)

A project template for reproducible, QC-ready pharmacokinetic analyses in R, designed to be
driven by an AI assistant through **skills**:

- **NCA:** non-compartmental analysis with [PKNCA](https://humanpred.github.io/pknca/).
- **Population PK estimation:** with [nlmixr2](https://nlmixr2.org/).
- **Simulation:** with [rxode2](https://nlmixr2.github.io/rxode2/), from a fitted model or a
  model file.

Every analysis is a numbered version. Each version writes its results to a database, logs
every script run, and records provenance in a hashed spec file. It is ready for QC only when
its automated test suite passes.

## Start a new study

1. **Clone the template.**

   ```sh
   git clone <this-repo> my-study && cd my-study
   ```

2. **Fill in `project.yaml`:** study ID, analysis titles, and the units of your data.
   Scripts refuse to run while `<...>` placeholders remain.
3. **Add your data.** Put datasets in `data/`. For simulations from your own model, put the
   model file in `model/`.
4. **Ask the assistant**, in plain language. For example:
   - *Run NCA for `data/pk.csv`. Oral dose, AMT is total mg.*
   - *Develop a popPK model for `data/pk.csv`, starting with one compartment.*
   - *Simulate 200 mg q12h from the popPK v1 model.*

   More prompts are in the
   [skills README](.posit/assistant/skills/README.md#suggested-prompts).

   You can also run it by hand in R, from the project root:

   ```r
   source(".posit/assistant/skills/pk-project/scripts/project.R")
   new_version("nca")        # scaffold script/nca/v1/ and tests/nca/v1/ from the templates
   # edit the blocks marked EDIT in script/nca/v1/*.R
   run_version("nca", 1L)    # analysis -> figures/tables -> spec -> QC suite
   project_status()          # every version and whether it is ready for QC
   ```

5. **Report it.** For NCA, `create_nca_report(n)` scaffolds a Quarto report in
   `output/nca/v<n>/MAR/` (ISoP pmx-report-template cover): one PDF with every table and
   figure, the source files and provenance, and the code. `render_nca_report(n)` renders it, but only if the version still matches
   its spec and passed QC.
6. **Hand the version to QC** once `run_version()` reports *ready for QC*. The reviewer
   checks the version's spec (`spec/<type>/v<n>.yaml`), its outputs, and the JUnit report
   in `output/<type>/v<n>/logs/`.

## What's in the repository

| Path | Contents |
|---|---|
| `project.yaml` | study-specific settings: study ID, analysis titles, units |
| `data/`, `model/` | your inputs |
| `script/`, `output/`, `spec/`, `tests/` | created per version by `new_version()` and `run_version()` (`{type}/v{n}/`) |
| `.posit/assistant/skills/` | the skills: procedures, templates, helpers (also linked at `.claude/skills/`) |
| `examples/abc-111/` | a complete worked example: NCA, popPK and simulation, all passing QC; NCA v1 also has a rendered report (`output/nca/v1/MAR/report/`) |
| `examples/gs-12345/` | a second worked example (theophylline, sample-layout data with mg/kg doses): NCA v1 split by arm, popPK v1–v2 (1-cmt, first-order absorption, initial estimates from the NCA), all passing QC, with rendered NCA v1 and popPK v2 reports |
| `docs/` | workflow guides with diagrams and scenario prompts, starting with the [NCA workflow](docs/pk-nca/README.md) |
| `AGENTS.md` | instructions for AI coding agents (`CLAUDE.md` points to it) |

Documentation for the skills, workflows, provenance model, QC checks and suggested prompts:
[`.posit/assistant/skills/README.md`](.posit/assistant/skills/README.md).

## Requirements

- **R and TinyTeX:** R ≥ 4.5, plus TinyTeX for PDF tables (otherwise tables are written as
  RTF).
- **Packages:**

  ```r
  install.packages(c("PKNCA", "nlmixr2", "tidyverse", "tfrmt", "docorator", "gt",
                     "duckdb", "DBI", "rlang", "yaml", "testthat", "withr", "here",
                     "patchwork", "sessioncheck", "whoami", "knitr", "rmarkdown", "fs",
                     "crane", "png", "nlmixr2save", "pointblank", "ggPMX"))
  ```

- **Tested versions:** PKNCA 0.12.1, nlmixr2 7.0.1, rxode2 5.1.6, duckdb 1.5.5.

The `poppk-estimation` and `poppk-simulation` skills are adapted from
[nlmixr2llm](https://github.com/mattfidler/nlmixr2llm/tree/merge-john-harrold/inst/skills).
The `pk-nca-report` skill is built on the ISoP
[pmx-report-template](https://github.com/isop-phmx/pmx-report-template) (MIT).

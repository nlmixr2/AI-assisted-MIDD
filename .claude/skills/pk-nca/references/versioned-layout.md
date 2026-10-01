# Versioned run scripts, outputs and provenance

Companion to [SKILL.md](../SKILL.md) (Versioned run scripts & provenance). The
scripts named here are scaffolded by `new_version("nca")` (`pk-project`); the steps inside
`analysis-nca.R` are explained in `pipeline.md`.

For an analysis meant to be reused, re-run, or QC'd (as opposed to one-off exploration),
split the pipeline across a versioned script directory rather than one monolithic
script, and land outputs in a matching versioned `output/` tree rather than alongside
the scripts:

```
script/nca/v{project_number}/
  analysis-nca.R                  # pk-nca/templates: steps 1-8 (pipeline.md), writes the database
  fig-halflife-diagnostics.R      # pk-nca/templates: figures/fig-halflife-diagnostics.pdf
  fig-mean-conc.R                 # pk-nca-figures/templates: figures/fig-mean-conc.pdf
  fig-mean-conc-semilog.R         # pk-nca-figures/templates: figures/fig-mean-conc-semilog.pdf
  fig-ind-conc.R                  # pk-nca-figures/templates: figures/fig-ind-conc.pdf
  fig-lambdaz.R                   # pk-nca-figures/templates: figures/fig-lambdaz.pdf
  tbl-pk-parameters.R             # pk-nca-tables/templates: tables/tbl-pk-parameters.pdf
  tbl-conc-by-nominal-time.R      # pk-nca-tables/templates: tables/tbl-conc-by-nominal-time.pdf
  generate-spec.R                 # pk-nca-run-spec/templates: spec/nca/v{project_number}.yaml

tests/nca/
  v{project_number}/
    test-nca-qc.R                 # QC-readiness suite (see pk-nca-qc-tests)

output/nca/
  v{project_number}/
    figures/fig-*.pdf, fig-*.RDS   # every figure: PDF (RTF without TinyTeX) + its display object
    tables/tbl-*.pdf
    logs/data-validation-*.html   # see pk-data-validation
    logs/*.log                    # see pk-nca-logging
    logs/qc-tests-*.xml           # QC test reports (see pk-nca-qc-tests)
    db/nca.duckdb                 # this version's NCA results (see pk-nca-database)
```

`project_number` is a positive integer, one directory per pipeline revision (`v1`, `v2`,
...) — see the `pk-nca-run-spec` skill for the full naming convention.

**`analysis-nca.R` ends by writing to the NCA results database** (see the companion
**pk-nca-database** skill) rather than downstream scripts re-running PKNCA themselves:

```r
source("{pk-nca-database skill dir}/scripts/nca_db.R")
write_nca_db(project_number = 1L, pkDataPath = pkDataPath, cObsData = cObsData,
             doseData = doseData, ncaRes = ncaRes, res_wide = res_wide,
             halflife_fit = halflife_fit)
```

Every `tbl-*.R`/`fig-*.R` script then starts with `read_nca_db(project_number)`
(instead of `source("script/nca/v{project_number}/analysis-nca.R")`) to get
`cObsData`/`doseData`/`ncaRes`/`halflife_fit` back — verified against a content hash —
without re-running PKNCA at all. **Outputs are versioned by directory, not file
name** — every script in `script/nca/v{project_number}/` saves into
`output/nca/v{project_number}/{tables,figures}/`, so v1's
`output/nca/v1/tables/tbl-pk-parameters.pdf` and v2's
`output/nca/v2/tables/tbl-pk-parameters.pdf` coexist and a new version never
overwrites an earlier one's outputs. Never save to a shared
`output/nca/{tables,figures,db,logs}/` directory — everything a version produces lives
under `output/nca/v{project_number}/`.

At the end, generate a provenance record via the **pk-nca-run-spec** skill by writing
`script/nca/v{project_number}/generate-spec.R`, which hashes every script in the version
directory, the source data file (`hash_source_file()`/`collect_data_provenance()`), the
derived `cObsData`/`doseData` objects, the NCA results database entry (path, version,
content hash — via `pk-nca-database`'s `read_nca_db()`), and every resolved
`output/nca/v{project_number}/{tables,figures}` file, then writes `spec/nca/v{project_number}.yaml`. Feed
the span-ratio flags from step 8 (`pipeline.md`) into that spec's
`diagnostics.flagged_subjects`.

Finally, create and run the version's QC-readiness tests via the **pk-nca-qc-tests**
skill — `create_qc_tests(project_number)` writes `tests/nca/v{project_number}/test-nca-qc.R`,
and `run_qc_tests(project_number)` must pass with zero failures before telling the user
the version is ready for QC. Run order for a version: `analysis-nca.R` → every
`fig-*.R`/`tbl-*.R` → `generate-spec.R` → `run_qc_tests()` — which is exactly what
`run_version("nca", n)` (pk-project) does, each script in a fresh R session.

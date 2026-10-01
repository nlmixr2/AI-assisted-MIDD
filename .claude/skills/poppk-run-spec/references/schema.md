# PopPK run-spec schema (`spec/poppk/v{n}.yaml`)

Top-level provenance fields are identical to the NCA spec (see `pk-nca-run-spec`
`references/schema.md`): `project_number`, `script_dir`, `scripts`, `script_hashes`,
`scripts_combined_hash`, `generated_at`, `r_version`, `packages`, `description`,
`outputs`, `qc`, `report`. The popPK-specific fields:

## `data`

| Field | Description |
|---|---|
| `dataset` | human-readable dataset name + path |
| `source_file` | `{path, hash}` of the raw data file (`collect_data_provenance()`) |
| `poppk_db` | `{path, project_number, generated_at, payload_hash}` from `read_poppk_db()` |
| `model_data` | description of the dataset passed to `nlmixr2()` (columns, EVID coding) |
| `units` | at least `conc`, `time`, `dose` |
| `hash` | `hash_data(pkData = pkData)` — `{combined, components: {pkData}}` |

## `models` — the model-building trail, one entry per run

`run_id`, `parent_run` (null for the base model), `description`, `est`, `objf`,
`delta_ofv` (null for the base model), `n_par`, `cov_ok`, `model_hash`.

## `fit_archives` — nlmixr2save fit archives (one entry per zip)

`path` (`output/poppk/v{n}/fits/<run>.zip`, or `fits/shared/<run>-noData.zip`), `run_id`,
`kind` (`fit archive` / `shared (no subject data)`), `hash`. Written by
`fit_archive_entries()` (poppk-estimation `scripts/poppk_fits.R`) and checked by the QC suite.

## `final_model`

| Field | Description |
|---|---|
| `run_id`, `est`, `objf` | the selected run |
| `rationale` | why this run was selected (required) |
| `parameters` | `{name, estimate (back-transformed), rse, bsv_cv}` per THETA |
| `acceptance_checks` | `{check, status (pass/warn/fail), detail}` from `acceptance_checks(fit)` |

## `diagnostics`

| Field | Description |
|---|---|
| `caveats` | the warn-level acceptance checks `{check, detail}` — must match a recomputation (QC-tested) |
| `notes` | free-text analyst notes (e.g. why a high %RSE is acceptable) |

## Worked example (abridged, from v1)

```yaml
models:
- run_id: run001
  parent_run: ~
  description: 1-cmt, first-order absorption, BSV on Ka/CL/V, additive error
  est: saem
  objf: 117.0866
  delta_ofv: ~
  n_par: 7
  cov_ok: yes
  model_hash: 5218c6d37c36fc1febeea792e6a1ebb0
- run_id: run002
  parent_run: run001
  description: run001 + power WT effect on CL/F (centred at 70 kg)
  est: saem
  objf: 116.4682
  delta_ofv: -0.6184
  n_par: 8
  cov_ok: yes
final_model:
  run_id: run001
  rationale: run002 WT effect on CL/F not supported (dOFV = -0.62 for 1 parameter, p ~ 0.43)
  parameters:
  - {name: tcl, estimate: 2.7598, rse: 8.22, bsv_cv: 26.86}
  acceptance_checks:
  - {check: ofv_finite, status: pass, detail: OFV = 117.087}
diagnostics:
  caveats: []
qc: {status: pending, reviewer: ~, reviewed_date: ~, notes: ~}
report: {title: PopPK Analysis for ABC-111, template: ~}
```

---
name: manage-skills
description: Creates, changes, renames, retires and checks the analysis skills in this repository, keeping each skill's frontmatter, templates, docs page and skill maps in step. Use when the user asks to add or edit a skill, fix a skill template, or check the skills for consistency.
---

# Managing the analysis skills

The analysis skills live in `.posit/assistant/skills/<name>/` (also linked at
`.claude/skills/`). This skill maintains the other skills; it never touches data or versions. A skill is more than its folder: it is registered in several
places, and a change that misses one leaves the assistant with stale instructions.

## Where a skill is registered

| Place | What to keep in step | Required |
|---|---|---|
| `.posit/assistant/skills/<name>/SKILL.md` | frontmatter `name` = folder name; `description` = what + when | always |
| `.posit/assistant/skills/README.md` | a row in the Skills table, linking `<name>/SKILL.md` | always |
| `docs/skills/<name>.md` + `docs/skills/README.md` | the skill's docs page and its row in the index | always |
| `AGENTS.md`, "Load the skill before acting" table | a row when users ask for the skill directly | user-facing skills |
| `pk-project/scripts/project.R`, `templates = c(...)` of the version type | every template `new_version()` scaffolds | skills with version templates |
| `docs/pk-nca/README.md`, `docs/poppk/README.md` | workflow diagrams and script order | skills in a workflow |
| `evals/` | test prompts and expected behaviour | when behaviour changes |

`file:///{skill_dir}/scripts/check_skills.R` checks all of these that can be checked
mechanically. Run it after every change, from the project root:

```sh
Rscript .posit/assistant/skills/manage-skills/scripts/check_skills.R
```

It fails on a wrong or duplicate name, a missing, too long or XML-containing description, a
path in `SKILL.md` that does not exist, an R file that does not parse, a `source()` of a
missing skill script, a template `new_version()` cannot find, or a missing README row or docs
page. It warns on a description without "Use when", one that is not third person or over
400 characters, a `SKILL.md` over 500 lines, a reference file not linked from `SKILL.md`, and a
skill not in `AGENTS.md`.

## Authoring rules

Details and examples: [references/authoring.md](references/authoring.md).

- **Description:** one line, third person, what the skill does, then "Use when ..." with
  the words a user would say. No function names, paths or usage; those go in the body.
- **Body:** the procedure the assistant follows. Keep `SKILL.md` under 500 lines; move
  detail to `references/*.md`, each linked directly from `SKILL.md` (one level deep).
- **Own files** are cited with the prefix `file:///{skill_dir}/`, files of another skill as
  `` `<skill>/scripts/<file>` ``. Both are checked.
- **Only verified code and facts.** Every function, argument and option named in a skill
  must exist in the repository or in the installed package's documentation. Record the
  versions verified ("Verified with PKNCA 0.12.1 ..."). If it cannot be verified, say so in
  the skill rather than guessing.
- **Reuse, don't copy.** Shared helpers stay in one skill (logging in `pk-nca-logging`, the
  table and figure shell in `pk-project`, provenance in `pk-nca-run-spec`) and are sourced.
- **Project rules still apply** (`AGENTS.md`): templates compute only in `analysis-*.R`,
  bookend every script with `nca_log_start()`/`nca_log_stop()`, take study values from
  `project.yaml`, mark analyst choices with `EDIT`, render deliverables with `render_tlf()`.

## Workflows

### Add a skill

1. Confirm no existing skill covers the request (skills README), and agree the name with
   the user: lowercase, hyphens, family prefix (`pk-`, `pk-nca-`, `poppk-`).
2. Copy `file:///{skill_dir}/templates/SKILL-template.md` to `<name>/SKILL.md` and fill it in.
   Add `scripts/`, `templates/`, `assets/` or `references/` only as needed.
3. If the skill scaffolds scripts into versions, add its templates to the version type's
   `templates = c(...)` in `pk-project/scripts/project.R`, in run order.
4. Write `docs/skills/<name>.md` from `file:///{skill_dir}/templates/doc-page-template.md`, and
   add rows to `docs/skills/README.md`, the skills README and, if user-facing, `AGENTS.md`.
5. Run `check_skills.R` until it reports 0 fail, and test the scripts (below).

### Change a skill or fix a template

1. Read the whole `SKILL.md` and the files you will change.
2. Fix bugs in the skill's `templates/` or `scripts/`, not in a scaffolded version: only
   future versions pick up the fix. Never edit a version whose spec exists, or `examples/`
   unless the user asks.
3. Update everything the change touches: the `SKILL.md` text, its docs page, the README rows,
   workflow guides and evals.
4. Run `check_skills.R` and the tests below, and tell the user which versions would need a
   new version to pick up the change.

### Rename a skill

Rename the folder and `name:` together, then replace the old name everywhere:
`grep -rn "<old-name>" .posit docs AGENTS.md README.md evals`. Check `source()` paths in
every template and script. Existing versions keep the old path in their scripts, so a rename
breaks them: tell the user, and prefer keeping the name.

### Retire a skill

Remove the folder, its README and `AGENTS.md` rows, its docs page and index row, and its
templates from `project.R`. `grep` for the name and for any script it provided; a remaining
`source()` fails `check_skills.R`. Scripts in existing versions keep sourcing it, so check
`examples/` and `script/` before removing a shared script.

### Check the skills

Run `check_skills.R` and report the fails and warns as they are printed. Fix fails; for
warns, explain and ask before changing a description.

## Testing a change

- `check_skills.R` (above) must report 0 fail.
- Tests that ship with a skill: `Rscript -e 'testthat::test_dir("<skill>/tests")'`.
- A template change: scaffold and run a version on a real dataset
  (`new_version()`, `run_version()`, pk-project) and confirm the QC suite passes; quote the
  result. Say which checks you could not run (for example, no TinyTeX or Quarto).
- A description change: check that a typical request would match it and that no other skill's
  description matches the same request.

# Authoring a skill

Rules for writing and changing the skills in this repository. They follow the Agent Skills
guidance (<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>)
and the conventions the existing skills already use.

## Contents

- How a skill is loaded
- Frontmatter
- Body
- Files in a skill
- Code in a skill
- Grounding: avoiding invented functions and facts
- Checklist before committing

## How a skill is loaded

1. At start-up the assistant sees only each skill's `name` and `description`, for every
   skill, all the time. The description decides whether the skill is used at all.
2. When a request matches, it reads the whole `SKILL.md`.
3. It reads reference files, templates and scripts only when `SKILL.md` points to them.

So: the description must be short and precise, `SKILL.md` must hold the procedure, and detail
the procedure only sometimes needs goes in `references/`.

## Frontmatter

```yaml
---
name: pk-nca-tables
description: Creates production NCA tables (PK parameters, concentrations by nominal time) with tfrmt and docorator. Use when the user asks for NCA tables, PK parameter tables, concentration tables or TLF tables.
---
```

| Field | Rule |
|---|---|
| `name` | same as the folder; lowercase letters, digits and hyphens; at most 64 characters; not "anthropic" or "claude"; family prefix `pk-`, `pk-nca-` or `poppk-` |
| `description` | one line; at most 1024 characters (aim for under 350); no `<` or `>`; third person ("Creates ...", not "I can ..." or "You can ..."); first what the skill does, then "Use when ..." with the words users say (NCA, AUC, VPC, MAR, ...) |

Keep usage out of the description: no function names, paths, arguments or steps. Two skills
must not claim the same request; if they overlap, narrow one ("Use pk-nca-figures for NCA
plots").

## Body

- Write instructions, not explanations: "Run `run_version()`", not "You may want to consider
  running ...". The assistant already knows R and PK; explain only what is specific to this
  repository.
- Usual sections, in this order: Overview, Core Process (numbered steps with the exact calls),
  Rules, Debugging quick reference (symptom → cause table), References, and a "Verified
  with" line.
- Give one way to do each thing. Offer an alternative only with the condition for using it.
- Name the checkpoints: what to look at before moving to the next step, and what to do when
  it fails.
- Under 500 lines. When it grows, move a topic to `references/<topic>.md` and link it from
  the section where it is needed.
- Use the same terms as the other skills: version, spec, QC suite, TLF shell, `EDIT` block,
  analysis script.

## Files in a skill

| Folder | Holds | Cited as |
|---|---|---|
| `scripts/` | helper functions the assistant or the version scripts `source()` | `file:///{skill_dir}/scripts/<file>.R` |
| `templates/` | version scripts `new_version()` copies, with `{{project_number}}` placeholders | `file:///{skill_dir}/templates/<file>.R` |
| `assets/` | files copied or read as-is (QC test templates, YAML, Quarto projects) | `file:///{skill_dir}/assets/<file>` |
| `references/` | detail read on demand, one topic per file | `[references/<topic>.md](references/<topic>.md)` |
| `tests/` | testthat tests of the skill's own helpers | run with `testthat::test_dir()` |

- References are one level deep: `SKILL.md` links to every reference file, and reference
  files do not send the reader on to other reference files.
- A reference file over about 100 lines starts with a short contents list.
- A file of another skill is cited as `` `<skill>/scripts/<file>.R` `` and sourced with its
  full path from the project root, `.posit/assistant/skills/<skill>/scripts/<file>.R`.

## Code in a skill

- Scripts solve the problem rather than leaving it to the assistant: they check their inputs
  and stop with a message that says what to fix.
- Templates follow the project rules (`AGENTS.md`): logging bookends, `nca_log_section()`
  for numbered steps, study values from `project_config()`, analyst choices inside `EDIT`
  blocks, fixed seeds, and `render_tlf()` for every deliverable.
- A template change reaches only versions scaffolded after it. Say so when you change one.
- Every R file must parse (templates are parsed with their `{{placeholders}}` replaced).

## Grounding: avoiding invented functions and facts

- Name only functions, arguments and options you have seen: in this repository, in the
  installed package's help (`?fun`, `args(fun)`), or in its documentation site.
- Record the versions a skill was verified with, and update the line when you re-verify.
- If the environment cannot run the code (no package, no TinyTeX, no Quarto), say which parts
  are untested, in the skill if it matters for users and always in your reply.
- Expected values in docs and evals come from an actual run, never from memory.

## Checklist before committing

- [ ] `check_skills.R` reports 0 fail; warns are explained or fixed.
- [ ] The skill's tests pass, and a changed template was run in a version whose QC suite passed.
- [ ] The docs page, the skills README row, the docs index row, `AGENTS.md` (if user-facing)
      and the workflow guides describe the skill as it now is.
- [ ] No version with a spec and nothing in `examples/` was edited, unless the user asked.

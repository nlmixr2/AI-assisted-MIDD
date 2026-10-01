# `manage-skills`

A skill for maintaining the analysis skills themselves: adding a new skill, changing or
fixing one, renaming or retiring one, and checking that all of them are consistent. It lives
next to the analysis skills in `.posit/assistant/skills/manage-skills/`, so the assistant
discovers it automatically, but it never reads data or runs a version. It exists because a skill is registered in several places
(its folder, the skills README, its docs page, `AGENTS.md`, the `new_version()` template
lists) and a change that misses one leaves the assistant with stale instructions.

## When it is used

- You ask to add, edit, rename or remove a skill, or to fix a bug in a skill's template.
- You ask whether the skills are consistent, or to check them after a change.
- To run an analysis, use the analysis skills ([pk-project](pk-project.md) and the others).

## What it produces

| File or object | Location | Contents |
|---|---|---|
| Check report | console | one line per failed or warned check, and a pass/warn/fail count; `Rscript` exits with status 1 on any fail |
| New skill | `.posit/assistant/skills/<name>/` | `SKILL.md` from the skill template, plus `scripts/`, `templates/`, `assets/`, `references/` as needed |
| Docs page | `docs/skills/<name>.md` | from the docs page template |

## How to use it

From the project root:

```sh
Rscript .posit/assistant/skills/manage-skills/scripts/check_skills.R
```

or in R:

```r
source(".posit/assistant/skills/manage-skills/scripts/check_skills.R")
res <- check_skills()          # data.frame: skill, check, status, detail
subset(res, status != "pass")
```

The checker uses base R only, so it runs before any analysis package is installed.

Typical prompts: "Add a skill for bioequivalence statistics", "Fix the VPC template so every
future version gets it", "Check the skills for consistency".

## Main functions and files

| Function or file | Purpose |
|---|---|
| `check_skills(skills_dir, root)` | Runs every check below on every skill (`scripts/check_skills.R`) |
| `templates/SKILL-template.md` | Starting point for a new skill's `SKILL.md` |
| `templates/doc-page-template.md` | Starting point for a new `docs/skills/<name>.md` |
| `references/authoring.md` | Frontmatter, body, file layout, code and grounding rules, with a checklist before committing |

## Rules and checks

| Check | Fails or warns when |
|---|---|
| name matches folder, name format | fail: `name:` differs from the folder, or is not lowercase letters, digits and hyphens (≤ 64) |
| description present, length, no XML | fail: missing, over 1024 characters, or containing `<` or `>` |
| description says when, third person, concise | warn: no "Use when", written as "I/You can", or over 400 characters |
| SKILL.md under 500 lines | warn |
| own paths exist, sibling paths exist | fail: a `file:///{skill_dir}/...` path, relative link or `` `<skill>/scripts/...` `` path does not exist |
| references linked, one level deep | warn: a reference file not linked from `SKILL.md`, or linking to another reference file |
| R files parse | fail: an R file (templates with `{{placeholders}}` replaced) does not parse |
| sourced skill scripts exist | fail: a `source(".posit/assistant/skills/...")` target is missing |
| new_version() templates exist | fail: a template listed in `pk-project/scripts/project.R` is missing |
| listed in skills README, docs page, docs index | fail: the skill is not registered |
| mentioned in AGENTS.md | warn: fine for helper skills such as the databases and logging |
| skills one folder deep | fail: a `SKILL.md` in a nested folder, which the assistant would not discover |
| names unique | fail |

- Fix bugs in the skill's `templates/`, not in a scaffolded version; only new versions pick up
  the fix. Never edit a version whose spec exists, or `examples/`, unless asked.
- Every function and argument a skill names must exist in the repository or the installed
  package's documentation, with the verified versions recorded.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `dir.exists(skills_dir) is not TRUE` | Run from the project root, or pass `skills_dir =` and `root =` |
| "own paths exist" fails for a path you just added | Paths are relative to the skill folder: `file:///{skill_dir}/scripts/x.R`, not `scripts/x.R` from the project root |
| "sourced skill scripts exist" fails after a rename | A template or script still sources the old path; `grep -rn "<old-name>" .posit` |
| "skills one folder deep" fails | A `SKILL.md` sits in a subfolder (for example `skills/group/name/`); assistants discover skills only at `skills/<name>/SKILL.md`, so move it up |

## Related

- [pk-project](pk-project.md): the `new_version()` template lists the checker verifies
- [Skills reference](README.md), [AGENTS.md](../../AGENTS.md)
- [SKILL.md](../../.posit/assistant/skills/manage-skills/SKILL.md)

---
name: <skill-name>
description: <Verb>s <what the skill does, in one sentence>. Use when the user asks <the requests and words that should load it>.
---

# <Title>

## Overview

<Two or three sentences: what the skill produces, where it sits in the workflow, which skills
it depends on (for example: reads the version's database with `read_nca_db()`, logs with
`pk-nca-logging`).>

## Core Process

Helpers: `file:///{skill_dir}/scripts/<file>.R`

1. **Prerequisites:** <what must exist first: a version that passed `run_version()`, a
   `project.yaml` block, ...>
2. <Step, with the exact call:>

   ```r
   source(".posit/assistant/skills/<skill-name>/scripts/<file>.R")
   <function>(<arguments>)
   ```

3. <Step. Say what to check before moving on.>

## Rules

- <Each rule the assistant must follow, stated as an instruction.>
- Compute only in `analysis-*.R`; other scripts read the version's database.
- Every script is bookended by `nca_log_start("<script-name>", project_number = n, output_dir = "output/<type>")` and `nca_log_stop()`.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| <error message or behaviour> | <cause and fix> |

## References

- [references/<topic>.md](references/<topic>.md): <what it covers>

Verified with <package> <version>, <package> <version>.

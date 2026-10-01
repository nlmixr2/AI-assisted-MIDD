# {{description}}
# Custom figure scaffolded by new_tlf() (pk-project) from the request's placeholders. It uses
# the same TLF shell as every figure (render_tlf(): title + page header; "Source data:",
# script and date-time footer) and reads the version's results database -- never recompute.
# Saves output/{{type}}/v{{project_number}}/figures/{{name}}.pdf (+ .RDS).

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("{{name}}", project_number = project_number, output_dir = "output/{{type}}")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")
{{db_block}}

out_dir <- sprintf("output/{{type}}/v%d/figures", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
u <- cfg$units

## Placeholders from the request -------------------------------------------------------
title <- {{title}}
subtitle <- {{subtitle}}
caption <- {{caption}}

## EDIT: build the figure -- one ggplot, or a list of ggplots (one page each) -------------
# Available: {{objects}}
p <- ggplot() +
  annotate("text", x = 0, y = 0, label = "EDIT: build the figure from the version's results") +
  theme_void() +
  labs(caption = caption)

# Title and subtitle go in the docorator header (render_tlf), never in the ggplot.
render_tlf(p, "{{name}}", out_dir, cfg, type = "{{type}}", source_data = source_data,
           title = title, subtitle = subtitle)

nca_log_stop()

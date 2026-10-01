# Terminal-phase (lambda z) fit quality across participants: span ratio vs adjusted
# R-squared, dashed reference at the span-ratio threshold (pk-nca references/diagnostics.md).
# Same tfrmt/docorator shell as the tables and the pk-nca-figures figures.
# Saves output/nca/v{{project_number}}/figures/fig-halflife-diagnostics.pdf (+ .RDS).

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-halflife-diagnostics", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
db_meta <- read_nca_db(project_number)
source(".posit/assistant/skills/pk-nca-figures/scripts/nca_figures.R")

out_dir <- sprintf("output/nca/v%d/figures", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

## EDIT: span-ratio threshold used to flag short terminal phases (same as fig-lambdaz.R) --
span_min <- 2

p <- ggplot(halflife_fit, aes(span.ratio, adj.r.squared, label = participant)) +
  geom_vline(xintercept = span_min, linetype = "dashed") +
  geom_point(aes(colour = span.ratio < span_min), size = 2.4) +
  geom_text(nudge_y = 0.0005, size = 3) +
  scale_colour_manual(values = c(`FALSE` = "black", `TRUE` = "firebrick"),
                      labels = c(`FALSE` = sprintf(">= %g", span_min), `TRUE` = sprintf("< %g", span_min)),
                      name = "Span ratio") +
  theme_pk() +
  labs(
    x = "Span ratio", y = "Adjusted R-squared",
    caption = sprintf("Dashed line: span ratio of %g. Points are labelled by participant.", span_min)
  )

# Title and subtitle go in the docorator header (render_tlf), not the ggplot.
render_pk_display(
  p, "fig-halflife-diagnostics", out_dir, cfg, source_data = db_meta$source_file_path,
  title = "Terminal-Phase Regression Diagnostics",
  subtitle = sprintf("%s; adjusted R-squared vs span ratio, all participants", cfg$study$id)
)

nca_log_stop()

# Steady-state exposure by regimen (Cmax,ss, Cmin,ss, AUC0-24,ss over the last dosing interval),
# boxplots of the simulated subjects, in the shared TLF shell like every other figure.
# Saves output/poppk-sim/v{{project_number}}/figures/fig-exposure.pdf (+ .RDS).

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-exposure", project_number = project_number, output_dir = "output/poppk-sim")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim.R")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_db.R")
read_sim_db(project_number)   # sims, metrics, exposure_summary, profiles, settings, source_provenance
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")
source_data <- sim_source_data(source_provenance)   # "Source data:" line of the TLF shell
u <- cfg$units

out_dir <- tlf_out_dir("poppk-sim", project_number)

metric_labels <- c(cmax = sprintf("Cmax,ss (%s)", u$conc), cmin = sprintf("Cmin,ss (%s)", u$conc),
                   auc24 = sprintf("AUC0-24,ss (%s*%s)", u$conc, u$time))
p <- metrics |>
  pivot_longer(c(cmax, cmin, auc24), names_to = "metric", values_to = "value") |>
  mutate(metric = factor(metric_labels[metric], levels = metric_labels)) |>
  ggplot(aes(scenario, value)) +
  geom_boxplot(outlier.alpha = 0.3, fill = "steelblue", alpha = 0.3) +
  facet_wrap(~ metric, scales = "free_y") +
  labs(x = NULL, y = NULL) +
  theme_tlf() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

# Title and subtitle go in the docorator header (render_tlf), not the ggplot.
render_tlf(p, "fig-exposure", out_dir, cfg, type = "poppk-sim", source_data = source_data,
           title = "Simulated Steady-State Exposure by Regimen",
           subtitle = sprintf("Last dosing interval of day 7; %d simulated subjects per regimen (%d x %d studies)",
                              settings$nSub * settings$nStud, settings$nSub, settings$nStud))

nca_log_stop()

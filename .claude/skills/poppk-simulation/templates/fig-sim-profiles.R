# Simulated concentration-time profiles (median and 90% prediction interval), in the shared
# TLF shell (pk-project scripts/tlf_shell.R) like every other table and figure:
#   page 1: all regimens overlaid;  then one page per regimen, with its steady-state
#   dosing interval shaded.
# Saves output/poppk-sim/v{{project_number}}/figures/fig-sim-profiles.pdf (+ .RDS: one plot per page).

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-sim-profiles", project_number = project_number, output_dir = "output/poppk-sim")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim.R")
source(".posit/assistant/skills/poppk-simulation/scripts/poppk_sim_db.R")
read_sim_db(project_number)   # sims, metrics, exposure_summary, profiles, settings, source_provenance
source(".posit/assistant/skills/pk-project/scripts/tlf_shell.R")
source_data <- sim_source_data(source_provenance)   # "Source data:" line of the TLF shell
u <- cfg$units

out_dir <- tlf_out_dir("poppk-sim", project_number)

x_lab <- lab_unit("Time", u$time)
y_lab <- lab_unit("Concentration", u$conc)
design <- sprintf("%d subjects x %d studies per regimen", settings$nSub, settings$nStud)
band <- "Line: median; ribbon: 90% prediction interval"   # has %, so it stays in the plot caption
theme_sim <- theme_tlf()

overlay <- ggplot(profiles, aes(time, median, colour = scenario, fill = scenario)) +
  geom_ribbon(aes(ymin = p05, ymax = p95), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.8) +
  labs(x = x_lab, y = y_lab, colour = NULL, fill = NULL, title = "All regimens", caption = band) +   # page label
  theme_sim

windows <- settings$windows |> mutate(scenario = factor(scenario, levels = levels(profiles$scenario)))
regimen_page <- function(sc) {
  d <- filter(profiles, scenario == sc)
  w <- filter(windows, scenario == sc)
  ggplot(d, aes(time, median)) +
    annotate("rect", xmin = w$start, xmax = w$end, ymin = -Inf, ymax = Inf, alpha = 0.1) +
    geom_ribbon(aes(ymin = p05, ymax = p95), fill = "steelblue", alpha = 0.3) +
    geom_line(colour = "steelblue4", linewidth = 0.8) +
    labs(x = x_lab, y = y_lab, title = sc,   # page label
         caption = sprintf("%s; grey band: steady-state dosing interval (%g-%g %s)", band, w$start, w$end, u$time)) +
    theme_sim
}

pages <- c(list(overlay), lapply(levels(profiles$scenario), regimen_page))
render_tlf(pages, "fig-sim-profiles", out_dir, cfg, type = "poppk-sim", source_data = source_data,
           title = "Simulated Concentration-Time Profiles", subtitle = design)

nca_log_stop()

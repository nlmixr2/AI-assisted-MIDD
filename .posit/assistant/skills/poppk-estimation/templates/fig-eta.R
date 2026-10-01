# Random effects of the final model (checklist item 4), standard TLF shell:
#   page 1: ETA distributions -- histogram (with density) and normal QQ per ETA, SD shrinkage in the labels
#   page 2: ETA vs baseline covariates (loess), when the data have any
# Treat ETA-based conclusions as weak where shrinkage > ~30%.
# Saves output/poppk/v{{project_number}}/figures/fig-eta.pdf (+ .RDS).

library(tidyverse)
library(patchwork)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-eta", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), fits, runs, pkData -- no refit
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_figures.R")

out_dir <- tlf_out_dir("poppk", project_number)
u <- cfg$units

## EDIT: covariates to plot against the ETAs (default: every baseline numeric covariate) ---
covariates <- baseline_covariates(pkData)

eta_long <- fit$eta |> mutate(ID = as.character(ID)) |> pivot_longer(-ID, names_to = "eta", values_to = "value")
shr <- fit$shrink["sd shrinkage (%)", unique(eta_long$eta), drop = TRUE]
eta_lab <- setNames(sprintf("%s (shrinkage %.1f%%)", names(shr), unlist(shr)), names(shr))
eta_long <- mutate(eta_long, eta = factor(eta_lab[eta], levels = eta_lab))

hist_p <- ggplot(eta_long, aes(value)) +
  geom_histogram(aes(y = after_stat(density)), bins = 10, fill = "grey80", colour = "grey40") +
  geom_density(colour = "steelblue4") + geom_vline(xintercept = 0, linetype = "dashed") +
  facet_wrap(~ eta, scales = "free", nrow = 1) + labs(x = "ETA", y = "Density") + theme_pmx()
qq_p <- ggplot(eta_long, aes(sample = value)) + stat_qq() + stat_qq_line(colour = "firebrick") +
  facet_wrap(~ eta, scales = "free", nrow = 1) + labs(x = "Theoretical quantiles", y = "ETA quantiles") + theme_pmx()
# Page labels only; the figure title is in the docorator header.
pages <- list((hist_p / qq_p) + plot_annotation(
  title = "ETA distributions and normal QQ plots; SD shrinkage in the panel labels"))

if (length(covariates)) {
  cov_df <- pkData |> distinct(ID, across(all_of(covariates))) |> mutate(ID = as.character(ID)) |>
    pivot_longer(-ID, names_to = "covariate", values_to = "cov_value")
  ec <- inner_join(eta_long, cov_df, by = "ID", relationship = "many-to-many")
  pages[[2]] <- ggplot(ec, aes(cov_value, value)) +
    geom_hline(yintercept = 0, linetype = "dashed") + geom_point() +
    geom_smooth(method = "loess", formula = y ~ x, se = FALSE, colour = "firebrick", span = 1) +
    facet_grid(eta ~ covariate, scales = "free") +
    labs(x = "Covariate value", y = "ETA",
         title = sprintf("ETA vs baseline covariates (%s); red: loess smooth", paste(covariates, collapse = ", "))) +
    theme_pmx() + theme(strip.text.y = element_text(size = 7))
}

render_poppk_display(pages, "fig-eta", out_dir, cfg, source_data = db_meta$source_file_path,
                     title = sprintf("Random Effects -- %s (Final Model)", final_run),
                     subtitle = sprintf("%s; ETA distributions%s", cfg$study$id,
                                        if (length(covariates)) " and ETA vs baseline covariates" else ""))

nca_log_stop()

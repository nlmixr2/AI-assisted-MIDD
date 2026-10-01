# Terminal-phase (lambda z) regression plots: ONE PAGE PER PARTICIPANT, semi-logarithmic
# scale, all observations (open) with the points used in the regression filled, and the
# regression line in RED. The line is PKNCA's own fit, rebuilt from the stored results
# (Clast,pred * exp(-lambda.z * (t - tlast)) over the regression interval), not a refit.
# Same docorator shell as the tables. From the pk-nca-figures skill.
# Saves output/nca/v{{project_number}}/figures/fig-lambdaz.pdf (+ .RDS: list of plots, one per participant).

library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-lambdaz", project_number = project_number)

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/pk-nca-database/scripts/nca_db.R")
db_meta <- read_nca_db(project_number)
source(".posit/assistant/skills/pk-nca-figures/scripts/nca_figures.R")

out_dir <- sprintf("output/nca/v%d/figures", project_number)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

## EDIT: span-ratio threshold used to flag short terminal phases ---------------------
span_min <- 2

# Regression details per participant (0-Inf interval), from the stored PKNCA results
fit <- ncaRes$result |>
  filter(end == Inf, PPTESTCD %in% c("lambda.z", "lambda.z.time.first", "lambda.z.time.last",
                                     "lambda.z.n.points", "tlast", "clast.pred", "half.life",
                                     "adj.r.squared", "span.ratio")) |>
  select(participant, PPTESTCD, PPORRES) |>
  pivot_wider(names_from = PPTESTCD, values_from = PPORRES) |>
  mutate(participant = as.character(participant))
if (!"lambda.z.time.last" %in% names(fit)) fit$lambda.z.time.last <- fit$tlast

x_lab <- sprintf("Time after dose (%s)", cfg$units$time)
y_lab <- sprintf("Concentration (%s, log scale)", cfg$units$conc)
hl_unit <- cfg$units$time

lambdaz_plot <- function(id) {
  d <- filter(cObsData, as.character(participant) == id, cObs > 0)
  f <- filter(fit, participant == id)
  base <- ggplot(d, aes(time, cObs)) + scale_y_log10() + theme_pk() +
    labs(x = x_lab, y = y_lab, title = sprintf("Participant %s", id))   # page label
  if (!nrow(f) || !is.finite(f$lambda.z)) {
    return(base + geom_point(shape = 21, fill = "white") +
             labs(caption = "Terminal phase could not be estimated (no lambda z)."))
  }
  d <- mutate(d, used = time >= f$lambda.z.time.first & time <= f$lambda.z.time.last)
  line <- tibble(time = seq(f$lambda.z.time.first, f$lambda.z.time.last, length.out = 50),
                 cObs = f$clast.pred * exp(-f$lambda.z * (time - f$tlast)))
  flag <- is.finite(f$span.ratio) && f$span.ratio < span_min
  base +
    geom_line(data = line, colour = "red", linewidth = 0.9) +
    geom_point(data = d, aes(fill = used), shape = 21, size = 2.4) +
    scale_fill_manual(values = c(`TRUE` = "black", `FALSE` = "white"),
                      labels = c(`TRUE` = "Used in regression", `FALSE` = "Not used"), name = NULL) +
    labs(
      # Page label only; the figure title is in the docorator header.
      title = sprintf("Participant %s%s", id, if (flag) sprintf(" -- span ratio < %g", span_min) else ""),
      caption = sprintf(
        "lambda z = %.4f 1/%s; half-life = %.2f %s; adj. R-squared = %.4f; span ratio = %.2f; %d points (%.2f-%.2f %s)",
        f$lambda.z, hl_unit, f$half.life, hl_unit, f$adj.r.squared, f$span.ratio,
        as.integer(f$lambda.z.n.points), f$lambda.z.time.first, f$lambda.z.time.last, hl_unit)
    )
}

ids <- participant_order(cObsData$participant)
plots <- setNames(lapply(ids, lambdaz_plot), ids)

render_pk_display(
  plots, "fig-lambdaz", out_dir, cfg, source_data = db_meta$source_file_path,
  title = "Terminal-Phase (Lambda z) Regression",
  subtitle = sprintf("%s; red line: PKNCA log-linear regression, filled points used in it; concentrations of 0 not shown",
                     cfg$study$id)
)

nca_log_stop()

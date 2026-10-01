# Compartment diagram of the final model, drawn from its differential equations by
# nlmixr2plot::modelDiagram() (https://nlmixr2.github.io/nlmixr2plot/articles/model-diagrams.html):
# dosing compartment(s) with a heavy border, mass transfer and elimination as arrows, each
# arrow labelled with the model term that drives it. The parsed graph (modelGraph(): nodes and
# edges) is written to the log so a reviewer can check how the equations were read.
# modelDiagram() is new in nlmixr2plot; with a version that lacks it the page says so (and the
# log explains), so the version still runs.
# Saves output/poppk/v{{project_number}}/figures/fig-model-diagram.pdf (+ .RDS).

library(nlmixr2)
library(tidyverse)

source(".posit/assistant/skills/pk-nca-logging/scripts/nca_log.R")
project_number <- {{project_number}}L
nca_log_start("fig-model-diagram", project_number = project_number, output_dir = "output/poppk")

source(".posit/assistant/skills/pk-project/scripts/project.R")
cfg <- project_config()
source(".posit/assistant/skills/poppk-database/scripts/poppk_db.R")
db_meta <- read_poppk_db(project_number)   # fit (final model), pkData -- no refit
source(".posit/assistant/skills/poppk-estimation/scripts/poppk_figures.R")

out_dir <- tlf_out_dir("poppk", project_number)

## EDIT: arrow labels -----------------------------------------------------------------
show_terms <- TRUE   # label arrows with the model terms (e.g. ka*depot, cl/v*central)

has_diagram <- all(c("modelDiagram", "modelGraph") %in% getNamespaceExports("nlmixr2plot"))
if (has_diagram) {
  graph <- nlmixr2plot::modelGraph(fit, data = pkData)   # dosing compartments from the data
  print(graph)                                           # nodes and edges, for the log
  p <- nlmixr2plot::modelDiagram(graph, engine = "ggplot2", labels = show_terms) +
    labs(caption = "Heavy border: dosing compartment. Arrows: mass transfer and elimination, labelled with the model terms.") +
    # the diagram's fixed aspect ratio makes the panel narrow: align the caption to the whole
    # plot, or it is right-aligned to the panel and runs off the left edge of the page
    theme(plot.caption.position = "plot", plot.caption = element_text(hjust = 0))
} else {
  message("nlmixr2plot ", utils::packageVersion("nlmixr2plot"), " has no modelDiagram(): ",
          "install a newer nlmixr2plot to draw the diagram")
  p <- ggplot() + theme_void() +
    annotate("text", x = 0, y = 0, size = 4, family = "serif",
             label = sprintf("Model diagram not drawn: nlmixr2plot %s has no modelDiagram().",
                             utils::packageVersion("nlmixr2plot")))
}

# Title and subtitle go in the docorator header (render_tlf), not the ggplot.
render_poppk_display(p, "fig-model-diagram", out_dir, cfg, source_data = db_meta$source_file_path,
                     title = sprintf("Model Structure -- %s (Final Model)", final_run),
                     subtitle = sprintf("%s; drawn from the model's differential equations", cfg$study$id))

nca_log_stop()

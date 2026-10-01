# Model file for poppk-simulation's "model-file" source:
#   sim_source <- list(type = "model-file", path = "model/<name>.R")
#
# Rules: define exactly ONE function with ini({}) and model({}); nothing else runs at
# source time (no library() calls, no data reads). Parameter values are the
# simulation's truth -- state their origin (publication, prior fit, assumption) here:
#
#   Source: <citation or "assumed">; units: dose mg, time h, conc mg/L.
#
# OMEGA (eta ~ variance) drives between-subject variability when nSub > 1. Add
# prior() lines (see references/uncertainty-and-priors.md) or pass thetaMat= to
# rxSolve() for parameter uncertainty across nStud > 1 studies. The residual line is
# only needed to simulate noisy observations (`sim` column).

one_cmt_oral <- function() {
  ini({
    tka <- log(1.57); label("Ka (1/h)")
    tcl <- log(2.76); label("CL/F (L/h)")
    tv  <- log(31.5); label("V/F (L)")
    eta.ka ~ 0.41
    eta.cl ~ 0.070
    eta.v  ~ 0.018
    add.sd <- 0.696;  label("Additive residual SD (mg/L)")
  })
  model({
    ka <- exp(tka + eta.ka)
    cl <- exp(tcl + eta.cl)
    v  <- exp(tv  + eta.v)
    d/dt(depot)  <- -ka * depot
    d/dt(center) <-  ka * depot - cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}

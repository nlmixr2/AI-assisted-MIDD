# Scenario tests for scripts/poppk_param_table.R (no nlmixr2 needed). Run from the project root:
#   testthat::test_file(".posit/assistant/skills/poppk-tables/tests/test-poppk-param-table.R")
# Each scenario builds the pieces of an nlmixr2 fit the table reads (iniDf, parFixedDf, OMEGA,
# mu-referencing) for a known model, and checks the table against that model and a data set.

library(testthat)
skill_dir <- tryCatch(dirname(normalizePath(testthat::test_path())),   # .../poppk-tables
                      error = function(e) normalizePath(".posit/assistant/skills/poppk-tables"))  # sourced from the project root
project_root <- normalizePath(file.path(skill_dir, "..", "..", "..", ".."))
source(file.path(skill_dir, "scripts", "poppk_param_table.R"), local = TRUE)

pk_data_file <- file.path(project_root, "examples", "abc-111", "data", "pk-data-2.csv")
pk_data <- read.csv(pk_data_file)   # 12 participants, 132 observations (EVID 0)

# Build fit-like inputs. thetas: name, est (estimation scale), back (back-transformed), label,
# fix; etas: name, var, theta (mu-referenced THETA or NA); off: eta1, eta2, cov; errs: name,
# err type, est, label.
make_inputs <- function(thetas, etas, errs, off = NULL, n_id = 12, n_obs = 132) {
  allth <- rbind(transform(thetas, err = NA_character_), transform(errs, back = est, fix = FALSE))
  allth$ntheta <- seq_len(nrow(allth))
  ini_th <- data.frame(ntheta = allth$ntheta, neta1 = NA_real_, neta2 = NA_real_, name = allth$name,
                       lower = -Inf, est = allth$est, upper = Inf, fix = allth$fix, label = allth$label,
                       backTransform = NA_character_, condition = NA_character_, err = allth$err)
  ini_eta <- data.frame(ntheta = NA_real_, neta1 = seq_len(nrow(etas)), neta2 = seq_len(nrow(etas)),
                        name = etas$name, lower = -Inf, est = etas$var, upper = Inf, fix = FALSE,
                        label = NA_character_, backTransform = NA_character_, condition = "id", err = NA_character_)
  om <- diag(etas$var, nrow(etas)); dimnames(om) <- list(etas$name, etas$name)
  ini_off <- NULL
  if (!is.null(off)) {
    i1 <- match(off$eta1, etas$name); i2 <- match(off$eta2, etas$name)
    om[cbind(i1, i2)] <- off$cov; om[cbind(i2, i1)] <- off$cov
    ini_off <- data.frame(ntheta = NA_real_, neta1 = pmax(i1, i2), neta2 = pmin(i1, i2),
                          name = sprintf("(%s,%s)", off$eta2, off$eta1), lower = -Inf, est = off$cov,
                          upper = Inf, fix = FALSE, label = NA_character_, backTransform = NA_character_,
                          condition = "id", err = NA_character_)
  }
  mu <- etas[!is.na(etas$theta), c("theta", "name")]; names(mu) <- c("theta", "eta")
  cv <- setNames(rep(NA_real_, nrow(allth)), allth$name)
  shr <- cv
  for (k in seq_len(nrow(mu))) {
    cv[mu$theta[k]] <- 100 * sqrt(exp(etas$var[etas$name == mu$eta[k]]) - 1)
    shr[mu$theta[k]] <- 10 * k
  }
  pf <- data.frame(Estimate = allth$est, SE = 0.1, `%RSE` = ifelse(allth$fix, NA, 10), `Back-transformed` = allth$back,
                   `CI Lower` = allth$back * 0.8, `CI Upper` = allth$back * 1.2, `BSV(CV%)` = cv,
                   `Shrink(SD)%` = shr, check.names = FALSE, row.names = allth$name)
  list(iniDf = rbind(ini_th, ini_eta, ini_off), parFixedDf = pf, omega = om, mu_ref = mu,
       n_id = n_id, n_obs = n_obs, objf = 100, est = "saem")
}

base_thetas <- data.frame(name = c("tka", "tcl", "tv"), est = log(c(1.5, 2.76, 31.5)), back = c(1.5, 2.76, 31.5),
                          label = c("Ka (1/h)", "CL/F (L/h)", "V/F (L)"), fix = FALSE)
base_etas <- data.frame(name = c("eta.ka", "eta.cl", "eta.v"), var = c(0.4, 0.07, 0.02), theta = c("tka", "tcl", "tv"))
add_err <- data.frame(name = "add.sd", err = "add", est = 0.7, label = "Additive residual SD (mg/L)")

test_that("scenario 1: 1-cmt oral, diagonal OMEGA, additive error -> three complete sections", {
  inp <- make_inputs(base_thetas, base_etas, add_err)
  rows <- poppk_param_rows(inp)
  expect_equal(as.vector(table(rows$kind)[c("fixed", "random", "ruv")]), c(3, 3, 1))
  expect_false(any(rows$kind == "corr"))
  expect_equal(unique(rows$section), c("Fixed effects", "Random effects (between-subject variability)",
                                       "Residual unexplained variability"))
  expect_equal(rows$est[rows$kind == "fixed"], c(1.5, 2.76, 31.5))                 # back-transformed
  expect_equal(rows$label[rows$kind == "random"], c("BSV on Ka (1/h)", "BSV on CL/F (L/h)", "BSV on V/F (L)"))
  expect_equal(rows$est[rows$kind == "random"], c(0.4, 0.07, 0.02))                # omega^2
  expect_equal(rows$bsv[rows$name == "eta.cl"], 100 * sqrt(exp(0.07) - 1))          # nlmixr2's CV% of tcl
  expect_true(all(is.na(rows$bsv[rows$kind == "fixed"])))                          # BSV only in its section
  expect_equal(rows$label[rows$kind == "ruv"], "Additive residual SD (mg/L)")
  expect_match(check_param_table(rows, inp, pk_data), "12 participants, 132 observations")
})

test_that("scenario 2: OMEGA block, combined error, fixed THETA, covariate THETA without ETA", {
  th <- rbind(base_thetas, data.frame(name = "cl.wt", est = 0.75, back = 0.75, label = "WT on CL/F (exponent)", fix = FALSE))
  th$fix[th$name == "tka"] <- TRUE
  errs <- rbind(add_err, data.frame(name = "prop.sd", err = "prop", est = 0.1, label = NA_character_))
  inp <- make_inputs(th, base_etas, errs, off = data.frame(eta1 = "eta.cl", eta2 = "eta.v", cov = 0.02))
  rows <- poppk_param_rows(inp)
  expect_equal(sum(rows$kind == "fixed"), 4)
  expect_equal(rows$label[rows$name == "tka"], "Ka (1/h) (fixed)")
  expect_true(is.na(rows$rse[rows$name == "tka"]))                                  # no RSE for a fixed THETA
  expect_false("cl.wt" %in% rows$name[rows$kind == "random"])                        # no ETA -> no BSV row
  corr <- rows[rows$kind == "corr", ]
  expect_equal(nrow(corr), 1)
  expect_equal(corr$est, 0.02 / sqrt(0.07 * 0.02))
  expect_equal(corr$label, "Correlation: CL/F (L/h) ~ V/F (L)")
  expect_equal(rows$label[rows$name == "prop.sd"], "Proportional residual SD (fraction)")  # label from error type
  expect_equal(rows$kind[nrow(rows) - 0:1], c("ruv", "ruv"))                          # RUV last
  expect_silent(check_param_table(rows, inp, pk_data))
})

test_that("scenario 3: ETA without a mu-referenced THETA keeps its row, with no CV%", {
  etas <- rbind(base_etas, data.frame(name = "eta.x", var = 0.1, theta = NA))
  inp <- make_inputs(base_thetas, etas, add_err)
  rows <- poppk_param_rows(inp)
  expect_equal(rows$label[rows$name == "eta.x"], "BSV eta.x")
  expect_true(is.na(rows$bsv[rows$name == "eta.x"]))
  expect_equal(rows$est[rows$name == "eta.x"], 0.1)
  expect_silent(check_param_table(rows, inp, pk_data))
})

test_that("scenario 4: fit and source data disagree -> stop with both counts", {
  inp <- make_inputs(base_thetas, base_etas, add_err)
  rows <- poppk_param_rows(inp)
  expect_error(check_param_table(rows, inp, pk_data[pk_data$ID != 12, ]), "Participants: 12 in the fit, 11 in the source data")
  inp_obs <- inp; inp_obs$n_obs <- 120
  expect_error(check_param_table(rows, inp_obs, pk_data), "Observations: 120 in the fit, 132 in the source data")
  mdv <- transform(pk_data, MDV = as.integer(EVID != 0))
  mdv <- rbind(mdv, transform(mdv[mdv$EVID == 0, ][1, ], MDV = 1L))
  expect_silent(check_param_table(rows, inp, mdv))                                   # MDV = 1 row is not an observation
})

test_that("scenario 5: table and model disagree -> stop naming the parameter", {
  inp <- make_inputs(base_thetas, base_etas, add_err)
  rows <- poppk_param_rows(inp)
  expect_error(check_param_table(rows[rows$name != "tcl", ], inp, pk_data), "Fixed effects \\(THETA\\) missing from the table: tcl")
  expect_error(check_param_table(rbind(rows, rows[rows$name == "eta.v", ]), inp, pk_data), "listed twice: eta.v")
  expect_error(check_param_table(rows[rows$kind != "ruv", ], inp, pk_data), "Residual error parameters missing")
  bad <- rows; bad$est[bad$name == "tv"] <- 30
  expect_error(check_param_table(bad, inp, pk_data), "Fixed-effect estimates differ")
  inp_blk <- make_inputs(base_thetas, base_etas, add_err, off = data.frame(eta1 = "eta.cl", eta2 = "eta.v", cov = 0.02))
  expect_error(check_param_table(rows, inp_blk, pk_data), "OMEGA correlations: 1 in the model, 0 in the table")
})

test_that("scenario 6: parameters without labels fall back to their model names", {
  th <- base_thetas; th$label <- NA_character_
  errs <- data.frame(name = "add.sd", err = "add", est = 0.7, label = NA_character_)
  rows <- poppk_param_rows(make_inputs(th, base_etas, errs))
  expect_equal(rows$label[rows$kind == "fixed"], c("tka", "tcl", "tv"))
  expect_equal(rows$label[rows$kind == "random"], c("BSV on tka", "BSV on tcl", "BSV on tv"))
  expect_equal(rows$label[rows$kind == "ruv"], "Additive residual SD")
})

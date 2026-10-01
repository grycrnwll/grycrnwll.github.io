# make_gdp_test.R -- the test-set forecast payload for the Module 6 deck.
#
# Run from anywhere with the course R runtime (paths are resolved from this file):
#   & "C:\Program Files\R\R-4.3.2\bin\Rscript.exe" slides/module_06/cache/make_gdp_test.R
#
# The deck's worked example fits ARIMA(p,1,q) models with drift to y_t = log real GDP
# per capita on the training window 1990 Q1 to 2006 Q4 (make_figures.R, section 4) and
# lets four information criteria choose: AIC, AICc and HQIC pick ARIMA(2,1,0) with
# drift, BIC picks ARIMA(1,1,0) with drift. This script takes those two winners, with
# their parameters FROZEN at the training estimates (no re-estimation; that is Module
# 7), out of sample: a rolling-origin forecast of the next five years, 2007 Q1 to
# 2011 Q4 (20 quarters, the Great Recession included), at horizons one and two
# quarters, against a random-walk-with-drift benchmark. Three views of every forecast:
# the log level the model works in, the level in chained (2017) dollars per person, and
# the quarterly growth rate in percent.
#
# Honesty note the outputs carry: the test data are the cached FRED pull in its
# 2026-09-30 vintage (../../../data/A939RX0Q048SBEA.csv), not the real-time data a
# forecaster had in 2007-2011. Vintage effects are a Module 7 topic.
#
# The fits are reproduced here with the SAME call on the SAME window as make_figures.R
# (forecast::Arima(y, order = c(p, 1L, q), include.drift = TRUE)) and checked against the
# cached results before anything else runs: coefficients against cache/ic_residuals.json
# (stored at six decimals, so the check is at that precision) and log-likelihood, AIC,
# AICc, BIC and HQIC against cache/ic_table.csv (full precision, 1e-8). A drifted fit
# stops the build.
#
# Rolling origin, parameters fixed: for every origin t, forecast::Arima(y_through_t,
# model = fit_train) re-runs the Kalman filter over the data through t with the training
# coefficients held fixed (stats::arima with fixed = coef; forecast's arima2() also
# carries the training sigma^2 over, so the intervals use the training innovation
# variance, read from the installed source), and forecast(h = 2, level = c(80, 95))
# gives the one- and two-step forecasts with Gaussian intervals at qnorm's z. The h = 1
# target 2007 Q1 has origin 2006 Q4; the h = 2 target 2007 Q1 has origin 2006 Q3 (the
# model applied to data through 2006 Q3, inside the training window). Both are
# cross-checked against the closed forms: the AR recursion on the growth rate for the
# point forecasts, sigma^2 sum_{j<h} psi_j^2 for the variances, psi from ARMAtoMA on the
# level's AR polynomial (the differencing folded in).
#
# Growth view. h = 1: growth-hat_{t+1|t} = 100 (y-hat_{t+1|t} - y_t), bounds shifted the
# same way (exact: y_t is known). h = 2: growth-hat_{t+2|t} = 100 (y-hat_{t+2|t} -
# y-hat_{t+1|t}) against the realised 100 (y_{t+2} - y_{t+1}); its error is
# eps_{t+2} + (psi_1 - 1) eps_{t+1}, variance sigma^2 [(psi_1 - 1)^2 + 1], Gaussian bounds
# at +/- z times that standard deviation. That variance is verified by Monte Carlo:
# 100,000 two-step paths simulated from each fitted model at the origin 2006 Q4 (seed
# 6376), the variance of the simulated two-step growth error within 2% of the formula or
# the build stops.
#
# Benchmark, random walk with drift: y-hat_{t+h|t} = y_t + h delta-bar, delta-bar the
# training-sample mean of the first difference, Gaussian bounds from the training-sample
# variance of the first difference (sd(), n - 1): h sigma_D^2 for the log level at
# horizon h, sigma_D^2 for the one-quarter growth rate at either horizon.
#
# Scores per model and horizon over the 20 targets: RMSE and MAE of the growth errors
# (percent per quarter), RMSE of the level error as a percent of the realised level,
# coverage counts of the 80% and 95% intervals (k of 20, on the log level; the level
# view gives the same flags, exp is monotone), and the growth RMSE and 95% coverage on
# the four worst quarters, 2008 Q3 to 2009 Q2, so the widget can say where the misses are.
#
# Outputs (all in this directory; byte-deterministic, no timestamps, one seed):
#   gdp_test.json         the widget payload (contract in the deck brief; numbers written
#                         at JSON_SIG_DIGITS significant figures)
#   gdp_test_scores.csv   one row per model x horizon with the scores
#   gdp_test_h1.csv       per-target tables, long format (model, target, origin, fields)
#   gdp_test_h2.csv
#   .gdp_test_ready       empty sentinel, written last; it, not the exit status, is the
#                         evidence of a complete run (make_figures.R convention)
# Requires: forecast, jsonlite. Single process.

# ---- windows: the one place to change them -----------------------------------
# Quarterly c(year, quarter). TRAIN_* must equal make_figures.R's WINDOW_START/END or
# the coefficient check below stops the build.
TRAIN_START <- c(1990, 1)
TRAIN_END   <- c(2006, 4)
TEST_START  <- c(2007, 1)
TEST_END    <- c(2011, 4)
TAIL_START  <- c(2003, 1)       # the training tail the widget draws before the test set
WORST_START <- c(2008, 3)       # the four worst quarters: a sub-period score
WORST_END   <- c(2009, 2)

# ---- constants ---------------------------------------------------------------
H_MAX     <- 2L                 # horizons one and two quarters
LEVELS    <- c(80, 95)          # interval levels, forecast::forecast()'s argument
Z         <- qnorm(0.5 * (1 + LEVELS / 100))   # 1.2816, 1.9600: what forecast() uses
names(Z)  <- c("80", "95")
SEED      <- 6376L              # the Monte Carlo seed (course convention)
MC_DRAWS  <- 100000L
MC_TOL    <- 0.02               # Monte Carlo variance within 2% of the formula
JSON_SIG_DIGITS <- 8L           # significant figures in gdp_test.json (log y ~ 10.8 keeps
                                # six decimals; six figures would leave it four, coarser
                                # than the growth arrays it has to agree with)
VINTAGE      <- "2026-09-30"    # the BEA release the cache holds (data/README.md)
VINTAGE_LAST <- 71212           # its 2026 Q2 value: the vintage check (make_figures.R hard stop 1)
SERIES_ID    <- "A939RX0Q048SBEA"
MODEL_KEYS   <- c("arima210d", "arima110d")      # the two distinct criterion winners
EXPECTED_WINNER <- list(AIC = "arima210d", AICc = "arima210d", BIC = "arima110d", HQIC = "arima210d")

Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1")
options(width = 120, digits = 7, warn = 1)

arg_file <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(arg_file) == 1L) {
  setwd(dirname(normalizePath(sub("^--file=", "", arg_file), winslash = "/")))
}
sentinel <- ".gdp_test_ready"
unlink(sentinel)

source("../../../helpers/data_utils.R")       # load_cached_fred()
source("../../../helpers/model_selection.R")  # hqic()

suppressPackageStartupMessages({
  library(forecast)
  library(jsonlite)
})
set.seed(SEED)

note <- function(key, value) cat(sprintf("%s=%s", key, paste(as.character(value), collapse = ";")), "\n")
q_label <- function(tt) sprintf("%d Q%d", floor(tt + 1e-8), round((tt - floor(tt + 1e-8)) * 4) + 1L)
q_time  <- function(yq) yq[1] + (yq[2] - 1) / 4          # c(year, quarter) -> ts time
q_span  <- function(a, b) sprintf("%s to %s", q_label(q_time(a)), q_label(q_time(b)))
n_quarters <- function(start, end) as.integer((end[1] - start[1]) * 4 + (end[2] - start[2]) + 1)
at_time <- function(x, tt) {                              # one value of a quarterly ts at time tt
  i <- which(abs(as.numeric(time(x)) - tt) < 1e-8)
  stopifnot(length(i) == 1L)
  as.numeric(x)[i]
}

# ---- data --------------------------------------------------------------------
DATA_FILE <- "../../../data/A939RX0Q048SBEA.csv"

# Hard stop 1: the cache is the vintage the deck names (make_figures.R hard stop 1, repeated
# so this payload cannot silently come from a different release than the fits).
raw <- read.csv(DATA_FILE)
stopifnot(identical(names(raw), c("observation_date", SERIES_ID)),
          nrow(raw) == 318L, !anyNA(raw[[SERIES_ID]]),
          identical(raw$observation_date[c(1, 318)], c("1947-01-01", "2026-04-01")),
          raw[[SERIES_ID]][318] == VINTAGE_LAST, all(raw[[SERIES_ID]] > 0))

lev_full <- load_cached_fred(DATA_FILE, value_col = SERIES_ID, frequency = 4)
y_full   <- log(lev_full)                                 # natural log, the series the models work in
lev      <- window(lev_full, start = TRAIN_START, end = TRAIN_END)
y        <- log(lev)                                      # make_figures.R's y, same two statements
dy       <- diff(y)
T_lev    <- length(y); T_dy <- length(dy)
train_lab <- q_span(TRAIN_START, TRAIN_END)
test_lab  <- q_span(TEST_START, TEST_END)

# Hard stop 2: complete quarterly runs, the test window entirely inside the cache.
stopifnot(frequency(y) == 4, T_lev == n_quarters(TRAIN_START, TRAIN_END), all(is.finite(y)),
          T_dy == T_lev - 1L,
          q_time(TEST_START) == q_time(TRAIN_END) + 0.25,
          q_time(TEST_END) + 0.25 <= max(time(y_full)) + 1e-8,
          all(is.finite(window(y_full, start = TAIL_START, end = TEST_END))))
note("series", sprintf("log(%s), natural log", SERIES_ID)); note("vintage", VINTAGE)
note("train", sprintf("%s (%d levels, %d differences)", train_lab, T_lev, T_dy))
note("test", sprintf("%s (%d quarters)", test_lab, n_quarters(TEST_START, TEST_END)))

# The benchmark's two numbers: the training mean and standard deviation of the growth rate.
drift_bar <- mean(dy)
sd_dy     <- sd(dy)
note("drift_train_pct_per_quarter", sprintf("%.6f", 100 * drift_bar))
note("sd_dgrowth_train_pct", sprintf("%.6f", 100 * sd_dy))

# ==============================================================================
# 1. The training fits, reproduced and checked against the deck's cache
# ==============================================================================
# The same call as make_figures.R's fit_cand(): forecast::Arima() on the log level, d = 1,
# include.drift = TRUE, package defaults otherwise (method CSS-ML).
order_of <- list(arima210d = c(2L, 1L, 0L), arima110d = c(1L, 1L, 0L))
label_of <- list(arima210d = "ARIMA(2,1,0) with drift", arima110d = "ARIMA(1,1,0) with drift")
fit_train <- lapply(order_of, function(o) Arima(y, order = o, include.drift = TRUE))

ic_json  <- fromJSON("ic_residuals.json", simplifyVector = TRUE)
ic_table <- read.csv("ic_table.csv", stringsAsFactors = FALSE)
# Hard stop 3: the cached winners are the ones this script freezes, and the two models are
# the distinct winners.
stopifnot(identical(unlist(ic_json$winner[names(EXPECTED_WINNER)]), unlist(EXPECTED_WINNER)),
          setequal(unique(unlist(ic_json$winner)), MODEL_KEYS),
          all(MODEL_KEYS %in% ic_table$key), all(MODEL_KEYS %in% names(ic_json$models)))

coef_dev <- numeric(0); ic_dev <- numeric(0)
for (key in MODEL_KEYS) {
  f <- fit_train[[key]]
  stopifnot(isTRUE(f$code == 0), all(is.finite(f$coef)), f$nobs == T_dy,
            identical(f$arma[c(1, 6, 2)], order_of[[key]]), "drift" %in% names(f$coef))
  jc <- unlist(ic_json$models[[key]]$coef)
  stopifnot(identical(names(jc), names(f$coef)))
  # The JSON stores round(coef, 6): a bit-identical refit rounds to the same six decimals.
  coef_dev[key] <- max(abs(f$coef - jc))
  row <- ic_table[ic_table$key == key, ]
  ic_dev[key] <- max(abs(c(f$loglik - row$loglik, f$aic - row$AIC, f$aicc - row$AICc,
                           f$bic - row$BIC, hqic(f) - row$HQIC)))
  note(sprintf("fit_%s", key), sprintf("%s loglik=%.6f sigma2=%.6e coef_dev_vs_json=%.2e ic_dev_vs_table=%.2e",
                                       paste(sprintf("%s=%.6f", names(f$coef), f$coef), collapse = " "),
                                       f$loglik, f$sigma2, coef_dev[key], ic_dev[key]))
  # Hard stop 4: the refit IS the deck's fit. Coefficients equal the JSON at its stored
  # precision (six decimals, so a bit-identical fit gives round(coef, 6) == JSON exactly);
  # log-likelihood and the four criteria equal the full-precision table to 1e-8.
  stopifnot(max(abs(round(f$coef, 6) - jc)) < 1e-8, coef_dev[key] <= 5e-7 + 1e-8,
            ic_dev[key] < 1e-8, identical(ic_json$models[[key]]$label, label_of[[key]]))
}
coef_match_max_abs <- max(coef_dev)

# The level's psi-weights: the AR polynomial of the level is phi(L)(1 - L); in R's sign
# convention (1 - sum ar_k L^k) its coefficients are a_{k-1} - a_k for a = c(1, -phi, 0).
psi_weights <- function(phi, lag_max = 4L) {
  a <- c(1, -phi, 0)
  ar_level <- a[seq_len(length(phi) + 1L)] - a[seq_len(length(phi) + 1L) + 1L]
  ARMAtoMA(ar = ar_level, ma = numeric(0), lag.max = lag_max)
}
model_info <- lapply(MODEL_KEYS, function(key) {
  f <- fit_train[[key]]
  phi <- unname(f$coef[grepl("^ar", names(f$coef))])
  psi <- psi_weights(phi)
  stopifnot(abs(psi[1] - (1 + phi[1])) < 1e-12)       # psi_1 = 1 + phi_1 for any ARIMA(p,1,0)
  list(key = key, label = label_of[[key]], phi = phi, delta = unname(f$coef[["drift"]]),
       sigma = sqrt(f$sigma2), psi = psi, se = sqrt(diag(f$var.coef)))
})
names(model_info) <- MODEL_KEYS
for (m in model_info) note(sprintf("psi_%s", m$key), sprintf("%.6f", m$psi))

# ==============================================================================
# 2. Rolling-origin forecasts, parameters fixed at the training estimates
# ==============================================================================
# Origins run from two quarters before the first target (h = 2) to one quarter before the
# last (h = 1): 2006 Q3 .. 2011 Q3. Each origin's forecast is taken ONCE at h = 1..2 and
# the two tables below pick out the horizon they need.
origin_times <- seq(q_time(TEST_START) - 0.5, q_time(TEST_END) - 0.25, by = 0.25)
target_times <- seq(q_time(TEST_START), q_time(TEST_END), by = 0.25)
n_test <- length(target_times)
stopifnot(n_test == 20L, length(origin_times) == n_test + 1L)
dates_test <- q_label(target_times)
logy_test  <- vapply(target_times, function(tt) at_time(y_full, tt), 0)
level_test <- vapply(target_times, function(tt) at_time(lev_full, tt), 0)
growth_test <- 100 * (logy_test - vapply(target_times - 0.25, function(tt) at_time(y_full, tt), 0))
stopifnot(abs(max(abs(exp(logy_test) - level_test)) / mean(level_test)) < 1e-12)

# One fixed-parameter forecast per origin: the package route and the closed forms.
fc_at_origin <- function(m, origin) {
  y_t <- window(y_full, start = TRAIN_START, end = origin)
  refit <- Arima(y_t, model = fit_train[[m$key]])
  # Hard stop 5: nothing was re-estimated; the training sigma^2 travels with the model.
  stopifnot(identical(unname(refit$coef), unname(fit_train[[m$key]]$coef)),
            identical(refit$sigma2, fit_train[[m$key]]$sigma2),
            abs(as.numeric(time(y_t))[length(y_t)] - origin) < 1e-8)
  fc <- forecast(refit, h = H_MAX, level = LEVELS)
  # Closed forms: the AR recursion on the growth rate from the last p observed differences,
  # and sigma^2 sum_{j<h} psi_j^2.
  yv <- as.numeric(y_t); dyv <- diff(yv); p <- length(m$phi)
  hist <- dyv[length(dyv) - seq_len(p) + 1L]           # most recent first
  d_hat <- numeric(H_MAX)
  for (h in seq_len(H_MAX)) {
    d_hat[h] <- m$delta + sum(m$phi * (hist[seq_len(p)] - m$delta))
    hist <- c(d_hat[h], hist)
  }
  point_cf <- yv[length(yv)] + cumsum(d_hat)
  se_cf    <- m$sigma * sqrt(cumsum(c(1, m$psi)[seq_len(H_MAX)]^2))
  se_pkg   <- (as.numeric(fc$upper[, "95%"]) - as.numeric(fc$mean)) / Z[["95"]]
  list(origin = origin, y_origin = yv[length(yv)], dy_hat = d_hat,
       mean = as.numeric(fc$mean),
       lo80 = as.numeric(fc$lower[, "80%"]), hi80 = as.numeric(fc$upper[, "80%"]),
       lo95 = as.numeric(fc$lower[, "95%"]), hi95 = as.numeric(fc$upper[, "95%"]),
       dev_point = max(abs(as.numeric(fc$mean) - point_cf)), dev_se = max(abs(se_pkg - se_cf)))
}
runs <- lapply(model_info, function(m) lapply(origin_times, function(o) fc_at_origin(m, o)))
for (key in MODEL_KEYS) {
  dp <- max(vapply(runs[[key]], function(r) r$dev_point, 0))
  ds <- max(vapply(runs[[key]], function(r) r$dev_se, 0))
  note(sprintf("crosscheck_%s_maxabs_point_se", key), sprintf("%.3g/%.3g", dp, ds))
  # Hard stop 6: the Kalman forecasts equal the closed forms (1e-10; observed ~1e-14).
  stopifnot(dp < 1e-10, ds < 1e-10)
}

# Per-horizon tables. Rows are the 20 targets in order; the origin is h quarters earlier.
# The h = 2 growth bounds use the derived variance sigma^2 [(psi_1 - 1)^2 + 1].
model_table <- function(m, h) {
  idx  <- seq_len(n_test) + (H_MAX - h)                 # runs[[idx]] has origin = target - h/4
  rr   <- runs[[m$key]][idx]
  org  <- vapply(rr, function(r) r$origin, 0)
  stopifnot(max(abs(org - (target_times - h / 4))) < 1e-8)
  pick <- function(f) vapply(rr, function(r) r[[f]][h], 0)
  logy_hat <- pick("mean")
  tab <- data.frame(model = m$key, horizon = h, target = dates_test, origin = q_label(org),
                    logy_hat = logy_hat, lo80 = pick("lo80"), hi80 = pick("hi80"),
                    lo95 = pick("lo95"), hi95 = pick("hi95"), stringsAsFactors = FALSE)
  if (h == 1L) {
    y_org <- vapply(rr, function(r) r$y_origin, 0)
    g_hat <- 100 * (logy_hat - y_org)                   # the bounds shift with it, exactly
    g_sd  <- 100 * m$sigma                              # recorded for the audit only
    tab$growth_hat  <- g_hat
    tab$growth_lo80 <- 100 * (tab$lo80 - y_org); tab$growth_hi80 <- 100 * (tab$hi80 - y_org)
    tab$growth_lo95 <- 100 * (tab$lo95 - y_org); tab$growth_hi95 <- 100 * (tab$hi95 - y_org)
  } else {
    g_hat <- 100 * vapply(rr, function(r) r$dy_hat[2], 0)
    stopifnot(max(abs(g_hat - 100 * (pick("mean") - vapply(rr, function(r) r$mean[1], 0)))) < 1e-10)
    g_sd  <- 100 * m$sigma * sqrt((m$psi[1] - 1)^2 + 1)
    tab$growth_hat  <- g_hat
    tab$growth_lo80 <- g_hat - Z[["80"]] * g_sd; tab$growth_hi80 <- g_hat + Z[["80"]] * g_sd
    tab$growth_lo95 <- g_hat - Z[["95"]] * g_sd; tab$growth_hi95 <- g_hat + Z[["95"]] * g_sd
  }
  attr(tab, "growth_sd") <- g_sd
  tab
}

# The benchmark on the same targets: y-hat = y_t + h delta-bar, Gaussian bounds from the
# training variance of the first difference.
bench_table <- function(h) {
  org   <- target_times - h / 4
  y_org <- vapply(org, function(tt) at_time(y_full, tt), 0)
  logy_hat <- y_org + h * drift_bar
  se_h  <- sqrt(h) * sd_dy
  tab <- data.frame(model = "rwdrift", horizon = h, target = dates_test, origin = q_label(org),
                    logy_hat = logy_hat,
                    lo80 = logy_hat - Z[["80"]] * se_h, hi80 = logy_hat + Z[["80"]] * se_h,
                    lo95 = logy_hat - Z[["95"]] * se_h, hi95 = logy_hat + Z[["95"]] * se_h,
                    stringsAsFactors = FALSE)
  g_hat <- rep(100 * drift_bar, n_test); g_sd <- 100 * sd_dy
  tab$growth_hat  <- g_hat
  tab$growth_lo80 <- g_hat - Z[["80"]] * g_sd; tab$growth_hi80 <- g_hat + Z[["80"]] * g_sd
  tab$growth_lo95 <- g_hat - Z[["95"]] * g_sd; tab$growth_hi95 <- g_hat + Z[["95"]] * g_sd
  attr(tab, "growth_sd") <- g_sd
  tab
}

# Level view, realisations, errors, inside flags: the same for every table.
finish_table <- function(tab) {
  tab$level_hat  <- exp(tab$logy_hat)
  tab$level_lo80 <- exp(tab$lo80); tab$level_hi80 <- exp(tab$hi80)
  tab$level_lo95 <- exp(tab$lo95); tab$level_hi95 <- exp(tab$hi95)
  tab$logy_test   <- logy_test
  tab$level_test  <- level_test
  tab$growth_test <- growth_test
  tab$error_logy   <- logy_test - tab$logy_hat
  tab$error_growth <- growth_test - tab$growth_hat
  tab$inside80 <- logy_test >= tab$lo80 & logy_test <= tab$hi80
  tab$inside95 <- logy_test >= tab$lo95 & logy_test <= tab$hi95
  # Hard stop 7: 20 rows, nothing missing, bounds nested, flags consistent with the bounds
  # in both views (exp is monotone, so the level view must give the same flags), inside80
  # implies inside95, and the level forecast is exp of the log forecast.
  stopifnot(nrow(tab) == n_test, !anyNA(tab), all(is.finite(as.matrix(tab[sapply(tab, is.numeric)]))),
            all(tab$lo95 <= tab$lo80), all(tab$lo80 <= tab$logy_hat), all(tab$logy_hat <= tab$hi80), all(tab$hi80 <= tab$hi95),
            identical(tab$inside80, level_test >= tab$level_lo80 & level_test <= tab$level_hi80),
            identical(tab$inside95, level_test >= tab$level_lo95 & level_test <= tab$level_hi95),
            all(!tab$inside80 | tab$inside95),
            identical(tab$level_hat, exp(tab$logy_hat)),
            all(tab$growth_lo80 <= tab$growth_hat), all(tab$growth_hat <= tab$growth_hi80),
            all(tab$growth_lo95 <= tab$growth_lo80), all(tab$growth_hi80 <= tab$growth_hi95))
  if (all(tab$horizon == 1L)) {
    # h = 1: the level forecast is the origin level grown at the growth forecast; the growth
    # error is the log error in percent.
    lev_org <- vapply(target_times - 0.25, function(tt) at_time(lev_full, tt), 0)
    stopifnot(max(abs(tab$level_hat - lev_org * exp(tab$growth_hat / 100))) / mean(level_test) < 1e-12,
              max(abs(tab$error_growth - 100 * tab$error_logy)) < 1e-10)
  }
  tab
}

tables <- list()
growth_sd <- list()
for (key in MODEL_KEYS) for (h in seq_len(H_MAX)) {
  tb <- model_table(model_info[[key]], h)
  growth_sd[[sprintf("%s_h%d", key, h)]] <- attr(tb, "growth_sd")
  tables[[sprintf("%s_h%d", key, h)]] <- finish_table(tb)
}
for (h in seq_len(H_MAX)) {
  tb <- bench_table(h)
  growth_sd[[sprintf("rwdrift_h%d", h)]] <- attr(tb, "growth_sd")
  tables[[sprintf("rwdrift_h%d", h)]] <- finish_table(tb)
}
ALL_KEYS <- c(MODEL_KEYS, "rwdrift")

# ==============================================================================
# 3. Scores
# ==============================================================================
worst_times <- seq(q_time(WORST_START), q_time(WORST_END), by = 0.25)
worst <- target_times %in% worst_times
stopifnot(sum(worst) == 4L)
score_block <- function(tab) {
  list(rmse_growth    = sqrt(mean(tab$error_growth^2)),
       mae_growth     = mean(abs(tab$error_growth)),
       rmse_level_pct = sqrt(mean((100 * (tab$level_test - tab$level_hat) / tab$level_test)^2)),
       cov80 = sum(tab$inside80), cov95 = sum(tab$inside95),
       rmse_growth_2008q3_2009q2 = sqrt(mean(tab$error_growth[worst]^2)),
       cov95_2008q3_2009q2       = sum(tab$inside95[worst]))
}
scores <- list(); score_rows <- list()
for (key in ALL_KEYS) for (h in seq_len(H_MAX)) {
  s <- score_block(tables[[sprintf("%s_h%d", key, h)]])
  scores[[key]][[sprintf("h%d", h)]] <- s
  score_rows[[length(score_rows) + 1L]] <- data.frame(
    model = key, label = if (key == "rwdrift") "random walk with drift (benchmark)" else label_of[[key]],
    horizon = h, n = n_test, as.data.frame(s), growth_sd_pct = growth_sd[[sprintf("%s_h%d", key, h)]],
    stringsAsFactors = FALSE)
  note(sprintf("score_%s_h%d", key, h),
       sprintf("rmse_growth=%.4f mae_growth=%.4f rmse_level_pct=%.4f cov80=%d/20 cov95=%d/20 worst4: rmse_growth=%.4f cov95=%d/4",
               s$rmse_growth, s$mae_growth, s$rmse_level_pct, s$cov80, s$cov95,
               s$rmse_growth_2008q3_2009q2, s$cov95_2008q3_2009q2))
}
score_table <- do.call(rbind, score_rows)
rownames(score_table) <- NULL

# ==============================================================================
# 4. Monte Carlo check of the h = 2 growth variance
# ==============================================================================
# At the origin 2006 Q4 (the first h = 1 origin), MC_DRAWS two-step paths from each fitted
# model: Delta y_{t+h} = delta + sum_k phi_k (Delta y_{t+h-k} - delta) + eps_{t+h}, eps ~
# N(0, sigma^2), from the observed differences through the origin. The variance of the
# simulated two-step growth error (realised minus the point forecast, in percent) is
# compared with 100^2 sigma^2 [(psi_1 - 1)^2 + 1]; the two-step LEVEL error variance with
# 100^2 sigma^2 (1 + psi_1^2) in the same units; and the simulated means with the point
# forecasts (within four standard errors of the simulated mean).
MC_ORIGIN <- q_time(TRAIN_END)
set.seed(SEED)
mc <- list()
for (key in MODEL_KEYS) {
  m  <- model_info[[key]]
  yv <- as.numeric(window(y_full, start = TRAIN_START, end = MC_ORIGIN)); dyv <- diff(yv)
  p  <- length(m$phi)
  r0 <- runs[[key]][[which(abs(origin_times - MC_ORIGIN) < 1e-8)]]
  eps <- matrix(rnorm(MC_DRAWS * H_MAX, mean = 0, sd = m$sigma), MC_DRAWS, H_MAX)
  hist <- matrix(rep(dyv[length(dyv) - seq_len(p) + 1L], each = MC_DRAWS), MC_DRAWS, p)   # most recent first
  d_sim <- matrix(0, MC_DRAWS, H_MAX)
  for (h in seq_len(H_MAX)) {
    d_sim[, h] <- m$delta + as.vector((hist - m$delta) %*% m$phi) + eps[, h]
    hist <- cbind(d_sim[, h], hist)[, seq_len(p), drop = FALSE]
  }
  g2_err  <- 100 * (d_sim[, 2] - r0$dy_hat[2])                     # two-step growth error, percent
  l2_err  <- 100 * (rowSums(d_sim) - sum(r0$dy_hat))               # two-step log-level error, percent
  v_form  <- (100 * m$sigma)^2 * ((m$psi[1] - 1)^2 + 1)
  v_sim   <- var(g2_err)
  vl_form <- (100 * m$sigma)^2 * (1 + m$psi[1]^2)
  vl_sim  <- var(l2_err)
  mean_dev <- abs(mean(g2_err)) / (sd(g2_err) / sqrt(MC_DRAWS))
  mc[[key]] <- list(var_formula = v_form, var_sim = v_sim, rel = v_sim / v_form - 1,
                    level_var_formula = vl_form, level_var_sim = vl_sim, mean_dev_se = mean_dev)
  note(sprintf("mc_%s", key), sprintf("origin %s draws=%d growth var formula=%.6f sim=%.6f (rel %+.4f); level var formula=%.6f sim=%.6f (rel %+.4f); mean dev=%.2f se",
                                      q_label(MC_ORIGIN), MC_DRAWS, v_form, v_sim, v_sim / v_form - 1,
                                      vl_form, vl_sim, vl_sim / vl_form - 1, mean_dev))
  # Hard stop 8: the Monte Carlo agrees with the formula within MC_TOL (both variances),
  # and the simulated mean is the point forecast.
  stopifnot(abs(v_sim / v_form - 1) < MC_TOL, abs(vl_sim / vl_form - 1) < MC_TOL, mean_dev < 4)
  # The same variance in the h = 2 table's growth bounds.
  stopifnot(abs(growth_sd[[sprintf("%s_h2", key)]]^2 - v_form) < 1e-10)
}

# ==============================================================================
# 5. Assemble and write
# ==============================================================================
tail_times <- seq(q_time(TAIL_START), q_time(TRAIN_END), by = 0.25)
stopifnot(length(tail_times) == n_quarters(TAIL_START, TRAIN_END))
logy_tail   <- vapply(tail_times, function(tt) at_time(y_full, tt), 0)
level_tail  <- vapply(tail_times, function(tt) at_time(lev_full, tt), 0)
growth_tail <- 100 * (logy_tail - vapply(tail_times - 0.25, function(tt) at_time(y_full, tt), 0))

horizon_block <- function(tab) list(
  logy_hat = tab$logy_hat, lo80 = tab$lo80, hi80 = tab$hi80, lo95 = tab$lo95, hi95 = tab$hi95,
  level_hat = tab$level_hat, level_lo80 = tab$level_lo80, level_hi80 = tab$level_hi80,
  level_lo95 = tab$level_lo95, level_hi95 = tab$level_hi95,
  growth_hat = tab$growth_hat, growth_lo80 = tab$growth_lo80, growth_hi80 = tab$growth_hi80,
  growth_lo95 = tab$growth_lo95, growth_hi95 = tab$growth_hi95,
  error_logy = tab$error_logy, error_growth = tab$error_growth,
  inside80 = tab$inside80, inside95 = tab$inside95)
model_block <- function(key) {
  if (key == "rwdrift") {
    head <- list(label = "random walk with drift (benchmark)",
                 coef = list(drift = drift_bar), se = list(drift = sd_dy / sqrt(T_dy)),
                 sigma_pct = 100 * sd_dy, psi1 = 1)
  } else {
    m <- model_info[[key]]; f <- fit_train[[key]]
    head <- list(label = m$label, coef = as.list(f$coef), se = as.list(m$se),
                 sigma_pct = 100 * m$sigma, psi1 = m$psi[1])
  }
  c(head, list(h1 = horizon_block(tables[[sprintf("%s_h1", key)]]),
               h2 = horizon_block(tables[[sprintf("%s_h2", key)]]),
               scores = scores[[key]]))
}

payload <- list(
  series = list(label = "real GDP per capita", log_label = "log real GDP per capita",
                level_units = "chained (2017) dollars per person", growth_units = "percent per quarter",
                train = train_lab, test = test_lab, vintage = VINTAGE,
                drift_train_pct = 100 * drift_bar, sd_dgrowth_train_pct = 100 * sd_dy),
  criteria = c("AIC", "AICc", "BIC", "HQIC"),
  winner = EXPECTED_WINNER,
  dates_train_tail = q_label(tail_times), level_train_tail = level_tail,
  logy_train_tail = logy_tail, growth_train_tail = growth_tail,
  dates_test = dates_test, level_test = level_test, logy_test = logy_test, growth_test = growth_test,
  models = setNames(lapply(ALL_KEYS, model_block), ALL_KEYS),
  checks = list(coef_match_max_abs = coef_match_max_abs,
                mc_h2_growth_var_formula = mc$arima210d$var_formula,
                mc_h2_growth_var_sim = mc$arima210d$var_sim))

# Hard stop 9: the contract's array lengths.
for (key in ALL_KEYS) for (h in c("h1", "h2")) {
  stopifnot(all(lengths(payload$models[[key]][[h]]) == n_test))
}
stopifnot(length(payload$dates_test) == n_test, length(payload$dates_train_tail) == length(tail_times))

write_json(payload, "gdp_test.json", digits = I(JSON_SIG_DIGITS), auto_unbox = TRUE,
           null = "null", na = "null", pretty = TRUE)
write.csv(score_table, "gdp_test_scores.csv", row.names = FALSE)
long <- function(h) {
  out <- do.call(rbind, lapply(ALL_KEYS, function(key) tables[[sprintf("%s_h%d", key, h)]]))
  rownames(out) <- NULL
  out
}
write.csv(long(1L), "gdp_test_h1.csv", row.names = FALSE)
write.csv(long(2L), "gdp_test_h2.csv", row.names = FALSE)

# Re-read the JSON: every array has 20 entries, no nulls, the winners are the contract's.
chk <- fromJSON("gdp_test.json", simplifyVector = TRUE)
stopifnot(identical(names(chk$models), ALL_KEYS),
          all(vapply(ALL_KEYS, function(k) all(lengths(chk$models[[k]]$h1) == n_test) && all(lengths(chk$models[[k]]$h2) == n_test), TRUE)),
          !grepl("null", readChar("gdp_test.json", file.info("gdp_test.json")$size, useBytes = TRUE), fixed = TRUE),
          identical(unlist(chk$winner), unlist(EXPECTED_WINNER)))

writeLines(character(0), sentinel)
note("outputs", "gdp_test.json, gdp_test_scores.csv, gdp_test_h1.csv, gdp_test_h2.csv; sentinel .gdp_test_ready")

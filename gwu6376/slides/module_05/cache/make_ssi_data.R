# make_ssi_data.R -- data exporter for the Module 5 SSI widget (makeSSI)
# ===========================================================================
# Builds slides/module_05/cache/ssi_unratensa.json: a replay payload for the
# stochastic-spectral-imputation widget on UNRATENSA, 1960-01 .. 2019-12.
#
# PORT of D:/Documents/research/seasonality/bls_presentation/R/make_w4_data.R
# (the instructor's research deck exporter, w4_spec.md s2-s3 as amended
# 2026-08-14). Ratified for Module 5 by overview/decisions_log.md Entry 13,
# decisions 47 and 55, and planning/module_05_deck_brief.md s3.2.
#
# Run from anywhere (paths are resolved from this file's location):
#     & 'C:\Program Files\R\R-4.3.2\bin\Rscript.exe' slides/module_05/cache/make_ssi_data.R
#
# Input : data/UNRATENSA.csv  (observation_date, UNRATENSA)  -- not seasonally
#           adjusted civilian unemployment rate, percent, cached FRED pull
#         data/UNRATE.csv     (observation_date, UNRATE)     -- the published
#           seasonally adjusted series, the overlay the widget draws at the end
# Output: slides/module_05/cache/ssi_unratensa.json
#           byte-deterministic: no timestamps, every stochastic draw carries an
#           explicit seed, "mean" variants draw nothing. Rerunning reproduces
#           the file exactly (verified by hashing two runs; see bench/ssi_bench.md).
#
# WHAT CHANGED IN THE PORT (relative to make_w4_data.R):
#   * Input series: UNRATENSA (a rate in percent), window 1960-01..2019-12 --
#     the module's pre-COVID window, matching UNRATE since Module 2. The
#     research deck used full-history BLS payrolls (1939-2025) and CPI apparel.
#   * Transform: LEVELS, not logs (TRANSFORM = "none"). The course models the
#     unemployment rate in levels with a first difference (Module 4's ARMA(1,2)
#     on diff(UNRATE); Module 5 path 1 dummies on diff(UNRATENSA)), so the
#     whitener's d = 1 differences the rate, not its log. The exporter keeps a
#     "log" switch for reference; the schema declares the map in meta.transform
#     and the arrays are named x_nsa / dx_nsa (were log_nsa / dlog_nsa).
#   * No package-default "band" comparison variant. The research talk shipped
#     one as an honest exhibit of its experimental specification stage; the
#     course widget keeps only the classic-SSI variant grid. (Its post-test on
#     UNRATENSA is recorded in meta.package_default_path for the record.)
#   * level_x13 renamed level_sa: the overlay is the PUBLISHED seasonally
#     adjusted series (UNRATE), which is BLS X-13 output but a concatenation of
#     annual vintages, not one run.
#   * Benchmarking kept (spec s1 principle 5): yearly SUMS forced to the NSA
#     yearly sums, which for a rate means the ANNUAL MEAN unemployment rate is
#     invariant to adjustment. Published UNRATE already satisfies this to
#     within ~0.01-0.05 pp (checked in the probe), so it is the natural
#     constraint here too.
#   * Everything else -- classic SSI path, the variant grid, the windowed
#     per-ordinate coefficient contract, the stopifnot validations, the JSON
#     schema -- is the research exporter's, unchanged. Schema version bumped to
#     3 to record the renames above.
#
# WHY CLASSIC SSI (target_set = "bins", phase_rule = "zero"), not defaults:
#   seas_test() on UNRATENSA detects seasonality (statistic ~122, p below
#   machine precision) but specifies it as a BAND, exactly as it did payrolls.
#   The package-default band branch divides by the estimated gain, imputes
#   nothing (draw$method = "none", seeds inert), and its post-test still
#   rejects (p ~ 3e-10 on this series). Classic SSI resets every seasonal-bin
#   ordinate to a drawn donor level -- stochastic, per-ordinate, and it passes
#   its own post-test (p ~ 0.88 at the bench's seed 6376; 0.87-0.90 across
#   seeds 1-9). "bins" REQUIRES phase_rule = "zero" (no gain, no phase on
#   that path).
#
# freqseas INTERNALS used (beyond the exported seas_test/seas_ssi/seas_adjust/
# benchmark_totals API), all read-only, all present in the installed package:
#   * freqseas:::fs_donor_pool  -- donor pools + thresholds per quantile
#   * freqseas:::fs_surgery     -- single-ordinate surgeries for the exact
#                                  per-ordinate delta validation
#   * freqseas:::fs_recolor     -- the package's own AR-recursion + de-
#                                  differencing inversion
#   * freqseas:::omega_seasonal -- the seasonal harmonic frequencies
#
# PER-ORDINATE MECHANISM AND THE EXACT-RECURSION CONTRACT ("coeffs_recursion"):
#   The classic surgery replaces target ordinate j (+ its conjugate mirror)
#   in the DFT E of the whitened residuals: disjoint supports across targets,
#   so Delta_E = sum_j Delta_E_j EXACTLY. The package's recoloring
#   (freqseas:::fs_recolor, read from the installed source) is
#     ystar[t] = estar_full[t - p] + sum_k ar[k] * ystar[t - k],  t > p,
#   with ystar[1..p] anchored to the original differenced series and
#   estar_full = c(e_head, estar); then diffinv from x[1]. Everything is
#   linear with fixed anchors, so the per-ordinate delta on the differenced
#   scale, delta_j(t) = dx*_t - dx_t, obeys the SAME recursion driven by the
#   single-ordinate sinusoid and started from zero:
#     u_j(t)     = Re[ c_j * exp(i * omega_j * (t - t0)) ]  for t >= t0, else 0
#     delta_j(t) = u_j(t) + sum_k ar[k] * delta_j(t - k)     (delta_j = 0, t < t0)
#   where t0 = n_trim + d + p is the first adjustable dx index and
#     c_j = 2 * Delta_E_j / n_e        (Nyquist: Re(Delta_E_j) / n_e, real).
#   This is EXACT (floating point only), transient included -- unlike the
#   research exporter's "coeffs_windowed" contract, which divided c_j by the
#   whitener polynomial A(omega_j) and tolerated the AR transient (< 5e-3 on
#   payrolls' log scale). On UNRATENSA in percentage points that transient is
#   ~5e-2, far outside the tolerance, so the port ships the recursion instead:
#   JS runs the p-term recursion per ordinate (O(T), deterministic arithmetic,
#   the same sanctioned category as the benchmarking mirror) and still snaps
#   the finished state to final_dx_check. Validated below: per-ordinate
#   recursion vs the package's own fs_surgery + fs_recolor < 1e-10, every
#   animation-order prefix < 1e-10, every variant's final < 1e-10.
# ===========================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(freqseas)
})

t_start <- Sys.time()

# ---------------------------------------------------------------------------
# 0. Paths (resolved from this script's location), window, transform
# ---------------------------------------------------------------------------
script_path <- {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f) == 1L && nzchar(f)) normalizePath(f, winslash = "/") else
    normalizePath(file.path(getwd(), "make_ssi_data.R"), winslash = "/", mustWork = FALSE)
}
cache_dir <- dirname(script_path)
repo_root <- normalizePath(file.path(cache_dir, "..", "..", ".."), winslash = "/")
nsa_csv   <- file.path(repo_root, "data", "UNRATENSA.csv")
sa_csv    <- file.path(repo_root, "data", "UNRATE.csv")
out_json  <- file.path(cache_dir, "ssi_unratensa.json")
for (f in c(nsa_csv, sa_csv)) if (!file.exists(f)) stop("Input not found: ", f)

WIN_START <- as.Date("1960-01-01")
WIN_END   <- as.Date("2019-12-01")
TRANSFORM <- "none"          # "none" = levels (course convention); "log" = research deck
SEED_DEFAULT <- 6376L        # the draw slide 31 plays first; matches the verification
                             # bench's classic-SSI call (bench/bench.R item 5 iv-b,
                             # seas_adjust(..., seed = 6376)) so deck and notes quote
                             # one post-test number

read_fred <- function(path, id) {
  d <- read.csv(path, stringsAsFactors = FALSE)
  stopifnot(identical(names(d), c("observation_date", id)))
  data.frame(date  = as.Date(d$observation_date),
             value = suppressWarnings(as.numeric(d[[id]])))
}
n_all <- read_fred(nsa_csv, "UNRATENSA")
s_all <- read_fred(sa_csv,  "UNRATE")
keep  <- function(d) d[d$date >= WIN_START & d$date <= WIN_END, ]
n_win <- keep(n_all); s_win <- keep(s_all)
stopifnot(identical(n_win$date, s_win$date))     # aligned month grids

date <- n_win$date
nsa  <- n_win$value                  # NSA -- the series we test/adjust
sa   <- s_win$value                  # published SA series (the overlay)
stopifnot(!anyNA(nsa), !anyNA(sa), !anyNA(date),
          length(nsa) == length(sa), length(nsa) == length(date),
          !anyDuplicated(date), all(diff(date) > 0),
          all(diff(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m"))) == 1L),
          all(nsa > 0))
message(sprintf("UNRATENSA %s .. %s: %d obs, range %.1f .. %.1f percent",
                format(date[1L], "%Y-%m"), format(date[length(date)], "%Y-%m"),
                length(nsa), min(nsa), max(nsa)))

to_level   <- function(v) if (TRANSFORM == "log") exp(v) else v
from_level <- function(v) if (TRANSFORM == "log") log(v) else v

x_num  <- from_level(nsa)            # what the package ingests
x      <- ts(x_num, frequency = 12)
dx     <- diff(x_num)                # first difference (Stage 0 chooses d = 1)
n_obs  <- length(nsa)
n_dx   <- length(dx)

# Benchmark geometry: benchmark_totals() windows are POSITIONAL (12-obs
# blocks from index 1); they equal calendar years only because the series
# starts in January and ends in December with no partial year. Assert that.
stopifnot(n_obs %% 12L == 0L,
          format(date[1L], "%m") == "01",
          format(date[n_obs], "%m") == "12")
n_years       <- n_obs %/% 12L
year_sums_nsa <- colSums(matrix(nsa, nrow = 12L))

# ---------------------------------------------------------------------------
# 1. Detection/specification stage, run ONCE and reused by every variant
# ---------------------------------------------------------------------------
tst <- seas_test(x)
wh  <- tst$whitener

stopifnot(isTRUE(tst$decision))       # seasonal, or the widget is pointless
stopifnot(wh$d == 1L)                 # the dx framing below requires d = 1
n_e    <- wh$n_e
grid   <- tst$partition$grid
n_spec <- grid$n_spec
t0     <- wh$n_trim + wh$d + wh$p     # first ADJUSTABLE index of dx (1-based)
stopifnot(t0 == wh$p + wh$n_trim + 1L)  # equivalent forms under d = 1
message(sprintf("Stage 0: d=%d, AR p=%d (phi: %s), n_e=%d, n_trim=%d, t0=%d",
                wh$d, wh$p, paste(round(wh$ar, 4), collapse = ", "),
                n_e, wh$n_trim, t0))
message(sprintf("Detected: statistic %.3f, p = %.3g, M = %d (%s), spec %s (shoulder_p=%.3g); running CLASSIC surgery",
                tst$evt$statistic, tst$evt$p, tst$M, tst$M_selection$source,
                tst$spec$label, tst$spec$shoulder_p))

# Raw positive-side periodogram of the whitened residuals: the domain donor
# levels and pgram_after live in. (The test uses the standardized copy, which
# for j >= 1 is this divided by sd(e - mean(e))^2 -- a constant log-offset.)
pgram_pos_full <- tst$pgram$pgram_raw[grid$pos_idx]     # length n_spec (incl. Nyquist)
Jmax           <- (n_e - 1L) %/% 2L                     # donor machinery excludes Nyquist
pgram_pos_gain <- tst$pgram$pgram_raw[grid$pos_idx[seq_len(Jmax)]]
J0_gain        <- tst$partition$J0[tst$partition$J0 <= Jmax]

# ---------------------------------------------------------------------------
# 2. Targets in ANIMATION ORDER: harmonic-by-harmonic from pi/6, center-out
# ---------------------------------------------------------------------------
jg_t   <- tst$partition$J1                 # 1-based grid index (omega = 2*pi*j/n_e)
tpos   <- grid$pos_idx[jg_t]               # full-DFT positions (jg + 1)
n_tg   <- length(jg_t)
omega_t <- grid$omega_pos[jg_t]
message(sprintf("Classic targets: %d seasonal-bin ordinates", n_tg))

omega_h <- freqseas:::omega_seasonal(tst$P, tst$N, exclude_nyquist = FALSE)
breaks  <- tst$partition$breaks
bin_of  <- function(w) cut(w, breaks = breaks, right = TRUE,
                           include.lowest = FALSE, labels = FALSE)
bin_t <- bin_of(omega_t)
bin_h <- bin_of(omega_h)
stopifnot(!anyNA(bin_t), !anyNA(bin_h), !anyDuplicated(bin_h),
          all(bin_t %in% bin_h))           # each seasonal bin holds exactly 1 harmonic
hidx  <- match(bin_t, bin_h)               # harmonic index (1..6) per target
anim  <- order(hidx, abs(omega_t - omega_h[hidx]), jg_t)   # animation permutation

pi_label <- function(w) {                  # "\u03c0" = unicode pi
  r <- w / pi
  for (q in 1:24) {
    num <- r * q
    if (abs(num - round(num)) < 1e-9) {
      num <- round(num)
      if (q == 1L)   return(if (num == 1L) "\u03c0" else paste0(num, "\u03c0"))
      if (num == 1L) return(paste0("\u03c0/", q))
      return(paste0(num, "\u03c0/", q))
    }
  }
  sprintf("%.3f\u03c0", r)
}
lab_h <- vapply(omega_h, pi_label, character(1))

targets_df <- data.frame(                  # shared, animation order
  j              = jg_t[anim],             # grid index: omega = 2*pi*j/n_e
  omega          = omega_t[anim],
  harmonic       = hidx[anim],             # 1..6 (pi/6 .. pi)
  harmonic_label = lab_h[hidx[anim]],
  stringsAsFactors = FALSE
)

# Per-harmonic excess from the specification stage (informational; the deck's
# "reading the periodogram" beat can quote it).
harm_tab <- as.data.frame(tst$spec$harmonic_table)
harmonics_df <- data.frame(harmonic = seq_along(omega_h), label = lab_h,
                           omega = omega_h,
                           excess = harm_tab$excess[match(round(omega_h, 8), round(harm_tab$omega, 8))],
                           elevated = harm_tab$elevated[match(round(omega_h, 8), round(harm_tab$omega, 8))],
                           n_targets = as.integer(table(factor(hidx, levels = seq_along(omega_h)))),
                           stringsAsFactors = FALSE)

# ---------------------------------------------------------------------------
# 3. Donor pools + thresholds per quantile level (shared block)
# ---------------------------------------------------------------------------
q_default <- eval(formals(freqseas:::seas_adjust.default)$donor_quantile)  # observed, not assumed
stopifnot(identical(q_default, 0.9))
q_other   <- c(0.7, 0.8, 0.95, 1.0)   # spread bracketing the default; 1.0 is the
                                      # untruncated-pool boundary case
q_all     <- sort(unique(c(q_default, q_other)))

donor_by_q <- lapply(q_all, function(q) {
  pool <- freqseas:::fs_donor_pool(pgram_pos_gain, J0_gain, donor_quantile = q)
  thr  <- stats::quantile(pgram_pos_gain[J0_gain], probs = q, names = FALSE)
  stopifnot(identical(pool, J0_gain[pgram_pos_gain[J0_gain] <= thr]))
  list(quantile = q, threshold = thr, pool_mean = mean(pgram_pos_gain[pool]),
       n_pool = length(pool), pool = pool)   # pool: grid indices (same coords as j)
})
names(donor_by_q) <- as.character(q_all)

# ---------------------------------------------------------------------------
# 4. Helpers: analytic windowed coefficients, evt re-test, reconstruction
# ---------------------------------------------------------------------------
E       <- tst$E                            # raw DFT of aligned whitened residuals
nyq_pos <- n_e %/% 2L + 1L                  # full-DFT Nyquist position (n_e even)
is_nyq  <- (n_e %% 2L == 0L) & (tpos == nyq_pos)
ar_coef <- as.numeric(wh$ar)                # whitener AR coefficients (length p)

# Whitened-domain coefficient c_j per target (tpos order), from a variant's
# aggregated imputed levels: Estar_j = donor magnitude sqrt(level * n_e) at the
# RETAINED phase (fs_surgery's classic rule); Nyquist forced exactly real.
coef_from_levels <- function(lvl) {
  ph <- Arg(E[tpos]); ph[!is.finite(ph)] <- 0
  Estar <- complex(modulus = sqrt(lvl * n_e), argument = ph)
  Estar[is_nyq] <- complex(real = Re(Estar[is_nyq]), imaginary = 0)
  pg_after <- Mod(Estar)^2 / n_e
  stopifnot(max(abs(pg_after - lvl) / lvl) < 1e-9)   # pgram_after == level, by construction
  ce <- 2 * (Estar - E[tpos]) / n_e
  ce[is_nyq] <- complex(real = (Re(Estar[is_nyq]) - Re(E[tpos[is_nyq]])) / n_e,
                        imaginary = 0)
  ce
}

# The exact recursion, in R (mirrors what JS does per ordinate). Linear, so a
# SUM of coefficients can be pushed through one recursion.
tt_win <- seq.int(t0, n_dx) - t0
Emat   <- exp(1i * outer(tt_win, omega_t))            # (n_dx - t0 + 1) x n_tg
recolor_delta <- function(u_win) {                    # u over t = t0..n_dx
  d_win <- if (length(ar_coef)) as.numeric(stats::filter(u_win, ar_coef, method = "recursive")) else u_win
  c(numeric(t0 - 1L), d_win)
}
delta_from_coeffs <- function(cvec) recolor_delta(as.vector(Re(Emat %*% cvec)))
recon_from_coeffs <- function(cvec) dx + delta_from_coeffs(cvec)

# Re-run seas_test on a series in the PACKAGE's input scale, replicating
# seas_ssi's internal post-test call exactly (verified against the installed
# source: same N/P/M/alpha/forced d/ar_max/whitening geometry).
post_test_num <- function(z) {
  seas_test(z, frequency = tst$N, P = tst$P, M = tst$M, alpha = tst$alpha,
            d = if (isTRUE(wh$d == 1L)) "first" else "none",
            ar_max = tst$ar_max,
            whiten_exclusion = if (is.null(wh$exclusion)) "guard" else wh$exclusion,
            whiten_guard     = if (is.null(wh$guard)) 3L else wh$guard)
}
post_test <- function(adj) post_test_num(as.numeric(adj$adjusted))

# Yearly-total benchmarking of one variant's final adjusted series. Levels are
# rebuilt from final_dx EXACTLY as JS does (cumulative sum from the anchor,
# then the inverse transform), constrained by the package operator, and
# double-validated: (i) benchmarked yearly sums reproduce the NSA yearly sums;
# (ii) an R-side mirror of the documented JS pro-rata rule reproduces the
# export bit-for-bit.
bench_block <- function(final_dx) {
  lvl <- to_level(cumsum(c(x_num[1L], final_dx)))       # adjusted levels [n_obs]
  bm  <- benchmark_totals(lvl, nsa, frequency = 12L)    # pro-rata per year
  bat <- attr(bm, "benchmark")
  stopifnot(bat$n_tail_unadjusted == 0L,
            length(bat$scale_factors) == n_years)
  bm  <- as.numeric(bm)
  ys  <- colSums(matrix(bm, nrow = 12L))
  stopifnot(max(abs(ys - year_sums_nsa) / year_sums_nsa) < 1e-9)
  sf     <- year_sums_nsa / colSums(matrix(lvl, nrow = 12L))
  mirror <- lvl * rep(sf, each = 12L)                   # the JS rule, in R
  stopifnot(identical(mirror, bm))
  post <- post_test_num(from_level(bm))
  list(level = bm,
       evt   = list(statistic = post$evt$statistic, p = post$evt$p))
}

# ---------------------------------------------------------------------------
# 5. Variant grid (classic path). One full package run per variant.
# ---------------------------------------------------------------------------
# Bootstrap draws at the default quantile: the default seed FIRST (the widget
# cycles Reseed through the payload order, so draw 1 of 10 is the bench's
# seed), then seeds 1..9.
vspec <- rbind(
  data.frame(quantile = q_default, method = "bootstrap",   seed = c(SEED_DEFAULT, 1:9)),
  data.frame(quantile = q_default, method = "exponential", seed = 1:3),
  data.frame(quantile = q_default, method = "mean",        seed = NA_integer_),
  do.call(rbind, lapply(q_other, function(q) rbind(
    data.frame(quantile = q, method = "bootstrap", seed = 1:3),
    data.frame(quantile = q, method = "mean",      seed = NA_integer_)
  )))
)
vspec$is_default <- vspec$quantile == q_default & vspec$method == "bootstrap" &
                    !is.na(vspec$seed) & vspec$seed == SEED_DEFAULT
stopifnot(sum(vspec$is_default) == 1L)

run_variant <- function(q, method, seed) {
  adj <- seas_ssi(tst, phase_rule = "zero", donor_quantile = q,
                  impute_method = method, target_set = "bins",
                  seed = if (is.na(seed)) NULL else as.integer(seed))
  stopifnot(identical(adj$spec, "classic"),
            identical(adj$draw$method, method),
            identical(adj$draw$targets, tpos))
  cvec  <- coef_from_levels(adj$draw$level)
  fin   <- diff(as.numeric(adj$adjusted))
  post  <- post_test(adj)
  stopifnot(identical(post$evt$p, adj$post_evt))   # my re-test == the package's own
  dev_f <- max(abs(recon_from_coeffs(cvec) - fin)) # recursion recon vs package output
  bch   <- bench_block(fin)                        # yearly-total benchmarking
  donor_j <- NULL
  if (method == "bootstrap") {                     # audit trail: which donor flashed
    pool <- donor_by_q[[as.character(q)]]$pool
    idx  <- adj$draw$donor_idx
    stopifnot(is.matrix(idx), nrow(idx) == 1L, max(idx) <= length(pool))
    donor_j <- pool[idx[1L, ]]
  }
  list(adj = adj, cvec = cvec, final_dx = fin, donor_j = donor_j,
       evt_after = list(statistic = post$evt$statistic, p = post$evt$p),
       coef_final_dev = dev_f,
       final_level_bench = bch$level, evt_after_bench = bch$evt)
}

message("Running ", nrow(vspec), " classic variants...")
runs <- vector("list", nrow(vspec))
for (i in seq_len(nrow(vspec))) {
  runs[[i]] <- run_variant(vspec$quantile[i], vspec$method[i], vspec$seed[i])
  message(sprintf("  [%2d/%d] q=%.2f %-11s seed=%-2s evt_after p=%.3g bench p=%.3g coef_dev=%.2e",
                  i, nrow(vspec), vspec$quantile[i], vspec$method[i],
                  ifelse(is.na(vspec$seed[i]), "-", vspec$seed[i]),
                  runs[[i]]$evt_after$p, runs[[i]]$evt_after_bench$p,
                  runs[[i]]$coef_final_dev))
}

# ---------------------------------------------------------------------------
# 6. Default-variant deep validation (mandatory stopifnot self-checks)
# ---------------------------------------------------------------------------
i_def   <- which(vspec$is_default)
def     <- runs[[i_def]]
adj_def <- def$adj

# (a) EXACT per-ordinate deltas through the package's own surgery + recolor.
message(sprintf("Default-variant validation: %d single-ordinate surgeries...", n_tg))
delta_exact <- matrix(0, n_dx, n_tg)
for (i in seq_len(n_tg)) {
  sb <- freqseas:::fs_surgery(E, Ghat_full = NULL, theta_full = NULL,
                              spec = "classic", sets = list(K = tpos[i]),
                              donor_level = adj_def$draw$level[i], n = n_e)
  rec <- freqseas:::fs_recolor(sb$estar, wh, x_num)
  delta_exact[, i] <- diff(rec) - dx
}

# (b) ADDITIVITY: sum of per-ordinate deltas == full adjustment, < 1e-8.
full_delta <- def$final_dx - dx
dev_add    <- max(abs(rowSums(delta_exact) - full_delta))
stopifnot(dev_add < 1e-8)

# (c) Head window: nothing before t0 ever moves (exactly).
dev_head <- max(abs(delta_exact[seq_len(t0 - 1L), , drop = FALSE]))
stopifnot(dev_head < 1e-12)

# (d) EXACT-RECURSION contract: the per-ordinate recursion (what JS runs)
#     reproduces the package's own single-ordinate surgery + recolor, and so
#     does every animation-order PARTIAL state. Both < 1e-10 or the build stops.
recur_ord  <- vapply(seq_len(n_tg), function(i)
  delta_from_coeffs(replace(complex(real = numeric(n_tg)), i, def$cvec[i])),
  numeric(n_dx))                                       # n_dx x n_tg
dev_ord    <- max(abs(delta_exact - recur_ord))        # single-ordinate exactness
run_dev    <- numeric(n_dx)
dev_prefix <- 0
for (k in seq_len(n_tg)) {
  i <- anim[k]
  run_dev    <- run_dev + (delta_exact[, i] - recur_ord[, i])
  dev_prefix <- max(dev_prefix, max(abs(run_dev)))
}
contract <- "coeffs_recursion"
message(sprintf("additivity=%.2e  head=%.2e  ordinate-exactness=%.2e  prefix-dev=%.2e -> contract %s",
                dev_add, dev_head, dev_ord, dev_prefix, contract))
stopifnot(dev_ord < 1e-10, dev_prefix < 1e-10)

# (e) FINAL reconstruction from coefficients is exact for every variant.
stopifnot(max(vapply(runs, function(r) r$coef_final_dev, 0)) < 1e-10)

# (f) Default variant reproduces the equivalent direct one-call adjustment
#     bit-for-bit at the same seed (mandatory).
adj_direct <- seas_adjust(x, phase_rule = "zero", target_set = "bins", seed = SEED_DEFAULT)
stopifnot(identical(as.numeric(adj_direct$adjusted), as.numeric(adj_def$adjusted)),
          identical(adj_direct$draw$level, adj_def$draw$level))

# (g) Head window in LEVEL terms: the first t0 level entries never change.
lvl_def <- to_level(cumsum(c(x_num[1L], def$final_dx)))
stopifnot(max(abs(lvl_def[seq_len(t0)] - nsa[seq_len(t0)])) < 1e-12)

# ---------------------------------------------------------------------------
# 7. For the record: the package-default path and the published series
# ---------------------------------------------------------------------------
adj_pkg  <- seas_adjust(x)          # target_set = "auto" -> detected band branch
post_pkg <- post_test(adj_pkg)
stopifnot(identical(post_pkg$evt$p, adj_pkg$post_evt))
tst_sa   <- seas_test(ts(from_level(sa), frequency = 12))   # published UNRATE, same defaults

# ---------------------------------------------------------------------------
# 8. Assemble + write JSON
# ---------------------------------------------------------------------------
fml <- formals(freqseas:::seas_adjust.default)   # observed defaults, not memory
defaults_observed <- list(
  donor_quantile        = eval(fml$donor_quantile),
  impute_method_options = eval(fml$impute_method),
  impute_method_default = eval(fml$impute_method)[1L],
  B                     = eval(fml$B),
  aggregate_options     = eval(fml$aggregate),
  aggregate_default     = eval(fml$aggregate)[1L],
  target_set_options    = eval(fml$target_set),
  target_set_default    = eval(fml$target_set)[1L],
  phase_rule_wrapper_default = eval(fml$phase_rule),
  conf_level            = eval(fml$conf_level),
  return_draws          = eval(fml$return_draws),
  donor_level_correct   = eval(fml$donor_level_correct),
  seed                  = NULL
)

variant_json <- function(i) {
  r <- runs[[i]]; v <- vspec[i, ]
  out <- list(
    id = sprintf("q%s_%s%s", format(v$quantile), v$method,
                 if (is.na(v$seed)) "" else paste0("_s", v$seed)),
    quantile = v$quantile, method = v$method,
    seed = if (is.na(v$seed)) NULL else as.integer(v$seed),
    is_default = v$is_default,
    # Parallel arrays in ANIMATION ORDER (aligned with shared.targets):
    c_re        = Re(r$cvec)[anim],
    c_im        = Im(r$cvec)[anim],
    pgram_after = r$adj$draw$level[anim],
    donor_j     = if (is.null(r$donor_j)) NULL else r$donor_j[anim],
    evt_after   = r$evt_after,
    coef_final_dev   = r$coef_final_dev,
    final_dx_check   = r$final_dx,
    final_level_bench = r$final_level_bench,
    evt_after_bench   = r$evt_after_bench
  )
  out
}

payload <- list(
  meta = list(
    title    = "Module 5 SSI widget data (classic SSI on UNRATENSA, 1960-2019)",
    source   = paste("FRED UNRATENSA (civilian unemployment rate, percent, not seasonally",
                     "adjusted) and UNRATE (published seasonally adjusted series), monthly,",
                     "cached in data/; window 1960-01 .. 2019-12"),
    series   = "UNRATENSA",
    sa_series = "UNRATE",
    window   = list(start = format(date[1L], "%Y-%m"), end = format(date[n_obs], "%Y-%m")),
    transform = TRANSFORM,
    transform_note = paste(
      "transform 'none': the package ingests the rate in LEVELS (percent);",
      "x_nsa = level_nsa, dx_nsa = diff(level_nsa); level = x_nsa[1] + cumsum(dx).",
      "transform 'log' (the research deck's choice for payrolls/apparel) would",
      "make x_nsa = log(level) and level = exp(x)."),
    units    = list(scale = 1, suffix = "%", digits = 1,
                    level_label = "reconstructed unemployment rate, percent"),
    spec     = "port of w4_spec.md s2-s3 (amended 2026-08-14) to Module 5; deck brief s3.2",
    contract = contract,
    n_obs = n_obs, n_dx = n_dx, n_e = n_e, n_spec = n_spec, t0 = t0,
    head_unadjusted = list(
      n_level = t0,                       # first t0 level entries never change
      first = format(date[1L], "%Y-%m"), last = format(date[t0], "%Y-%m"),
      why = paste("n_trim + d + p trimmed/anchor observations the whitener never",
                  "surgers (fs_recolor anchors); flagged 'unadjusted by construction'")),
    index_convention = paste(
      "j is the 1-based Fourier grid index of the length-n_e whitened aligned",
      "grid; omega_j = 2*pi*j/n_e (compute from j and n_e in JS for exact",
      "phases). shared.omega/pgram_before are indexed by j (array position j).",
      "t is the 1-based index into dx_nsa/final_dx_check (dx_nsa[t] =",
      "x_nsa[t+1] - x_nsa[t])."),
    coef_convention = paste(
      "Whitened-domain sinusoid u_j(t) = Re( (c_re + i*c_im) * exp(i * omega_j",
      "* (t - t0)) ) for t >= t0, and 0 for t < t0. Recolor by the whitener's",
      "AR recursion started from zero: delta_j(t) = u_j(t) + sum_k ar[k] *",
      "delta_j(t - k), with ar = meta.stage0.ar (length p). partial_dx(t, k) =",
      "dx_nsa(t) + sum_{j <= k} delta_j(t) over the first k targets in",
      "animation order. EXACT (floating point only); the finished state is",
      "still snapped to final_dx_check. Levels: x[1] = x_nsa[1]; x[t+1] = x[t]",
      "+ partial_dx(t); level = inverse transform of x. The first t0 level",
      "entries never change."),
    validation = list(
      additivity_dev   = dev_add,
      head_dev         = dev_head,
      ordinate_exact_dev = dev_ord,
      prefix_recon_dev = dev_prefix,
      final_recon_dev_max = max(vapply(runs, function(r) r$coef_final_dev, 0)),
      js_snap_tolerance   = 1e-6,
      bench_yearsum_rel_tolerance = 1e-6
    ),
    benchmark = list(
      method   = "pro_rata_yearly",
      operator = "freqseas::benchmark_totals(period = 'year')",
      rule = paste(
        "Proportional (multiplicative) per-year matching on positional",
        "12-observation blocks from index 1 (== calendar years here):",
        "factor_y = year_sums_nsa[y] / sum(level[(y-1)*12+1 .. y*12]);",
        "benchmarked[t] = level[t] * factor_y within year y's block. For a",
        "rate this pins each year's MEAN unemployment rate to the NSA mean.",
        "JS mirrors this at every animation frame on the CURRENT",
        "reconstruction (deterministic accounting arithmetic); the finished",
        "state must reproduce final_level_bench within 1e-6 relative."),
      n_years = n_years,
      n_tail_unadjusted = 0L
    ),
    schema_version = 3L,
    schema_note = paste(
      "v3 (2026-09-17, Module 5 port): meta.transform declares the input map;",
      "log_nsa/dlog_nsa renamed x_nsa/dx_nsa and final_dlog_check renamed",
      "final_dx_check; level_x13 renamed level_sa; the package-default band",
      "comparison variant and the is_band_default flag are dropped; the",
      "coefficient contract is 'coeffs_recursion' (whitened-domain c_j plus the",
      "AR recursion, exact) instead of 'coeffs_windowed' (c_j / A(omega), the",
      "AR transient tolerated);",
      "shared.harmonics, meta.head_unadjusted, meta.package_default_path and",
      "meta.published_sa_test added. v2 (2026-08-14) added yearly-total",
      "benchmarking; v1 fields otherwise unchanged."),
    standardization = paste(
      "pgram_before is the RAW periodogram of the whitened residuals",
      "(|DFT|^2/n_e), the domain of donor thresholds/levels/pgram_after. The",
      "detection test sees it divided by var(e - mean(e)) -- a constant",
      "factor, i.e. a constant offset on the log10 axis."),
    internals_used = c("freqseas:::fs_donor_pool", "freqseas:::fs_surgery",
                       "freqseas:::fs_recolor", "freqseas:::omega_seasonal"),
    stage0 = list(
      d = wh$d, d_reason = wh$d_reason, ar_order = wh$p, ar = as.list(wh$ar),
      mu = wh$mu, sigma2 = wh$sigma2, n_trim = wh$n_trim,
      bic_path = as.list(wh$bic_path), M = tst$M,
      M_source = tst$M_selection$source,
      detected_spec = tst$spec$label, shoulder_p = tst$spec$shoulder_p,
      phase_R = tst$spec$phase_R, alpha = tst$alpha,
      whitener_label = sprintf("d = %d, AR(%d) by BIC (ar_max = %d), %d residuals trimmed",
                               wh$d, wh$p, tst$ar_max, wh$n_trim)
    ),
    package_default_path = list(
      note = paste("seas_adjust(x) at pure package defaults (target_set='auto',",
                   "phase_rule='minimum'): the detected spec is 'band', so the",
                   "surgery divides by the estimated gain and imputes nothing.",
                   "Recorded for the bench; NOT shipped as a widget variant."),
      spec = adj_pkg$spec, draw_method = adj_pkg$draw$method,
      evt_after = list(statistic = post_pkg$evt$statistic, p = post_pkg$evt$p)
    ),
    published_sa_test = list(
      note = "seas_test at the same defaults on the published UNRATE over the window",
      statistic = tst_sa$evt$statistic, p = tst_sa$evt$p, decision = tst_sa$decision,
      M = tst_sa$M
    ),
    freqseas_version = as.character(utils::packageVersion("freqseas")),
    r_version = paste(R.version$major, R.version$minor, sep = ".")
  ),
  defaults = list(
    package = defaults_observed,
    used = list(target_set = "bins", phase_rule = "zero",
                donor_quantile = q_default, impute_method = "bootstrap",
                B = 1L, seed_default = SEED_DEFAULT),
    note = paste("Variant grid runs classic SSI (target_set='bins', which",
                 "REQUIRES phase_rule='zero'); everything else at package",
                 "defaults.")
  ),
  shared = list(
    dates      = format(date, "%Y-%m-%d"),
    level_nsa  = nsa,
    level_sa   = sa,
    x_nsa      = x_num,
    dx_nsa     = dx,
    whitened   = as.numeric(tst$e),      # the series the DFT operates on
    omega      = grid$omega_pos,         # length n_spec, omega_j = 2*pi*j/n_e
    pgram_before = pgram_pos_full,       # raw whitened periodogram, positive side
    evt_before = list(statistic = tst$evt$statistic, p = tst$evt$p,
                      critical = tst$evt$critical, alpha = tst$alpha,
                      N1 = tst$partition$N1, N0 = tst$partition$N0),
    targets    = targets_df,             # animation order; j/omega/harmonic/label
    harmonics  = harmonics_df,           # per-harmonic excess and target counts
    donor      = list(
      default_quantile = q_default,
      quantiles   = q_all,
      by_quantile = unname(donor_by_q)   # {quantile, threshold, pool_mean, n_pool, pool[]}
    ),
    benchmark  = list(
      n_years       = n_years,
      year_sums_nsa = year_sums_nsa      # sum of level_nsa per 12-obs block
    )
  ),
  variants = lapply(seq_len(nrow(vspec)), variant_json)
)

write_json(payload, out_json, digits = I(9), auto_unbox = TRUE, null = "null",
           na = "null", pretty = FALSE)

sz <- file.info(out_json)$size
p_after <- vapply(runs, function(r) r$evt_after$p, 0)
p_bench <- vapply(runs, function(r) r$evt_after_bench$p, 0)
message(sprintf("Wrote %s (%.0f KB) -- contract %s, %d classic variants",
                out_json, sz / 1024, contract, nrow(vspec)))
message(sprintf("evt_before: statistic %.3f, p = %.3g (alpha %.2f, critical %.3f)",
                tst$evt$statistic, tst$evt$p, tst$alpha, tst$evt$critical))
message(sprintf("default variant (q=%.1f bootstrap seed %d): evt_after p=%.3g, benchmarked p=%.3g",
                q_default, SEED_DEFAULT, def$evt_after$p, def$evt_after_bench$p))
message(sprintf("evt_after p range (classic variants): %.3g .. %.3g",
                min(p_after), max(p_after)))
message(sprintf("evt_after_bench p range (classic variants): %.3g .. %.3g",
                min(p_bench), max(p_bench)))
message(sprintf("package-default path (band, not shipped): post p = %.3g | published UNRATE: statistic %.3f, p = %.3g",
                post_pkg$evt$p, tst_sa$evt$statistic, tst_sa$evt$p))
flip <- which(p_after >= tst$alpha & p_bench < tst$alpha)
if (length(flip) > 0L) {
  message("*** WARNING: benchmarking FLIPS fail-to-reject back to REJECT for variants: ",
          paste(flip, collapse = ", "), " ***")
} else {
  message("Benchmarking flips no classic variant back to rejection at alpha = ", tst$alpha)
}
message(sprintf("Elapsed: %s", format(Sys.time() - t_start)))

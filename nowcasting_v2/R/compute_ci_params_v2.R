#### Per-information-stage CI params for v2 ####
#
# Turns a WEEKLY (Monday-cadence) backtest CSV into interval parameters that vary
# by within-quarter information stage `jt` (= n_months_in_quarter).
#
# Why per-stage -- and how much it actually turned out to matter.
#
# The old params were calibrated on quarter-end as-ofs only, where jt == 2 for
# every single observation, then applied to every Monday the site publishes. That
# is structurally wrong, and RDP 2024-04 Table 3 reports accuracy separately by
# stage (FC 0.87 / M1 0.70 / M2 0.78 / M3 0.88) for exactly that reason.
#
# Having measured it on a weekly grid, two things came out differently from the
# expectation, and both are worth knowing before anyone invests further here:
#
#  * jt = 0 does not occur, and structurally cannot. GDP releases ~60 days after
#    quarter-end, i.e. two months into the next quarter, so a quarter always has
#    at least two months of data by the time it becomes the target. The jt = 0
#    random-walk fallback in nowcast_midas() is effectively dead code in
#    production. Observed stages are 2 and 3, with jt = 1 rare and thin.
#
#  * jt = 2 and jt = 3 are NOT significantly different: sd 0.5377 vs 0.5398 on
#    n = 17 each, var.test F = 0.89, p = 0.697. So per-stage calibration is the
#    right structure but, on current evidence, does not change the published band.
#    It is kept because it is measured rather than assumed, and because it will
#    apply the correct band if the stages ever do diverge.
#
# Two deliberate departures from the old compute_ci_params.R:
#
#  1. BIAS IS MEASURED AND REPORTED, BUT NEVER APPLIED. RDP 2024-04 does not
#     bias-correct: the word "bias" does not appear in the paper, its replication
#     code applies no adjustment to its forecasts, and it evaluates purely on RMSE
#     -- a loss that already penalises bias and variance jointly. Subtracting the
#     mean error afterwards would publish a number that none of our RMSE figures
#     describe, and would be a deviation from the paper dressed up as fidelity.
#
#     So `qoq_bias_applied_pp` is always 0. The measured bias and its t-statistic
#     are still emitted (`qoq_bias_pp`, `bias_t`, `bias_significant`) so the site
#     can DISCLOSE a systematic tendency rather than silently correct for it --
#     which is also more useful to a reader.
#
#     This matters: at alpha = 0.10 the measured bias is +0.34pp with t = 4.7.
#     Applying it would have moved the published Q2 nowcast from +0.47% to +0.13%
#     and turned most of the evolution chart negative.
#
#  2. t(df), NOT the normal. sd is estimated, not known. At n=17 the old z=1.96
#     made the 95% band 8.2% too narrow.
#
#  3. ONE OBSERVATION PER (target_quarter, jt). A weekly grid gives ~3-4 Mondays
#     inside the same quarter at the same stage, and those share almost the same
#     information set -- counting them as independent would inflate n and shrink
#     the interval spuriously. We keep the LAST (most informed) Monday in each
#     cell, so n per stage is the number of quarters, not the number of Mondays.
#
# Usage (from nowcasting_v2/):
#   Rscript R/compute_ci_params_v2.R <backtest.csv> <out.json> [model_label]

suppressMessages({ library(jsonlite) })

args  <- commandArgs(trailingOnly = TRUE)
src   <- if (length(args) >= 1) args[[1]] else stop("need a backtest csv")
out   <- if (length(args) >= 2) args[[2]] else stop("need an output json path")
label <- if (length(args) >= 3) args[[3]] else basename(src)

MIN_N     <- 12L    # below this a per-stage sd is too noisy to publish; fall back to pooled
BIAS_ALPHA <- 0.05  # two-sided significance required before we subtract a bias

# Calibrate on post-COVID target quarters only, as the original compute_ci_params.R
# did. This was re-tested rather than inherited, and the data backs it:
#
#   pre-2020  n=85  sd=0.3382
#   post-2021 n=38  sd=0.5824
#   var.test  F=2.97  p<0.0001  -> the regimes genuinely differ
#
# So pooling the full history (or merely excising the 2020-21 pandemic quarters
# and keeping 2012-2019) would understate current uncertainty by ~40%. The
# pre-COVID era was simply an easier forecasting environment for this model.
#
# The pandemic quarters themselves are excluded by construction: they fall before
# CALIB_FROM. Leaving them in would triple the apparent sd (jt=2: 1.225 raw vs
# 0.412 robust) on the strength of four quarters carrying +6.5, -3.8, -2.7, -2.6pp.
#
# Judgement call worth revisiting: these bands describe accuracy in ordinary
# post-pandemic quarters. Another COVID-scale shock is not in them.
CALIB_FROM <- as.Date("2022-01-01")

b <- read.csv(src, stringsAsFactors = FALSE)
b$target_quarter_date <- as.Date(b$target_quarter_date)
b <- b[!is.na(b$qoq_error) & !is.na(b$n_months_in_quarter), ]
if (!nrow(b)) stop("no usable rows in ", src)

n_all <- nrow(b)
b     <- b[b$target_quarter_date >= CALIB_FROM, ]
cat(sprintf("%s: kept %d of %d rows (target quarter >= %s)\n",
            label, nrow(b), n_all, CALIB_FROM))
if (!nrow(b)) stop("no rows at or after CALIB_FROM ", CALIB_FROM)

# --- one row per (target quarter, stage): keep the last as-of in each cell ------
b$as_of <- as.Date(b$as_of)
b <- b[order(b$target_quarter_date, b$n_months_in_quarter, b$as_of), ]
key <- paste(b$target_quarter_date, b$n_months_in_quarter, sep = "|")
b <- b[!duplicated(key, fromLast = TRUE), ]
cat(sprintf("%s: %d independent (quarter, stage) observations\n", label, nrow(b)))

stats_for <- function(e) {
  n <- length(e)
  if (n < 3L) return(NULL)
  bias <- mean(e); sdv <- sd(e); rmse <- sqrt(mean(e^2))
  tstat <- bias / (sdv / sqrt(n))
  sig   <- abs(tstat) > qt(1 - BIAS_ALPHA / 2, n - 1L)
  list(n = n,
       # Measured and reported for disclosure; NEVER applied -- see note above.
       qoq_bias_pp        = round(bias, 4),
       bias_t             = round(tstat, 3),
       bias_significant   = sig,
       qoq_bias_applied_pp = 0,
       qoq_sd_pp          = round(sdv, 4),
       qoq_rmse_pp        = round(rmse, 4),
       t_68               = round(qt(0.84134, n - 1L), 4),   # one-sd-equivalent quantile
       t_95               = round(qt(0.975,   n - 1L), 4))
}

pooled <- stats_for(b$qoq_error)
if (is.null(pooled)) stop("not enough observations to calibrate")

by_jt <- list()
for (j in sort(unique(b$n_months_in_quarter))) {
  e <- b$qoq_error[b$n_months_in_quarter == j]
  s <- stats_for(e)
  if (is.null(s) || s$n < MIN_N) {
    cat(sprintf("  jt=%d: n=%d < %d -- will fall back to pooled\n", j, length(e), MIN_N))
    next
  }
  s$stage <- j
  by_jt[[as.character(j)]] <- s
  cat(sprintf("  jt=%d: n=%2d  bias %+0.4f (t=%+.2f%s)  sd %.4f  t95 %.3f\n",
              j, s$n, s$qoq_bias_pp, s$bias_t,
              if (s$bias_significant) ", SIGNIFICANT but not applied" else ", n.s.", s$qoq_sd_pp, s$t_95))
}

params <- list(
  schema      = "v2-ci-by-stage-1",
  basis       = sprintf(paste("empirical pseudo-out-of-sample error dispersion, by within-quarter",
                              "information stage (jt = n_months_in_quarter); post-COVID target quarters",
                              "only (>= %s). Pre-2020 errors are significantly tighter (F=2.97, p<0.0001)",
                              "so pooling them would understate current uncertainty."), CALIB_FROM),
  calibrated_from = as.character(CALIB_FROM),
  method      = paste("interval = point +/- t(df) * sd, centred on the model's raw output.",
                      "The measured bias is reported (qoq_bias_pp, bias_t) but NOT applied:",
                      "RDP 2024-04 does not bias-correct and evaluates on RMSE, which already",
                      "penalises bias. Stages with fewer than MIN_N observations fall back to `pooled`."),
  min_n       = MIN_N,
  bias_alpha  = BIAS_ALPHA,
  pooled      = pooled,
  by_jt       = by_jt,
  model       = label,
  source      = src,
  computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)

write_json(params, out, auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat(sprintf("wrote %s  (pooled n=%d, sd=%.4f; %d per-stage entries)\n",
            out, pooled$n, pooled$qoq_sd_pp, length(by_jt)))

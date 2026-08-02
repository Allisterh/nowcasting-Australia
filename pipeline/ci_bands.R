#### Bias-aware empirical confidence bands ####
# Replaces the old hardcoded +/-0.7% (68%) / +/-1.4% (95%) multiplicative bands
# with intervals derived from the model's actual POOS backtest error.
#
# Backtest error is defined as `forecast - actual`, so a positive mean error =>
# the model OVER-predicts. We therefore center the interval for the *actual* on
# the bias-corrected forecast (qoq - bias) and span it by z * sd, where sd is the
# dispersion of errors about their mean (sd = sqrt(rmse^2 - bias^2), so the bias
# is not double-counted). The displayed POINT stays the raw model forecast, so
# the band is asymmetric about the point — it extends further DOWN, honestly
# reflecting the model's tendency to run hot.
#
# Params (qoq_bias_pp, qoq_sd_pp, z_68, z_95) come from seed/ci_params.json,
# regenerated from a backtest by compute_ci_params.R. Functions are vectorised
# so they serve both latest.json (scalar) and nowcasts.json (per-vintage).

#' QoQ-growth band edges (percentage points) for a forecast.
ci_qoq_band <- function(qoq_point, bias_pp, sd_pp, z) {
  center <- qoq_point - bias_pp
  list(low = center - z * sd_pp, high = center + z * sd_pp)
}

#' Level ($M) of the prior quarter implied by a point level + its QoQ growth.
ci_prev_level <- function(point_level, qoq_point) point_level / (1 + qoq_point / 100)

#' Level ($M) band edges for a forecast, via the QoQ band + the prior level.
ci_level_band <- function(qoq_point, prev_level, bias_pp, sd_pp, z) {
  b <- ci_qoq_band(qoq_point, bias_pp, sd_pp, z)
  list(low  = round(prev_level * (1 + b$low  / 100)),
       high = round(prev_level * (1 + b$high / 100)))
}

#' Load + validate the CI params produced by compute_ci_params.R (flat, v1) or
#' compute_ci_params_v2.R (per-information-stage, schema "v2-ci-by-stage-1").
load_ci_params <- function(path = "seed/ci_params.json") {
  if (!file.exists(path)) {
    stop(sprintf("CI params not found at '%s'. Regenerate with: Rscript compute_ci_params.R", path))
  }
  p <- jsonlite::fromJSON(path)

  if (!is.null(p$schema) && p$schema == "v2-ci-by-stage-1") {
    if (is.null(p$pooled) || !is.numeric(p$pooled$qoq_sd_pp) || p$pooled$qoq_sd_pp <= 0) {
      stop(sprintf("%s: pooled$qoq_sd_pp missing or invalid", path))
    }
    return(p)
  }

  if (!is.numeric(p$qoq_bias_pp) || !is.numeric(p$qoq_sd_pp) ||
      is.na(p$qoq_bias_pp) || is.na(p$qoq_sd_pp) || p$qoq_sd_pp <= 0) {
    stop("ci_params.json: qoq_bias_pp / qoq_sd_pp missing or invalid")
  }
  if (is.null(p$z_68)) p$z_68 <- 1.0
  if (is.null(p$z_95)) p$z_95 <- 1.96
  p
}

#' Resolve the interval parameters that apply at a given within-quarter
#' information stage.
#'
#' A nowcast made with 0 months of target-quarter data is a different estimator
#' from one made with 3, so it does not get the same interval. For per-stage
#' params we look up `jt`; if that stage was too thin to calibrate (or `jt` is
#' unknown) we fall back to the pooled figures. Flat/legacy params ignore `jt`.
#'
#' Returns list(bias_pp, sd_pp, z_68, z_95, n, stage) where `stage` is the stage
#' actually used ("pooled" when falling back) so callers can surface it.
ci_params_for_stage <- function(p, jt = NULL) {
  flat <- function(bias, sd, z68, z95, n, stage) {
    list(bias_pp = bias, sd_pp = sd, z_68 = z68, z_95 = z95, n = n, stage = stage)
  }

  if (is.null(p$schema) || p$schema != "v2-ci-by-stage-1") {
    return(flat(p$qoq_bias_pp, p$qoq_sd_pp, p$z_68, p$z_95, p$n, "flat"))
  }

  s <- NULL
  if (!is.null(jt) && !is.na(jt) && !is.null(p$by_jt)) {
    s <- p$by_jt[[as.character(jt)]]
  }
  if (is.null(s)) {
    s <- p$pooled
    return(flat(s$qoq_bias_applied_pp, s$qoq_sd_pp, s$t_68, s$t_95, s$n, "pooled"))
  }
  flat(s$qoq_bias_applied_pp, s$qoq_sd_pp, s$t_68, s$t_95, s$n, as.character(jt))
}

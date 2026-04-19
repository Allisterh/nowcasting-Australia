#### Stationarity Diagnostic for DFM Indicators ####
# Purpose: For each indicator, apply candidate Bpanel trans code and test
# stationarity (ADF + KPSS). Results drive the per-series transform vector
# wired into 05_estimate_model.R.
#
# ADF H0: series has unit root (non-stationary)   → want p < 0.05 (reject)
# KPSS H0: series is stationary                    → want p > 0.05 (fail to reject)
# Dual-test agreement: stationary iff ADF rejects AND KPSS fails to reject.

suppressPackageStartupMessages({
  library(tidyverse)
  library(tseries)
  library(urca)
  library(glue)
})

#### Bpanel trans code mapping (from nowcasting::Bpanel source) ####
# 0: level        → x
# 1: MoM %        → diff(x)/lag(x,-1)
# 2: first diff   → diff(x)
# 3: ΔYoY %       → diff(diff(x,12)/lag(x,-12))
# 4: ΔYoY diff    → diff(diff(x,12))
# 5: YoY diff     → diff(x,12)
# 6: YoY %        → diff(x,12)/lag(x,-12)
# 7: 3-mo %       → diff(x,3)/lag(x,-3)

apply_trans <- function(x, code) {
  x <- as.numeric(x)
  if (code == 0) return(x)
  if (code == 1) return(c(NA, diff(x) / head(x, -1)))
  if (code == 2) return(c(NA, diff(x)))
  if (code == 5) return(c(rep(NA, 12), diff(x, 12)))
  if (code == 6) return(c(rep(NA, 12), diff(x, 12) / head(x, -12)))
  if (code == 7) return(c(rep(NA, 3), diff(x, 3) / head(x, -3)))
  if (code == 3) {
    yoy_pct <- c(rep(NA, 12), diff(x, 12) / head(x, -12))
    return(c(NA, diff(yoy_pct)))
  }
  if (code == 4) return(c(rep(NA, 13), diff(diff(x, 12))))
  stop(glue("Unknown trans code: {code}"))
}

trans_label <- function(code) {
  c("0: level", "1: MoM %", "2: first diff", "3: ΔYoY %",
    "4: ΔYoY diff", "5: YoY diff", "6: YoY %", "7: 3-mo %")[code + 1]
}

#### Run tests ####

run_tests <- function(series, label, mask_covid = FALSE) {
  if (mask_covid) {
    # series is named by date string; mask Mar-Jul 2020
    covid_idx <- grep("^2020-0[3-7]", names(series))
    series[covid_idx] <- NA
  }
  x <- series[!is.na(series)]
  if (length(x) < 24) {
    return(tibble(label = label, n = length(x),
                  adf_stat = NA, adf_p = NA, kpss_stat = NA, kpss_p = NA,
                  verdict = "insufficient data"))
  }
  # tseries::adf.test and kpss.test report CAPPED p-values ([0.01, 0.99] and
  # [0.01, 0.1] respectively). Pull the raw test statistic alongside so
  # strongly-rejecting series don't all look like p=0.01. For the ADF stat
  # we use urca::ur.df (drift model, AIC lag selection) — more informative.
  adf_raw  <- tryCatch(suppressWarnings(adf.test(x)), error = function(e) NULL)
  kpss_raw <- tryCatch(suppressWarnings(kpss.test(x)), error = function(e) NULL)
  adf_stat <- tryCatch(
    as.numeric(summary(ur.df(x, type = "drift", selectlags = "AIC"))@teststat[1]),
    error = function(e) NA
  )
  kpss_stat <- if (!is.null(kpss_raw)) as.numeric(kpss_raw$statistic) else NA
  adf_p     <- if (!is.null(adf_raw)) adf_raw$p.value else NA
  kpss_p    <- if (!is.null(kpss_raw)) kpss_raw$p.value else NA
  verdict <- dplyr::case_when(
    is.na(adf_p) | is.na(kpss_p) ~ "test failed",
    adf_p < 0.05 & kpss_p > 0.05 ~ "STATIONARY",
    adf_p < 0.05 & kpss_p <= 0.05 ~ "trend-stationary?",
    adf_p >= 0.05 & kpss_p > 0.05 ~ "borderline",
    TRUE ~ "NON-STATIONARY"
  )
  tibble(label = label, n = length(x),
         adf_stat = round(adf_stat, 3), adf_p = round(adf_p, 4),
         kpss_stat = round(kpss_stat, 3), kpss_p = round(kpss_p, 4),
         verdict = verdict)
}

#### Candidate transforms (James's priors from 05_estimate_model.R:254-255) ####

candidate_trans <- tribble(
  ~indicator,           ~code, ~rationale,
  "household_spending",  1,    "Trending $ level → MoM %",
  "cons_conf",           2,    "Bounded index → first diff",
  "building_app",        1,    "Trending noisy count → MoM %",
  "bus_conf",            2,    "Bounded diffusion index → first diff",
  "exports_goods",       1,    "Trending $ level → MoM %",
  "exports_servs",       7,    "Quarterly $ on monthly grid → 3-mo %",
  "imports_goods",       1,    "Trending $ level → MoM %",
  "imports_servs",       7,    "Quarterly $ on monthly grid → 3-mo %",
  "employment",          1,    "Trending level → MoM %",
  "unemp_rate",          2,    "Bounded rate → first diff",
  "participation",       2,    "Bounded rate → first diff",
  "hours_worked",        1,    "Trending level → MoM %",
  "gdp_quarterly",       7,    "Quarterly level on monthly grid → 3-mo % = QoQ %"
)

#### Main ####

main <- function() {
  md_path <- "pipeline/.cache/processed/master_dataset_wide.rds"
  if (!file.exists(md_path)) stop(glue("Master dataset not found: {md_path}"))
  d <- readRDS(md_path)

  results_all <- list()

  for (i in seq_len(nrow(candidate_trans))) {
    ind <- candidate_trans$indicator[i]
    code <- candidate_trans$code[i]
    rationale <- candidate_trans$rationale[i]

    if (!ind %in% names(d)) {
      message(glue("SKIP {ind}: not in master dataset"))
      next
    }

    raw <- d[[ind]]
    names(raw) <- as.character(d$date)

    # Apply candidate transform
    transformed <- apply_trans(raw, code)
    names(transformed) <- as.character(d$date)

    # Run tests both on full sample and COVID-masked
    r_full <- run_tests(transformed, glue("{ind} [code {code}] full"), mask_covid = FALSE)
    r_mask <- run_tests(transformed, glue("{ind} [code {code}] COVID-masked"), mask_covid = TRUE)

    # Also run on the level (trans=0) for reference
    r_level <- run_tests(setNames(raw, as.character(d$date)),
                         glue("{ind} [code 0] level (reference)"), mask_covid = FALSE)

    results_all[[ind]] <- bind_rows(r_level, r_full, r_mask) |>
      mutate(rationale = c("—", rationale, rationale))
  }

  final <- bind_rows(results_all)
  cat("\n\n=== STATIONARITY TEST RESULTS ===\n\n")
  print(final, n = 100)

  # Write to cache for record
  out_path <- "pipeline/.cache/stationarity_check.csv"
  write_csv(final, out_path)
  cat(glue("\n\nWritten to {out_path}\n"))

  # Summary: any non-stationary candidates
  fails <- final |> filter(grepl("COVID-masked", label), verdict != "STATIONARY")
  if (nrow(fails) > 0) {
    cat("\n⚠ Candidate transforms that did NOT produce stationarity (COVID-masked):\n")
    print(fails)
  } else {
    cat("\n✓ All candidate transforms produced stationarity on COVID-masked sample.\n")
  }

  invisible(final)
}

if (sys.nframe() == 0) main()

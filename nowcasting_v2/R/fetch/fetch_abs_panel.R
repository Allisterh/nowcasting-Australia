# =============================================================================
# fetch_abs_panel.R  — Tier-1 ABS predictors for nowcast v2 (RBA MAI panel)
# =============================================================================
# Fetches the free, long-history ABS series that map onto the RBA RDP 2024-04
# monthly predictor panel (see rba_paper/content/Data/mai_info.csv).
#
# Output contract: one tidy CSV per series at data_raw/<id>.csv with columns
#   date,value   (date = first-of-month YYYY-MM-01; quarterly at quarter starts)
# Each fetcher prints: "<id>: N obs, MIN -> MAX".
#
# Series IDs were CONFIRMED against fixtures (tests/fixtures/abs_*.rds), not
# guessed. See seed/panel_info_tier1.csv for the id->series_id mapping + status.
#
# All series are ABS Seasonally Adjusted, matching the RBA panel concepts:
#   emp/ft_emp/pt_emp  = employment LEVELS ('000)   [6202.0 table 1]
#   ue                 = unemployment RATE (%)      [6202.0 table 1]  (RBA: rate)
#   ud                 = underemployed total LEVEL  [6202.0 table 23]
#   hours              = monthly hours worked ('000)[6202.0 table 19]
#   rt                 = retail turnover total ($m) [8501.0 table 1]
#   export             = total goods credits ($m)   [5368.0]
#   house_prices       = RPPI 8-cap (index)         [6416.0] -- DISCONTINUED
# -----------------------------------------------------------------------------

# Resolve repo-relative paths whether sourced from repo root or nowcasting_v2/.
.abs_setup <- local({
  here <- function(...) {
    cand <- c(file.path("nowcasting_v2", "R", "_setup.R"),
              file.path("R", "_setup.R"),
              file.path("..", "R", "_setup.R"),
              file.path("..", "..", "R", "_setup.R"))
    for (p in cand) if (file.exists(p)) return(normalizePath(dirname(dirname(p))))
    normalizePath(".")
  }
  here()
})
source(file.path(.abs_setup, "R", "_setup.R"))

suppressMessages({
  library(readabs)
  library(dplyr)
  library(lubridate)
  library(readr)
})

.v2_root  <- .abs_setup
.data_raw <- file.path(.v2_root, "data_raw")
dir.create(.data_raw, recursive = TRUE, showWarnings = FALSE)

# -----------------------------------------------------------------------------
# Parser: tidy an readabs frame (one series) into date,value (first-of-month).
# Pure function over the readabs tibble so it is unit-testable from a fixture.
# -----------------------------------------------------------------------------
parse_abs_series <- function(df, series_id) {
  stopifnot(all(c("series_id", "date", "value") %in% names(df)))
  out <- df |>
    filter(.data$series_id == !!series_id, !is.na(.data$value)) |>
    transmute(
      date  = lubridate::floor_date(as.Date(.data$date), "month"),
      value = as.numeric(.data$value)
    ) |>
    distinct(date, .keep_all = TRUE) |>
    arrange(date)
  if (nrow(out) == 0L) {
    stop(sprintf("parse_abs_series: no observations for series_id '%s'", series_id))
  }
  out
}

.write_series <- function(tbl, id) {
  path <- file.path(.data_raw, paste0(id, ".csv"))
  readr::write_csv(tbl, path)
  cat(sprintf("%s: %d obs, %s -> %s\n",
              id, nrow(tbl),
              format(min(tbl$date), "%Y-%m-%d"),
              format(max(tbl$date), "%Y-%m-%d")))
  invisible(path)
}

# -----------------------------------------------------------------------------
# Single-series fetcher via readabs::read_abs_series (works for known IDs).
# -----------------------------------------------------------------------------
fetch_abs_id <- function(id, series_id, write = TRUE) {
  message(sprintf("Fetching ABS %s (%s) ...", id, series_id))
  raw <- readabs::read_abs_series(series_id)
  sa  <- raw |> filter(.data$series_type == "Seasonally Adjusted")
  if (nrow(sa) == 0L) sa <- raw  # some series have no SA variant
  tbl <- parse_abs_series(sa, series_id)
  if (write) .write_series(tbl, id)
  tbl
}

# -----------------------------------------------------------------------------
# Series-ID registry (CONFIRMED against fixtures). Underemployment + hours live
# in separate 6202.0 tables, so we pull them by id (read_abs_series handles the
# table lookup). Retail uses the discontinued-but-long 8501.0 turnover series.
# -----------------------------------------------------------------------------
ABS_PANEL_IDS <- c(
  emp    = "A84423043C",  # Employed total ; Persons ; SA            (6202.0 t1)
  ft_emp = "A84423041X",  # Employed full-time ; Persons ; SA        (6202.0 t1)
  pt_emp = "A84423042A",  # Employed part-time ; Persons ; SA        (6202.0 t1)
  ue     = "A84423050A",  # Unemployment rate ; Persons ; SA (%)     (6202.0 t1)
  ud     = "A85255719L",  # Underemployed total ; Persons ; SA ('000)(6202.0 t23)
  hours  = "A84426277X",  # Monthly hours worked all jobs ; Persons ; SA
  rt     = "A3348585R",   # Retail turnover ; Total state/industry ; SA ($m)
  export = "A2718577A",   # International trade: credits, total goods ; SA ($m)
  building_app = "A422070J" # Building approvals; total dwelling units ; SA (8731.0)
  # house_prices: see note below -- no maintained free long-history series.
)

# household_spending (MHSI) is a DERIVED predictor: the model uses the REAL
# (CPI-deflated) MHSI, so it can't be a plain fetch_abs_id. See fetch_mhsi_real().
MHSI_NOMINAL_ID <- "A130200584T"  # MHSI total ; current prices ; SA   (5682.0)
CPI_ID          <- "A2325846C"    # CPI all groups (6401.0 Table 17), quarterly

fetch_emp        <- function() fetch_abs_id("emp",    ABS_PANEL_IDS[["emp"]])
fetch_ft_emp     <- function() fetch_abs_id("ft_emp", ABS_PANEL_IDS[["ft_emp"]])
fetch_pt_emp     <- function() fetch_abs_id("pt_emp", ABS_PANEL_IDS[["pt_emp"]])
fetch_ue         <- function() fetch_abs_id("ue",     ABS_PANEL_IDS[["ue"]])
fetch_ud         <- function() fetch_abs_id("ud",     ABS_PANEL_IDS[["ud"]])
fetch_hours      <- function() fetch_abs_id("hours",  ABS_PANEL_IDS[["hours"]])
fetch_rt         <- function() fetch_abs_id("rt",     ABS_PANEL_IDS[["rt"]])
fetch_export     <- function() fetch_abs_id("export", ABS_PANEL_IDS[["export"]])

# house_prices: the ABS RPPI (cat 6416.0, weighted avg 8 capitals, id
# A83728455L) is the concept the RBA uses, but ABS DISCONTINUED that index at
# 2021:Q4 and moved to cat 6432.0 (mean price, 2011+). Neither free ABS series
# satisfies BOTH "history >= 2005" AND "latest within ~3 months". We therefore
# record house_prices as MISSING in panel_info_tier1.csv and defer the
# CoreLogic/splice handling to Tier-3. Helper kept for completeness/testing.
fetch_house_prices <- function() {
  fetch_abs_id("house_prices", "A83728455L")
}

# -----------------------------------------------------------------------------
# household_spending = REAL (CPI-deflated) Monthly Household Spending Indicator.
# real = nominal MHSI / CPI * 100, with quarterly CPI linearly interpolated to
# monthly (and flat-extrapolated past the last CPI quarter). Mirrors the v2
# deflation recorded in seed/panel_info.csv. Writes household_spending.csv +
# household_spending_real.csv + household_spending_nominal.csv + cpi_monthly.csv.
# -----------------------------------------------------------------------------
fetch_mhsi_real <- function(write = TRUE) {
  message("Fetching MHSI (real, CPI-deflated) ...")
  nom <- fetch_abs_id("household_spending_nominal", MHSI_NOMINAL_ID, write = write)
  cpi_q <- fetch_abs_id("cpi_quarterly_tmp", CPI_ID, write = FALSE)
  # Quarterly CPI -> monthly spine by LAST-PUBLISHED-VALUE (step), not linear.
  #
  # Linear interpolation of an interior month uses the FOLLOWING quarter's CPI,
  # which did not exist when that month's spending was published: April 2026 MHSI
  # comes out ~28 May, while the June-quarter CPI it was being interpolated
  # against lands in late July. The deflated series is then frozen into
  # household_spending.csv, and .truncate_acc only trims it -- it never re-derives
  # the deflator -- so every historical as-of in the backtest inherits a deflator
  # built from CPI prints from the future. Those errors calibrate the CI bands.
  #
  # method="constant", f=0 carries the last published quarterly CPI forward, which
  # is exactly the information set available in real time. rule=2 still
  # flat-extrapolates past the final CPI quarter (that edge was never a leak).
  # Cost: a small step at each quarter boundary instead of a smooth ramp.
  spine <- seq(min(cpi_q$date), max(nom$date), by = "month")
  cpi_v <- approx(as.numeric(cpi_q$date), cpi_q$value, xout = as.numeric(spine),
                  method = "constant", f = 0, rule = 2)$y
  cpi_monthly <- data.frame(date = spine, value = round(cpi_v, 4))
  if (write) .write_series(cpi_monthly, "cpi_monthly")
  idx <- cpi_monthly$value[match(nom$date, cpi_monthly$date)]
  if (any(is.na(idx))) stop("fetch_mhsi_real: CPI does not cover the MHSI span")
  real <- data.frame(date = nom$date, value = nom$value / idx * 100)
  if (write) { .write_series(real, "household_spending")
               .write_series(real, "household_spending_real") }
  invisible(real)
}

fetch_abs_panel <- function(ids = names(ABS_PANEL_IDS)) {
  res <- list()
  for (id in ids) {
    res[[id]] <- tryCatch(
      fetch_abs_id(id, ABS_PANEL_IDS[[id]]),
      error = function(e) {
        message(sprintf("  !! %s FAILED: %s", id, conditionMessage(e)))
        NULL
      }
    )
  }
  res[["household_spending"]] <- tryCatch(
    fetch_mhsi_real(),
    error = function(e) { message(sprintf("  !! MHSI real FAILED: %s", conditionMessage(e))); NULL })
  invisible(res)
}

if (sys.nframe() == 0L && !interactive()) {
  res <- fetch_abs_panel()
  failed <- names(res)[vapply(res, is.null, logical(1))]
  if (length(failed)) {
    message(sprintf("FETCH FAILED for %d ABS series: %s -- exiting non-zero so the run is not silently stale.",
                    length(failed), paste(failed, collapse = ", ")))
    quit(status = 1L)
  }
}

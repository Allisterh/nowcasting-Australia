#### Emit JSON artifacts for the website ####
# Writes the 5 JSON files consumed by the Next.js site at nowcast.wlsn.me.
#
# Contract (must match src/lib/types.ts):
#   - latest.json       — headline
#   - gdp.json          — historical GDP actuals
#   - nowcasts.json     — every weekly vintage ever saved
#   - indicators.json   — 12 monthly indicator series
#   - performance.json  — accuracy scorecard
#
# Called from run_complete_nowcast.R after the nowcast + vintage save.

library(jsonlite)
library(dplyr)
library(lubridate)
library(readr)
library(tidyr)

#### Indicator name mapping (R wide-column → website JSON id) ####
# The R pipeline uses one naming convention; the JSON contract uses another.
# Keep this in lock-step with src/lib/types.ts and data/indicators.json.
INDICATOR_ID_MAP <- c(
  employment    = "employment",
  unemp_rate    = "unemp_rate",
  participation = "part_rate",
  hours_worked  = "hours_worked",
  retail        = "retail_trade",
  cons_conf     = "cons_conf",
  building_app  = "building_approvals",
  bus_conf      = "bus_conf",
  exports_goods = "goods_exp",
  exports_servs = "services_exp",
  imports_goods = "goods_imp",
  imports_servs = "services_imp"
)

INDICATOR_GROUPS <- list(
  Labour   = c("employment", "unemp_rate", "part_rate", "hours_worked"),
  Consumer = c("retail_trade", "cons_conf"),
  Business = c("building_approvals", "bus_conf"),
  External = c("goods_exp", "services_exp", "goods_imp", "services_imp")
)

INDICATOR_META <- list(
  employment         = list(name = "Employment",            unit = "persons",           source = "ABS Labour Force Survey"),
  unemp_rate         = list(name = "Unemployment Rate",     unit = "percent",           source = "ABS Labour Force Survey"),
  part_rate          = list(name = "Participation Rate",    unit = "percent",           source = "ABS Labour Force Survey"),
  hours_worked       = list(name = "Hours Worked",          unit = "hours (thousands)", source = "ABS Labour Force Survey"),
  retail_trade       = list(name = "Retail Trade",          unit = "$ millions",        source = "ABS Retail Trade"),
  cons_conf          = list(name = "Consumer Confidence",   unit = "index",             source = "OECD via FRED"),
  building_approvals = list(name = "Building Approvals",    unit = "count",             source = "ABS Building Approvals"),
  bus_conf           = list(name = "NAB Business Confidence", unit = "index",           source = "NAB Monthly Business Survey"),
  goods_exp          = list(name = "Goods Exports",         unit = "$ millions",        source = "ABS International Trade"),
  services_exp       = list(name = "Services Exports",      unit = "$ millions",        source = "ABS International Trade"),
  goods_imp          = list(name = "Goods Imports",         unit = "$ millions",        source = "ABS International Trade"),
  services_imp       = list(name = "Services Imports",      unit = "$ millions",        source = "ABS International Trade")
)

#### Release-date calculation ####
# ABS releases quarterly GDP on the first Wednesday of the month 3 months after
# the quarter ends. e.g. Q1 ends Mar → release in Jun; Q4 ends Dec → release in Mar (of following year).
gdp_release_date <- function(quarter_str) {
  parts <- strsplit(quarter_str, " Q", fixed = TRUE)[[1]]
  if (length(parts) != 2) return(NA)
  yr <- suppressWarnings(as.integer(parts[1]))
  q  <- suppressWarnings(as.integer(parts[2]))
  if (is.na(yr) || is.na(q) || !(q %in% 1:4)) return(NA)
  quarter_end_month <- q * 3L          # Q1→3, Q2→6, Q3→9, Q4→12
  release_month <- quarter_end_month + 3L
  release_year  <- yr
  if (release_month > 12L) {
    release_month <- release_month - 12L
    release_year  <- yr + 1L
  }
  month_start <- as.Date(sprintf("%d-%02d-01", release_year, release_month))
  first_dow   <- as.numeric(format(month_start, "%w"))  # 0=Sun, 3=Wed
  days_to_wed <- (3L - first_dow) %% 7L
  month_start + days_to_wed
}

date_to_quarter <- function(d) sprintf("%d Q%d", year(d), quarter(d))

#### Main emitter ####
#' Write the 5 JSON artifacts consumed by the Next.js site.
#'
#' @param target_dir Destination directory (e.g. "../data" when called from
#'   pipeline/).
#' @param nowcast    Output of `generate_nowcast()` — a list with
#'   `target_quarter`, `nowcast_value`, `qoq_growth`, `yoy_growth`,
#'   `latest_actual_quarter`, `latest_actual_value`.
#' @param master     Output of `build_master_dataset()` — list with `$wide`
#'   and `$long` tibbles.
#' @param vintage_info Output of `save_vintage()` — list containing
#'   `vintage_id` and `file_path`. Used to locate `vintage_tracking.csv`.
#' @return invisible(NULL). Side effect: writes 5 .json files to target_dir.
emit_json <- function(target_dir, nowcast, master, vintage_info) {
  dir.create(target_dir, showWarnings = FALSE, recursive = TRUE)

  # Read the vintage tracking CSV FIRST. The most recent row is the canonical
  # "latest nowcast" — it's what the pipeline most recently produced.
  # We fall back to the passed-in `nowcast` arg only if no vintages exist yet.
  vintage_csv <- file.path(VINTAGE_BASE_DIR, "vintage_tracking.csv")
  latest_vintage <- if (file.exists(vintage_csv)) {
    vraw_all <- read_csv(vintage_csv, show_col_types = FALSE)
    if (nrow(vraw_all) > 0) {
      vraw_all |>
        mutate(run_timestamp_dt = as.POSIXct(run_timestamp, tz = "UTC")) |>
        arrange(desc(run_timestamp_dt)) |>
        slice(1)
    } else NULL
  } else NULL

  # Use the latest vintage if we have one; otherwise the legacy RDS.
  if (!is.null(latest_vintage)) {
    target_quarter        <- as.character(latest_vintage$target_quarter)
    point_value           <- round(as.numeric(latest_vintage$nowcast_value))
    qoq_growth_pct        <- round(as.numeric(latest_vintage$qoq_growth), 2)
    yoy_growth_pct        <- round(as.numeric(latest_vintage$yoy_growth), 2)
    latest_actual_value   <- round(as.numeric(latest_vintage$latest_actual_value))
    data_through_date     <- as.Date(latest_vintage$data_as_of_date)
  } else {
    target_quarter        <- nowcast$target_quarter
    point_value           <- round(as.numeric(nowcast$nowcast_value))
    qoq_growth_pct        <- round(as.numeric(nowcast$qoq_growth), 2)
    yoy_growth_pct        <- round(as.numeric(nowcast$yoy_growth), 2)
    latest_actual_value   <- round(as.numeric(nowcast$latest_actual_value))
    data_through_date     <- max(master$wide$date, na.rm = TRUE)
  }

  next_release <- gdp_release_date(target_quarter)

  # Build a tidy GDP series from master$wide (for gdp.json, the headline reference,
  # and performance actuals).
  gdp_wide <- master$wide |>
    select(date, value = gdp_quarterly) |>
    filter(!is.na(value)) |>
    arrange(date) |>
    mutate(
      qoq_pct = (value / lag(value) - 1) * 100,
      yoy_pct = (value / lag(value, 4) - 1) * 100,
      quarter = vapply(date, date_to_quarter, character(1))
    )

  # Derive the latest actual's quarter + QoQ from the most recent published GDP row.
  latest_actual_row <- if (nrow(gdp_wide) > 0) tail(gdp_wide, 1) else NULL
  latest_actual_quarter <- if (!is.null(latest_actual_row)) latest_actual_row$quarter else nowcast$latest_actual_quarter
  latest_actual_qoq <- if (!is.null(latest_actual_row)) latest_actual_row$qoq_pct else NA_real_

  # "Released days before next release" is a negative number; e.g. if Q4 was released
  # 92 days before Q1's scheduled release, this field reads -92.
  prev_release <- gdp_release_date(latest_actual_quarter)
  released_days_before_next <- if (!is.na(prev_release) && !is.na(next_release)) {
    as.integer(as.numeric(difftime(prev_release, next_release, units = "days")))
  } else NA_integer_

  # --- 1. latest.json ---
  latest_obj <- list(
    generated_at          = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    target_quarter        = target_quarter,
    data_through          = format(data_through_date, "%Y-%m"),
    next_gdp_release_date = format(next_release, "%Y-%m-%d"),
    nowcast = list(
      gdp_chain_volume_millions = point_value,
      qoq_growth_pct            = qoq_growth_pct,
      yoy_growth_pct            = yoy_growth_pct,
      ci_68_low                 = round(point_value * 0.993),
      ci_68_high                = round(point_value * 1.007),
      ci_95_low                 = round(point_value * 0.986),
      ci_95_high                = round(point_value * 1.014)
    ),
    latest_actual = list(
      quarter                   = latest_actual_quarter,
      gdp_chain_volume_millions = latest_actual_value,
      qoq_growth_pct            = round(latest_actual_qoq, 2),
      released_days_before_next = released_days_before_next
    )
  )
  write(
    toJSON(latest_obj, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null"),
    file.path(target_dir, "latest.json")
  )

  # --- 2. gdp.json ---
  gdp_series <- gdp_wide |>
    transmute(
      quarter = quarter,
      value   = round(value),
      qoq_pct = round(qoq_pct, 2),
      yoy_pct = round(yoy_pct, 2)
    )
  write(
    toJSON(list(series = gdp_series), auto_unbox = TRUE, pretty = TRUE, na = "null"),
    file.path(target_dir, "gdp.json")
  )

  # --- 3. nowcasts.json ---
  # Reuse vraw_all read at top of function.
  vintages_out <- if (exists("vraw_all") && !is.null(vraw_all) && nrow(vraw_all) > 0) {
    vraw_all |>
      mutate(
        run_date_d    = as.Date(run_timestamp),
        release_d     = as.Date(vapply(target_quarter, function(q) {
          rd <- gdp_release_date(q)
          if (inherits(rd, "Date")) as.character(rd) else NA_character_
        }, character(1))),
        days_until_release = as.integer(as.numeric(difftime(run_date_d, release_d, units = "days")))
      ) |>
      transmute(
        run_date          = format(run_date_d, "%Y-%m-%d"),
        target_quarter,
        point             = round(as.numeric(nowcast_value)),
        qoq_growth_pct    = round(as.numeric(qoq_growth), 2),
        ci_68_low         = round(as.numeric(nowcast_value) * 0.993),
        ci_68_high        = round(as.numeric(nowcast_value) * 1.007),
        ci_95_low         = round(as.numeric(nowcast_value) * 0.986),
        ci_95_high        = round(as.numeric(nowcast_value) * 1.014),
        data_through      = format(as.Date(data_as_of_date), "%Y-%m"),
        days_until_release
      )
  } else {
    tibble(
      run_date = character(), target_quarter = character(),
      point = integer(), qoq_growth_pct = double(),
      ci_68_low = integer(), ci_68_high = integer(),
      ci_95_low = integer(), ci_95_high = integer(),
      data_through = character(), days_until_release = integer()
    )
  }
  write(
    toJSON(list(vintages = vintages_out), auto_unbox = TRUE, pretty = TRUE, na = "null"),
    file.path(target_dir, "nowcasts.json")
  )

  # --- 4. indicators.json ---
  long_df <- master$long
  indicators_list <- lapply(names(INDICATOR_ID_MAP), function(r_id) {
    json_id <- unname(INDICATOR_ID_MAP[[r_id]])
    meta    <- INDICATOR_META[[json_id]]
    group   <- Find(function(g) json_id %in% INDICATOR_GROUPS[[g]], names(INDICATOR_GROUPS))

    series_df <- long_df |>
      filter(indicator_id == r_id) |>
      arrange(date) |>
      transmute(
        date  = format(date, "%Y-%m"),
        value = round(value, 3)
      )

    list(
      id     = json_id,
      name   = meta$name,
      group  = group,
      unit   = meta$unit,
      source = meta$source,
      series = series_df
    )
  })
  write(
    toJSON(list(indicators = indicators_list), auto_unbox = TRUE, pretty = TRUE, na = "null"),
    file.path(target_dir, "indicators.json")
  )

  # --- 5. performance.json ---
  # For each target quarter that has both a final nowcast AND a published actual,
  # compute level-error (nowcast_value − actual_value) and percent-error. Aggregate
  # to MAE / RMSE / directional hit rate.
  perf_obj <- local({
    if (nrow(vintages_out) == 0 || nrow(gdp_wide) == 0) {
      return(list(
        mae_millions = 0, mae_pct = 0, rmse_millions = 0,
        hit_rate_direction = 0, errors = list()
      ))
    }
    finals <- vintages_out |>
      group_by(target_quarter) |>
      slice_max(run_date, n = 1, with_ties = FALSE) |>
      ungroup()

    gdp_match <- gdp_wide |>
      transmute(target_quarter = quarter, actual = value, actual_qoq = qoq_pct)

    paired <- finals |>
      inner_join(gdp_match, by = "target_quarter")

    if (nrow(paired) == 0) {
      return(list(
        mae_millions = 0, mae_pct = 0, rmse_millions = 0,
        hit_rate_direction = 0, errors = list()
      ))
    }

    paired <- paired |>
      mutate(
        error_millions = point - actual,
        error_pct      = (point - actual) / actual * 100,
        direction_ok   = sign(qoq_growth_pct) == sign(actual_qoq)
      ) |>
      arrange(target_quarter)

    errors_df <- paired |>
      transmute(
        target_quarter,
        final_nowcast  = round(point),
        actual         = round(actual),
        error_millions = round(error_millions),
        error_pct      = round(error_pct, 2)
      )

    list(
      mae_millions       = round(mean(abs(paired$error_millions))),
      mae_pct            = round(mean(abs(paired$error_pct)), 2),
      rmse_millions      = round(sqrt(mean(paired$error_millions^2))),
      hit_rate_direction = round(mean(paired$direction_ok, na.rm = TRUE), 2),
      errors             = errors_df
    )
  })
  write(
    toJSON(perf_obj, auto_unbox = TRUE, pretty = TRUE, na = "null"),
    file.path(target_dir, "performance.json")
  )

  message(sprintf("✓ Emitted 5 JSON files to %s", normalizePath(target_dir)))
  invisible(NULL)
}

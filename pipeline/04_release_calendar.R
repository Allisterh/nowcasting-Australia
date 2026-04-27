#### Australian GDP Nowcasting - Release Calendar ####
# Purpose: Track ABS data release schedule and manage ragged edge
# Author: James Wilson
# Date: 2025-12-30

#### Load dependencies ####
library(dplyr)
library(tidyr)
library(tibble)
library(stringr)
library(lubridate)
library(glue)

#### Load component metadata ####
component_metadata <- readRDS("seed/component_metadata.rds")
indicator_mapping <- component_metadata$indicators

#### Define ABS Release Calendar ####

# Typical ABS release schedule (approximate - adjust based on actual patterns)
# Most ABS monthly data is released ~30 days after reference month
# GDP is released ~60 days after reference quarter

abs_release_schedule <- tribble(
  ~indicator_id, ~release_day_of_month, ~release_lag_days, ~release_frequency,

  # Labour Force (released ~2 weeks after reference month)
  "employment", 15, 15, "monthly",
  "unemp_rate", 15, 15, "monthly",
  "participation", 15, 15, "monthly",
  "hours_worked", 15, 15, "monthly",

  # Retail Trade (released ~30 days after reference month)
  "household_spending", 30, 30, "monthly",

  # International Trade (released ~6 weeks after reference month).
  # Master splits goods (monthly) from services (quarterly, published with
  # the National Accounts). Use the same ~45-day lag for all four; services
  # are really longer, but the master's quarterly services row is aligned to
  # quarter-end so the lag only matters for the monthly goods rows.
  "exports_goods", 7, 45, "monthly",
  "imports_goods", 7, 45, "monthly",
  "exports_servs", 7, 62, "quarterly",  # BoP 5302.0: ~62-63 days post quarter-end
  "imports_servs", 7, 62, "quarterly",

  # Building Approvals (released ~30 days after reference month)
  "building_app", 30, 30, "monthly",

  # Consumer confidence (OECD via FRED) — typically released within days.
  "cons_conf", 5, 5, "monthly",

  # NAB Business Confidence — 2nd Tuesday of following month (~8-14 days
  # after reference month-end, avg ≈ 11). Was 5 days; too aggressive.
  "bus_conf", 11, 11, "monthly",

  # GDP (ABS 5206.0) — Q4 2025 released 2026-03-05 = 64d after quarter-end.
  "gdp_quarterly", 5, 64, "quarterly"
)

message("ABS Release Schedule:")
print(abs_release_schedule)

#### Release Date Calculation Functions ####

#' Calculate expected release date for a data point.
#'
#' Convention: lag days are measured from the END of the reference period.
#' Master stores `reference_date` as first-of-month (for monthly series) or
#' first of the last month of the quarter (for quarterly series). So:
#'   monthly    → anchor = ceiling_date(reference_date, "month") - 1 day
#'                        = end of the reference month (e.g. Feb 28 for Feb)
#'   quarterly  → anchor = ceiling_date(reference_date, "quarter") - 1 day
#'                        = end of the reference quarter (e.g. Dec 31 for Q4)
#' Then release = anchor + lag_days.
#'
#' This matches the end-of-period convention the lag values (15, 30, 45, 62…)
#' were calibrated against and keeps `get_available_data` in sync with the
#' release-date logic in pipeline/04_emit_json.R.
#'
#' @param reference_date Date of the economic activity.
#' @param indicator_id Indicator identifier.
#' @return Expected release date.
calculate_release_date <- function(reference_date, indicator_id) {
  schedule <- abs_release_schedule |>
    filter(indicator_id == !!indicator_id)

  if (nrow(schedule) == 0) {
    warning(glue("No release schedule found for {indicator_id}"))
    # Default: 30 days after month-end of the reference period.
    anchor <- ceiling_date(reference_date, "month") - days(1)
    return(anchor + days(30))
  }

  lag_days <- schedule$release_lag_days[1]
  freq     <- schedule$release_frequency[1]
  anchor   <- if (isTRUE(freq == "quarterly")) {
    ceiling_date(reference_date, "quarter") - days(1)
  } else {
    ceiling_date(reference_date, "month") - days(1)
  }
  release_date <- anchor + days(lag_days)

  return(release_date)
}

#' Get data available as of a specific date
#'
#' @param master_data Master dataset (wide or long format)
#' @param as_of_date The date for which to filter available data
#' @param format Format of master_data ("wide" or "long")
#' @return Filtered dataset with only data released by as_of_date
get_available_data <- function(master_data,
                                as_of_date = Sys.Date(),
                                format = "wide") {
  message(glue("\nFiltering data available as of: {as_of_date}"))

  if (format == "long") {
    # Long format: filter by calculating release date for each observation
    filtered <- master_data |>
      rowwise() |>
      mutate(
        release_date = calculate_release_date(date, indicator_id)
      ) |>
      ungroup() |>
      filter(release_date <= as_of_date) |>
      select(-release_date)

    message(glue("  → {nrow(filtered)} observations available"))
    return(filtered)
  } else if (format == "wide") {
    # Wide format: more complex - need to filter each column separately
    # This is important for the ragged edge problem

    # Get long format first
    long_data <- master_data |>
      pivot_longer(
        cols = -date,
        names_to = "indicator_id",
        values_to = "value"
      )

    # Filter based on release dates
    filtered_long <- long_data |>
      rowwise() |>
      mutate(
        release_date = calculate_release_date(date, indicator_id)
      ) |>
      ungroup() |>
      filter(release_date <= as_of_date) |>
      select(-release_date)

    # Convert back to wide
    filtered_wide <- filtered_long |>
      pivot_wider(
        names_from = indicator_id,
        values_from = value
      )

    n_obs <- sum(!is.na(filtered_long$value))
    message(glue("  → {n_obs} observations available across all indicators"))

    return(filtered_wide)
  } else {
    stop("format must be 'wide' or 'long'")
  }
}

#' Create ragged edge visualization
#'
#' @param master_data Master dataset
#' @param as_of_date Reference date
#' @return Summary of data availability by indicator
summarize_data_availability <- function(master_data, as_of_date = Sys.Date()) {
  message("\n=== Data Availability Summary ===\n")

  # Get long format
  if ("date" %in% names(master_data) && length(names(master_data)) > 2) {
    long_data <- master_data |>
      pivot_longer(
        cols = -date,
        names_to = "indicator_id",
        values_to = "value"
      )
  } else {
    long_data <- master_data
  }

  # Calculate availability for each indicator
  availability <- long_data |>
    filter(!is.na(value)) |>
    group_by(indicator_id) |>
    summarise(
      latest_ref_date = max(date),
      n_observations = n(),
      .groups = "drop"
    ) |>
    rowwise() |>
    mutate(
      expected_release = calculate_release_date(latest_ref_date, indicator_id),
      is_available = expected_release <= as_of_date
    ) |>
    ungroup() |>
    arrange(desc(latest_ref_date))

  print(availability)

  # Count available vs not yet released
  n_available <- sum(availability$is_available)
  n_total <- nrow(availability)

  message(glue("\n{n_available}/{n_total} indicators have latest data released"))

  return(availability)
}

#### Backtesting Support ####

#' Generate sequence of dates for backtesting
#'
#' @param start_date Start of backtest period
#' @param end_date End of backtest period
#' @param frequency Frequency of nowcast updates ("daily", "weekly", "monthly")
#' @return Vector of dates
generate_backtest_dates <- function(start_date,
                                     end_date,
                                     frequency = "weekly") {
  if (frequency == "daily") {
    dates <- seq.Date(
      from = as.Date(start_date),
      to = as.Date(end_date),
      by = "day"
    )
  } else if (frequency == "weekly") {
    dates <- seq.Date(
      from = as.Date(start_date),
      to = as.Date(end_date),
      by = "week"
    )
  } else if (frequency == "monthly") {
    dates <- seq.Date(
      from = as.Date(start_date),
      to = as.Date(end_date),
      by = "month"
    )
  } else {
    stop("frequency must be 'daily', 'weekly', or 'monthly'")
  }

  return(dates)
}

#' Create backtest dataset for a specific date
#'
#' @param master_data Full master dataset
#' @param backtest_date Date to simulate being "today"
#' @return Dataset filtered to only include data available as of backtest_date
create_backtest_snapshot <- function(master_data, backtest_date) {
  message(glue("\nCreating backtest snapshot for: {backtest_date}"))

  # Filter to data available as of backtest date
  snapshot <- get_available_data(
    master_data,
    as_of_date = backtest_date,
    format = "wide"
  )

  return(snapshot)
}

#### Real-Time Data Tracking ####

#' Track which indicators have been updated recently
#'
#' @param lookback_days Number of days to look back for releases
#' @return Summary of recent data releases
track_recent_releases <- function(lookback_days = 7) {
  message(glue("\n=== Data Releases in Last {lookback_days} Days ===\n"))

  cutoff_date <- Sys.Date() - days(lookback_days)

  # Check cache files for modification dates
  cache_dir <- ".cache/abs_raw"

  if (!dir.exists(cache_dir)) {
    message("No cached data found")
    return(NULL)
  }

  cache_files <- list.files(cache_dir, pattern = "\\.rds$", full.names = TRUE)

  if (length(cache_files) == 0) {
    message("No cached data files found")
    return(NULL)
  }

  recent_updates <- tibble(
    file = cache_files,
    modified = file.mtime(cache_files) |> as.Date()
  ) |>
    filter(modified >= cutoff_date) |>
    mutate(
      series_id = str_extract(basename(file), "^[^.]+")
    ) |>
    arrange(desc(modified))

  if (nrow(recent_updates) > 0) {
    message(glue("Found {nrow(recent_updates)} recently updated series:"))
    print(recent_updates)
  } else {
    message("No data updated in the specified period")
  }

  return(recent_updates)
}

#' Calculate "news" - how much each data release changed the available data
#'
#' @param indicator_id Indicator that was just released
#' @param new_value New data value
#' @param previous_data Previous dataset
#' @return Impact of the new data release
calculate_data_news <- function(indicator_id, new_value, previous_data) {
  # This is a placeholder - will be more sophisticated in 06_generate_nowcast.R
  # where we calculate how much the nowcast changed due to new data

  message(glue("New data for {indicator_id}: {new_value}"))

  return(list(
    indicator = indicator_id,
    new_value = new_value,
    impact = NA # To be calculated with nowcast update
  ))
}

#### Example Usage ####

# Example: Check what data is available today
# master_data <- readRDS(".cache/processed/master_dataset_wide.rds")
# available_today <- get_available_data(master_data, as_of_date = Sys.Date())
# availability_summary <- summarize_data_availability(master_data, Sys.Date())

# Example: Create backtest snapshot for a historical date
# backtest_snapshot <- create_backtest_snapshot(master_data, as.Date("2023-06-15"))

# Example: Generate backtest dates for past year
# backtest_dates <- generate_backtest_dates(
#   start_date = "2023-01-01",
#   end_date = "2023-12-31",
#   frequency = "weekly"
# )

# Example: Check recent data releases
# recent <- track_recent_releases(lookback_days = 7)

#### Save release calendar ####

saveRDS(abs_release_schedule, ".cache/processed/release_schedule.rds")
message("\nRelease schedule saved to: .cache/processed/release_schedule.rds")

#### Notes ####

message("\n=== Release Calendar Script Ready ===")
message("\nKey functions:")
message("  - get_available_data() - Filter to data available as of specific date")
message("  - summarize_data_availability() - Check what's available now")
message("  - generate_backtest_dates() - Create dates for historical evaluation")
message("  - create_backtest_snapshot() - Get historical data snapshot")
message("  - track_recent_releases() - See what updated recently")
message("\nThis enables:")
message("  1. Real-time nowcasting with ragged edge data")
message("  2. Backtesting with historically available data only")
message("  3. Tracking impact of new data releases")

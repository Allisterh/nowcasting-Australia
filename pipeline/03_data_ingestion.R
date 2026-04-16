#### Australian GDP Nowcasting - Data Ingestion ####
# Purpose: Fetch and process ABS data via readabs package
# Author: James Wilson
# Date: 2025-12-30

#### Load dependencies ####
library(tidyverse)
library(readabs)
library(lubridate)
library(janitor)
library(glue)

#### Load component metadata ####
component_metadata <- readRDS("seed/component_metadata.rds")
indicator_mapping <- component_metadata$indicators

#### Core Data Fetching Functions ####

#' Fetch ABS indicator using readabs package
#'
#' @param series_id ABS series ID (e.g., "A2325807X")
#' @param table_no ABS table number (e.g., "5206.0")
#' @param start_date Start date for data (default: "2000-01-01")
#' @param use_cache Use cached data if available (default: TRUE)
#' @return Tibble with standardized columns: date, value, series_id, series_name
fetch_abs_indicator <- function(series_id,
                                 table_no = NULL,
                                 start_date = "2000-01-01",
                                 use_cache = TRUE) {
  # Check if series_id is valid
  if (is.na(series_id) || is.null(series_id)) {
    warning("Series ID is NA or NULL - skipping")
    return(NULL)
  }

  message(glue("Fetching ABS series: {series_id}"))

  # Define cache file path
  cache_file <- glue(".cache/abs_raw/{series_id}.rds")

  # Check cache
  if (use_cache && file.exists(cache_file)) {
    message("  → Loading from cache")
    data <- readRDS(cache_file)
    return(data)
  }

  # Fetch data from ABS
  tryCatch(
    {
      if (!is.null(table_no)) {
        # Fetch by table number and series ID
        raw_data <- read_abs(cat_no = table_no, series_id = series_id)
      } else {
        # Fetch by series ID only
        raw_data <- read_abs_series(series_id)
      }

      # Standardize data format
      clean_data <- raw_data |>
        select(
          date,
          value,
          series_id,
          series = series,
          unit,
          series_type
        ) |>
        rename(series_name = series) |>
        filter(date >= ymd(start_date)) |>
        arrange(date)

      # Save to cache
      dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
      saveRDS(clean_data, cache_file)
      message(glue("  → Cached to {cache_file}"))

      return(clean_data)
    },
    error = function(e) {
      warning(glue("Error fetching series {series_id}: {e$message}"))
      return(NULL)
    }
  )
}

#' Clean and standardize ABS data
#'
#' @param raw_data Raw data from readabs
#' @return Tibble with cleaned and standardized format
clean_abs_data <- function(raw_data) {
  if (is.null(raw_data) || nrow(raw_data) == 0) {
    return(NULL)
  }

  clean_data <- raw_data |>
    # Ensure date is proper date type
    mutate(date = ymd(date)) |>
    # Remove any NA values
    filter(!is.na(value), !is.na(date)) |>
    # Sort by date
    arrange(date) |>
    # Remove duplicates (keep latest if multiple entries for same date)
    distinct(date, series_id, .keep_all = TRUE)

  return(clean_data)
}

#' Aggregate higher frequency data to monthly
#'
#' @param data Data with potentially weekly or daily frequency
#' @param target_freq Target frequency ("monthly" or "quarterly")
#' @return Aggregated data
aggregate_to_frequency <- function(data, target_freq = "monthly") {
  if (is.null(data) || nrow(data) == 0) {
    return(NULL)
  }

  if (target_freq == "monthly") {
    aggregated <- data |>
      mutate(
        year = year(date),
        month = month(date)
      ) |>
      group_by(year, month, series_id, series_name) |>
      summarise(
        value = mean(value, na.rm = TRUE),
        date = floor_date(first(date), "month"),
        .groups = "drop"
      ) |>
      select(date, value, series_id, series_name)
  } else if (target_freq == "quarterly") {
    aggregated <- data |>
      mutate(
        year = year(date),
        quarter = quarter(date)
      ) |>
      group_by(year, quarter, series_id, series_name) |>
      summarise(
        value = mean(value, na.rm = TRUE),
        date = floor_date(first(date), "quarter"),
        .groups = "drop"
      ) |>
      select(date, value, series_id, series_name)
  } else {
    stop("target_freq must be 'monthly' or 'quarterly'")
  }

  return(aggregated)
}

#' Handle data revisions by tracking vintages
#'
#' @param series_id ABS series ID
#' @param current_data Current data snapshot
#' @return List with current data and revision history
handle_revisions <- function(series_id, current_data) {
  vintage_file <- glue(".cache/processed/vintages_{series_id}.rds")

  # Load previous vintages if they exist
  if (file.exists(vintage_file)) {
    vintages <- readRDS(vintage_file)
  } else {
    vintages <- list()
  }

  # Add current vintage with timestamp
  vintage_date <- Sys.Date()
  vintages[[as.character(vintage_date)]] <- current_data

  # Save updated vintages
  dir.create(dirname(vintage_file), recursive = TRUE, showWarnings = FALSE)
  saveRDS(vintages, vintage_file)

  return(list(
    current = current_data,
    vintages = vintages
  ))
}

#### Batch Data Fetching ####

#' Fetch all indicators defined in component metadata
#'
#' @param use_cache Use cached data if available
#' @param start_date Start date for historical data
#' @return List of data tibbles by indicator_id
fetch_all_abs_indicators <- function(use_cache = TRUE,
                                      start_date = "2000-01-01") {
  message("\n=== Fetching All ABS Indicators ===\n")

  indicators <- component_metadata$indicators

  # Initialize storage
  indicator_data <- list()

  # Fetch each indicator
  for (i in seq_len(nrow(indicators))) {
    ind <- indicators[i, ]

    message(glue("\n[{i}/{nrow(indicators)}] {ind$indicator_name}"))

    # Check if series ID is populated
    if (is.na(ind$abs_series_id)) {
      message("  → Series ID not yet populated - skipping")
      next
    }

    # Fetch data
    data <- fetch_abs_indicator(
      series_id = ind$abs_series_id,
      start_date = start_date,
      use_cache = use_cache
    )

    # Clean data
    if (!is.null(data)) {
      data <- clean_abs_data(data)

      # Add indicator metadata
      data <- data |>
        mutate(
          indicator_id = ind$indicator_id,
          component_id = ind$component_id,
          frequency = ind$frequency
        )

      indicator_data[[ind$indicator_id]] <- data
    }
  }

  message(glue("\n✓ Fetched {length(indicator_data)} indicators"))

  return(indicator_data)
}

#' Combine all indicators into master dataset
#'
#' @param indicator_data List of indicator data tibbles
#' @return Wide-format tibble with all indicators
build_master_dataset <- function(indicator_data) {
  message("\n=== Building Master Dataset ===\n")

  if (length(indicator_data) == 0) {
    warning("No indicator data available")
    return(NULL)
  }

  # Combine all indicators
  combined <- indicator_data |>
    bind_rows(.id = "indicator_id")

  # Create wide format for modeling
  # First, remove duplicates by taking the mean if there are multiple values
  wide_data <- combined |>
    select(date, indicator_id, value) |>
    group_by(date, indicator_id) |>
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(
      names_from = indicator_id,
      values_from = value
    ) |>
    arrange(date)

  message(glue("Master dataset: {nrow(wide_data)} time periods × {ncol(wide_data) - 1} indicators"))

  # Save master dataset
  saveRDS(combined, ".cache/processed/master_dataset_long.rds")
  saveRDS(wide_data, ".cache/processed/master_dataset_wide.rds")

  message("Saved to: .cache/processed/")

  return(list(
    long = combined,
    wide = wide_data
  ))
}

#### Data Quality Checks ####

#' Check data quality and completeness
#'
#' @param master_data Master dataset (wide format)
#' @return Summary of data quality issues
check_data_quality <- function(master_data) {
  message("\n=== Data Quality Report ===\n")

  # Check for missing values
  missing_summary <- master_data |>
    summarise(across(-date, ~ sum(is.na(.)))) |>
    pivot_longer(everything(), names_to = "indicator", values_to = "n_missing") |>
    filter(n_missing > 0) |>
    arrange(desc(n_missing))

  if (nrow(missing_summary) > 0) {
    message("Missing values detected:")
    print(missing_summary)
  } else {
    message("✓ No missing values")
  }

  # Check for recent data availability
  latest_dates <- master_data |>
    summarise(across(-date, ~ max(date[!is.na(.)], na.rm = TRUE))) |>
    pivot_longer(everything(), names_to = "indicator", values_to = "latest_date") |>
    arrange(latest_date)

  message("\nLatest available data by indicator:")
  print(latest_dates)

  # Check frequency consistency
  date_gaps <- master_data |>
    mutate(date_diff = as.numeric(difftime(date, lag(date), units = "days"))) |>
    pull(date_diff) |>
    na.omit() |>
    table()

  message("\nDate gaps (days):")
  print(date_gaps)

  return(list(
    missing = missing_summary,
    latest = latest_dates,
    gaps = date_gaps
  ))
}

#### Example Usage ####

# Example: Fetch a single indicator
# gdp_data <- fetch_abs_indicator(
#   series_id = "A2325807X",  # GDP chain volume (example)
#   table_no = "5206.0",
#   start_date = "2000-01-01"
# )

# Example: Fetch all indicators (once series IDs are populated)
# all_data <- fetch_all_abs_indicators()
# master <- build_master_dataset(all_data)
# quality <- check_data_quality(master$wide)

#### Notes ####

message("\n=== Data Ingestion Script Ready ===")
message("\nNext steps:")
message("1. Populate ABS series IDs in 02_define_gdp_components.R")
message("2. Test fetching a single series with fetch_abs_indicator()")
message("3. Run fetch_all_abs_indicators() to get all data")
message("4. Check data quality with check_data_quality()")
message("\nExample series IDs to try:")
message("  - GDP: A2325807X (Table 5206.0)")
message("  - Employment: A84423127L (Table 6202.0)")
message("  - Retail: A3349873A (Table 8501.0)")

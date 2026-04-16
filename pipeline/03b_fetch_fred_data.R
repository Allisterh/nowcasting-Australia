#### Australian GDP Nowcasting - FRED Data Integration ####
# Purpose: Fetch supplementary indicators from FRED (St. Louis Fed)
# Author: James Wilson
# Date: 2026-01-01

#### Load dependencies ####
library(tidyverse)
library(lubridate)
library(glue)

# Note: We'll use direct CSV download from FRED since fredr package requires API key
# Alternative: Install fredr package and set API key for programmatic access

#### FRED Data Fetching Functions ####

#' Fetch FRED series via CSV download
#'
#' @param series_id FRED series ID (e.g., "CSCICP02AUM460S")
#' @param start_date Start date for data (default: "2000-01-01")
#' @param use_cache Use cached data if available (default: TRUE)
#' @return Tibble with standardized columns: date, value, series_id, series_name
fetch_fred_indicator <- function(series_id,
                                  start_date = "2000-01-01",
                                  use_cache = TRUE) {
  message(glue("Fetching FRED series: {series_id}"))

  # Define cache file path
  cache_file <- glue(".cache/fred_raw/{series_id}.rds")

  # Check cache
  if (use_cache && file.exists(cache_file)) {
    message("  → Loading from cache")
    data <- readRDS(cache_file)
    return(data)
  }

  # Construct FRED download URL
  fred_url <- glue("https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}")

  # Retry-with-backoff loop. FRED's edge occasionally resets HTTP/2 streams
  # (seen on Windows CI), which would otherwise silently wipe this indicator
  # from the model and produce a wrong nowcast.
  max_attempts <- 3
  raw_data <- NULL
  last_error <- NULL
  for (attempt in seq_len(max_attempts)) {
    raw_data <- tryCatch(
      read_csv(fred_url, show_col_types = FALSE),
      error = function(e) e,
      warning = function(w) w
    )
    if (!inherits(raw_data, c("error", "warning"))) break
    last_error <- raw_data
    raw_data <- NULL
    if (attempt < max_attempts) {
      backoff <- 5 * attempt
      message(glue("  → attempt {attempt}/{max_attempts} failed ({conditionMessage(last_error)}); retrying in {backoff}s..."))
      Sys.sleep(backoff)
    }
  }
  if (is.null(raw_data)) {
    stop(glue(
      "FRED fetch for {series_id} failed after {max_attempts} attempts: ",
      "{conditionMessage(last_error)}"
    ))
  }

  # Standardize column names (FRED uses "observation_date" and series_id as column names)
  colnames(raw_data) <- c("date", "value")

  # Convert date to Date type
  raw_data <- raw_data |>
    mutate(date = ymd(date))

  # Clean and filter data
  clean_data <- raw_data |>
    mutate(
      series_id = series_id,
      series_name = paste0("FRED: ", series_id),
      unit = "Index",
      series_type = "FRED"
    ) |>
    filter(
      date >= ymd(start_date),
      !is.na(value)
    ) |>
    arrange(date)

  # Save to cache
  dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
  saveRDS(clean_data, cache_file)
  message(glue("  → Cached to {cache_file}"))
  message(glue("  → Fetched {nrow(clean_data)} observations from {min(clean_data$date)} to {max(clean_data$date)}"))

  return(clean_data)
}

#' Fetch all FRED indicators for nowcasting
#'
#' @param use_cache Use cached data if available
#' @param start_date Start date for historical data
#' @return List of data tibbles by indicator_id
fetch_all_fred_indicators <- function(use_cache = TRUE,
                                       start_date = "2000-01-01") {
  message("\n=== Fetching FRED Indicators ===\n")

  # Define FRED series to fetch
  fred_series <- tribble(
    ~indicator_id, ~series_id, ~indicator_name, ~component_id, ~frequency,
    "cons_conf", "CSCICP02AUM460S", "Consumer Confidence (OECD)", "C_hh", "monthly"
  )

  # Initialize storage
  fred_data <- list()

  # Fetch each series
  for (i in seq_len(nrow(fred_series))) {
    series <- fred_series[i, ]

    message(glue("\n[{i}/{nrow(fred_series)}] {series$indicator_name}"))

    # Fetch data
    data <- fetch_fred_indicator(
      series_id = series$series_id,
      start_date = start_date,
      use_cache = use_cache
    )

    # Add indicator metadata
    if (!is.null(data)) {
      data <- data |>
        mutate(
          indicator_id = series$indicator_id,
          component_id = series$component_id,
          frequency = series$frequency
        )

      fred_data[[series$indicator_id]] <- data
    }
  }

  message(glue("\n✓ Fetched {length(fred_data)} FRED indicators"))

  # Guard against silent indicator drops. fetch_fred_indicator() should now
  # stop() on failure after retries, but belt-and-suspenders: if any series
  # ended up NULL, halt loudly rather than let the model run with fewer
  # indicators than expected.
  expected <- nrow(fred_series)
  if (length(fred_data) != expected) {
    stop(glue(
      "FRED fetch incomplete: got {length(fred_data)} of {expected} series. ",
      "Missing: {paste(setdiff(fred_series$indicator_id, names(fred_data)), collapse = ', ')}"
    ))
  }

  return(fred_data)
}

#' Combine ABS and FRED data
#'
#' @param abs_data List of ABS indicator data
#' @param fred_data List of FRED indicator data
#' @return Combined list of all indicators
combine_abs_fred_data <- function(abs_data, fred_data) {
  # Combine the two lists
  all_data <- c(abs_data, fred_data)

  message(glue("\nCombined {length(abs_data)} ABS + {length(fred_data)} FRED = {length(all_data)} total indicators"))

  return(all_data)
}

#### Example Usage ####

if (FALSE) {
  # Fetch FRED data only
  fred_data <- fetch_all_fred_indicators(use_cache = FALSE)

  # Load ABS data
  source("03_data_ingestion.R")
  abs_data <- fetch_all_abs_indicators(use_cache = TRUE)

  # Combine both sources
  all_indicators <- combine_abs_fred_data(abs_data, fred_data)

  # Build master dataset with all indicators
  master <- build_master_dataset(all_indicators)

  # Save
  saveRDS(master, ".cache/processed/master_dataset_wide.rds")
}

message("\n=== FRED Data Integration Ready ===\n")
message("Functions available:")
message("  - fetch_fred_indicator() - Fetch single FRED series")
message("  - fetch_all_fred_indicators() - Fetch all configured FRED series")
message("  - combine_abs_fred_data() - Merge ABS and FRED data")
message("\nConfigured FRED series:")
message("  - CSCICP02AUM460S: OECD Consumer Confidence for Australia")
message("\nTo add this to your nowcast:")
message("  1. source('03b_fetch_fred_data.R')")
message("  2. fred_data <- fetch_all_fred_indicators()")
message("  3. Combine with ABS data and re-run model")

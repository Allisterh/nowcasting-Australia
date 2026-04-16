#### Australian GDP Nowcasting - Vintage Tracking System ####
# Purpose: Save and track historical nowcast "vintages" to visualize evolution
# Author: James Wilson
# Date: 2026-01-02
#
# What this does:
#   1. Automatically saves each nowcast run with unique timestamp
#   2. Tracks all vintages in human-readable CSV index
#   3. Enables comparison of vintages over time
#   4. Supports visualization of nowcast evolution

library(tidyverse)
library(lubridate)
library(glue)

# Base directory for vintages
VINTAGE_BASE_DIR <- ".cache/model_output/vintages"
VINTAGE_CSV <- file.path(VINTAGE_BASE_DIR, "vintage_tracking.csv")


#### Core Function 1: Save Vintage ####

#' Save a nowcast vintage with complete metadata
#'
#' @param nowcast_result Output from generate_nowcast()
#' @param model Estimated DFM model object
#' @param master_data Current master dataset (wide format)
#' @param all_indicators List of indicator objects
#' @return List with vintage_id, file_path, metadata
#'
#' @examples
#' vintage_info <- save_vintage(nowcast, model, master$wide, all_indicators)
save_vintage <- function(nowcast_result,
                         model,
                         master_data,
                         all_indicators) {

  # Generate unique vintage ID with timestamp
  run_timestamp <- Sys.time()
  vintage_id <- format(run_timestamp, "vintage_%Y%m%d_%H%M%S")

  # Extract target quarter for organization
  target_quarter <- nowcast_result$target_quarter
  quarter_folder <- gsub(" ", "", target_quarter)  # "2026 Q4" -> "2026Q4"

  # Create directory structure
  quarter_dir <- file.path(VINTAGE_BASE_DIR, quarter_folder)
  if (!dir.exists(quarter_dir)) {
    dir.create(quarter_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Get previous vintage for comparison (if exists)
  previous_vintage <- tryCatch(
    get_latest_vintage(target_quarter),
    error = function(e) NULL
  )

  # Create data snapshot
  data_snapshot <- create_data_snapshot(
    master_data = master_data,
    all_indicators = all_indicators,
    previous_snapshot = if (!is.null(previous_vintage)) previous_vintage$data_snapshot else NULL
  )

  # Extract model diagnostics
  model_diagnostics <- extract_model_diagnostics(model)

  # Create vintage comparison
  vintage_comparison <- if (!is.null(previous_vintage)) {
    list(
      previous_vintage_id = previous_vintage$vintage_metadata$vintage_id,
      nowcast_change_dollars = nowcast_result$nowcast_value - previous_vintage$nowcast_value,
      qoq_growth_change_pp = nowcast_result$qoq_growth - previous_vintage$qoq_growth,
      yoy_growth_change_pp = nowcast_result$yoy_growth - previous_vintage$yoy_growth,
      days_between = as.numeric(difftime(run_timestamp, previous_vintage$vintage_metadata$run_timestamp, units = "days")),
      new_data_received = data_snapshot$indicators_updated_since_last
    )
  } else {
    list(
      previous_vintage_id = NA_character_,
      nowcast_change_dollars = NA_real_,
      qoq_growth_change_pp = NA_real_,
      yoy_growth_change_pp = NA_real_,
      days_between = NA_real_,
      new_data_received = character(0)
    )
  }

  # Build complete vintage object
  vintage <- c(
    # Preserve all existing nowcast fields
    nowcast_result,

    # Add vintage metadata
    list(
      vintage_metadata = list(
        vintage_id = vintage_id,
        run_timestamp = run_timestamp,
        data_as_of_date = Sys.Date(),
        model_version = "v1.0"
      ),

      # Data availability snapshot
      data_snapshot = data_snapshot,

      # Model diagnostics
      model_diagnostics = model_diagnostics,

      # Comparison to previous
      vintage_comparison = vintage_comparison
    )
  )

  # Save vintage RDS file
  vintage_path <- file.path(quarter_dir, paste0(vintage_id, ".rds"))
  saveRDS(vintage, vintage_path)

  # Update CSV tracking
  vintage_info <- list(
    vintage_id = vintage_id,
    file_path = vintage_path,
    run_timestamp = run_timestamp,
    target_quarter = target_quarter,
    nowcast_value = nowcast_result$nowcast_value,
    qoq_growth = nowcast_result$qoq_growth,
    yoy_growth = nowcast_result$yoy_growth,
    latest_actual_value = nowcast_result$latest_actual_value,
    n_indicators = data_snapshot$indicators_available,
    n_indicators_updated = length(data_snapshot$indicators_updated_since_last),
    log_likelihood = model_diagnostics$log_likelihood
  )

  update_vintage_tracking_csv(vintage_info)

  return(vintage_info)
}


#### Core Function 2: Load Vintage ####

#' Load a specific vintage by ID or date
#'
#' @param vintage_id Vintage ID (e.g., "vintage_20260102_143022")
#' @param date Date to find nearest vintage (alternative to vintage_id)
#' @param target_quarter Which quarter (required if using date)
#' @return Vintage object (list)
#'
#' @examples
#' # Load by ID
#' vintage <- load_vintage(vintage_id = "vintage_20260102_143022")
#'
#' # Load nearest to date
#' vintage <- load_vintage(date = as.Date("2026-01-02"), target_quarter = "2026 Q4")
load_vintage <- function(vintage_id = NULL,
                         date = NULL,
                         target_quarter = NULL) {

  # Load tracking CSV
  tracking <- read_vintage_tracking_csv()

  if (!is.null(vintage_id)) {
    # Load by exact ID
    vintage_row <- tracking %>% filter(vintage_id == !!vintage_id)

    if (nrow(vintage_row) == 0) {
      stop("Vintage not found: ", vintage_id)
    }

    file_path <- vintage_row$file_path[1]

  } else if (!is.null(date) && !is.null(target_quarter)) {
    # Load nearest to date
    date <- as.Date(date)
    vintage_row <- tracking %>%
      filter(target_quarter == !!target_quarter) %>%
      mutate(date_diff = abs(as.numeric(difftime(as.Date(run_timestamp), date, units = "days")))) %>%
      arrange(date_diff) %>%
      slice_head(n = 1)

    if (nrow(vintage_row) == 0) {
      stop("No vintages found for quarter: ", target_quarter)
    }

    file_path <- vintage_row$file_path[1]

  } else {
    stop("Must provide either vintage_id OR (date + target_quarter)")
  }

  # Load and return vintage
  vintage <- readRDS(file_path)
  return(vintage)
}


#### Core Function 3: Get Vintage History ####

#' Get all vintages for a target quarter
#'
#' @param target_quarter Quarter string (e.g., "2026 Q4")
#' @param include_actual Include actual GDP if released (default: TRUE)
#' @return Tibble with vintage history ready for visualization
#'
#' @examples
#' history <- get_vintage_history("2026 Q4")
#' print(history)
get_vintage_history <- function(target_quarter, include_actual = TRUE) {

  # Load tracking CSV
  tracking <- read_vintage_tracking_csv()

  # Filter to target quarter
  history <- tracking %>%
    filter(target_quarter == !!target_quarter) %>%
    arrange(run_timestamp) %>%
    mutate(
      run_date = as.Date(run_timestamp),
      nowcast_change = nowcast_value - lag(nowcast_value),
      qoq_change = qoq_growth - lag(qoq_growth),
      cumulative_change = nowcast_value - first(nowcast_value)
    )

  # Optionally add actual GDP if released
  if (include_actual) {
    # Try to load master dataset to get actual
    tryCatch({
      master <- readRDS(".cache/processed/master_dataset_complete.rds")
      actual_gdp <- master$wide %>%
        filter(quarter == target_quarter) %>%
        select(gdp_quarterly) %>%
        pull()

      if (length(actual_gdp) > 0 && !is.na(actual_gdp[1])) {
        # Calculate actual growth rates
        prev_quarter_gdp <- master$wide %>%
          arrange(date) %>%
          filter(date < min(history$run_date)) %>%
          filter(!is.na(gdp_quarterly)) %>%
          slice_tail(n = 1) %>%
          pull(gdp_quarterly)

        if (length(prev_quarter_gdp) > 0) {
          actual_qoq <- ((actual_gdp[1] / prev_quarter_gdp[1]) - 1) * 100

          history <- history %>%
            mutate(
              actual_gdp = actual_gdp[1],
              actual_qoq_growth = actual_qoq,
              forecast_error = nowcast_value - actual_gdp[1],
              forecast_error_pct = ((nowcast_value / actual_gdp[1]) - 1) * 100
            )
        }
      }
    }, error = function(e) {
      # Actual not available yet - continue without it
      invisible(NULL)
    })
  }

  return(history)
}


#### Core Function 4: Compare Vintages ####

#' Compare two vintages and identify changes
#'
#' @param vintage_id_1 First vintage ID
#' @param vintage_id_2 Second vintage ID
#' @return List with comparison details
#'
#' @examples
#' comparison <- compare_vintages(
#'   vintage_id_1 = "vintage_20260102_143022",
#'   vintage_id_2 = "vintage_20260109_091534"
#' )
#' print(comparison$changes)
compare_vintages <- function(vintage_id_1, vintage_id_2) {

  # Load both vintages
  vintage1 <- load_vintage(vintage_id = vintage_id_1)
  vintage2 <- load_vintage(vintage_id = vintage_id_2)

  # Calculate changes
  changes <- list(
    nowcast_change_dollars = vintage2$nowcast_value - vintage1$nowcast_value,
    nowcast_change_pct = ((vintage2$nowcast_value / vintage1$nowcast_value) - 1) * 100,
    qoq_growth_change_pp = vintage2$qoq_growth - vintage1$qoq_growth,
    yoy_growth_change_pp = vintage2$yoy_growth - vintage1$yoy_growth,
    days_between = as.numeric(difftime(
      vintage2$vintage_metadata$run_timestamp,
      vintage1$vintage_metadata$run_timestamp,
      units = "days"
    ))
  )

  # Identify new data
  new_data <- list(
    indicators_updated = vintage2$data_snapshot$indicators_updated_since_last,
    n_indicators_updated = length(vintage2$data_snapshot$indicators_updated_since_last)
  )

  # Model changes
  model_changes <- list(
    log_likelihood_change = vintage2$model_diagnostics$log_likelihood - vintage1$model_diagnostics$log_likelihood
  )

  return(list(
    vintage1_id = vintage_id_1,
    vintage2_id = vintage_id_2,
    changes = changes,
    new_data = new_data,
    model_changes = model_changes
  ))
}


#### Helper Function 1: Read/Create CSV ####

#' Load vintage tracking CSV or create if doesn't exist
#'
#' @return Tibble with vintage tracking data
read_vintage_tracking_csv <- function() {

  if (file.exists(VINTAGE_CSV)) {
    tracking <- read_csv(VINTAGE_CSV, show_col_types = FALSE) %>%
      mutate(
        run_timestamp = as.POSIXct(run_timestamp),
        nowcast_value = as.numeric(nowcast_value),
        qoq_growth = as.numeric(qoq_growth),
        yoy_growth = as.numeric(yoy_growth),
        latest_actual_value = as.numeric(latest_actual_value),
        data_as_of_date = as.Date(data_as_of_date),
        n_indicators = as.integer(n_indicators),
        n_indicators_updated = as.integer(n_indicators_updated),
        log_likelihood = as.numeric(log_likelihood)
      )
    return(tracking)
  } else {
    # Create new empty tracking file
    tracking <- tibble(
      vintage_id = character(),
      run_timestamp = as.POSIXct(character()),
      target_quarter = character(),
      nowcast_value = numeric(),
      qoq_growth = numeric(),
      yoy_growth = numeric(),
      latest_actual_value = numeric(),
      data_as_of_date = as.Date(character()),
      n_indicators = integer(),
      n_indicators_updated = integer(),
      log_likelihood = numeric(),
      file_path = character()
    )

    # Create directory and save
    if (!dir.exists(VINTAGE_BASE_DIR)) {
      dir.create(VINTAGE_BASE_DIR, recursive = TRUE, showWarnings = FALSE)
    }

    write_csv(tracking, VINTAGE_CSV)
    return(tracking)
  }
}


#### Helper Function 2: Update CSV ####

#' Append new vintage to tracking CSV
#'
#' @param vintage_info List with vintage metadata
update_vintage_tracking_csv <- function(vintage_info) {

  # Load existing
  tracking <- read_vintage_tracking_csv()

  # Create new row with explicit type conversions
  new_row <- tibble(
    vintage_id = as.character(vintage_info$vintage_id),
    run_timestamp = as.POSIXct(vintage_info$run_timestamp),
    target_quarter = as.character(vintage_info$target_quarter),
    nowcast_value = as.numeric(vintage_info$nowcast_value),
    qoq_growth = as.numeric(vintage_info$qoq_growth),
    yoy_growth = as.numeric(vintage_info$yoy_growth),
    latest_actual_value = as.numeric(vintage_info$latest_actual_value),
    data_as_of_date = as.Date(Sys.Date()),
    n_indicators = as.integer(vintage_info$n_indicators),
    n_indicators_updated = as.integer(vintage_info$n_indicators_updated),
    log_likelihood = as.numeric(vintage_info$log_likelihood),
    file_path = as.character(vintage_info$file_path)
  )

  # Append and save
  tracking <- bind_rows(tracking, new_row)
  write_csv(tracking, VINTAGE_CSV)

  invisible(NULL)
}


#### Helper Function 3: Create Data Snapshot ####

#' Capture current data availability snapshot
#'
#' @param master_data Master dataset (wide format)
#' @param all_indicators List of indicator objects
#' @param previous_snapshot Previous snapshot for comparison (optional)
#' @return List with data snapshot details
create_data_snapshot <- function(master_data,
                                 all_indicators,
                                 previous_snapshot = NULL) {

  # Count available indicators
  n_indicators <- length(all_indicators)

  # Get latest dates for each indicator
  # Remove date and quarter columns (if they exist) before pivoting
  latest_dates <- master_data %>%
    select(-any_of(c("quarter", "Quarter"))) %>%
    pivot_longer(cols = -date, names_to = "indicator", values_to = "value") %>%
    filter(!is.na(value)) %>%
    group_by(indicator) %>%
    summarize(latest_date = max(date, na.rm = TRUE), .groups = "drop")

  # Identify indicators updated since previous snapshot
  indicators_updated <- character()
  if (!is.null(previous_snapshot) && "latest_data_dates" %in% names(previous_snapshot)) {
    previous_dates <- previous_snapshot$latest_data_dates

    updated <- latest_dates %>%
      left_join(previous_dates, by = "indicator", suffix = c("_current", "_previous")) %>%
      filter(latest_date_current > latest_date_previous | is.na(latest_date_previous)) %>%
      pull(indicator)

    indicators_updated <- updated
  }

  return(list(
    indicators_available = n_indicators,
    indicators_updated_since_last = indicators_updated,
    latest_data_dates = latest_dates,
    snapshot_date = Sys.Date()
  ))
}


#### Helper Function 4: Extract Model Diagnostics ####

#' Extract diagnostics from DFM model
#'
#' @param model Estimated DFM model object
#' @return List with model diagnostics
extract_model_diagnostics <- function(model) {

  diagnostics <- list(
    log_likelihood = NA_real_,
    convergence_iterations = NA_integer_,
    convergence_status = "unknown"
  )

  # Try to extract log-likelihood
  tryCatch({
    if ("Res" %in% names(model) && "loglik" %in% names(model$Res)) {
      diagnostics$log_likelihood <- model$Res$loglik
    }
  }, error = function(e) invisible(NULL))

  # Try to extract convergence info
  tryCatch({
    if ("Res" %in% names(model) && "niter" %in% names(model$Res)) {
      diagnostics$convergence_iterations <- model$Res$niter
    }
  }, error = function(e) invisible(NULL))

  # Convergence status
  tryCatch({
    if ("Res" %in% names(model) && "converged" %in% names(model$Res)) {
      diagnostics$convergence_status <- if (model$Res$converged) "converged" else "not_converged"
    }
  }, error = function(e) invisible(NULL))

  return(diagnostics)
}


#### Helper Function 5: Get Latest Vintage ####

#' Get most recent vintage for a target quarter
#'
#' @param target_quarter Quarter string (e.g., "2026 Q4")
#' @return Most recent vintage object or NULL if none exist
get_latest_vintage <- function(target_quarter) {

  # Load tracking CSV
  tracking <- read_vintage_tracking_csv()

  # Get latest for target quarter
  latest_row <- tracking %>%
    filter(target_quarter == !!target_quarter) %>%
    arrange(desc(run_timestamp)) %>%
    slice_head(n = 1)

  if (nrow(latest_row) == 0) {
    return(NULL)
  }

  # Load and return vintage
  vintage <- readRDS(latest_row$file_path[1])
  return(vintage)
}


#### Accuracy Evaluation ####

ACCURACY_CSV <- file.path(VINTAGE_BASE_DIR, "accuracy_log.csv")

#' Evaluate past nowcasts against newly available GDP actuals
#'
#' Compares the final nowcast for each target quarter against actual GDP data.
#' Only evaluates quarters that have new actuals and haven't been logged yet.
#'
#' @param master_data Master dataset (wide format) with fresh GDP data
#' @return Tibble of newly evaluated quarters (invisible), or NULL if none
#'
#' @examples
#' evaluate_accuracy(master$wide)
evaluate_accuracy <- function(master_data) {

  # Get actual GDP with growth rates
  gdp_actuals <- master_data |>
    filter(!is.na(gdp_quarterly)) |>
    select(date, gdp_quarterly) |>
    arrange(date) |>
    mutate(
      quarter_label = paste0(year(date), " Q", quarter(date)),
      actual_qoq = (gdp_quarterly / lag(gdp_quarterly) - 1) * 100
    )

  # Load vintage tracking
  tracking <- read_vintage_tracking_csv()
  if (nrow(tracking) == 0) return(invisible(NULL))

  # Get the final (most recent) nowcast per target quarter
  final_nowcasts <- tracking |>
    group_by(target_quarter) |>
    slice_max(run_timestamp, n = 1) |>
    ungroup()

  # Match against actuals
  evaluated <- final_nowcasts |>
    inner_join(
      gdp_actuals |> select(quarter_label, actual_gdp = gdp_quarterly, actual_qoq),
      by = c("target_quarter" = "quarter_label")
    ) |>
    mutate(
      error_level = nowcast_value - actual_gdp,
      error_qoq_pp = qoq_growth - actual_qoq,
      evaluated_date = Sys.Date()
    ) |>
    select(
      target_quarter, nowcast_run = run_timestamp,
      nowcast_value, actual_gdp, error_level,
      nowcast_qoq = qoq_growth, actual_qoq, error_qoq_pp,
      evaluated_date
    )

  if (nrow(evaluated) == 0) return(invisible(NULL))

  # Load existing log to avoid duplicates
  if (file.exists(ACCURACY_CSV)) {
    existing <- read_csv(ACCURACY_CSV, show_col_types = FALSE)
    evaluated <- evaluated |>
      anti_join(existing, by = "target_quarter")
  }

  if (nrow(evaluated) == 0) return(invisible(NULL))

  # Write results
  if (file.exists(ACCURACY_CSV)) {
    write_csv(evaluated, ACCURACY_CSV, append = TRUE)
  } else {
    dir.create(dirname(ACCURACY_CSV), recursive = TRUE, showWarnings = FALSE)
    write_csv(evaluated, ACCURACY_CSV)
  }

  return(invisible(evaluated))
}


#### Success Message ####
cat("✓ Vintage tracking system loaded successfully\n\n")
cat("Available functions:\n")
cat("  • save_vintage() - Save a nowcast vintage\n")
cat("  • load_vintage() - Load a specific vintage\n")
cat("  • get_vintage_history() - Get all vintages for a quarter\n")
cat("  • compare_vintages() - Compare two vintages\n")
cat("  • evaluate_accuracy() - Compare past nowcasts to actuals\n\n")

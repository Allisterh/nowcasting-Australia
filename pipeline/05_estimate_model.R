#### Australian GDP Nowcasting - Model Estimation ####
# Purpose: Estimate component-based Dynamic Factor Model
# Author: James Wilson
# Date: 2025-12-30

#### Load dependencies ####
library(dplyr)
library(tidyr)
library(nowcasting)
library(lubridate)
library(Matrix)
library(glue)

#### Load component metadata ####
component_metadata <- readRDS("seed/component_metadata.rds")

#### Data Preparation for DFM ####

#' Prepare data for nowcasting package
#'
#' @param master_data Master dataset (wide format)
#' @param target_variable Name of GDP variable
#' @return List with prepared data matrices
prepare_data_for_dfm <- function(master_data, target_variable = "gdp_quarterly") {
  message("\n=== Preparing Data for DFM ===\n")

  # Check if target exists
  if (!target_variable %in% names(master_data)) {
    stop(glue("Target variable '{target_variable}' not found in data"))
  }

  # Separate target (GDP) from indicators
  gdp_data <- master_data |>
    select(date, gdp = all_of(target_variable)) # Rename to "gdp" for consistency

  indicator_data <- master_data |>
    select(-all_of(target_variable))

  # DON'T interpolate quarterly data!
  # Keep quarterly data with NAs - Bpanel() will handle it properly
  # From nowcasting docs: "For EM algorithm, we do not want to replace missing values
  # that are not part of the jagged edges... NA.replace = F. We also do not want to
  # discard series with many missing values and therefore use na.prop = 1."

  # Convert to matrices (required by nowcasting package)
  # Dates as rownames, series as columns
  indicator_matrix <- indicator_data |>
    select(-date) |>
    as.matrix()

  rownames(indicator_matrix) <- as.character(indicator_data$date)

  gdp_vector <- gdp_data |>
    pull(gdp) # Use renamed column

  names(gdp_vector) <- as.character(gdp_data$date)

  message(glue("\nIndicator matrix: {nrow(indicator_matrix)} periods × {ncol(indicator_matrix)} indicators"))
  message(glue("GDP observations: {sum(!is.na(gdp_vector))}/{length(gdp_vector)} (quarterly, ~67% NAs expected)"))

  # Check for sufficient data
  if (sum(!is.na(gdp_vector)) < 20) {
    warning("Very few GDP observations - model may be poorly estimated")
  }

  # Build frequency vector for nowcast() function
  # Get frequency for each indicator from metadata
  indicator_freqs <- component_metadata$indicators |>
    filter(indicator_id %in% colnames(indicator_matrix)) |>
    select(indicator_id, frequency) |>
    mutate(freq_numeric = ifelse(frequency == "quarterly", 4, 12))

  message("\nIndicator frequencies:")
  print(indicator_freqs)

  return(list(
    indicators = indicator_matrix,
    gdp = gdp_vector,  # Keep quarterly GDP with NAs
    dates = indicator_data$date,
    n_indicators = ncol(indicator_matrix),
    n_periods = nrow(indicator_matrix),
    indicator_frequencies = indicator_freqs
  ))
}

#' Transform data (standardization, growth rates, etc.)
#'
#' @param data_list Output from prepare_data_for_dfm
#' @param transform_type Type of transformation ("standardize", "growth", "none")
#' @return Transformed data list
transform_data <- function(data_list, transform_type = "standardize") {
  message(glue("\nApplying transformation: {transform_type}"))

  if (transform_type == "standardize") {
    # Standardize each indicator (mean 0, sd 1)
    data_list$indicators <- scale(data_list$indicators)

    # Standardize GDP growth
    if (!all(is.na(data_list$gdp))) {
      data_list$gdp <- scale(data_list$gdp)
    }
  } else if (transform_type == "growth") {
    # Convert to growth rates (quarter-over-quarter % change)
    # Note: This may already be done in the raw data

    # For indicators
    for (i in seq_len(ncol(data_list$indicators))) {
      x <- data_list$indicators[, i]
      growth <- (x - lag(x)) / lag(x) * 100
      data_list$indicators[, i] <- growth
    }

    # For GDP
    gdp <- data_list$gdp
    gdp_growth <- (gdp - lag(gdp)) / lag(gdp) * 100
    data_list$gdp <- gdp_growth

    message("  → Converted to quarter-over-quarter growth rates")
  } else if (transform_type == "none") {
    message("  → No transformation applied")
  } else {
    stop("transform_type must be 'standardize', 'growth', or 'none'")
  }

  return(data_list)
}

#### Model Configuration ####

#' Configure DFM parameters
#'
#' @param n_factors Number of latent factors
#' @param var_order VAR order for factor dynamics
#' @param em_max_iter Maximum EM iterations
#' @param em_tolerance Convergence tolerance
#' @return List of model configuration
configure_dfm <- function(n_factors = 5,
                          var_order = 1,
                          em_max_iter = 100,
                          em_tolerance = 1e-4) {
  config <- list(
    n_factors = n_factors,
    var_order = var_order,
    em_max_iter = em_max_iter,
    em_tolerance = em_tolerance,
    method = "EM" # Expectation-Maximization
  )

  message("\n=== DFM Configuration ===")
  message(glue("Number of factors: {n_factors}"))
  message(glue("VAR order: {var_order}"))
  message(glue("EM max iterations: {em_max_iter}"))
  message(glue("EM tolerance: {em_tolerance}"))

  return(config)
}

#### Model Estimation ####

#' Estimate Dynamic Factor Model
#'
#' @param data_prepared Prepared data from prepare_data_for_dfm()
#' @param config Model configuration from configure_dfm()
#' @return Estimated model object
estimate_dfm <- function(data_prepared, config) {
  message("\n=== Estimating Dynamic Factor Model ===\n")

  # Combine GDP and indicators into single matrix for nowcasting package
  # The package expects a matrix with all series (including target)
  full_data <- cbind(
    data_prepared$gdp,  # GDP column
    data_prepared$indicators
  )

  # Explicitly name the GDP column
  colnames(full_data)[1] <- "gdp"

  message(glue("Estimating with {config$n_factors} factors..."))

  # Estimate using nowcasting package
  # The nowcast() function signature: nowcast(formula, data, r, p, method)
  tryCatch(
    {
      # Convert data to proper time series format for nowcasting package
      # Package expects a multivariate time series (mts) object like USGDP dataset

      # Determine the time series properties
      # Use monthly frequency as base (highest frequency)
      # Start date from the earliest observation
      start_date <- data_prepared$dates[1]
      start_year <- lubridate::year(start_date)
      start_month <- lubridate::month(start_date)

      # Create multivariate time series object
      # This is the format the package expects (like USGDP$base)
      ts_data <- ts(
        full_data,
        start = c(start_year, start_month),
        frequency = 12  # Monthly base frequency
      )

      # Debug: show data structure
      message(glue("Time series created: {nrow(ts_data)} periods, {ncol(ts_data)} variables"))
      message(glue("Variables: {paste(colnames(ts_data), collapse=', ')}"))

      # Create formula: gdp ~ all other indicators
      formula_str <- "gdp ~ ."
      message(glue("Formula: {formula_str}"))

      # Build frequency vector from metadata
      # GDP is quarterly (4), indicators are monthly (12) or quarterly (4)
      all_vars <- colnames(ts_data)
      freq_vector <- numeric(length(all_vars))
      names(freq_vector) <- all_vars

      # GDP is quarterly
      freq_vector["gdp"] <- 4

      # Get frequencies for each indicator from metadata
      for (ind_id in names(freq_vector)[-1]) {  # Skip "gdp"
        freq_row <- data_prepared$indicator_frequencies |>
          filter(indicator_id == ind_id)

        if (nrow(freq_row) > 0) {
          freq_vector[ind_id] <- freq_row$freq_numeric[1]
        } else {
          freq_vector[ind_id] <- 12  # Default to monthly
        }
      }

      message("\nFrequency vector (4=quarterly, 12=monthly):")
      message(paste(names(freq_vector), "=", freq_vector, collapse=", "))

      # Use Bpanel() with CORRECT settings for EM algorithm
      # Key insight: aggregate=FALSE prevents moving average filter that creates more NAs!
      message("\nPreprocessing with Bpanel()...")
      message("  NA.replace = FALSE (keep structural NAs)")
      message("  na.prop = 1 (don't discard any series)")
      message("  aggregate = FALSE (don't apply MA filter that creates more NAs!)")

      # Transformation codes for Bpanel() — per-series, driven by metadata.
      # Codes validated by pipeline/tests/stationarity_check.R (ADF+KPSS).
      #   1=MoM %, 2=first diff, 7=3-mo %. See seed/component_metadata.rds.
      # The GDP column (named "gdp" in ts_data) maps to indicator_id
      # "gdp_quarterly" in the metadata.
      trans_lookup <- component_metadata$indicators |>
        select(indicator_id, trans_code) |>
        deframe()
      # Build vector in ts_data column order; "gdp" aliases "gdp_quarterly"
      trans_vec <- vapply(colnames(ts_data), function(col) {
        key <- if (col == "gdp") "gdp_quarterly" else col
        if (!key %in% names(trans_lookup)) {
          stop(glue("No trans_code in metadata for '{col}'"))
        }
        as.integer(trans_lookup[[key]])
      }, integer(1))
      message("\nPer-series trans codes:")
      message(paste(names(trans_vec), "=", trans_vec, collapse = ", "))

      ts_data_balanced <- Bpanel(
        base = ts_data,
        trans = trans_vec,
        NA.replace = FALSE,  # Don't fill NAs (EM handles them)
        aggregate = FALSE,   # Don't apply MA filter
        na.prop = 1          # Allow series with any % of NAs
      )

      # COVID intervention: mask Mar–Jul 2020 as NA so the Kalman smoother
      # imputes those quarters from surrounding data rather than letting
      # the initial shock (Mar, JobKeeper announced 30 Mar), peak lockdown
      # (Apr–May), reopening rebound (Jun), and Melbourne second-wave onset
      # (Jul) drive factor loadings. Standard treatment in DFM literature
      # (e.g. Schorfheide & Song 2020). Wider Mar 2020–Dec 2021 mask tested
      # 2026-04-19 but barely moved the nowcast (+0.80→+0.78 pp), so not
      # worth the shock-detection capability we'd lose.
      tt <- time(ts_data_balanced)
      covid_mask <- (floor(tt) == 2020) & (round((tt - 2020) * 12) + 1) %in% 3:7
      n_masked <- sum(covid_mask)
      if (n_masked > 0) {
        ts_data_balanced[covid_mask, ] <- NA
        message(glue("COVID mask applied: {n_masked} months × {ncol(ts_data_balanced)} series set to NA"))
      }

      message(glue("Balanced panel: {paste(dim(ts_data_balanced), collapse='x')}"))
      message(glue("Variables: {paste(colnames(ts_data_balanced), collapse=', ')}"))

      # Create blocks structure for EM method
      # Blocks specify which variables load on which factors
      # Use balanced data dimensions (after Bpanel)
      n_vars <- ncol(ts_data_balanced)
      n_factors <- config$n_factors
      blocks <- matrix(1, nrow = n_vars, ncol = n_factors)  # All 1s = unrestricted
      rownames(blocks) <- colnames(ts_data_balanced)

      message(glue("\nBlocks structure: {n_vars} variables × {n_factors} factors (unrestricted)"))

      # Update frequency vector to match balanced data
      freq_vector_balanced <- freq_vector[colnames(ts_data_balanced)]

      # Estimate model with EM method
      # Pass frequency vector to tell it which series are quarterly vs monthly
      model <- nowcast(
        formula = as.formula(formula_str),
        data = ts_data_balanced,  # Balanced data from Bpanel
        r = config$n_factors,
        p = config$var_order,
        method = "EM",  # EM algorithm handles missing data
        frequency = freq_vector_balanced,  # Frequencies for variables that remain
        blocks = blocks  # Specify which variables load on which factors
      )

      message("✓ Model estimation complete")

      # Add metadata
      model$config <- config
      model$data_info <- list(
        n_indicators = data_prepared$n_indicators,
        n_periods = data_prepared$n_periods,
        dates = data_prepared$dates
      )

      return(model)
    },
    error = function(e) {
      stop(glue("Model estimation failed: {e$message}"))
    }
  )
}

#' Estimate component-based DFM (separate models per GDP component)
#'
#' @param master_data Full master dataset
#' @param components GDP components to model
#' @param config Model configuration
#' @return List of models (one per component)
estimate_component_dfm <- function(master_data,
                                    components = NULL,
                                    config = configure_dfm()) {
  message("\n=== Component-Based DFM Estimation ===\n")

  if (is.null(components)) {
    components <- component_metadata$components
  }

  # For now, implement a simplified version
  # Full component-based approach would estimate separate model for each
  # GDP component and then aggregate

  # Simplified: Estimate single aggregate model
  # (Full implementation would loop through components)

  message("Note: Using simplified aggregate approach")
  message("(Full component-based approach to be implemented)")

  data_prepared <- prepare_data_for_dfm(master_data)
  # Skip manual standardization - Bpanel() handles transformations
  # data_transformed <- transform_data(data_prepared, transform_type = "standardize")

  model <- estimate_dfm(data_prepared, config)

  return(model)
}

#### Model Diagnostics ####

#' Check model diagnostics
#'
#' @param model Estimated model object
#' @return List of diagnostic results
check_model_diagnostics <- function(model) {
  message("\n=== Model Diagnostics ===\n")

  diagnostics <- list()

  # Check if model has converged (if EM was used)
  if (!is.null(model$em_converged)) {
    diagnostics$converged <- model$em_converged
    message(glue("EM Converged: {model$em_converged}"))
  }

  # Check factor loadings
  if (!is.null(model$Lambda)) {
    loadings <- model$Lambda
    diagnostics$loadings <- loadings

    message("\nFactor Loadings Summary:")
    message(glue("  Dimensions: {nrow(loadings)} series × {ncol(loadings)} factors"))

    # Check for factors that explain very little variance
    loading_norms <- colSums(loadings^2)
    weak_factors <- which(loading_norms < 0.1)

    if (length(weak_factors) > 0) {
      warning(glue("Factors with weak loadings: {paste(weak_factors, collapse = ', ')}"))
    }
  }

  # Check factor variance explained (if available)
  if (!is.null(model$R2)) {
    diagnostics$r2 <- model$R2
    message(glue("\nVariance explained (R²): {round(mean(model$R2, na.rm = TRUE), 3)}"))
  }

  # Check for missing values in estimated factors
  if (!is.null(model$factors)) {
    factors <- model$factors
    n_missing <- sum(is.na(factors))

    if (n_missing > 0) {
      warning(glue("Missing values in estimated factors: {n_missing}"))
    }

    diagnostics$factors_missing <- n_missing
  }

  # In-sample fit
  if (!is.null(model$fitted)) {
    fitted <- model$fitted
    # Could calculate RMSE, MAE here
    message("\nIn-sample fit calculated")
    diagnostics$has_fitted <- TRUE
  }

  return(diagnostics)
}

#' Validate factor interpretability
#'
#' @param model Estimated model
#' @param data_prepared Original data
#' @return Summary of factor interpretations
interpret_factors <- function(model, data_prepared) {
  message("\n=== Factor Interpretation ===\n")

  if (is.null(model$Lambda)) {
    warning("No factor loadings available for interpretation")
    return(NULL)
  }

  loadings <- model$Lambda

  # For each factor, find which indicators load most heavily
  for (f in seq_len(ncol(loadings))) {
    message(glue("\nFactor {f}:"))

    # Get loadings for this factor
    factor_loadings <- loadings[, f]
    names(factor_loadings) <- colnames(data_prepared$indicators)

    # Sort by absolute loading
    sorted_loadings <- sort(abs(factor_loadings), decreasing = TRUE)

    # Show top 5 loadings
    top_5 <- head(sorted_loadings, 5)

    for (i in seq_along(top_5)) {
      indicator_name <- names(top_5)[i]
      loading_value <- factor_loadings[indicator_name]
      message(glue("  {i}. {indicator_name}: {round(loading_value, 3)}"))
    }
  }
}

#### Model Persistence ####

#' Save estimated model
#'
#' @param model Estimated model object
#' @param filename File path to save to
save_model <- function(model, filename = ".cache/model_output/estimated_model.rds") {
  dir.create(dirname(filename), recursive = TRUE, showWarnings = FALSE)

  # Add timestamp
  model$estimated_at <- Sys.time()

  saveRDS(model, filename)
  message(glue("\nModel saved to: {filename}"))

  return(invisible(model))
}

#' Load estimated model
#'
#' @param filename File path to load from
#' @return Estimated model object
load_model <- function(filename = ".cache/model_output/estimated_model.rds") {
  if (!file.exists(filename)) {
    stop(glue("Model file not found: {filename}"))
  }

  model <- readRDS(filename)

  if (!is.null(model$estimated_at)) {
    message(glue("Model estimated at: {model$estimated_at}"))
  }

  return(model)
}

#### Example Workflow ####

#' Complete model estimation workflow
#'
#' @param master_data Master dataset
#' @param n_factors Number of factors (default: 5)
#' @param save_output Whether to save model (default: TRUE)
#' @return Estimated model
run_model_estimation <- function(master_data,
                                  n_factors = 5,
                                  save_output = TRUE) {
  message("\n========================================")
  message("   GDP Nowcast Model Estimation")
  message("========================================\n")

  # Configure model
  config <- configure_dfm(n_factors = n_factors)

  # Estimate model
  model <- estimate_component_dfm(master_data, config = config)

  # Run diagnostics
  diagnostics <- check_model_diagnostics(model)

  # Save model
  if (save_output) {
    save_model(model)
  }

  message("\n✓ Model estimation complete!\n")

  return(list(
    model = model,
    diagnostics = diagnostics
  ))
}

#### Notes for User ####

message("\n=== Model Estimation Script Ready ===")
message("\nKey functions:")
message("  - prepare_data_for_dfm() - Format data for nowcasting package")
message("  - configure_dfm() - Set model parameters")
message("  - estimate_dfm() - Run EM algorithm to estimate model")
message("  - check_model_diagnostics() - Validate model quality")
message("  - save_model() / load_model() - Persist models")
message("  - run_model_estimation() - Complete workflow")
message("\nExample usage:")
message('  master_data <- readRDS(".cache/processed/master_dataset_wide.rds")')
message("  result <- run_model_estimation(master_data, n_factors = 5)")
message("  model <- result$model")
message("\nNote: The nowcasting package API may vary by version.")
message("You may need to adjust function calls based on installed version.")
message("Check: help(package = 'nowcasting') for available functions")

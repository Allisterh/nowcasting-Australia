#### Australian GDP Nowcasting - Nowcast Generation ####
# Purpose: Generate GDP growth nowcast with uncertainty and tracking
# Author: James Wilson
# Date: 2025-12-30

#### Load dependencies ####
library(dplyr)
library(purrr)
library(tibble)
library(nowcasting)
library(lubridate)
library(glue)

#### Source previous scripts ####
source("04_release_calendar.R")
source("05_estimate_model.R")

#### Load component metadata ####
component_metadata <- readRDS("seed/component_metadata.rds")

#### Core Nowcast Generation ####

#' Generate GDP nowcast using estimated model
#'
#' @param model Estimated DFM model
#' @param current_data Current available indicator data
#' @param target_quarter Quarter to nowcast (e.g., "2025 Q4")
#' @return List with nowcast point estimate and uncertainty
generate_nowcast <- function(model,
                              current_data,
                              target_quarter = NULL) {
  message("\n=== Generating GDP Nowcast ===\n")

  # Determine target quarter if not specified
  # Derive from latest actual GDP data, not Sys.Date()
  if (is.null(target_quarter)) {
    latest_gdp_date <- current_data |>
      filter(!is.na(gdp_quarterly)) |>
      pull(date) |>
      max()
    next_q_date <- latest_gdp_date %m+% months(3)
    target_quarter <- paste0(year(next_q_date), " Q", quarter(next_q_date))
    message(glue("Target quarter: {target_quarter}"))
  }

  # Generate nowcast from model forecast output
  # nowcast() with EM back-transforms forecasts to original scale automatically
  tryCatch(
    {
      # Extract nowcast from nowcasting package model.
      #
      # model$yfcst has columns:
      #   y   — observed GDP (NA for quarters not yet released)
      #   in  — in-sample Kalman-smoothed fit (non-NA only where y is observed)
      #   out — out-of-sample nowcast / forecast, populated for quarters where y
      #         is NA. Per the R Journal paper (RJ-2019-020), this is THE
      #         mixed-frequency nowcast produced by the package.
      #
      # Earlier versions of this function grabbed tail(in[!is.na(in)], 1),
      # which returned the in-sample fit for the LATEST OBSERVED quarter —
      # effectively a backcast of the prior quarter, labelled as a nowcast
      # for target_quarter. Every historical vintage was mis-sourced as a
      # result. Correct extraction: locate target_quarter in the ts index
      # and pull yfcst[row, "out"].
      if (!is.null(model$yfcst)) {
        yf <- model$yfcst
        target_year    <- as.integer(sub(" Q.*$", "", target_quarter))
        target_q_num   <- as.integer(sub("^.*Q", "", target_quarter))
        target_time    <- target_year + (target_q_num - 1) / 4
        times          <- as.numeric(time(yf))
        row_idx        <- which(abs(times - target_time) < 1e-8)

        if (length(row_idx) != 1) {
          stop(glue(
            "generate_nowcast: target_quarter {target_quarter} (t={target_time}) ",
            "not found in yfcst time index (range {min(times)}..{max(times)}). ",
            "The nowcasting package extends yfcst one quarter past the last ",
            "observed GDP by default; if you need a further-ahead target ",
            "you'll have to extend the forecast horizon at fit time."
          ))
        }

        out_val <- yf[row_idx, "out"]
        in_val  <- yf[row_idx, "in"]
        y_val   <- yf[row_idx, "y"]

        # Prefer out (prospective nowcast). Fall back to in only if target
        # quarter is ALREADY OBSERVED — useful for historical backtests where
        # we want the model's smoothed estimate of a released quarter.
        #
        # IMPORTANT: with GDP trans=7 (3-mo % change) wired into Bpanel,
        # yfcst is returned in the TRANSFORMED scale — i.e., a fractional
        # QoQ growth rate (e.g., 0.0081 = 0.81% QoQ). This must be back-
        # transformed to a $-level before consumers downstream (latest.json
        # schema, CI calculation, site cards) see it.
        if (!is.na(out_val)) {
          qoq_fraction <- as.numeric(out_val)
          source_col <- "out (nowcast)"
        } else if (!is.na(in_val)) {
          qoq_fraction <- as.numeric(in_val)
          source_col <- "in (retrospective fit — target already observed)"
        } else {
          stop(glue(
            "generate_nowcast: yfcst has no value for {target_quarter} ",
            "(row {row_idx}): both in and out are NA. The target is probably ",
            "too far ahead for the fitted horizon."
          ))
        }

        prediction_var <- NA

      } else if (!is.null(model$yfitted)) {
        # Fallback: use yfitted (assumed same transformed scale)
        qoq_fraction <- as.numeric(tail(model$yfitted[, 1], 1))
        prediction_var <- NA
        source_col <- "yfitted (fallback)"
      } else {
        stop("generate_nowcast: model has no yfcst/yfitted output")
      }

      # Back-transform: QoQ fraction → $M level + percent
      gdp_data <- current_data |>
        filter(!is.na(gdp_quarterly)) |>
        arrange(date)

      latest_actual_value   <- tail(gdp_data$gdp_quarterly, 1)
      latest_actual_date    <- tail(gdp_data$date, 1)
      latest_actual_quarter <- paste0(year(latest_actual_date), " Q", quarter(latest_actual_date))

      # Level = last_observed * (1 + QoQ_fraction)
      point_estimate <- latest_actual_value * (1 + qoq_fraction)
      qoq_growth     <- qoq_fraction * 100

      # YoY: target is one quarter past latest_actual, so 4 quarters before
      # target = 3 quarters before latest_actual = tail(,4)[1]
      if (nrow(gdp_data) >= 4) {
        gdp_4q_ago_from_target <- tail(gdp_data$gdp_quarterly, 4)[1]
        yoy_growth <- ((point_estimate - gdp_4q_ago_from_target) / gdp_4q_ago_from_target) * 100
      } else {
        yoy_growth <- NA
      }

      message(glue(
        "Nowcast for {target_quarter}: QoQ={sprintf('%+.2f%%', qoq_growth)}  ",
        "implied level=${format(round(point_estimate), big.mark=',')}M  ",
        "YoY={sprintf('%+.2f%%', yoy_growth)}  [{source_col}]"
      ))

      return(list(
        point_estimate = point_estimate,
        nowcast_value = point_estimate,
        prediction_variance = prediction_var,
        target_quarter = target_quarter,
        nowcast_date = Sys.Date(),
        generated_date = Sys.Date(),
        qoq_growth = qoq_growth,
        yoy_growth = yoy_growth,
        latest_actual_value = latest_actual_value,
        latest_actual_quarter = latest_actual_quarter
      ))
    },
    error = function(e) {
      warning(glue("Error generating nowcast: {e$message}"))
      return(NULL)
    }
  )
}

#' Manual Kalman filter prediction (fallback)
#'
#' @param model Estimated model
#' @param data_transformed Transformed data
#' @return Predicted GDP growth
predict_with_kalman <- function(model, data_transformed) {
  # This is a simplified manual implementation
  # In practice, would use model's Kalman filter results

  if (!is.null(model$factors)) {
    # Use latest estimated factors
    latest_factors <- tail(model$factors, 1)

    # Predict GDP from factors using loadings
    if (!is.null(model$Lambda)) {
      gdp_loading <- model$Lambda[1, ] # GDP is first series
      predicted_gdp <- sum(latest_factors * gdp_loading)
      return(predicted_gdp)
    }
  }

  warning("Unable to compute manual Kalman prediction")
  return(NA)
}

#### Uncertainty Quantification ####

#' Calculate confidence intervals for nowcast
#'
#' @param nowcast_result Nowcast output from generate_nowcast()
#' @param confidence_levels Vector of confidence levels (e.g., c(0.68, 0.95))
#' @return Data frame with confidence bands
calculate_confidence_intervals <- function(nowcast_result,
                                            confidence_levels = c(0.68, 0.95)) {
  message("\n=== Calculating Confidence Intervals ===\n")

  point_estimate <- nowcast_result$point_estimate
  prediction_var <- nowcast_result$prediction_variance

  if (is.na(prediction_var)) {
    # If variance not available, use historical RMSE as proxy
    # This would be calculated from backtesting
    warning("Prediction variance not available - using approximate intervals")
    prediction_sd <- 1.0 # Placeholder: should be from historical validation
  } else {
    prediction_sd <- sqrt(prediction_var)
  }

  # Calculate intervals
  intervals <- map_dfr(confidence_levels, function(conf) {
    z <- qnorm((1 + conf) / 2) # Z-score for confidence level
    lower <- point_estimate - z * prediction_sd
    upper <- point_estimate + z * prediction_sd

    tibble(
      confidence_level = conf,
      point_estimate = point_estimate,
      lower_bound = lower,
      upper_bound = upper,
      interval_width = upper - lower
    )
  })

  message("Confidence intervals:")
  print(intervals)

  return(intervals)
}

#### Component Contributions ####

#' Calculate component contributions to GDP nowcast
#'
#' @param model Estimated model
#' @param nowcast_result Nowcast output
#' @return Data frame with component contributions
calculate_component_contributions <- function(model, nowcast_result) {
  message("\n=== Calculating Component Contributions ===\n")

  # This requires component-based model structure
  # Simplified version: attribute to indicator groups

  components <- component_metadata$components

  # Placeholder: would calculate actual contributions from component models
  # For now, create illustrative structure

  contributions <- components |>
    mutate(
      contribution_pp = NA_real_, # percentage points
      contribution_pct = NA_real_ # percent of total growth
    )

  message("Note: Component contributions require full component-based model")
  message("This is a placeholder - implement after testing base model")

  return(contributions)
}

#### Nowcast Evolution Tracking ####

#' Track nowcast evolution over quarter as data arrives
#'
#' @param model Estimated model
#' @param master_data Full historical dataset
#' @param target_quarter Quarter to track
#' @param update_frequency "daily", "weekly", or "monthly"
#' @return Data frame with nowcast time series
track_nowcast_evolution <- function(model,
                                     master_data,
                                     target_quarter,
                                     update_frequency = "weekly") {
  message("\n=== Tracking Nowcast Evolution ===\n")
  message(glue("Target quarter: {target_quarter}"))

  # Determine quarter boundaries
  quarter_start <- ymd(paste0(substr(target_quarter, 1, 4), "-",
    sprintf("%02d", (as.numeric(substr(target_quarter, 7, 7)) - 1) * 3 + 1), "-01"
  ))
  quarter_end <- quarter_start + months(3) - days(1)

  # Generate update dates
  update_dates <- generate_backtest_dates(
    start_date = quarter_start,
    end_date = min(quarter_end, Sys.Date()),
    frequency = update_frequency
  )

  message(glue("Tracking {length(update_dates)} nowcast updates"))

  # Generate nowcast for each date
  nowcast_history <- map_dfr(update_dates, function(date) {
    message(glue("  → {date}"))

    # Get data available as of this date
    available_data <- get_available_data(
      master_data,
      as_of_date = date,
      format = "wide"
    )

    # Generate nowcast
    nowcast <- generate_nowcast(model, available_data, target_quarter)

    if (!is.null(nowcast)) {
      tibble(
        date = date,
        nowcast = nowcast$point_estimate,
        target_quarter = target_quarter
      )
    } else {
      tibble(
        date = date,
        nowcast = NA_real_,
        target_quarter = target_quarter
      )
    }
  })

  # Calculate nowcast changes (news)
  nowcast_history <- nowcast_history |>
    arrange(date) |>
    mutate(
      nowcast_change = nowcast - lag(nowcast),
      cumulative_change = nowcast - first(nowcast)
    )

  message(glue("\n✓ Tracked {nrow(nowcast_history)} nowcast updates"))
  message(glue("  Latest nowcast: {round(tail(nowcast_history$nowcast, 1), 2)}%"))
  message(glue("  Change from start: {round(tail(nowcast_history$cumulative_change, 1), 2)} pp"))

  return(nowcast_history)
}

#### Data Release Impact ####

#' Calculate impact of each data release on nowcast
#'
#' @param nowcast_history Output from track_nowcast_evolution()
#' @param release_schedule ABS release schedule
#' @return Data frame with data release impacts
calculate_data_release_impact <- function(nowcast_history, release_schedule = NULL) {
  message("\n=== Calculating Data Release Impact ===\n")

  if (is.null(release_schedule)) {
    release_schedule <- readRDS(".cache/processed/release_schedule.rds")
  }

  # Identify which data releases occurred between each nowcast update
  # Match nowcast changes to likely data releases

  nowcast_changes <- nowcast_history |>
    filter(!is.na(nowcast_change), nowcast_change != 0) |>
    select(date, nowcast_change)

  # For each change, identify which indicators were released around that time
  # This requires checking release calendar

  # Simplified: attribute changes to indicators with releases near that date
  release_impacts <- nowcast_changes |>
    mutate(
      likely_indicator = NA_character_,
      impact_pp = nowcast_change
    )

  message(glue("Found {nrow(release_impacts)} nowcast updates"))

  if (nrow(release_impacts) > 0) {
    # Show largest impacts
    top_impacts <- release_impacts |>
      arrange(desc(abs(impact_pp))) |>
      head(5)

    message("\nLargest nowcast changes:")
    print(top_impacts)
  }

  return(release_impacts)
}

#### Complete Nowcast Workflow ####

#' Generate complete nowcast with all analysis
#'
#' @param model Estimated DFM model
#' @param master_data Full dataset
#' @param target_quarter Quarter to nowcast (NULL = current)
#' @param track_evolution Whether to track evolution over quarter
#' @return Comprehensive nowcast results
run_complete_nowcast <- function(model,
                                  master_data,
                                  target_quarter = NULL,
                                  track_evolution = TRUE) {
  message("\n========================================")
  message("   GDP Nowcast Generation")
  message("========================================\n")

  # Get current available data
  current_data <- get_available_data(
    master_data,
    as_of_date = Sys.Date(),
    format = "wide"
  )

  # 1. Generate current nowcast
  nowcast <- generate_nowcast(model, current_data, target_quarter)

  if (is.null(nowcast)) {
    stop("Failed to generate nowcast")
  }

  # 2. Calculate confidence intervals
  confidence_intervals <- calculate_confidence_intervals(
    nowcast,
    confidence_levels = c(0.68, 0.95)
  )

  # 3. Component contributions
  component_contributions <- calculate_component_contributions(model, nowcast)

  # 4. Track evolution (if requested)
  if (track_evolution && !is.null(target_quarter)) {
    nowcast_evolution <- track_nowcast_evolution(
      model,
      master_data,
      target_quarter,
      update_frequency = "weekly"
    )

    # 5. Data release impact
    release_impact <- calculate_data_release_impact(nowcast_evolution)
  } else {
    nowcast_evolution <- NULL
    release_impact <- NULL
  }

  # Compile results
  results <- list(
    current_estimate = nowcast$point_estimate,
    target_quarter = nowcast$target_quarter,
    nowcast_date = nowcast$nowcast_date,
    confidence_intervals = confidence_intervals,
    component_contributions = component_contributions,
    nowcast_evolution = nowcast_evolution,
    release_impact = release_impact,
    metadata = list(
      model_config = model$config,
      data_as_of = Sys.Date()
    )
  )

  # Print summary
  message("\n========================================")
  message("   Nowcast Summary")
  message("========================================\n")
  message(glue("Target Quarter: {results$target_quarter}"))
  message(glue("Nowcast: {round(results$current_estimate, 2)}%"))
  message(glue("68% CI: [{round(confidence_intervals$lower_bound[1], 2)}%, {round(confidence_intervals$upper_bound[1], 2)}%]"))
  message(glue("95% CI: [{round(confidence_intervals$lower_bound[2], 2)}%, {round(confidence_intervals$upper_bound[2], 2)}%]"))
  message(glue("As of: {results$nowcast_date}"))
  message("\n========================================\n")

  return(results)
}

#### Save Nowcast Results ####

#' Save nowcast results
#'
#' @param results Output from run_complete_nowcast()
#' @param filename File path to save to
save_nowcast_results <- function(results,
                                  filename = NULL) {
  if (is.null(filename)) {
    timestamp <- format(Sys.Date(), "%Y-%m-%d")
    filename <- glue(".cache/model_output/nowcast_{timestamp}.rds")
  }

  dir.create(dirname(filename), recursive = TRUE, showWarnings = FALSE)

  saveRDS(results, filename)
  message(glue("\nNowcast results saved to: {filename}"))

  return(invisible(results))
}

#### Example Usage ####

# Example workflow:
# model <- load_model()
# master_data <- readRDS(".cache/processed/master_dataset_wide.rds")
# results <- run_complete_nowcast(model, master_data, target_quarter = "2025 Q4")
# save_nowcast_results(results)

#### Notes ####

message("\n=== Nowcast Generation Script Ready ===")
message("\nKey functions:")
message("  - generate_nowcast() - Core nowcast generation with Kalman filter")
message("  - calculate_confidence_intervals() - Uncertainty quantification")
message("  - calculate_component_contributions() - GDP component breakdown")
message("  - track_nowcast_evolution() - Track changes over quarter")
message("  - calculate_data_release_impact() - Measure 'news' effect")
message("  - run_complete_nowcast() - Complete workflow")
message("  - save_nowcast_results() - Persist results")
message("\nOutputs:")
message("  - Point estimate of GDP growth")
message("  - 68% and 95% confidence intervals")
message("  - Component contributions (requires full component model)")
message("  - Nowcast evolution time series")
message("  - Data release impact attribution")

#### Generate Markdown Summary ####

#' Generate markdown summary of nowcast results
#'
#' @param nowcast_result Nowcast result object
#' @param model Estimated model
#' @param output_path Path to save markdown file
#' @return Path to saved markdown file
generate_nowcast_summary <- function(nowcast_result,
                                     model,
                                     output_path = ".cache/outputs/nowcast_summary.md") {
  
  # Ensure output directory exists
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  
  # Get forecast trajectory
  yfcst <- model$yfcst
  latest_actual_idx <- max(which(!is.na(yfcst[, "y"])))
  
  # Build markdown content
  md_content <- glue("
# Australian GDP Nowcast Summary

**Generated:** {Sys.Date()}

---

## 🎯 Latest Nowcast

### Target Quarter: **{nowcast_result$target_quarter}**

| Metric | Value |
|--------|-------|
| **Forecast GDP** | ${format(round(nowcast_result$nowcast_value), big.mark=',')} million |
| **Quarter-on-Quarter Growth** | {sprintf('%+.2f%%', nowcast_result$qoq_growth)} |
| **Year-on-Year Growth** | {sprintf('%+.2f%%', nowcast_result$yoy_growth)} |

---

## 📊 Latest Actual Data

**Quarter:** {nowcast_result$latest_actual_quarter}
**GDP:** ${format(round(nowcast_result$latest_actual_value), big.mark=',')} million

---

## 📈 Recent GDP Trajectory

| Quarter | Level ($B) | Type | Q-o-Q Growth |
|---------|-------------|------|--------------|
")
  
  # Add trajectory table
  start_idx <- max(1, latest_actual_idx - 4)
  end_idx <- min(latest_actual_idx + 3, nrow(yfcst))
  
  for (i in start_idx:end_idx) {
    qtr <- rownames(yfcst)[i]
    actual <- yfcst[i, "y"]
    forecast <- ifelse(is.na(yfcst[i, "in"]), yfcst[i, "out"], yfcst[i, "in"])
    
    # Calculate growth
    if (i > start_idx) {
      prev_val <- ifelse(!is.na(yfcst[i-1, "y"]), yfcst[i-1, "y"],
                         ifelse(!is.na(yfcst[i-1, "in"]), yfcst[i-1, "in"], yfcst[i-1, "out"]))
      curr_val <- ifelse(!is.na(actual), actual, forecast)
      growth <- ((curr_val / prev_val) - 1) * 100
      growth_str <- sprintf("%+.2f%%", growth)
    } else {
      growth_str <- "-"
    }
    
    type_str <- ifelse(!is.na(actual), "Actual", "**Forecast**")
    value_str <- sprintf("%.1f", ifelse(!is.na(actual), actual, forecast) / 1000)
    
    md_content <- paste0(md_content, glue("| {qtr} | {value_str} | {type_str} | {growth_str} |\n"))
  }
  
  # Add interpretation
  md_content <- paste0(md_content, glue("

---

## 🔍 Key Insights

"))
  
  # Interpret the forecast
  if (nowcast_result$qoq_growth > 1.5) {
    interpretation <- "**Strong growth expected:** The forecast indicates robust quarterly expansion, significantly above recent trends."
  } else if (nowcast_result$qoq_growth > 0.5) {
    interpretation <- "**Moderate growth expected:** The forecast shows solid but sustainable quarterly expansion."
  } else if (nowcast_result$qoq_growth > 0) {
    interpretation <- "**Modest growth expected:** The forecast indicates continued expansion at a slower pace."
  } else {
    interpretation <- "**Contraction expected:** The forecast indicates negative quarterly growth."
  }
  
  md_content <- paste0(md_content, glue("
- {interpretation}
- Year-on-year growth of {sprintf('%.2f%%', nowcast_result$yoy_growth)} indicates {ifelse(nowcast_result$yoy_growth > 2.5, 'strong', ifelse(nowcast_result$yoy_growth > 1.5, 'healthy', 'modest'))} annual economic performance.
- Nowcast based on {model$data_info$n_indicators} high-frequency economic indicators through {format(Sys.Date(), '%B %Y')}.

---

## 🛠️ Model Specification

| Component | Details |
|-----------|---------|
| **Method** | {nowcast_result$model_info$method} |
| **Latent Factors** | {nowcast_result$model_info$n_factors} |
| **Economic Indicators** | {nowcast_result$model_info$n_indicators} series |
| **Frequency Mix** | Quarterly GDP + monthly/quarterly indicators |
| **Data Through** | {format(Sys.Date(), '%B %Y')} |

---

## 📁 Output Files

**Data Files:**
- `.cache/model_output/estimated_model.rds` - Full model
- `.cache/model_output/latest_nowcast.rds` - Nowcast summary
- `.cache/model_output/forecast_trajectory.rds` - Forecast series

---

## ℹ️ Notes

- This nowcast is a statistical forecast based on current economic indicators
- Results update as new data releases become available
- Forecast subject to revision as more complete information arrives
- Not an official projection - for research and analysis purposes

**Last updated:** {format(Sys.Date(), '%d %B %Y')}

---

*Generated by Australian GDP Nowcasting Model*  
*Methodology: NYFED-style Dynamic Factor Model with EM algorithm*
"))
  
  # Write to file
  writeLines(md_content, output_path)
  message(glue("✓ Markdown summary saved to: {output_path}"))
  
  return(output_path)
}

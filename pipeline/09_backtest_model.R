#### Nowcast Model Backtesting ####
# Purpose: POOS backtest — re-estimate the DFM on historical data (as-of-date
# snapshots) and compare nowcasts to actual GDP outcomes.
#
# Adapted from the prototype at james-mess/code/project_nowcast/archive/
#   09_backtest_model.R. Differences:
#   - dependencies limited to what production pipeline uses (no theme_jw)
#   - paths relative to pipeline/ cwd
#   - captures qoq growth forecast alongside level, so directional accuracy works
#
# Usage (from repo root):
#   setwd("pipeline")
#   source("09_backtest_model.R")
#   master <- readRDS(".cache/processed/master_dataset_complete.rds")
#   config <- configure_dfm(n_factors = 3, var_order = 1)
#   results <- run_backtest(master, config)
#
# Expected runtime per r: ~40-60 minutes (24 quarterly iterations, each
# re-estimating the DFM).

library(tidyverse)
library(lubridate)
library(glue)

# Source production pipeline (provides configure_dfm, estimate_component_dfm,
# generate_nowcast, get_available_data, generate_backtest_dates).
source("04_release_calendar.R")
source("05_estimate_model.R")
source("06_generate_nowcast.R")

#### Main backtest loop ####

#' Run POOS backtest.
#'
#' @param master_data master dataset — either the `list(wide, long)` from
#'   `build_master_dataset()` or a pre-extracted wide tibble.
#' @param config DFM config from `configure_dfm()`.
#' @param start_date,end_date window for backtesting (ISO strings).
#' @param frequency "quarterly" (default — one backtest per quarter end) or
#'   anything accepted by `generate_backtest_dates()`.
#' @param verbose print per-iteration progress.
#' @return list(backtest_results, accuracy_metrics, actual_gdp, config, period).
run_backtest <- function(master_data,
                         config,
                         start_date = "2020-01-01",
                         end_date = "2025-12-31",
                         frequency = "quarterly",
                         verbose = TRUE) {

  if (verbose) {
    cat("\n========================================\n")
    cat("  NOWCAST MODEL BACKTESTING\n")
    cat("========================================\n\n")
    cat(glue("Period: {start_date} to {end_date}\n"))
    cat(glue("Frequency: {frequency}\n"))
    cat(glue("Model: {config$n_factors}-factor DFM\n\n"))
  }

  if (is.list(master_data) && "wide" %in% names(master_data)) {
    master_data <- master_data$wide
    if (verbose) cat("Using wide format from master dataset list\n\n")
  }

  if (frequency == "quarterly") {
    start <- as.Date(start_date)
    end <- as.Date(end_date)
    first_quarter <- ceiling_date(start, "quarter") - days(1)
    backtest_dates <- seq.Date(from = first_quarter, to = end, by = "3 months")
  } else {
    backtest_dates <- generate_backtest_dates(
      start_date = as.Date(start_date),
      end_date = as.Date(end_date),
      frequency = frequency
    )
  }

  if (verbose) cat(glue("Backtest dates: {length(backtest_dates)} iterations\n\n"))

  # Actual GDP for comparison (both level and qoq growth).
  actual_gdp <- master_data |>
    filter(!is.na(gdp_quarterly)) |>
    arrange(date) |>
    mutate(
      quarter     = paste0(year(date), " Q", quarter(date)),
      qoq_actual  = (gdp_quarterly / lag(gdp_quarterly) - 1) * 100
    ) |>
    select(date, actual_gdp = gdp_quarterly, quarter, qoq_actual)

  backtest_results <- tibble()

  for (i in seq_along(backtest_dates)) {
    backtest_date <- backtest_dates[i]
    if (verbose) cat(glue("[{i}/{length(backtest_dates)}] {backtest_date}\n"))

    tryCatch({
      historical_data <- get_available_data(
        master_data = master_data,
        as_of_date  = backtest_date,
        format      = "wide"
      )

      target_quarter_date <- floor_date(backtest_date, "quarter")
      target_quarter      <- paste0(year(target_quarter_date), " Q", quarter(target_quarter_date))

      n_indicators <- sum(!is.na(historical_data[nrow(historical_data), -1]))

      if (verbose) {
        cat(glue("  target: {target_quarter}, periods: {nrow(historical_data)}, live_indicators: {n_indicators}\n"))
        cat("  estimating DFM... ")
      }

      model <- estimate_component_dfm(historical_data, config = config)
      if (verbose) cat("done.\n  nowcasting... ")

      nowcast <- generate_nowcast(model, historical_data)
      if (verbose) cat("done.\n")

      result_row <- tibble(
        backtest_date          = backtest_date,
        target_quarter         = target_quarter,
        target_quarter_date    = target_quarter_date,
        nowcast_gdp            = as.numeric(nowcast$nowcast_value),
        qoq_growth_forecast    = as.numeric(nowcast$qoq_growth),
        n_indicators_available = n_indicators,
        n_periods              = nrow(historical_data),
        model_converged        = !is.null(model)
      )
      backtest_results <- bind_rows(backtest_results, result_row)

      if (verbose) {
        cat(glue("  → nowcast ${scales::comma(round(nowcast$nowcast_value))}M ({sprintf('%+.2f', nowcast$qoq_growth)}%)\n\n"))
      }
    }, error = function(e) {
      if (verbose) cat(glue("  ✗ ERROR: {e$message}\n\n"))
      result_row <- tibble(
        backtest_date          = backtest_date,
        target_quarter         = NA_character_,
        target_quarter_date    = as.Date(NA),
        nowcast_gdp            = NA_real_,
        qoq_growth_forecast    = NA_real_,
        n_indicators_available = NA_integer_,
        n_periods              = NA_integer_,
        model_converged        = FALSE
      )
      backtest_results <<- bind_rows(backtest_results, result_row)
    })
  }

  # Join in the eventual actual for each target quarter.
  backtest_results <- backtest_results |>
    left_join(
      actual_gdp |> select(quarter, actual_gdp, qoq_actual),
      by = c("target_quarter" = "quarter")
    ) |>
    mutate(
      error              = nowcast_gdp - actual_gdp,
      pct_error          = (error / actual_gdp) * 100,
      abs_error          = abs(error),
      abs_pct_error      = abs(pct_error),
      qoq_error          = qoq_growth_forecast - qoq_actual,
      abs_qoq_error      = abs(qoq_error),
      direction_correct  = sign(qoq_growth_forecast) == sign(qoq_actual)
    )

  accuracy_metrics <- calculate_accuracy_metrics(backtest_results)

  if (verbose) {
    cat("\n=== Accuracy metrics ===\n")
    print(accuracy_metrics)
    cat("\n")
  }

  list(
    backtest_results = backtest_results,
    accuracy_metrics = accuracy_metrics,
    actual_gdp       = actual_gdp,
    config           = config,
    period           = c(start_date, end_date)
  )
}

#### Accuracy metrics ####

#' Aggregate accuracy stats (MAE / RMSE / MAPE / correlation / hit rate / qoq MAE).
#' Uses valid forecasts only (model converged, actual known, nowcast non-NA).
calculate_accuracy_metrics <- function(backtest_results) {
  valid <- backtest_results |>
    filter(model_converged, !is.na(actual_gdp), !is.na(nowcast_gdp))

  n <- nrow(valid)
  if (n == 0) {
    warning("No valid forecasts to evaluate")
    return(tibble(metric = "No valid forecasts", value = NA_real_))
  }

  mae         <- mean(valid$abs_error, na.rm = TRUE)
  rmse        <- sqrt(mean(valid$error^2, na.rm = TRUE))
  mape        <- mean(valid$abs_pct_error, na.rm = TRUE)
  median_ae   <- median(valid$abs_error, na.rm = TRUE)
  bias        <- mean(valid$error, na.rm = TRUE)
  correlation <- cor(valid$nowcast_gdp, valid$actual_gdp, use = "complete.obs")

  qoq_valid  <- valid |> filter(!is.na(qoq_growth_forecast), !is.na(qoq_actual))
  qoq_mae    <- if (nrow(qoq_valid) > 0) mean(qoq_valid$abs_qoq_error, na.rm = TRUE) else NA_real_
  qoq_rmse   <- if (nrow(qoq_valid) > 0) sqrt(mean(qoq_valid$qoq_error^2, na.rm = TRUE)) else NA_real_
  hit_rate   <- if (nrow(qoq_valid) > 0) mean(qoq_valid$direction_correct, na.rm = TRUE) * 100 else NA_real_

  tibble(
    metric = c(
      "n_forecasts",
      "mae_millions", "rmse_millions", "mape_pct",
      "mean_bias_millions", "median_abs_error_millions",
      "correlation_level",
      "mae_qoq_pp", "rmse_qoq_pp", "hit_rate_direction_pct"
    ),
    value = c(
      n,
      mae, rmse, mape,
      bias, median_ae,
      correlation,
      qoq_mae, qoq_rmse, hit_rate
    )
  )
}

#### Visualizations (ggplot, minimal deps) ####

plot_nowcast_vs_actual <- function(backtest_results, save_path, subtitle = NULL) {
  d <- backtest_results |>
    filter(model_converged, !is.na(actual_gdp)) |>
    arrange(target_quarter_date)
  p <- ggplot(d, aes(x = target_quarter_date)) +
    geom_line(aes(y = actual_gdp), colour = "#034159", linewidth = 1.1) +
    geom_point(aes(y = actual_gdp), colour = "#034159", size = 2.5) +
    geom_point(aes(y = nowcast_gdp), colour = "#0cf25d", size = 3, shape = 17) +
    geom_segment(aes(xend = target_quarter_date, y = actual_gdp, yend = nowcast_gdp),
                 colour = "grey60", linetype = "dotted", linewidth = 0.4) +
    scale_y_continuous(labels = scales::comma) +
    scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
    labs(title = "Backtest: nowcasts vs actual GDP",
         subtitle = subtitle,
         x = NULL, y = "GDP ($ million)") +
    theme_minimal(base_size = 11)
  ggsave(save_path, p, width = 8, height = 5, dpi = 150)
  invisible(p)
}

plot_forecast_errors <- function(backtest_results, save_path, subtitle = NULL) {
  d <- backtest_results |>
    filter(model_converged, !is.na(actual_gdp), !is.na(error)) |>
    mutate(sign = ifelse(error > 0, "over", "under"),
           lbl  = sprintf("%+.2f%%", pct_error)) |>
    arrange(target_quarter)
  p <- ggplot(d, aes(x = target_quarter, y = error, fill = sign)) +
    geom_col(width = 0.7) +
    geom_hline(yintercept = 0, linewidth = 0.6) +
    geom_text(aes(label = lbl), vjust = ifelse(d$error > 0, -0.4, 1.3), size = 2.8) +
    scale_fill_manual(values = c(over = "#0cf25d", under = "#034159"), guide = "none") +
    scale_y_continuous(labels = scales::comma) +
    labs(title = "Backtest: forecast errors by quarter",
         subtitle = subtitle,
         x = NULL, y = "Error ($ million, nowcast − actual)") +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(save_path, p, width = 9, height = 5, dpi = 150)
  invisible(p)
}

#### Markdown report ####

generate_backtest_report <- function(backtest_output, save_path) {
  r       <- backtest_output$backtest_results
  m       <- backtest_output$accuracy_metrics
  period  <- backtest_output$period
  n_fac   <- backtest_output$config$n_factors

  v <- function(name) m |> filter(metric == name) |> pull(value)

  lines <- c(
    sprintf("# Backtest report — %d-factor DFM", n_fac),
    "",
    sprintf("**Generated:** %s", Sys.Date()),
    sprintf("**Period:** %s to %s", period[1], period[2]),
    sprintf("**Model:** %d-factor DFM, VAR(%d)", n_fac, backtest_output$config$var_order),
    "",
    "## Aggregate metrics",
    "",
    "| Metric | Value |",
    "|---|---|",
    sprintf("| Number of forecasts | %d |", round(v("n_forecasts"))),
    sprintf("| MAE (levels, $M) | %s |", scales::comma(round(v("mae_millions")))),
    sprintf("| RMSE (levels, $M) | %s |", scales::comma(round(v("rmse_millions")))),
    sprintf("| MAPE (%%) | %.2f |", v("mape_pct")),
    sprintf("| Mean bias ($M) | %s |", scales::comma(round(v("mean_bias_millions")))),
    sprintf("| Median |error| ($M) | %s |", scales::comma(round(v("median_abs_error_millions")))),
    sprintf("| Level correlation | %.3f |", v("correlation_level")),
    sprintf("| MAE (QoQ, pp) | %.3f |", v("mae_qoq_pp")),
    sprintf("| RMSE (QoQ, pp) | %.3f |", v("rmse_qoq_pp")),
    sprintf("| Directional hit rate (%%) | %.1f |", v("hit_rate_direction_pct")),
    "",
    "## Per-quarter results",
    "",
    "| Quarter | Nowcast ($M) | Actual ($M) | Error ($M) | Error (%) | QoQ forecast | QoQ actual |",
    "|---|---|---|---|---|---|---|"
  )
  tbl <- r |>
    filter(model_converged, !is.na(actual_gdp)) |>
    arrange(target_quarter_date) |>
    transmute(
      target_quarter,
      nowcast_str     = scales::comma(round(nowcast_gdp)),
      actual_str      = scales::comma(round(actual_gdp)),
      error_str       = scales::comma(round(error)),
      pct_error_str   = sprintf("%+.2f%%", pct_error),
      qoq_fore_str    = sprintf("%+.2f%%", qoq_growth_forecast),
      qoq_act_str     = sprintf("%+.2f%%", qoq_actual)
    )
  rows <- sprintf("| %s | %s | %s | %s | %s | %s | %s |",
                  tbl$target_quarter, tbl$nowcast_str, tbl$actual_str,
                  tbl$error_str, tbl$pct_error_str, tbl$qoq_fore_str, tbl$qoq_act_str)

  lines <- c(lines, rows, "",
             "## Charts",
             "",
             "- `nowcast_vs_actual.png` — levels",
             "- `forecast_errors.png` — per-quarter error distribution")

  writeLines(lines, save_path)
  message(glue("Report saved: {save_path}"))
  invisible(save_path)
}

#### Save helper ####

save_backtest_results <- function(backtest_output, output_dir) {
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  saveRDS(backtest_output$backtest_results, file.path(output_dir, "backtest_results.rds"))
  saveRDS(backtest_output$accuracy_metrics, file.path(output_dir, "accuracy_metrics.rds"))
  saveRDS(backtest_output, file.path(output_dir, "backtest_complete.rds"))
  write_csv(backtest_output$backtest_results, file.path(output_dir, "backtest_results.csv"))
  write_csv(backtest_output$accuracy_metrics, file.path(output_dir, "accuracy_metrics.csv"))
  message(glue("Results saved to {output_dir}"))
}

message("\n=== Backtest harness ready ===")
message("Functions: run_backtest(), calculate_accuracy_metrics(), plot_nowcast_vs_actual(), plot_forecast_errors(), generate_backtest_report(), save_backtest_results()\n")

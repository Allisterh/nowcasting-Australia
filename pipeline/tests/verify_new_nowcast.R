#### End-to-end verification of new nowcast after trans codes wired ####
# Uses cached master dataset to avoid refetching data. Runs:
#   estimate_dfm() → generate_nowcast() → inspect output
# Does NOT save vintages or touch JSON.

suppressPackageStartupMessages({
  library(tidyverse)
  library(nowcasting)
  library(glue)
  library(lubridate)
})

# Working dir: pipeline/
setwd("pipeline")

source("04_release_calendar.R")
source("05_estimate_model.R")
source("06_generate_nowcast.R")

master_data <- readRDS(".cache/processed/master_dataset_wide.rds")

cat("\n=== Estimating DFM (r=3) with new trans codes ===\n\n")
config <- configure_dfm(n_factors = 3)
data_prepared <- prepare_data_for_dfm(master_data)
model <- estimate_dfm(data_prepared, config)

cat("\n\n=== Generating nowcast ===\n")
nowcast <- generate_nowcast(model, master_data)

cat("\n\n=== RESULT ===\n")
cat(sprintf("target_quarter:         %s\n", nowcast$target_quarter))
cat(sprintf("nowcast_value ($M):     %s\n", format(round(nowcast$nowcast_value), big.mark=",")))
cat(sprintf("qoq_growth (%%):         %+.3f\n", nowcast$qoq_growth))
cat(sprintf("yoy_growth (%%):         %+.3f\n", nowcast$yoy_growth))
cat(sprintf("latest_actual_quarter:  %s\n", nowcast$latest_actual_quarter))
cat(sprintf("latest_actual_value:    %s\n", format(round(nowcast$latest_actual_value), big.mark=",")))

# Sanity checks
cat("\n=== Sanity checks ===\n")
stopifnot(is.finite(nowcast$qoq_growth))
stopifnot(abs(nowcast$qoq_growth) < 5)      # Australia hasn't had >5% QoQ since COVID bounce
stopifnot(nowcast$nowcast_value > 500000)   # Q4 2025 was ~693k
stopifnot(nowcast$nowcast_value < 800000)   # sanity upper
stopifnot(abs(nowcast$yoy_growth) < 10)     # Australia YoY rarely >5%
cat("✓ All sanity checks passed.\n")

# Expose for interactive use
invisible(list(model = model, nowcast = nowcast))

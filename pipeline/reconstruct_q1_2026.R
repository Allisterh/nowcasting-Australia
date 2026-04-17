#### Q1 2026 weekly vintage reconstruction ####
# One-off — builds a dense weekly track record for the 2026 Q1 nowcast under
# the post-MHSI-swap model. Steps:
#   1. Wipe all pre-existing vintages (they were produced with retail, not
#      household_spending, so their nowcasts don't reflect the current model).
#   2. Keep the 2026-04-17 vintage (first real MHSI-era run) as-is.
#   3. Re-simulate Mondays 2026-03-09 through 2026-04-13 using as-of-date
#      data snapshots, re-estimate DFM(r=3), generate Q1 2026 nowcast for each.
#   4. Regenerate site JSONs via emit_json().
#
# Run from pipeline/:  Rscript reconstruct_q1_2026.R

library(tidyverse)
library(lubridate)
library(glue)

if (!file.exists("04_release_calendar.R")) stop("Run from the pipeline/ directory.")

source("04_release_calendar.R")
source("05_estimate_model.R")
source("06_generate_nowcast.R")
source("08_vintage_tracking.R")   # provides VINTAGE_BASE_DIR / VINTAGE_CSV

#### Config ####

TARGET_QUARTER <- "2026 Q1"
KEEP_VINTAGE_ID <- "vintage_20260417_125842"

RECONSTRUCTION_DATES <- as.Date(c(
  "2026-03-09", "2026-03-16", "2026-03-23",
  "2026-03-30", "2026-04-06", "2026-04-13"
))

config <- configure_dfm(n_factors = 3, var_order = 1)

#### Step 1: wipe existing vintages, keep 2026-04-17 ####

cat("\n== Step 1: wiping pre-MHSI vintages ==\n")

existing <- read_csv(VINTAGE_CSV, show_col_types = FALSE)
cat(sprintf("Existing vintages: %d rows\n", nrow(existing)))

keep_row <- existing |> filter(vintage_id == KEEP_VINTAGE_ID)
if (nrow(keep_row) != 1) {
  stop(sprintf("Expected exactly 1 row for %s, found %d", KEEP_VINTAGE_ID, nrow(keep_row)))
}

# Delete RDS files for every vintage EXCEPT the keeper.
to_delete <- existing |> filter(vintage_id != KEEP_VINTAGE_ID)
for (fp in to_delete$file_path) {
  # file_path in CSV can be absolute from old project or relative .cache/... — handle both.
  candidates <- c(fp, file.path(".cache", sub("^.*/\\.cache/", "", fp)),
                  file.path(VINTAGE_BASE_DIR, basename(dirname(fp)), basename(fp)))
  for (c in candidates) {
    if (file.exists(c)) { file.remove(c); cat(sprintf("  removed %s\n", c)); break }
  }
}

# Write CSV with only the keeper row.
write_csv(keep_row, VINTAGE_CSV)
cat(sprintf("CSV reset to %d row(s) (kept %s)\n", nrow(keep_row), KEEP_VINTAGE_ID))

#### Step 2: load master dataset + Q1 2025 anchor for YoY ####

cat("\n== Step 2: loading master dataset ==\n")
master <- readRDS(".cache/processed/master_dataset_complete.rds")
master_wide <- master$wide
cat(sprintf("Master: %d periods × %d series\n", nrow(master_wide), ncol(master_wide) - 1))

gdp_history <- master_wide |>
  filter(!is.na(gdp_quarterly)) |>
  arrange(date) |>
  mutate(quarter = paste0(year(date), " Q", quarter(date)))

q1_2025_level <- gdp_history |> filter(quarter == "2025 Q1") |> pull(gdp_quarterly)
q4_2025_level <- gdp_history |> filter(quarter == "2025 Q4") |> pull(gdp_quarterly)

cat(sprintf("Anchor 2025 Q1 GDP: $%s M (for YoY)\n", format(round(q1_2025_level), big.mark = ",")))
cat(sprintf("Anchor 2025 Q4 GDP: $%s M (latest_actual for vintage rows)\n", format(round(q4_2025_level), big.mark = ",")))

#### Step 3: reconstruct weekly vintages ####

cat("\n== Step 3: reconstructing weekly vintages ==\n")

quarter_dir <- file.path(VINTAGE_BASE_DIR, "2026Q1")
dir.create(quarter_dir, showWarnings = FALSE, recursive = TRUE)

new_rows <- list()

for (d in RECONSTRUCTION_DATES) {
  d <- as.Date(d, origin = "1970-01-01")
  cat(sprintf("\n--- %s ---\n", d))

  snapshot <- get_available_data(master_wide, as_of_date = d, format = "wide")
  n_indicators_with_data <- sum(!is.na(snapshot[nrow(snapshot), -1]))
  cat(sprintf("  %d periods, %d indicators with recent data\n",
              nrow(snapshot), n_indicators_with_data))

  cat("  estimating DFM... ")
  model <- estimate_component_dfm(snapshot, config = config)
  cat("done.\n")

  cat("  nowcasting... ")
  nowcast <- generate_nowcast(model, snapshot, target_quarter = TARGET_QUARTER)
  cat("done.\n")

  point  <- as.numeric(nowcast$nowcast_value)
  qoq    <- as.numeric(nowcast$qoq_growth)
  yoy    <- (point / q1_2025_level - 1) * 100
  cat(sprintf("  → $%sM  QoQ %+.2f%%  YoY %+.2f%%\n",
              format(round(point), big.mark = ","), qoq, yoy))

  # Vintage ID + RDS with "_sim_" marker so these are distinguishable from live runs.
  ts_str    <- format(d, "%Y%m%d")
  vintage_id <- sprintf("vintage_sim_%s_090000", ts_str)
  run_ts     <- sprintf("%sT09:00:00Z", format(d, "%Y-%m-%d"))
  rds_path   <- file.path(quarter_dir, paste0(vintage_id, ".rds"))

  saveRDS(list(
    nowcast_value        = point,
    qoq_growth           = qoq,
    yoy_growth           = yoy,
    target_quarter       = TARGET_QUARTER,
    data_as_of_date      = d,
    model_config         = config,
    simulated            = TRUE,
    simulation_note      = "Reconstructed weekly vintage (post-MHSI, r=3)"
  ), rds_path)

  new_rows[[length(new_rows) + 1]] <- tibble(
    vintage_id           = vintage_id,
    run_timestamp        = run_ts,
    target_quarter       = TARGET_QUARTER,
    nowcast_value        = point,
    qoq_growth           = qoq,
    yoy_growth           = yoy,
    latest_actual_value  = q4_2025_level,
    data_as_of_date      = format(d, "%Y-%m-%d"),
    n_indicators         = 13L,
    n_indicators_updated = NA_integer_,  # not computed for reconstructions
    log_likelihood       = NA_real_,
    file_path            = rds_path
  )
}

#### Step 4: merge into tracking CSV ####

cat("\n== Step 4: updating vintage_tracking.csv ==\n")
all_rows <- bind_rows(keep_row, bind_rows(new_rows)) |>
  arrange(run_timestamp)
write_csv(all_rows, VINTAGE_CSV)
cat(sprintf("CSV now has %d rows (1 real + %d reconstructed)\n",
            nrow(all_rows), length(new_rows)))

#### Step 5: regenerate site JSONs ####

cat("\n== Step 5: regenerating JSON artifacts ==\n")
source("04_emit_json.R")

# We pass the latest real nowcast state as fallback; emit_json reads the CSV
# as canonical source, so `nowcast` arg is only used when no vintages exist.
latest_vintage_for_arg <- list(
  target_quarter        = TARGET_QUARTER,
  nowcast_value         = all_rows$nowcast_value[nrow(all_rows)],
  qoq_growth            = all_rows$qoq_growth[nrow(all_rows)],
  yoy_growth            = all_rows$yoy_growth[nrow(all_rows)],
  latest_actual_quarter = "2025 Q4",
  latest_actual_value   = q4_2025_level,
  generated_date        = Sys.Date()
)

emit_json(
  target_dir   = "../data",
  nowcast      = latest_vintage_for_arg,
  master       = master,
  vintage_info = list(vintage_id = tail(all_rows$vintage_id, 1),
                      file_path  = tail(all_rows$file_path, 1))
)

cat("\n== DONE ==\n")
cat(sprintf("Total runtime: %s\n", format(Sys.time(), "%H:%M:%S")))

#### Recovery: finish Step 4 + Step 5 from reconstruct_q1_2026.R ####
# The original script saved all 6 vintage RDS files then died on a bind_rows
# type mismatch (character vs datetime). All the expensive DFM fitting is
# already done — this just (a) builds vintage rows from the RDS files,
# (b) merges with the existing CSV, (c) emits the site JSONs.

library(tidyverse)
library(lubridate)

if (!file.exists("08_vintage_tracking.R")) stop("Run from pipeline/.")
source("08_vintage_tracking.R")   # for VINTAGE_CSV

# --- Read existing CSV with all cols as character to dodge type mismatches.
existing <- read_csv(VINTAGE_CSV, show_col_types = FALSE,
                     col_types = cols(.default = col_character()))

# --- Master dataset (for Q4 2025 actual + emit_json).
master <- readRDS(".cache/processed/master_dataset_complete.rds")
gdp_hist <- master$wide |>
  filter(!is.na(gdp_quarterly)) |>
  arrange(date) |>
  mutate(q = paste0(year(date), " Q", quarter(date)))
q4_2025_level <- gdp_hist |> filter(q == "2025 Q4") |> pull(gdp_quarterly)

# --- Load the 6 sim RDS files and build vintage rows as character throughout.
sim_files <- sort(list.files(".cache/model_output/vintages/2026Q1",
                             pattern = "^vintage_sim_", full.names = TRUE))

new_rows <- map_dfr(sim_files, function(fp) {
  r <- readRDS(fp)
  vid <- tools::file_path_sans_ext(basename(fp))
  as_of <- as.Date(r$data_as_of_date)
  tibble(
    vintage_id           = vid,
    run_timestamp        = format(as.POSIXct(sprintf("%s 09:00:00", as_of), tz = "UTC"),
                                  "%Y-%m-%dT%H:%M:%SZ"),
    target_quarter       = r$target_quarter,
    nowcast_value        = as.character(r$nowcast_value),
    qoq_growth           = as.character(r$qoq_growth),
    yoy_growth           = as.character(r$yoy_growth),
    latest_actual_value  = as.character(q4_2025_level),
    data_as_of_date      = format(as_of, "%Y-%m-%d"),
    n_indicators         = "13",
    n_indicators_updated = NA_character_,
    log_likelihood       = NA_character_,
    file_path            = fp
  )
})

all_rows <- bind_rows(existing, new_rows) |> arrange(run_timestamp)
write_csv(all_rows, VINTAGE_CSV)
cat(sprintf("Wrote %d rows to %s (%d existing + %d new)\n",
            nrow(all_rows), VINTAGE_CSV, nrow(existing), nrow(new_rows)))

# --- Emit site JSONs. emit_json reads the CSV as canonical source, so the
#     `nowcast` arg is only a fallback. Build it from the most recent row.
source("04_emit_json.R")
latest <- tail(all_rows, 1)

nowcast_arg <- list(
  target_quarter        = latest$target_quarter,
  nowcast_value         = as.numeric(latest$nowcast_value),
  qoq_growth            = as.numeric(latest$qoq_growth),
  yoy_growth            = as.numeric(latest$yoy_growth),
  latest_actual_quarter = "2025 Q4",
  latest_actual_value   = as.numeric(latest$latest_actual_value),
  generated_date        = Sys.Date()
)

emit_json(
  target_dir   = "../data",
  nowcast      = nowcast_arg,
  master       = master,
  vintage_info = list(vintage_id = latest$vintage_id, file_path = latest$file_path)
)

cat("\n== Recovery complete ==\n")

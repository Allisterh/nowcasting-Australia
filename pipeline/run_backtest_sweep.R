#### Factor-count sweep backtest ####
# Runs the POOS backtest at n_factors = 2, 3, 4. Saves per-r results to
# .cache/backtest_output/r{N}/. Writes a consolidated comparison markdown
# + CSV at .cache/backtest_output/comparison.{md,csv}.
#
# Usage (from repo root):
#   cd pipeline && Rscript run_backtest_sweep.R
#
# Expected total runtime: 2-3 hours (3 × ~45 min per r).

setwd(dirname(sys.frame(1)$ofile))  # ensure cwd = pipeline/
# Rscript doesn't populate sys.frame for top-level; fall back:
if (!dir.exists(".cache")) setwd("pipeline")

cat("\n========================================\n")
cat("  FACTOR-COUNT BACKTEST SWEEP\n")
cat("========================================\n")
cat(sprintf("Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("r values: 2, 3, 4\n")
cat("Window: 2020-01-01 to 2025-12-31 (quarterly)\n")
cat("========================================\n\n")

# Load backtest harness (which sources 04/05/06 internally).
source("09_backtest_model.R")

# Load the master dataset produced by the most recent pipeline run.
cat("Loading master dataset... ")
master <- readRDS(".cache/processed/master_dataset_complete.rds")
cat(sprintf("ok (%d periods, %d indicators)\n\n",
            nrow(master$wide), ncol(master$wide) - 1))

out_root <- ".cache/backtest_output"
dir.create(out_root, showWarnings = FALSE, recursive = TRUE)

sweep_start <- Sys.time()
summaries <- list()

for (r in c(2, 3, 4)) {
  cat(sprintf("\n\n########## r = %d ##########\n", r))
  r_start <- Sys.time()
  config <- configure_dfm(n_factors = r, var_order = 1)

  results <- run_backtest(
    master_data = master,
    config      = config,
    start_date  = "2020-01-01",
    end_date    = "2025-12-31",
    frequency   = "quarterly",
    verbose     = TRUE
  )

  out_dir <- file.path(out_root, sprintf("r%d", r))
  save_backtest_results(results, output_dir = out_dir)

  subtitle <- sprintf("r = %d  |  2020–2025", r)
  plot_nowcast_vs_actual(results$backtest_results,
                         save_path = file.path(out_dir, "nowcast_vs_actual.png"),
                         subtitle = subtitle)
  plot_forecast_errors(results$backtest_results,
                       save_path = file.path(out_dir, "forecast_errors.png"),
                       subtitle = subtitle)
  generate_backtest_report(results, save_path = file.path(out_dir, "backtest_report.md"))

  r_runtime <- as.numeric(difftime(Sys.time(), r_start, units = "mins"))
  cat(sprintf("\nr = %d complete in %.1f min\n", r, r_runtime))

  # Stash the metrics keyed by r for the comparison writeup.
  met <- results$accuracy_metrics
  met$r <- r
  summaries[[as.character(r)]] <- met
}

sweep_runtime <- as.numeric(difftime(Sys.time(), sweep_start, units = "mins"))

# --- Consolidated comparison ----------------------------------------------

cat("\n\n=== Building comparison ===\n")

long_metrics <- bind_rows(summaries)
wide_metrics <- long_metrics |>
  pivot_wider(names_from = r, values_from = value, names_prefix = "r")

write_csv(wide_metrics, file.path(out_root, "comparison.csv"))

# Markdown comparison ------------------------------------------------------

fmt_num <- function(x, digits = 2) {
  if (is.na(x)) return("—")
  if (abs(x) >= 1000) return(scales::comma(round(x)))
  formatC(x, format = "f", digits = digits)
}

lines <- c(
  "# Factor-count backtest comparison",
  "",
  sprintf("**Generated:** %s", format(Sys.time(), "%Y-%m-%d %H:%M UTC")),
  sprintf("**Window:** 2020–2025 quarterly (%d forecasts per r)",
          round(long_metrics |> filter(metric == "n_forecasts") |> pull(value) |> max(na.rm = TRUE))),
  sprintf("**Total sweep runtime:** %.1f minutes", sweep_runtime),
  "",
  "## Summary table",
  "",
  "| Metric | r = 2 | r = 3 | r = 4 |",
  "|---|---:|---:|---:|"
)
for (i in seq_len(nrow(wide_metrics))) {
  row <- wide_metrics[i, ]
  lines <- c(lines, sprintf("| %s | %s | %s | %s |",
                            row$metric, fmt_num(row$r2), fmt_num(row$r3), fmt_num(row$r4)))
}

lines <- c(
  lines,
  "",
  "## Reading this table",
  "",
  "- **Lower is better:** MAE, RMSE, MAPE, median |error|, MAE/RMSE (QoQ), |bias|",
  "- **Higher is better:** correlation, directional hit rate",
  "- MAE/RMSE in levels ($M) vs QoQ (pp) let you judge whether a model's error is spread across the level or concentrated in directional misses.",
  "",
  "## Per-r artifacts",
  "",
  "Each `r{N}/` directory contains:",
  "- `backtest_results.{rds,csv}` — per-quarter results with errors",
  "- `accuracy_metrics.{rds,csv}` — aggregate metrics",
  "- `backtest_complete.rds` — entire run output including config",
  "- `nowcast_vs_actual.png`, `forecast_errors.png` — diagnostics charts",
  "- `backtest_report.md` — self-contained report",
  "",
  "## Recommendation workflow",
  "",
  "1. Eyeball MAE and MAPE across the three r values.",
  "2. If r = 3 isn't the winner, check whether the gap is material (say, >5% relative improvement) vs within-noise.",
  "3. Cross-check hit rate and QoQ MAE — a model with lower level error but worse direction-calling may actually be weaker for the user-facing number.",
  "4. Inspect per-quarter charts for each r: does the winner degrade less around COVID, or does it overfit weak quarters?",
  ""
)

writeLines(lines, file.path(out_root, "comparison.md"))

cat(sprintf("\n\n========================================\n"))
cat(sprintf("  SWEEP COMPLETE\n"))
cat(sprintf("========================================\n"))
cat(sprintf("Total runtime: %.1f minutes\n", sweep_runtime))
cat(sprintf("Outputs: %s/\n", out_root))
cat("  r2/ r3/ r4/  — per-r artifacts\n")
cat("  comparison.md — headline summary table\n")
cat("  comparison.csv — metrics in wide form\n\n")

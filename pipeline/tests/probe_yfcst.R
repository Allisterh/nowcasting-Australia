#### Probe yfcst output scale after trans codes applied ####
# One-off diagnostic: run the model and dump yfcst tail to confirm what
# scale the nowcast comes out in (level? QoQ fraction? standardized?).

suppressPackageStartupMessages({
  library(tidyverse)
  library(nowcasting)
  library(glue)
})

# Source from pipeline/ relative to repo root
source("pipeline/05_estimate_model.R", chdir = TRUE)

master_data <- readRDS("pipeline/.cache/processed/master_dataset_wide.rds")
config <- configure_dfm(n_factors = 3)
data_prepared <- prepare_data_for_dfm(master_data)
model <- estimate_dfm(data_prepared, config)

saveRDS(model, "pipeline/.cache/model_output/probe_model.rds")

cat("\n\n=== yfcst tail + scale check ===\n")
yf <- model$yfcst
cat("dim:", dim(yf), "\n")
cat("colnames:", paste(colnames(yf), collapse = ", "), "\n")
cat("time range:", range(as.numeric(time(yf))), "\n\n")
cat("Last 15 rows:\n")
print(tail(yf, 15))

cat("\n\nPer-column summary (non-NA):\n")
for (col in colnames(yf)) {
  v <- yf[, col]; v <- v[!is.na(v)]
  if (length(v) > 0) {
    cat(sprintf("  %s: n=%3d  min=%10.5f  max=%10.5f  mean=%10.5f\n",
                col, length(v), min(v), max(v), mean(v)))
  } else {
    cat(sprintf("  %s: all NA\n", col))
  }
}

# Check target quarter specifically
target_time <- 2026 + 0/4  # 2026 Q1
times <- as.numeric(time(yf))
idx <- which(abs(times - target_time) < 1e-6)
if (length(idx) == 1) {
  cat(sprintf("\nQ1 2026 row (idx %d, t=%.4f):\n", idx, times[idx]))
  print(yf[idx, ])
}

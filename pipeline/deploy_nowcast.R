#### Deploy nowcast: estimate → nowcast → vintage → JSONs ####
# Leaner than run_complete_nowcast.R: skips data-fetch steps (assumes the
# cached master_dataset_complete.rds is current). Use this when you've
# changed model spec (trans codes, COVID mask, factor count, etc.) and
# want to push a fresh nowcast without refetching ABS/FRED/NAB.
#
# Usage (from repo root):
#   Rscript -e 'setwd("pipeline"); source("deploy_nowcast.R")'

if (basename(getwd()) != "pipeline") {
  if (file.exists("pipeline/deploy_nowcast.R")) setwd("pipeline")
  else stop("deploy_nowcast.R: run from pipeline/ or repo root")
}

cat("\n========================================\n")
cat("  DEPLOY NOWCAST (skip fetch)\n")
cat("========================================\n\n")

master_path <- ".cache/processed/master_dataset_complete.rds"
if (!file.exists(master_path)) {
  stop(sprintf("Cached master not found (%s). Run run_complete_nowcast.R first.",
               master_path))
}
master <- readRDS(master_path)
cat(sprintf("Loaded cached master: %d periods × %d cols (through %s)\n\n",
            nrow(master$wide), ncol(master$wide) - 1,
            as.character(max(master$wide$date))))

source("05_estimate_model.R")
source("06_generate_nowcast.R")
source("08_vintage_tracking.R")
source("04_emit_json.R")

cat("\nStep 1 / 4: Estimate DFM (r=3, VAR(1))\n")
cat("----------------------------------------\n")
config <- configure_dfm(n_factors = 3, var_order = 1)
model <- estimate_component_dfm(master$wide, config = config)
saveRDS(model, ".cache/model_output/estimated_model.rds")

cat("\nStep 2 / 4: Generate nowcast\n")
cat("----------------------------------------\n")
nowcast <- generate_nowcast(model, master$wide)

cat("\nStep 3 / 4: Save vintage\n")
cat("----------------------------------------\n")
all_indicators <- NULL  # not required by save_vintage when using cached master
vintage_info <- save_vintage(
  nowcast_result = nowcast,
  model = model,
  master_data = master$wide,
  all_indicators = all_indicators
)
cat(sprintf("  vintage: %s\n", vintage_info$vintage_id))

cat("\nStep 4 / 4: Emit JSON\n")
cat("----------------------------------------\n")
emit_json(
  target_dir = "../data",
  nowcast = nowcast,
  master = master,
  vintage_info = vintage_info
)

cat("\n========================================\n")
cat("  DEPLOY COMPLETE\n")
cat("========================================\n")
cat(sprintf("Target:     %s\n", nowcast$target_quarter))
cat(sprintf("Nowcast:    $%s M   (%+.2f%% QoQ, %+.2f%% YoY)\n",
            format(round(nowcast$nowcast_value), big.mark=","),
            nowcast$qoq_growth, nowcast$yoy_growth))
cat(sprintf("Level:      $%s M (%s actual)\n",
            format(round(nowcast$latest_actual_value), big.mark=","),
            nowcast$latest_actual_quarter))
cat(sprintf("JSON:       ../data/latest.json\n"))
cat(sprintf("Vintage:    %s\n", vintage_info$file_path))

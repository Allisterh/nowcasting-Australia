#### test_emit_json.R ####
# Smoke test for 04_emit_json.R. Exercises the emitter with fixture data
# (or falls back to the legacy james-mess RDS files if fixtures are absent)
# and asserts the 5 JSON files are written with the right top-level shape.
#
# Run from pipeline/ with:   Rscript tests/test_emit_json.R

library(jsonlite)

# Locate pipeline root
if (basename(getwd()) == "tests") setwd("..")
stopifnot(file.exists("run_complete_nowcast.R"))

# Load emit_json
source("04_emit_json.R")

# VINTAGE_BASE_DIR is defined in 08_vintage_tracking.R — we need a non-empty CSV
# for the full smoke test. Source 08 to make the constant available.
source("08_vintage_tracking.R")

# Fixture strategy:
#   1. Preferred: fixtures under pipeline/tests/fixtures/
#   2. Fallback: the legacy RDS files under james-mess/
FIXTURE_DIR <- "tests/fixtures"
LEGACY_DIR  <- "../../../../R/james-mess/data/project_nowcast"

fixture_or_legacy <- function(fixture_rel, legacy_rel) {
  f <- file.path(FIXTURE_DIR, fixture_rel)
  if (file.exists(f)) return(f)
  l <- file.path(LEGACY_DIR, legacy_rel)
  if (file.exists(l)) return(l)
  stop(sprintf("Neither fixture (%s) nor legacy (%s) found", f, l))
}

latest_rds <- fixture_or_legacy("latest_nowcast.rds", "model_output/latest_nowcast.rds")
master_rds <- fixture_or_legacy("master_dataset_complete.rds", "processed/master_dataset_complete.rds")

latest <- readRDS(latest_rds)
master <- readRDS(master_rds)

# If the legacy file has the stale "2025 Qq" target_quarter, patch it so emit_json
# gets a parseable value. New pipeline runs produce proper quarter strings.
if (grepl("Qq$", latest$target_quarter)) {
  latest$target_quarter <- "2026 Q1"
  latest$latest_actual_quarter <- "2025 Q4"
}

# If legacy vintage_tracking.csv is missing, we still want the emitter to
# produce an empty vintages array and empty performance section.
vintage_tracking <- file.path(VINTAGE_BASE_DIR, "vintage_tracking.csv")
if (!file.exists(vintage_tracking)) {
  # Temporarily point VINTAGE_BASE_DIR at the legacy location so the vintage
  # CSV can be found.
  legacy_vbd <- file.path(LEGACY_DIR, "model_output/vintages")
  if (file.exists(file.path(legacy_vbd, "vintage_tracking.csv"))) {
    assignInGlobalEnv <- function(x, val) assign(x, val, envir = .GlobalEnv)
    assignInGlobalEnv("VINTAGE_BASE_DIR", legacy_vbd)
  }
}

# Use a temp output dir so we don't clobber the real data/
out_dir <- tempfile("emit_json_test_")
dir.create(out_dir, recursive = TRUE)

vintage_info_stub <- list(
  vintage_id = "test_fixture",
  file_path  = "fixture"
)

emit_json(
  target_dir   = out_dir,
  nowcast      = latest,
  master       = master,
  vintage_info = vintage_info_stub
)

# Assertions
expected_files <- c("latest.json", "gdp.json", "nowcasts.json", "indicators.json", "performance.json")
for (f in expected_files) {
  path <- file.path(out_dir, f)
  stopifnot(file.exists(path))
  parsed <- fromJSON(path, simplifyVector = FALSE)
  stopifnot(is.list(parsed))
  cat(sprintf("✓ %s parsed OK\n", f))
}

# Shape checks
latest_j <- fromJSON(file.path(out_dir, "latest.json"), simplifyVector = FALSE)
stopifnot(!is.null(latest_j$target_quarter))
stopifnot(is.numeric(latest_j$nowcast$gdp_chain_volume_millions))
stopifnot(is.numeric(latest_j$nowcast$qoq_growth_pct))
stopifnot(!is.null(latest_j$next_gdp_release_date))

gdp_j <- fromJSON(file.path(out_dir, "gdp.json"))
stopifnot(length(gdp_j$series) > 0 || nrow(gdp_j$series) > 0)

ind_j <- fromJSON(file.path(out_dir, "indicators.json"), simplifyVector = FALSE)
stopifnot(length(ind_j$indicators) == 12)  # exactly 12 predictors
stopifnot(all(sapply(ind_j$indicators, function(x) x$id) %in%
  c("employment","unemp_rate","part_rate","hours_worked","household_spending","cons_conf",
    "building_approvals","bus_conf","goods_exp","services_exp","goods_imp","services_imp")))

# Data-update audit trail (data-visibility feature). Every indicator carries the
# updated_this_run flag, and latest.json carries a data_updates record. This first
# emit runs into an EMPTY temp dir, so there is no previously-committed JSON to
# diff against -> nothing is flagged and the series list is empty. (The advance-
# detection path is covered by nowcasting_v2/tests/test_data_updates.py.)
stopifnot(!is.null(latest_j$data_updates))
stopifnot(!is.null(latest_j$data_updates$run_date))
stopifnot(is.list(latest_j$data_updates$series))
stopifnot(length(latest_j$data_updates$series) == 0)
stopifnot(all(sapply(ind_j$indicators, function(x) is.logical(x$updated_this_run))))
stopifnot(all(sapply(ind_j$indicators, function(x) isFALSE(x$updated_this_run))))
# Unflagged indicators must OMIT prev/latest_period entirely (a named NULL would
# serialise as {} and violate the frontend's `prev_period?: string` contract).
stopifnot(all(sapply(ind_j$indicators, function(x) is.null(x$prev_period))))
stopifnot(all(sapply(ind_j$indicators, function(x) is.null(x$latest_period))))
cat("✓ data_updates audit trail present; no advances on empty baseline\n")

cat("\n✅ emit_json smoke test PASSED\n")
cat(sprintf("   Output in: %s\n", out_dir))

#### Add trans_code column to component_metadata ####
# One-off utility: writes per-series Bpanel trans codes + rationale into
# seed/component_metadata.rds so 05_estimate_model.R can read them as the
# single source of truth. Rerun if priors change.
#
# Validated empirically by pipeline/tests/stationarity_check.R — all codes
# below produce ADF p<0.05 AND KPSS p>0.05 on the COVID-masked sample.

suppressPackageStartupMessages({
  library(tidyverse)
})

md_path <- "pipeline/seed/component_metadata.rds"
md <- readRDS(md_path)

trans_spec <- tribble(
  ~indicator_id,        ~trans_code, ~trans_rationale,
  "household_spending",  1,          "MoM %: trending $ level, non-stationary; MoM growth stationary",
  "cons_conf",           2,          "First diff: bounded index ~[-30,30], level drifts",
  "building_app",        1,          "MoM %: trending noisy count, log-equivalent scale handles outliers",
  "bus_conf",            2,          "First diff: bounded diffusion index, level drifts",
  "exports_goods",       1,          "MoM %: trending $ level",
  "exports_servs",       7,          "3-mo %: quarterly series on monthly grid, maps to QoQ %",
  "imports_goods",       1,          "MoM %: trending $ level",
  "imports_servs",       7,          "3-mo %: quarterly series on monthly grid, maps to QoQ %",
  "employment",          1,          "MoM %: trending labour force, stationary in growth",
  "unemp_rate",          2,          "First diff: rate bounded ~[3,7]%, level drifts",
  "participation",       2,          "First diff: rate bounded ~[63,67]%, level drifts",
  "hours_worked",        1,          "MoM %: trending level, stationary in growth",
  "gdp_quarterly",       7,          "3-mo %: quarterly level on monthly grid → QoQ % (target)"
)

# Join onto metadata
md$indicators <- md$indicators |>
  select(-any_of(c("trans_code", "trans_rationale"))) |>
  left_join(trans_spec, by = "indicator_id")

# Validate: every indicator must have a code
missing <- md$indicators |> filter(is.na(trans_code))
if (nrow(missing) > 0) {
  stop(paste("Indicators missing trans_code:",
             paste(missing$indicator_id, collapse = ", ")))
}

cat("Updated indicators table:\n")
print(md$indicators |> select(indicator_id, frequency, trans_code, trans_rationale))

saveRDS(md, md_path)
cat("\nWrote updated metadata to:", md_path, "\n")

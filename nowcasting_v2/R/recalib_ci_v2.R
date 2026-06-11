# Recalibrate the v2 CI bands under the HISTORICALLY-ACCURATE publication lags
# (.lag_acc in backtest_v2.R: matches the live emit except MHSI=35d, the true
# historical schedule for the calibration window, avoiding the look-ahead leak a
# 28d MHSI lag introduced). Re-runs both production-model backtests (headline
# qa_a05, stress umidas_a20; panel B3_nab_wmi = exclude AiG + rt) on the CURRENT
# panel rds. compute_ci_params.R then turns the CSVs into ci_params_v2*.json.
#
# Run from nowcasting_v2/:  Rscript R/recalib_ci_v2.R
source("R/backtest_v2.R")

AIG <- c("aig_pmi", "aig_pci", "aig_psi")
dir.create("cache/ci_recalib", recursive = TRUE, showWarnings = FALSE)

cat("\n==== QA (qa_a05) backtest under ACCURATE historical lags (MHSI=35) ====\n")
backtest_v2(out_csv = "cache/ci_recalib/qa_a05_acc.csv",
            model = "qa", sel_alpha = 0.05, dfm_q = 1L, qa_lag = 0L:1L,
            exclude_ids = c(AIG, "rt"), lag_fn = .lag_acc, verbose = FALSE)

cat("\n==== UMIDAS (umidas_a20) backtest under ACCURATE historical lags (MHSI=35) ====\n")
backtest_v2(out_csv = "cache/ci_recalib/umidas_a20_acc.csv",
            model = "umidas", sel_alpha = 0.20, dfm_q = 1L, qa_lag = 0L:1L,
            exclude_ids = c(AIG, "rt"), lag_fn = .lag_acc, verbose = FALSE)

cat("\n==== done. CSVs in cache/ci_recalib/ ====\n")

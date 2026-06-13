# spec_sweep.R — two spec-LEVER experiments (James, 2026-06-12).
# Bucket-B DATA expansion already came back NO-GO at production spec; this probes the
# two places v2's SPEC deviates from the RBA's published method, not the data.
#
#   Config A (reference): sel_alpha=0.05, covid_dummies=ON   -> cache/bucketb/summary.csv
#                          (production headline; marginals null by construction — gate
#                           admits 0 Bucket-B series at 0.05, so every variant == baseline)
#   Config B (LEVER 1):    sel_alpha=0.10, covid_dummies=ON   (the RBA's actual alpha)
#   Config C (LEVER 2):    sel_alpha=0.05, covid_dummies=OFF  (drop 2020-21 selection dummies)
#
# Each config runs the SAME variant set, holding all other knobs at the production
# headline (model=qa, dfm_q=1, qa_lag=0:1, exclude=AIG+rt):
#   baseline      -> production 29-set (all 9 Bucket-B excluded)
#   marg_<id>     -> production + that one Bucket-B series (x9)
#   full_bucketb  -> production + all 9
# The marginal deltas isolate "does this lever let series X in, and does that help?".
#
# JUDGING (James's call: all 3 windows reported, he decides). full = circular for the
# COVID-off lever (it refits 2020) — postCOVID(2022+)/OOS8 are the honest read. Each
# config's deltas are vs ITS OWN baseline; we also print every baseline vs the
# production a=0.05/covid-ON reference so the lever's headline cost is visible.
# Resume-safe: every variant's result CSV is read back if present.

suppressWarnings(suppressMessages({
  here <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
}))
if (is.na(here) || !nzchar(here)) here <- "R"
source(file.path(here, "backtest_v2.R"))
suppressMessages({ library(dplyr); library(readr) })

PANEL <- "cache/panel_vintage_bucketb.rds"; INFO <- "seed/panel_info.csv"
OUT   <- "cache/specsweep"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
POSTCOVID_FROM <- as.Date("2022-01-01"); OOS_N <- 8L

AIG <- c("aig_pmi","aig_pci","aig_psi"); BASE_EXCL <- c(AIG, "rt")
NEW <- c("debit_card","credit_personal","import","hs_ba","nh_ba","alt_add","non_res_ba","twi","icp")

# production a=0.05 / covid-ON reference (from cache/bucketb/summary.csv baseline)
REF <- list(full = 0.4535, pc = 0.3422, oos8 = 0.2409)

# the three configs. A is the reference; recomputed here too for an apples-to-apples
# selection trace, but its numbers should match REF.
CONFIGS <- list(
  A_ref      = list(alpha = 0.05, covid = TRUE),
  B_alpha10  = list(alpha = 0.10, covid = TRUE),
  C_covidoff = list(alpha = 0.05, covid = FALSE)
)

.metrics <- function(res) {
  res <- res[!is.na(res$qoq_error), , drop = FALSE]
  res$tqd <- as.Date(res$target_quarter_date); res <- res[order(res$tqd), ]
  pc  <- res[res$tqd >= POSTCOVID_FROM, , drop = FALSE]
  oos <- if (nrow(res) >= OOS_N) tail(res, OOS_N) else res
  rmse <- function(d) if (nrow(d)) sqrt(mean(d$qoq_error^2)) else NA_real_
  hit  <- function(d) if (nrow(d)) mean(d$direction_correct, na.rm = TRUE) * 100 else NA_real_
  data.frame(rmse_full = rmse(res), rmse_pc = rmse(pc), rmse_oos = rmse(oos),
             hit_pc = hit(pc), n_pc = nrow(pc))
}

run_one <- function(cfg_id, var_id, exclude_ids, alpha, covid) {
  out_csv <- file.path(OUT, paste0(cfg_id, "__", var_id, ".csv"))
  if (file.exists(out_csv)) {
    m <- .metrics(read_csv(out_csv, show_col_types = FALSE))
    cat(sprintf(">>> %-22s CACHED  full=%.4f pc=%.4f oos8=%.4f\n", var_id, m$rmse_full, m$rmse_pc, m$rmse_oos))
    return(cbind(config = cfg_id, variant = var_id, alpha = alpha, covid = covid, n_sel = NA_integer_, m))
  }
  t0 <- Sys.time()
  bt <- backtest_v2(panel_rds = PANEL, panel_info_csv = INFO, out_csv = out_csv, model = "qa",
                    exclude_ids = exclude_ids, sel_alpha = alpha, dfm_q = 1L,
                    covid_dummies = covid, qa_lag = 0L:1L, verbose = FALSE)
  el <- as.numeric(difftime(Sys.time(), t0, units = "mins")); m <- .metrics(bt$results)
  cat(sprintf(">>> %-22s full=%.4f pc=%.4f oos8=%.4f  (%.1f min, %d sel: %s)\n",
              var_id, m$rmse_full, m$rmse_pc, m$rmse_oos, el, length(bt$fixed_selection),
              paste(bt$fixed_selection, collapse = "|")))
  cbind(config = cfg_id, variant = var_id, alpha = alpha, covid = covid,
        n_sel = length(bt$fixed_selection), m)
}

variants <- c(list(baseline = c(BASE_EXCL, NEW)),
              setNames(lapply(NEW, function(s) c(BASE_EXCL, setdiff(NEW, s))),
                       paste0("marg_", NEW)),
              list(full_bucketb = BASE_EXCL))

rows <- list()
for (cfg_id in names(CONFIGS)) {
  cf <- CONFIGS[[cfg_id]]
  cat(sprintf("\n############## %s  (alpha=%.2f, covid=%s) ##############\n",
              cfg_id, cf$alpha, cf$covid))
  for (var_id in names(variants)) {
    rows[[paste0(cfg_id, "__", var_id)]] <- tryCatch(
      run_one(cfg_id, var_id, variants[[var_id]], cf$alpha, cf$covid),
      error = function(e) { cat(sprintf("  [FAIL] %s/%s: %s\n", cfg_id, var_id, conditionMessage(e))); NULL })
  }
}
summ <- do.call(rbind, Filter(Negate(is.null), rows))

# within-config deltas vs that config's own baseline (negative = better)
summ$d_full <- NA_real_; summ$d_pc <- NA_real_; summ$d_oos <- NA_real_
for (cfg_id in unique(summ$config)) {
  b <- summ[summ$config == cfg_id & summ$variant == "baseline", ]
  idx <- summ$config == cfg_id
  summ$d_full[idx] <- round(summ$rmse_full[idx] - b$rmse_full, 4)
  summ$d_pc[idx]   <- round(summ$rmse_pc[idx]   - b$rmse_pc,   4)
  summ$d_oos[idx]  <- round(summ$rmse_oos[idx]  - b$rmse_oos,  4)
}
# each baseline's lever cost vs the production reference
summ$d_full_vs_ref <- round(summ$rmse_full - REF$full, 4)
summ$d_pc_vs_ref   <- round(summ$rmse_pc   - REF$pc,   4)
summ$d_oos_vs_ref  <- round(summ$rmse_oos  - REF$oos8, 4)

write_csv(summ, file.path(OUT, "summary_specsweep.csv"))

cat("\n================= SPEC-SWEEP SUMMARY =================\n")
cat(sprintf("production reference (a=0.05, covid ON): full=%.4f pc=%.4f oos8=%.4f\n\n",
            REF$full, REF$pc, REF$oos8))
cat("--- config baselines vs production reference (lever headline cost) ---\n")
print(summ[summ$variant == "baseline",
           c("config","alpha","covid","n_sel","rmse_full","rmse_pc","rmse_oos",
             "d_full_vs_ref","d_pc_vs_ref","d_oos_vs_ref")], row.names = FALSE)
cat("\n--- within-config marginals (Δ vs that config's baseline; negative = better) ---\n")
for (cfg_id in names(CONFIGS)) {
  s <- summ[summ$config == cfg_id, ]
  s <- s[order(s$d_pc), c("variant","n_sel","rmse_full","rmse_pc","rmse_oos","d_full","d_pc","d_oos","hit_pc")]
  cat(sprintf("\n[%s]\n", cfg_id)); print(s, row.names = FALSE)
}
cat(sprintf("\n-> %s\n", file.path(OUT, "summary_specsweep.csv")))

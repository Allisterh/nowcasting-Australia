# bucketb_backtest.R — marginal one-at-a-time backtest of the 9 Bucket-B series
# against the live 29-series headline config, plus a full-Bucket-B variant.
#
# Design (see BUCKET-B-NIGHT-LOG.md): ONE combined panel (cache/panel_vintage_bucketb.rds,
# 29 baseline + 9 Bucket-B). Each variant differs ONLY in exclude_ids, so the
# estimation math + config are held fixed at the production headline:
#   model=qa, sel_alpha=0.05, dfm_q=1, qa_lag=0:1, exclude=c(AIG,"rt").
#   baseline   -> exclude AIG,rt + ALL 9 Bucket-B  (== production 29-set)
#   marg_<id>  -> exclude AIG,rt + 8 Bucket-B      (production + that one series)
#   full       -> exclude AIG,rt                   (production + all 9)
# Scores RMSE/hit over full / post-COVID(2022+) / last-8q-OOS windows vs latest GDP.
# Resume-safe: per-variant results CSV is read back if present.

suppressWarnings(suppressMessages({
  here <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
}))
if (is.na(here) || !nzchar(here)) here <- "R"
source(file.path(here, "backtest_v2.R"))
suppressMessages({ library(dplyr); library(readr) })

PANEL  <- "cache/panel_vintage_bucketb.rds"
INFO   <- "seed/panel_info.csv"
OUT    <- "cache/bucketb"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
POSTCOVID_FROM <- as.Date("2022-01-01"); OOS_N <- 8L

AIG  <- c("aig_pmi","aig_pci","aig_psi")
BASE_EXCL <- c(AIG, "rt")                                  # production headline exclusions
NEW  <- c("debit_card","credit_personal","import","hs_ba","nh_ba","alt_add","non_res_ba","twi","icp")

# headline config, held fixed across every variant
CFG <- list(model = "qa", sel_alpha = 0.05, dfm_q = 1L, qa_lag = 0L:1L)

.metrics <- function(res) {
  res <- res[!is.na(res$qoq_error), , drop = FALSE]
  res$tqd <- as.Date(res$target_quarter_date); res <- res[order(res$tqd), ]
  pc  <- res[res$tqd >= POSTCOVID_FROM, , drop = FALSE]
  oos <- if (nrow(res) >= OOS_N) tail(res, OOS_N) else res
  rmse <- function(d) if (nrow(d)) sqrt(mean(d$qoq_error^2)) else NA_real_
  hit  <- function(d) if (nrow(d)) mean(d$direction_correct, na.rm = TRUE) * 100 else NA_real_
  data.frame(n_full=nrow(res), rmse_full=rmse(res), hit_full=hit(res),
             n_pc=nrow(pc), rmse_pc=rmse(pc), hit_pc=hit(pc),
             n_oos=nrow(oos), rmse_oos=rmse(oos), hit_oos=hit(oos),
             oos_from=if(nrow(oos)) as.character(min(oos$tqd)) else NA_character_)
}

run_one <- function(id, exclude_ids) {
  out_csv <- file.path(OUT, paste0("bt_", id, ".csv"))
  if (file.exists(out_csv)) {
    m <- .metrics(readr::read_csv(out_csv, show_col_types = FALSE))
    cat(sprintf(">>> %-18s CACHED  full=%.4f pc=%.4f oos8=%.4f\n", id, m$rmse_full, m$rmse_pc, m$rmse_oos))
    return(cbind(variant=id, m, runtime_min=0))
  }
  t0 <- Sys.time()
  bt <- backtest_v2(panel_rds=PANEL, panel_info_csv=INFO, out_csv=out_csv,
                    model=CFG$model, exclude_ids=exclude_ids, sel_alpha=CFG$sel_alpha,
                    dfm_q=CFG$dfm_q, qa_lag=CFG$qa_lag, verbose=FALSE)
  el <- as.numeric(difftime(Sys.time(), t0, units="mins")); m <- .metrics(bt$results)
  cat(sprintf(">>> %-18s full=%.4f pc=%.4f oos8=%.4f  (%.1f min, %d sel)\n",
              id, m$rmse_full, m$rmse_pc, m$rmse_oos, el, length(bt$fixed_selection)))
  cbind(variant=id, m, runtime_min=round(el,2))
}

variants <- list(baseline = c(BASE_EXCL, NEW))            # production 29-set
for (s in NEW) variants[[paste0("marg_", s)]] <- c(BASE_EXCL, setdiff(NEW, s))
variants[["full_bucketb"]] <- BASE_EXCL                   # all 9 added

cat(sprintf("Bucket-B backtest: %d variants on %s\n", length(variants), PANEL))
rows <- list()
for (id in names(variants)) {
  cat(sprintf("\n========== %s ==========\n", id))
  rows[[id]] <- tryCatch(run_one(id, variants[[id]]),
    error=function(e){ cat(sprintf("  [FAIL] %s: %s\n", id, conditionMessage(e))); NULL })
}
summ <- do.call(rbind, Filter(Negate(is.null), rows))

# marginal deltas vs baseline (negative = improvement)
b <- summ[summ$variant=="baseline", ]
summ$d_full <- round(summ$rmse_full - b$rmse_full, 4)
summ$d_pc   <- round(summ$rmse_pc   - b$rmse_pc,   4)
summ$d_oos  <- round(summ$rmse_oos  - b$rmse_oos,  4)
readr::write_csv(summ, file.path(OUT, "summary.csv"))
cat("\n=================== SUMMARY (Δ vs baseline; negative = better) ===================\n")
print(summ[order(summ$d_pc), c("variant","rmse_full","rmse_pc","rmse_oos","d_full","d_pc","d_oos","hit_pc")], row.names=FALSE)
cat(sprintf("\n-> %s\n", file.path(OUT, "summary.csv")))

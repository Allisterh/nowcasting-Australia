# bucketb_backtest_alpha.R — focused follow-up to bucketb_backtest.R.
# The headline α=0.05 marginal test was null BY CONSTRUCTION: the univariate Wald
# selection never admits any Bucket-B series (full Wald table: cache/bucketb/wald.csv).
# Only TWO Bucket-B series clear the bar at a looser α: credit_personal (Wald 7.64)
# and non_res_ba (6.95) — both pass α=0.10 and α=0.20 (the stress config's α). So
# test their ACTUAL accuracy impact where they're actually selected.
#
# For each α in {0.10, 0.20}: baseline + add credit_personal / non_res_ba / both.
# Within-α deltas isolate the pure marginal effect. Also reports vs the production
# α=0.05 baseline (from bucketb_backtest.R) for the "is it worth it" view.
suppressWarnings(suppressMessages({ here <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) NA) }))
if (is.na(here) || !nzchar(here)) here <- "R"
source(file.path(here, "backtest_v2.R"))
suppressMessages({ library(dplyr); library(readr) })

PANEL <- "cache/panel_vintage_bucketb.rds"; INFO <- "seed/panel_info.csv"; OUT <- "cache/bucketb"
POSTCOVID_FROM <- as.Date("2022-01-01"); OOS_N <- 8L
AIG <- c("aig_pmi","aig_pci","aig_psi"); BASE_EXCL <- c(AIG, "rt")
NEW <- c("debit_card","credit_personal","import","hs_ba","nh_ba","alt_add","non_res_ba","twi","icp")
ADD <- c("credit_personal","non_res_ba")          # the only Bucket-B series ever selected

.metrics <- function(res) {
  res <- res[!is.na(res$qoq_error), , drop=FALSE]; res$tqd <- as.Date(res$target_quarter_date)
  res <- res[order(res$tqd), ]; pc <- res[res$tqd >= POSTCOVID_FROM, , drop=FALSE]
  oos <- if (nrow(res) >= OOS_N) tail(res, OOS_N) else res
  rmse <- function(d) if (nrow(d)) sqrt(mean(d$qoq_error^2)) else NA_real_
  hit  <- function(d) if (nrow(d)) mean(d$direction_correct, na.rm=TRUE)*100 else NA_real_
  data.frame(rmse_full=rmse(res), rmse_pc=rmse(pc), rmse_oos=rmse(oos),
             hit_pc=hit(pc), n_pc=nrow(pc))
}
run_one <- function(tag, exclude_ids, alpha) {
  out_csv <- file.path(OUT, paste0("bta_", tag, ".csv"))
  if (file.exists(out_csv)) { m <- .metrics(read_csv(out_csv, show_col_types=FALSE))
    cat(sprintf(">>> %-28s CACHED full=%.4f pc=%.4f oos8=%.4f\n", tag, m$rmse_full, m$rmse_pc, m$rmse_oos))
    return(cbind(variant=tag, alpha=alpha, m)) }
  bt <- backtest_v2(panel_rds=PANEL, panel_info_csv=INFO, out_csv=out_csv, model="qa",
                    exclude_ids=exclude_ids, sel_alpha=alpha, dfm_q=1L, qa_lag=0L:1L, verbose=FALSE)
  m <- .metrics(bt$results)
  cat(sprintf(">>> %-28s a=%.2f sel=%d  full=%.4f pc=%.4f oos8=%.4f\n",
              tag, alpha, length(bt$fixed_selection), m$rmse_full, m$rmse_pc, m$rmse_oos))
  cbind(variant=tag, alpha=alpha, m)
}

rows <- list()
for (a in c(0.10, 0.20)) {
  asfx <- sprintf("a%02d", round(a*100))
  defs <- list(
    base = c(BASE_EXCL, NEW),                                # production set @ this α
    cp   = c(BASE_EXCL, setdiff(NEW, "credit_personal")),
    nrb  = c(BASE_EXCL, setdiff(NEW, "non_res_ba")),
    both = c(BASE_EXCL, setdiff(NEW, ADD)))
  for (nm in names(defs)) {
    tag <- paste0(nm, "_", asfx)
    cat(sprintf("\n========== %s ==========\n", tag))
    rows[[tag]] <- tryCatch(run_one(tag, defs[[nm]], a),
      error=function(e){ cat(sprintf("  [FAIL] %s: %s\n", tag, conditionMessage(e))); NULL })
  }
}
summ <- do.call(rbind, Filter(Negate(is.null), rows))

# within-α deltas vs that α's baseline
summ$d_full <- NA; summ$d_pc <- NA; summ$d_oos <- NA
for (a in unique(summ$alpha)) {
  b <- summ[summ$alpha==a & grepl("^base_", summ$variant), ]
  idx <- summ$alpha==a
  summ$d_full[idx] <- round(summ$rmse_full[idx] - b$rmse_full, 4)
  summ$d_pc[idx]   <- round(summ$rmse_pc[idx]   - b$rmse_pc,   4)
  summ$d_oos[idx]  <- round(summ$rmse_oos[idx]  - b$rmse_oos,  4)
}
write_csv(summ, file.path(OUT, "summary_alpha.csv"))
cat("\n=== α-sweep summary (within-α Δ vs that α's baseline; negative=better) ===\n")
print(summ[, c("variant","alpha","rmse_full","rmse_pc","rmse_oos","d_full","d_pc","d_oos","hit_pc")], row.names=FALSE)
cat(sprintf("\nproduction α=0.05 baseline (ref): full=0.4535 pc=0.3422 oos8=0.2409\n"))
cat(sprintf("-> %s\n", file.path(OUT,"summary_alpha.csv")))

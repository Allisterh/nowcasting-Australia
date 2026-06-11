# bucketb_report.R — assemble the morning results table from the backtest summary.
# Emits cache/bucketb/results_table.md (markdown) applying the agreed keep-rule:
#   KEEP   : improves post-COVID (d_pc < 0) AND no material full-sample regression
#            (d_full <= +TOL)
#   STAR ⭐ : clean sweep — improves ALL three windows (d_pc<0 & d_full<=0 & d_oos<=0)
#   else   : — (neutral / not worth a panel slot)
# TOL = 0.02 pp QoQ (a regression smaller than this is "not material").
source("R/_setup.R")
suppressMessages({ library(dplyr) })
TOL <- 0.02
POSTCOVID_FROM <- as.Date("2022-01-01"); OOS_N <- 8L

s <- read.csv("cache/bucketb/summary.csv", stringsAsFactors = FALSE)

v1 <- local({
  f <- "cache/v1_baseline_r3_backtest.csv"; if (!file.exists(f)) return(NULL)
  d <- read.csv(f); d <- d[!is.na(d$qoq_error), ]; d$tqd <- as.Date(d$target_quarter_date)
  d <- d[order(d$tqd), ]; rmse <- function(x) if (nrow(x)) sqrt(mean(x$qoq_error^2)) else NA
  c(pc = rmse(d[d$tqd >= POSTCOVID_FROM, ]), full = rmse(d),
    oos = rmse(if (nrow(d) >= OOS_N) tail(d, OOS_N) else d))
})

verdict <- function(r) {
  if (r$variant %in% c("baseline","full_bucketb")) return("")
  if (is.na(r$d_pc)) return("—")
  if (r$d_pc < 0 && r$d_full <= 0 && r$d_oos <= 0) return("⭐ KEEP (all 3)")
  if (r$d_pc < 0 && r$d_full <= TOL)               return("✓ KEEP")
  "—"
}

s <- s[order(s$variant != "baseline", s$d_pc), ]   # baseline first, then by d_pc
lines <- c(
  "| variant | post-COVID | full | OOS8 | Δ pc | Δ full | Δ oos | hit_pc | verdict |",
  "|---|---|---|---|---|---|---|---|---|")
for (i in seq_len(nrow(s))) {
  r <- s[i, ]; nm <- sub("^marg_", "+", r$variant)
  d <- function(x) if (is.na(x)) "" else sprintf("%+.3f", x)
  lines <- c(lines, sprintf("| %s | %.3f | %.3f | %.3f | %s | %s | %s | %.0f%% | %s |",
    nm, r$rmse_pc, r$rmse_full, r$rmse_oos, d(r$d_pc), d(r$d_full), d(r$d_oos), r$hit_pc, verdict(r)))
}
if (!is.null(v1))
  lines <- c(lines, sprintf("| _v1 (13-DFM) ref_ | %.3f | %.3f | %.3f | | | | | |", v1["pc"], v1["full"], v1["oos"]))

keep <- s$variant[vapply(seq_len(nrow(s)), function(i) grepl("KEEP", verdict(s[i,])), logical(1))]
hdr <- c("## Bucket-B marginal backtest — results",
  sprintf("Headline config (qa, α=0.05, dfm_q=1, qa_lag=0:1). Baseline = production 29-set. "),
  sprintf("Δ = variant − baseline (negative = improvement). KEEP-rule: improves post-COVID without material (>%.2f) full-sample regression; ⭐ = improves all three windows.", TOL),
  "")
out <- c(hdr, lines, "",
  if (length(keep)) sprintf("**Series clearing the keep-rule:** %s", paste(sub("^marg_","",keep), collapse=", "))
  else "**No single Bucket-B series cleared the keep-rule.**")
writeLines(out, "cache/bucketb/results_table.md")
cat(paste(out, collapse = "\n"), "\n")

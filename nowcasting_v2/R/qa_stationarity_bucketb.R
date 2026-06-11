# qa_stationarity_bucketb.R — stationarity QA gate for the Bucket-B series.
# Builds the combined panel (29 baseline + 9 Bucket-B), applies the RBA per-series
# transform (transform_panel: tcode/tlog), then runs ADF (urca::ur.df, drift) and
# KPSS (urca::ur.kpss, level) on each NEW series' TRANSFORMED form. Verdict:
#   STATIONARY iff ADF rejects unit-root at 5% (tau < crit) AND KPSS fails to
#   reject stationarity at 5% (stat < crit). Prints raw-vs-transformed for context.
source(file.path("R", "_setup.R"))
source(file.path("R", "build_panel.R"))
source(file.path("R", "transform_panel.R"))
suppressMessages({ library(urca); library(dplyr) })

NEW <- c("debit_card","credit_personal","import","hs_ba","nh_ba","alt_add","non_res_ba","twi","icp")

cat("== building combined panel (incl. 9 Bucket-B) ==\n")
w   <- build_panel(out_rds = "cache/panel_vintage_bucketb.rds")
tfs <- transform_panel(w, "seed/panel_info.csv")

adf_tau <- function(x) { x <- x[!is.na(x)]
  if (length(x) < 12) return(c(stat=NA, c5=NA))
  r <- tryCatch(ur.df(x, type="drift", selectlags="AIC"), error=function(e) NULL)
  if (is.null(r)) return(c(stat=NA, c5=NA))
  c(stat=as.numeric(r@teststat[1]), c5=as.numeric(r@cval[1,"5pct"])) }
kpss_stat <- function(x) { x <- x[!is.na(x)]
  if (length(x) < 12) return(c(stat=NA, c5=NA))
  r <- tryCatch(ur.kpss(x, type="mu"), error=function(e) NULL)
  if (is.null(r)) return(c(stat=NA, c5=NA))
  c(stat=as.numeric(r@teststat[1]), c5=as.numeric(r@cval[1,"5pct"])) }

cat(sprintf("\n%-15s %5s | %-28s | %-26s | %s\n", "series","n","ADF tau (stat<crit=>stationary)","KPSS (stat<crit=>stationary)","VERDICT"))
cat(strrep("-", 100), "\n")
res <- list()
for (id in NEW) {
  z <- tfs[[id]]; n <- sum(!is.na(z))
  a <- adf_tau(z); k <- kpss_stat(z)
  adf_ok  <- !is.na(a["stat"]) && a["stat"] < a["c5"]     # reject unit root
  kpss_ok <- !is.na(k["stat"]) && k["stat"] < k["c5"]     # fail to reject stationarity
  verdict <- if (adf_ok && kpss_ok) "STATIONARY" else if (adf_ok || kpss_ok) "BORDERLINE" else "NON-STATIONARY"
  cat(sprintf("%-15s %5d | ADF=%7.2f vs %6.2f  %-3s | KPSS=%6.3f vs %5.3f  %-3s | %s\n",
      id, n, a["stat"], a["c5"], ifelse(adf_ok,"OK","x"),
      k["stat"], k["c5"], ifelse(kpss_ok,"OK","x"), verdict))
  res[[id]] <- data.frame(id=id, n=n, adf=a["stat"], adf_c5=a["c5"], adf_ok=adf_ok,
                          kpss=k["stat"], kpss_c5=k["c5"], kpss_ok=kpss_ok, verdict=verdict)
}
out <- do.call(rbind, res)
dir.create("cache/bucketb", showWarnings = FALSE, recursive = TRUE)
write.csv(out, "cache/bucketb/stationarity_qa.csv", row.names = FALSE)
cat("\n-> cache/bucketb/stationarity_qa.csv\n")
ns <- out$id[out$verdict == "NON-STATIONARY"]
if (length(ns)) cat(sprintf("\n!! NON-STATIONARY after RBA transform: %s — need alt transform or drop.\n", paste(ns, collapse=", ")))

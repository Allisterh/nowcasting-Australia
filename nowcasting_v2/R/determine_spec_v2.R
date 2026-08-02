####################################################################################################
# Re-derive the DFM estimation options (q, s, p) on OUR panel.
#
# Adapts Determine_TP_MAI_Estimation_Options.R from the RBA replication bundle.
# That script is one of the three the paper's own driver comments out ("fails due
# to censored dataset"), so it has never been run against v2's data -- q=1, s=2,
# p=1 were ported across as constants and never re-derived. This closes that gap.
#
# The paper's procedure, in order:
#
#   q  Hallin & Liska (2007) log information criterion (num_dyn_factors). NOT a
#      single number: it sweeps a penalty constant c and you read q off the
#      SECOND stability region -- the run of c values over which the estimate
#      stops moving. The first stability region is degenerate (q = q_max), the
#      second is the answer. This needs eyes on the table; we print it.
#   r  number of STATIC factors, from the modified Bai & Ng criterion (mod_bnic),
#      cross-checked against the dynamic-eigenvalue variance decomposition.
#   s  DERIVED, not estimated: r = q(s + 1), so s = (r - q)/q. The paper's s = 2
#      is simply r = 3 with q = 1.
#   p  VAR/AR order of the estimated factors, from var_order()'s AIC/SIC over
#      max_lags, cross-checked against the PACF.
#
# All five functions come from the vendored, byte-identical RBA methods.
#
# Run from nowcasting_v2/:  Rscript R/determine_spec_v2.R
####################################################################################################

source("R/_setup.R")
source("R/methods/misc_methods.R")
source("R/methods/ndfm_methods.R")
source("R/methods/qmle_dfm_methods.R")
source("R/methods/var_methods.R")
source("R/methods/mai_utils.R")
suppressMessages({ source("R/build_panel.R"); source("R/transform_panel.R"); source("R/build_mai.R") })

# production constants + as-of truncation, taken verbatim from the emit
for (e in parse("R/emit_v2_json.R")) {
  if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") &&
      as.character(e[[2]])[1] %in% c("AIG", "GDP_LAG", ".LAG_ACC", ".lag_acc",
                                     ".truncate_acc", ".mondays_to_date")) {
    eval(e, envir = globalenv())
  }
}
for (e in parse("R/backtest_v2.R")) {
  if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") &&
      as.character(e[[2]])[1] == ".truncate_gdp") eval(e, envir = globalenv())
}

options(digits = 4)

# ---- our panel, at the production as-of, with the production selection --------
wide <- build_panel()
gdp  <- read.csv("data_raw/rt_dgdp_qtr.csv"); gdp$date <- as.Date(gdp$date)
as_of <- as.Date(tail(.mondays_to_date(gdp), 1))
tfs  <- transform_panel(.truncate_acc(wide, as_of), "seed/panel_info.csv")
gdpt <- .truncate_gdp(gdp, as_of, gdp_lag = GDP_LAG)

sel_res <- build_mai(tfs = tfs, gdp = gdpt, sel_alpha = 0.05, dfm_q = 1L,
                     exclude_ids = c(AIG, "rt"), out_csv = NULL, out_rds = NULL)
selected <- sel_res$diagnostics$selected

cat(sprintf("\nas_of %s | selected %d of %d candidates\n  %s\n\n",
            as_of, length(selected), length(setdiff(names(tfs), "date")),
            paste(selected, collapse = ", ")))

d0 <- min(tfs$date[!is.na(rowSums(tfs[, selected, drop = FALSE]))])
Y  <- ts(as.matrix(tfs[, selected, drop = FALSE]),
         start = c(as.integer(format(tfs$date[1], "%Y")),
                   as.integer(format(tfs$date[1], "%m"))), frequency = 12)
yna <- remove_na_values(x = Y, na_opt = "exclude")
cat(sprintf("balanced block for spec determination: %d obs x %d series\n",
            nrow(yna), ncol(yna)))
if (ncol(yna) < 15L) {
  cat("\n!! CAVEAT: the paper ran this on 30 targeted predictors. Factor-number\n",
      "   criteria are unreliable on a panel this narrow -- treat the q estimate\n",
      "   below as indicative, and lean on the variance decomposition.\n\n", sep = "")
}

# ---- q: Hallin & Liska log IC (paper's exact settings) ------------------------
cat("=== q: number of DYNAMIC factors (Hallin-Liska log IC, penalty p3) ===\n")
# FORCED ADAPTATION: the paper passes nbck = 10L, which sweeps sub-panels of
# size (nvar - 10) .. nvar. That assumes ~30 targeted predictors. Our selection
# is 9 series, so nvar - 10 = -1 and the procedure dies in sample.int(). We pass
# nbck = NULL, which makes the function use its own default of floor(nvar / 4) --
# i.e. the same rule scaled to panel width. Everything else is the paper's.
# q_max must also fit the SMALLEST sub-panel: the criterion indexes q_max + 1
# eigenvalues out of a sub-panel of size (nvar - nbck), so q_max <= nvar-nbck-1.
# The paper's q_max = 8 on 30 series is comfortable; on 9 it overruns.
.nbck  <- floor(ncol(yna) / 4L)
.q_max <- min(8L, ncol(yna) - .nbck - 1L)
cat(sprintf("(adapted: nbck = %d, q_max = %d; paper used 10 and 8 on 30 series)\n",
            .nbck, .q_max))
ndf <- num_dyn_factors(x = yna, q_max = .q_max, nbck = .nbck, stp = 1.0,
                       c_max = 3.0, penalty = "p3", cf = 1000.0,
                       m = 12L, h = 12L, scale_opt = TRUE, plot_opt = FALSE)
tab <- data.frame(c = ndf$cr, q_hat = ndf$nfactor, variability = ndf$v_nfactor)
print(tab, row.names = FALSE)
runs <- rle(as.integer(ndf$nfactor))
cat("\nstability regions (runs of a constant q as c increases):\n")
pos <- 1L
for (i in seq_along(runs$lengths)) {
  cat(sprintf("  q = %d over %d consecutive c values (c = %.2f .. %.2f)%s\n",
              runs$values[i], runs$lengths[i], ndf$cr[pos],
              ndf$cr[pos + runs$lengths[i] - 1L],
              if (i == 1L) "   <- first region (degenerate)" else ""))
  pos <- pos + runs$lengths[i]
}

# ---- r: static factors, and the variance decomposition -----------------------
cat("\n=== r: number of STATIC factors (modified Bai & Ng) ===\n")
print(mod_bnic(x = yna, kmax = min(8L, ncol(yna) - 1L), scale_opt = TRUE))

nv <- min(10L, ncol(yna))
cat("\n=== explained variation: dynamic vs static eigenvalues ===\n")
dn  <- dyn_eig(x = yna, q = nv, m = 12L, h = 12L)
sfm <- pc_factor(x = yna, r = min(3L, ncol(yna) - 1L), norm_opt = "LN",
                 scale_opt = FALSE, sign_opt = TRUE, vardec_opt = TRUE)
vc <- rbind(Dynamic = dn$vardec[seq_len(nv), 2L], Static = sfm$vardec[seq_len(nv), 2L])
colnames(vc) <- as.character(seq_len(nv))
print(round(vc, 4))

# ---- p: AR/VAR order of the estimated factors --------------------------------
cat("\n=== p: lag order of the estimated factor (AIC / SIC) ===\n")
print(var_order(y = sfm$factors, max_lags = 4L))
cat("\nPACF of factor 1 (paper cross-checks the IC against this):\n")
print(round(as.numeric(pacf(sfm$factors[, 1L], lag.max = 4L, plot = FALSE)$acf), 3))

cat(sprintf("\n---\nCurrent production spec: q = 1, s = 2, p = 1 (ported from the paper).\n"))
cat("s is derived as (r - q)/q once q and r are settled -- it is not estimated.\n")

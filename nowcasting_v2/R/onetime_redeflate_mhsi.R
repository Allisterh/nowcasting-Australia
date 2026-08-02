# ONE-OFF, ALREADY APPLIED (2026-08-02). Kept so the data correction it made is
# auditable and reproducible without a network fetch. Do NOT re-run it: it is
# idempotent in intent but reads cpi_monthly.csv assuming that file still holds
# the LINEARLY interpolated series, which it no longer does after the first run.
#
# Rebuild household_spending.csv with the real-time (LOCF) CPI deflator,
# without refetching from ABS.
#
# fetch_mhsi_real() now carries the last PUBLISHED quarterly CPI forward instead
# of linearly interpolating (which used the FOLLOWING quarter's print to deflate
# an interior month -- a look-ahead). That fix only bites when the fetcher runs
# in CI, so the committed CSV still holds linearly-deflated values.
#
# We don't need to wait: the quarterly CPI is exactly recoverable from
# data_raw/cpi_monthly.csv, because linear interpolation passes through its own
# nodes. Verified: reconstructing the monthly series from the Mar/Jun/Sep/Dec
# values reproduces it to 5e-05 (CSV stores 4dp), while the other two candidate
# offsets are out by ~0.6.
#
# Run from nowcasting_v2/.

cm  <- read.csv("data_raw/cpi_monthly.csv");             cm$date  <- as.Date(cm$date)
nom <- read.csv("data_raw/household_spending_nominal.csv"); nom$date <- as.Date(nom$date)
old <- read.csv("data_raw/household_spending.csv");      old$date <- as.Date(old$date)

# --- recover the quarterly CPI -------------------------------------------------
qm    <- as.integer(format(cm$date, "%m")) %in% c(3, 6, 9, 12)
cpi_q <- data.frame(date = cm$date[qm], value = cm$value[qm])
stopifnot(nrow(cpi_q) > 40)

# sanity: linear interpolation through these nodes must reproduce cm
chk <- approx(as.numeric(cpi_q$date), cpi_q$value, xout = as.numeric(cm$date), rule = 2)$y
stopifnot(max(abs(chk - cm$value)) < 1e-3)
cat(sprintf("recovered %d quarterly CPI obs (%s..%s); reconstruction err %.2g\n",
            nrow(cpi_q), min(cpi_q$date), max(cpi_q$date), max(abs(chk - cm$value))))

# --- redo the deflation the way the fixed fetcher will -------------------------
spine <- seq(min(cpi_q$date), max(nom$date), by = "month")
cpi_v <- approx(as.numeric(cpi_q$date), cpi_q$value, xout = as.numeric(spine),
                method = "constant", f = 0, rule = 2)$y
cpi_new <- data.frame(date = spine, value = round(cpi_v, 4))

idx <- cpi_new$value[match(nom$date, cpi_new$date)]
stopifnot(!any(is.na(idx)))
new <- data.frame(date = nom$date, value = nom$value / idx * 100)

# --- impact --------------------------------------------------------------------
j <- merge(old, new, by = "date", suffixes = c("_old", "_new"))
d <- (j$value_new / j$value_old - 1) * 100
cat(sprintf("household_spending: %d months, level diff median %+.3f%% max |%.3f%%|\n",
            nrow(j), median(d), max(abs(d))))
# what the model actually sees is the log-difference (tcode t2 + tlog)
lo <- diff(log(j$value_old)); ln <- diff(log(j$value_new))
cat(sprintf("MoM log-diff: mean abs change %.4f pp, max %.4f pp\n",
            mean(abs(ln - lo)) * 100, max(abs(ln - lo)) * 100))

write.csv(cpi_new, "data_raw/cpi_monthly.csv", row.names = FALSE)
write.csv(new, "data_raw/household_spending.csv", row.names = FALSE)
write.csv(new, "data_raw/household_spending_real.csv", row.names = FALSE)
cat("rewrote cpi_monthly.csv, household_spending.csv, household_spending_real.csv\n")

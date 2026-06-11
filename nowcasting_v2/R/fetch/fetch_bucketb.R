# =============================================================================
# fetch_bucketb.R  — Bucket-B candidate predictors for the v2 panel experiment
# =============================================================================
# Sources the 9 easily-accessible RBA-panel series v2 doesn't yet use, so each
# can be marginally backtested (see BUCKET-B-NIGHT-LOG.md). Reuses the confirmed
# parsers from fetch_rba_panel.R / fetch_abs_panel.R (sourcing them is safe: their
# auto-run blocks are guarded by sys.nframe()==0). Output contract identical:
# data_raw/<id>.csv with columns date,value (first-of-month), prints "<id>: N obs".
#
# CONFIRMED ids (against live data 2026-06-11) — full table in BUCKET-B-NIGHT-LOG.md.
# -----------------------------------------------------------------------------

.bb_setup <- local({
  cand <- c(file.path("nowcasting_v2", "R", "_setup.R"), file.path("R", "_setup.R"),
            file.path("..", "R", "_setup.R"), file.path("..", "..", "R", "_setup.R"))
  for (p in cand) if (file.exists(p)) return(normalizePath(dirname(dirname(p))))
  normalizePath(".")
})
source(file.path(.bb_setup, "R", "_setup.R"))
source(file.path(.bb_setup, "R", "fetch", "fetch_rba_panel.R"))  # parse_rba_csv, .write_series_rba, RBA_BASE
source(file.path(.bb_setup, "R", "fetch", "fetch_abs_panel.R"))  # fetch_abs_id, .write_series

suppressMessages({ library(dplyr); library(lubridate); library(readr) })

# --- generic RBA CSV download for arbitrary table filenames (browser UA + retry) ---
.dl_rba_file <- function(fname) {
  url  <- paste0(RBA_BASE, fname)
  dest <- file.path(tempdir(), fname)
  for (attempt in 1:4) {
    res <- tryCatch(
      utils::download.file(url, dest, mode = "wb", quiet = TRUE,
        headers = c("User-Agent" = "nowcasting/2.0 (+https://nowcast.wlsn.me)")),
      error = function(e) e)
    if (!inherits(res, "error") && file.exists(dest) && file.size(dest) > 1000) {
      hb <- readBin(dest, "raw", n = 64)
      if (!grepl("<!DOCTYPE|<html", rawToChar(hb), ignore.case = TRUE)) return(dest)
    }
    Sys.sleep(min(30, 3 * 2^(attempt - 1)))
  }
  stop(sprintf("RBA download failed for %s (%s)", fname, url))
}

# ---------------------------------------------------------------------------
# ABS Bucket-B (fetch_abs_id handles the SA filter + tidy). All CONFIRMED SA.
# ---------------------------------------------------------------------------
BUCKETB_ABS <- c(
  hs_ba      = "A418431A",   # 8731.0  Houses, Total Sectors, Number, SA
  nh_ba      = "A421265R",   # 8731.0  Dwellings excl houses, Total Sectors, Number, SA
  alt_add    = "A419852T",   # 8731.0  Total Residential alterations & additions, value, SA
  non_res_ba = "A2413226R"   # 8731.0  Total Non-residential, Total Work, Australia, value, SA
)

# Imports: ABS 5368.0 'Debits, Total goods' (A2718603V) is recorded NEGATIVE (BoP
# debit sign convention). Negate to a positive level so it matches export's sign
# and tlog=TRUE (log-growth) is well-defined.
fetch_import <- function(write = TRUE) {
  tbl <- fetch_abs_id("import", "A2718603V", write = FALSE)
  tbl$value <- -tbl$value
  if (any(tbl$value <= 0)) stop("fetch_import: non-positive import level after negation")
  if (write) .write_series(tbl, "import"); tbl
}

# ---------------------------------------------------------------------------
# RBA Bucket-B
# ---------------------------------------------------------------------------
fetch_credit_personal <- function(write = TRUE) {
  tbl <- parse_rba_csv(.dl_rba_file("d2-data.csv"), "DLCACOPN")  # Credit; Other personal
  if (write) .write_series_rba(tbl, "credit_personal"); tbl
}

fetch_debit_card <- function(write = TRUE) {
  tbl <- parse_rba_csv(.dl_rba_file("c2-data.csv"), "CDCPTTVSA")  # Debit card; Value of purchases SA
  if (write) .write_series_rba(tbl, "debit_card"); tbl
}

fetch_icp <- function(write = TRUE) {
  tbl <- parse_rba_csv(.dl_rba_file("i2-data.csv"), "GRCPAIAD")   # Commodity prices - A$
  tbl <- tbl[tbl$date <= Sys.Date(), , drop = FALSE]             # guard: drop any future-dated rows
  if (write) .write_series_rba(tbl, "icp"); tbl
}

# TWI is published DAILY (f11.1). Aggregate to a monthly MEAN (the RBA-paper twi is
# monthly). parse_rba_csv keeps first-per-month, so parse the daily column manually.
fetch_twi <- function(write = TRUE) {
  p <- .dl_rba_file("f11.1-data.csv")
  lines <- readr::read_lines(p)
  sid_row <- which(grepl("^Series ID,", lines))[1]
  ids <- trimws(strsplit(lines[sid_row], ",", fixed = TRUE)[[1]])
  col <- which(ids == "FXRTWI")[1]
  if (is.na(col)) stop("fetch_twi: FXRTWI column not found in f11.1")
  dl <- lines[(sid_row + 1L):length(lines)]
  dl <- dl[grepl("^[0-9]", dl)]
  parts <- strsplit(dl, ",", fixed = TRUE)
  raw_date <- vapply(parts, function(x) if (length(x) >= 1) x[1] else NA_character_, "")
  raw_val  <- vapply(parts, function(x) if (length(x) >= col) x[col] else NA_character_, "")
  d <- as.Date(raw_date, format = "%d-%b-%Y")
  v <- suppressWarnings(as.numeric(raw_val))
  tbl <- tibble(date = lubridate::floor_date(d, "month"), value = v) |>
    filter(!is.na(date), !is.na(value)) |>
    group_by(date) |> summarise(value = mean(value), .groups = "drop") |>
    arrange(date)
  if (nrow(tbl) == 0L) stop("fetch_twi: no monthly TWI obs after aggregation")
  if (write) .write_series_rba(tbl, "twi"); tbl
}

# ---------------------------------------------------------------------------
# Runner. Fetches all 9; fails loud (non-zero exit) if any series fails so the
# experiment is never silently run on a partial panel.
# ---------------------------------------------------------------------------
fetch_bucketb <- function() {
  res <- list()
  for (id in names(BUCKETB_ABS)) {
    res[[id]] <- tryCatch(fetch_abs_id(id, BUCKETB_ABS[[id]]),
      error = function(e) { message(sprintf("  !! %s FAILED: %s", id, conditionMessage(e))); NULL })
  }
  res[["import"]] <- tryCatch(fetch_import(),
    error = function(e) { message(sprintf("  !! import FAILED: %s", conditionMessage(e))); NULL })
  rba <- list(credit_personal = fetch_credit_personal, debit_card = fetch_debit_card,
              twi = fetch_twi, icp = fetch_icp)
  for (id in names(rba)) {
    res[[id]] <- tryCatch(rba[[id]](),
      error = function(e) { message(sprintf("  !! %s FAILED: %s", id, conditionMessage(e))); NULL })
  }
  invisible(res)
}

if (sys.nframe() == 0L && !interactive()) {
  res <- fetch_bucketb()
  failed <- names(res)[vapply(res, is.null, logical(1))]
  if (length(failed)) {
    message(sprintf("BUCKET-B FETCH FAILED for %d series: %s", length(failed), paste(failed, collapse = ", ")))
    quit(status = 1L)
  }
  cat(sprintf("\nBucket-B: %d/%d series fetched OK.\n", length(res) - length(failed), length(res)))
}

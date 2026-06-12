# =============================================================================
# fetch_asx200.R  — S&P/ASX 200 monthly end-of-month price index (Bucket-C)
# =============================================================================
# asx200 is in the RBA's own selected MAI but absent from the RBA's redistributable
# data (licensed). Sourced from ASX historical market statistics:
#   https://www.asx.com.au/about/market-statistics/historical-market-statistics
#
# Split (mirrors the from-James / Cowork pattern):
#   - HISTORICAL base: James downloaded the ASX table -> data_raw/asx200_source.csv
#     (cols: Year, Month, "S&P/ASX 200 price index"). The Month column is stored
#     INCONSISTENTLY (full name "May"; abbrev-YY "Oct-10"; abbrev'YY "Apr'15"; some
#     with non-UTF8 garbage bytes) and prices have thousands-commas / stray bytes.
#     clean_asx200_source() parses it into the date,value contract using the always-
#     clean Year column + the month NAME only.
#   - LATEST month: fetch_asx200_latest() scrapes the page's current-year table for
#     the newest end-of-month close, to append going forward.
#
# Output contract: data_raw/asx200.csv with columns date,value (first-of-month).
# -----------------------------------------------------------------------------

.asx_setup <- local({
  cand <- c(file.path("nowcasting_v2","R","_setup.R"), file.path("R","_setup.R"),
            file.path("..","R","_setup.R"), file.path("..","..","R","_setup.R"))
  for (p in cand) if (file.exists(p)) return(normalizePath(dirname(dirname(p))))
  normalizePath(".")
})
source(file.path(.asx_setup, "R", "_setup.R"))
suppressMessages({ library(dplyr); library(lubridate); library(readr) })

.data_raw_asx <- file.path(.asx_setup, "data_raw")
ASX_URL <- "https://www.asx.com.au/about/market-statistics/historical-market-statistics"

# -----------------------------------------------------------------------------
# Parse the messy ASX export into tidy date,value. Pure over a file path.
# Robust to: full month names, "Mon-YY", "Mon'YY", non-UTF8 garbage in the month
# and price fields, and thousands-commas. Uses the clean numeric Year column for
# the year and only the month NAME from column 2.
# -----------------------------------------------------------------------------
clean_asx200_source <- function(src = file.path(.data_raw_asx, "asx200_source.csv")) {
  raw <- readr::read_csv(src, show_col_types = FALSE,
                         locale = readr::locale(encoding = "latin1"))
  if (ncol(raw) < 3L) stop("clean_asx200_source: expected >=3 cols (Year, Month, price)")
  names(raw)[1:3] <- c("year", "month", "price")
  yr  <- as.integer(gsub("[^0-9]", "", raw$year))
  mi  <- match(tolower(substr(gsub("[^A-Za-z]", "", raw$month), 1, 3)), tolower(month.abb))
  val <- as.numeric(gsub("[^0-9.]", "", raw$price))
  if (any(is.na(mi)))  stop(sprintf("clean_asx200_source: %d unparseable months", sum(is.na(mi))))
  if (any(is.na(yr)))  stop("clean_asx200_source: unparseable year(s)")
  out <- tibble(date = as.Date(sprintf("%04d-%02d-01", yr, mi)), value = val) |>
    filter(!is.na(date), !is.na(value)) |>
    distinct(date, .keep_all = TRUE) |>
    arrange(date)
  # sanity: ASX 200 has traded ~3000..10000 over 2010+
  if (any(out$value < 1000 | out$value > 15000))
    stop("clean_asx200_source: value(s) outside plausible ASX-200 range (1000..15000)")
  out
}

# -----------------------------------------------------------------------------
# Scrape the latest end-of-month close from the ASX page's current-year table.
# !! PROTOTYPE — NOT production-safe. The page is reachable from the host, but it
# carries MULTIPLE tables/columns (All Ordinaries, S&P/ASX 200, company/security
# counts). This naive "first <td>Month</td><td>number</td>" parse grabs the WRONG
# column: tested 2026-06-12 it returned 8965 for May-2026 vs the correct S&P/ASX
# 200 close 8731.7 (8965 ~ All Ords). Targeting the right column needs structural
# HTML parsing of the specific year-tab table. Until then, ongoing monthly updates
# should come via the manual/Cowork channel (how the historic was sourced).
# Returns a 1-row date,value tibble or NULL.
# -----------------------------------------------------------------------------
fetch_asx200_latest <- function(url = ASX_URL) {
  dest <- file.path(tempdir(), "asx_hist.html")
  ok <- tryCatch({
    utils::download.file(url, dest, mode = "wb", quiet = TRUE,
      headers = c("User-Agent" =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"))
    file.exists(dest) && file.size(dest) > 2000
  }, error = function(e) FALSE)
  if (!ok) { message("fetch_asx200_latest: page unreachable (likely WAF) -> use Cowork channel"); return(NULL) }
  html <- paste(readr::read_lines(dest, locale = readr::locale(encoding = "latin1")), collapse = "\n")
  # rows look like: <td>May</td><td>8731.7</td> (or with year tabs). Grab Month,Value pairs.
  m <- gregexpr("<td[^>]*>\\s*([A-Za-z]{3,9})\\s*</td>\\s*<td[^>]*>\\s*([0-9][0-9,\\.]*)\\s*</td>", html, perl = TRUE)
  hits <- regmatches(html, m)[[1]]
  if (!length(hits)) { message("fetch_asx200_latest: no month,value rows found in HTML (JS-rendered?)"); return(NULL) }
  mon <- sub(".*<td[^>]*>\\s*([A-Za-z]{3,9}).*", "\\1", hits[1], perl = TRUE)
  val <- as.numeric(gsub("[^0-9.]", "", sub(".*</td>\\s*<td[^>]*>\\s*([0-9][0-9,\\.]*).*", "\\1", hits[1], perl = TRUE)))
  mi  <- match(tolower(substr(mon,1,3)), tolower(month.abb))
  yr  <- as.integer(format(Sys.Date(), "%Y"))
  if (is.na(mi) || is.na(val)) return(NULL)
  # if we're early in the year and the latest month is Dec, it's last year's
  d <- as.Date(sprintf("%04d-%02d-01", yr, mi)); if (d > Sys.Date()) d <- d - years(1)
  tibble(date = d, value = val)
}

# -----------------------------------------------------------------------------
# Build/refresh data_raw/asx200.csv = cleaned historic, with the latest scraped
# month appended if newer. Fails loud on a bad clean.
# -----------------------------------------------------------------------------
# scrape_latest defaults FALSE: the prototype scraper mis-targets the page (see
# fetch_asx200_latest note) so we never auto-append an unverified value. The
# historic source CSV is the trusted base; new months come via the manual channel.
fetch_asx200 <- function(write = TRUE, scrape_latest = FALSE) {
  hist <- clean_asx200_source()
  if (scrape_latest) {
    lat <- tryCatch(fetch_asx200_latest(), error = function(e) NULL)
    if (!is.null(lat) && nrow(lat) && lat$date > max(hist$date)) {
      message(sprintf("fetch_asx200: appended scraped %s = %.1f", lat$date, lat$value))
      hist <- bind_rows(hist, lat) |> distinct(date, .keep_all = TRUE) |> arrange(date)
    }
  }
  if (write) {
    readr::write_csv(hist, file.path(.data_raw_asx, "asx200.csv"))
    cat(sprintf("asx200: %d obs, %s -> %s\n", nrow(hist),
                format(min(hist$date), "%Y-%m-%d"), format(max(hist$date), "%Y-%m-%d")))
  }
  invisible(hist)
}

if (sys.nframe() == 0L && !interactive()) fetch_asx200()

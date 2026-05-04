#### Fetch ABS release calendar (per indicator) ####
# Each ABS publication exposes a "latest-release" page that quotes both the
# date of the most recent release ("Release date") and the next scheduled
# release ("Next Release"). Reading those is the only way to get the real
# schedule — ABS shifts dates around public holidays and operational tweaks,
# so a deterministic weekday rule is only ever a rough approximation.
#
# The fetched values feed `last_release_date` and `next_release_estimate` in
# data/indicators.json. Failures (network drops, page-structure changes) fall
# back to the per-indicator weekday rule in pipeline/04_emit_json.R.

library(rvest)
library(httr)
library(stringr)
library(lubridate)
library(dplyr)
library(tibble)

# Per-indicator URL for the ABS latest-release page. Several indicators share
# a publication (employment/unemp_rate/part_rate/hours_worked → Labour Force;
# goods_exp/goods_imp → International Trade in Goods; services_exp/services_imp
# → Balance of Payments). We dedupe the HTTP fetches by URL.
#
# cons_conf (FRED/OECD) and bus_conf (NAB) are not ABS publications and have
# no entry here — emit_json's fallback rule handles them.
INDICATOR_ABS_URL <- list(
  employment         = "https://www.abs.gov.au/statistics/labour/employment-and-unemployment/labour-force-australia/latest-release",
  unemp_rate         = "https://www.abs.gov.au/statistics/labour/employment-and-unemployment/labour-force-australia/latest-release",
  part_rate          = "https://www.abs.gov.au/statistics/labour/employment-and-unemployment/labour-force-australia/latest-release",
  hours_worked       = "https://www.abs.gov.au/statistics/labour/employment-and-unemployment/labour-force-australia/latest-release",
  household_spending = "https://www.abs.gov.au/statistics/economy/finance/monthly-household-spending-indicator/latest-release",
  building_approvals = "https://www.abs.gov.au/statistics/industry/building-and-construction/building-approvals-australia/latest-release",
  goods_exp          = "https://www.abs.gov.au/statistics/economy/international-trade/international-trade-goods/latest-release",
  goods_imp          = "https://www.abs.gov.au/statistics/economy/international-trade/international-trade-goods/latest-release",
  services_exp       = "https://www.abs.gov.au/statistics/economy/international-trade/balance-payments-and-international-investment-position-australia/latest-release",
  services_imp       = "https://www.abs.gov.au/statistics/economy/international-trade/balance-payments-and-international-investment-position-australia/latest-release"
)

# Parse a "DD/MM/YYYY" or "D/M/YYYY" date out of a body text. Returns Date
# of length 1 (NA on failure).
.first_dmy <- function(text) {
  if (length(text) == 0 || is.na(text)) return(as.Date(NA))
  m <- str_match(text, "(\\b\\d{1,2}/\\d{1,2}/\\d{4}\\b)")
  if (is.na(m[1, 2])) return(as.Date(NA))
  suppressWarnings(dmy(m[1, 2]))
}

# Scrape one ABS latest-release page. Returns list(last = Date, next_ = Date).
# On any failure, both fields are NA.
fetch_abs_release_meta_one <- function(url, timeout_s = 20) {
  resp <- tryCatch(
    httr::GET(
      url,
      httr::user_agent("nowcast.wlsn.me release-calendar fetcher"),
      httr::timeout(timeout_s)
    ),
    error = function(e) NULL
  )
  if (is.null(resp) || httr::status_code(resp) != 200) {
    return(list(last = as.Date(NA), next_ = as.Date(NA)))
  }
  page <- tryCatch(
    rvest::read_html(httr::content(resp, as = "text", encoding = "UTF-8")),
    error = function(e) NULL
  )
  if (is.null(page)) return(list(last = as.Date(NA), next_ = as.Date(NA)))

  body_text <- rvest::html_text2(page)

  # "Release date" / "Release date and time" — the date the latest publication
  # was released. ABS phrasing is consistent across catalogues.
  last_match <- str_match(
    body_text,
    "(?i)Release date(?:\\s+and\\s+time)?\\s*[:\\-]?\\s*(\\d{1,2}/\\d{1,2}/\\d{4})"
  )
  last_date <- if (!is.na(last_match[1, 2])) {
    suppressWarnings(dmy(last_match[1, 2]))
  } else as.Date(NA)

  # "Next Release" — the next scheduled release. Take the FIRST date that
  # follows the phrase; ABS lists upcoming releases chronologically.
  next_match <- str_match(
    body_text,
    "(?i)Next\\s+Release\\s*[:\\-]?\\s*(\\d{1,2}/\\d{1,2}/\\d{4})"
  )
  next_date <- if (!is.na(next_match[1, 2])) {
    suppressWarnings(dmy(next_match[1, 2]))
  } else as.Date(NA)

  list(last = last_date, next_ = next_date)
}

#' Fetch the ABS-published release calendar for every indicator we map.
#'
#' @return tibble(json_id, last_release_date, next_release_estimate) — Date
#'   columns. Indicators not backed by ABS, or for which the fetch failed,
#'   appear with NAs and the caller falls back to a deterministic rule.
fetch_abs_release_calendar <- function() {
  unique_urls <- unique(unlist(INDICATOR_ABS_URL, use.names = FALSE))
  meta_by_url <- setNames(
    lapply(unique_urls, function(u) {
      message(glue::glue("Fetching ABS release page: {u}"))
      fetch_abs_release_meta_one(u)
    }),
    unique_urls
  )

  tibble(
    json_id = names(INDICATOR_ABS_URL),
    url     = unname(unlist(INDICATOR_ABS_URL, use.names = FALSE))
  ) |>
    mutate(
      last_release_date     = as.Date(vapply(
        url,
        function(u) {
          d <- meta_by_url[[u]]$last
          if (inherits(d, "Date")) as.character(d) else NA_character_
        },
        character(1)
      )),
      next_release_estimate = as.Date(vapply(
        url,
        function(u) {
          d <- meta_by_url[[u]]$next_
          if (inherits(d, "Date")) as.character(d) else NA_character_
        },
        character(1)
      ))
    ) |>
    select(json_id, last_release_date, next_release_estimate)
}

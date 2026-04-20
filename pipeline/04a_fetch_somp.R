#### Fetch RBA SoMP year-ended GDP growth forecasts ####
# The Statement on Monetary Policy publishes GDP growth forecasts quarterly,
# but only at 6-month endpoints (Jun / Dec). So for each of our own Q2 / Q4
# target quarters, we pull the "latest SoMP at end of target quarter" and read
# the matching column out of its Detailed Forecast Table (Table 3.1).
#
# Q1 / Q3 targets have no matching RBA forecast — return NA.
#
# URL pattern (stable since at least 2022):
#   https://www.rba.gov.au/publications/smp/<YYYY>/<mon>/outlook.html
# where <mon> ∈ {feb, may, aug, nov}.
#
# Table is matched by its caption text ("Detailed Forecast Table") rather than
# its numeric ID (`table-3-1`) — RBA has renumbered sections before and the
# caption phrasing has been stable since at least 2019. GDP row is identified
# by <th scope="row"> text "Gross domestic product"; column headers are
# <th>Dec YYYY</th> etc.

library(rvest)
library(httr)
library(dplyr)
library(readr)

# Which SoMP release covers a given target quarter's end-date?
# Target Q2 YYYY (Jun) → May YYYY SoMP (published one month before quarter-end,
#   forecasts Jun YYYY one month ahead).
# Target Q4 YYYY (Dec) → Nov YYYY SoMP.
# Q1 / Q3 → no direct match (SoMP only publishes Jun/Dec endpoints).
somp_release_for_target <- function(target_quarter) {
  parts <- strsplit(target_quarter, " Q", fixed = TRUE)[[1]]
  if (length(parts) != 2) return(NULL)
  yr <- as.integer(parts[1])
  q  <- as.integer(parts[2])
  if (is.na(yr) || is.na(q)) return(NULL)
  if (q == 2L) return(list(year = yr, mon = "may", col = sprintf("Jun %d", yr)))
  if (q == 4L) return(list(year = yr, mon = "nov", col = sprintf("Dec %d", yr)))
  NULL
}

somp_outlook_url <- function(year, mon) {
  sprintf("https://www.rba.gov.au/publications/smp/%d/%s/outlook.html", year, mon)
}

# Fetch + parse a single SoMP page. Returns a data frame with columns
# (column_label, gdp_yoy) or NULL on failure.
somp_parse_table <- function(url) {
  resp <- tryCatch(httr::GET(url, httr::timeout(20)), error = function(e) NULL)
  if (is.null(resp) || httr::status_code(resp) != 200) return(NULL)

  page <- tryCatch(rvest::read_html(httr::content(resp, as = "text", encoding = "UTF-8")),
                   error = function(e) NULL)
  if (is.null(page)) return(NULL)

  # Prefer caption-text match — survives RBA section renumbering (e.g. Table 3.1
  # → Table 4.1). Fall back to the historical ID/class selectors if caption
  # parsing fails for some reason.
  tbl <- local({
    all_tables <- rvest::html_elements(page, "table")
    if (length(all_tables) == 0) return(NULL)
    captions <- vapply(all_tables, function(t) {
      cap <- rvest::html_element(t, "caption")
      if (inherits(cap, "xml_missing")) return("")
      trimws(rvest::html_text(cap))
    }, character(1))
    idx <- which(grepl("Detailed Forecast Table", captions, ignore.case = TRUE))
    if (length(idx) > 0) return(all_tables[[idx[1]]])
    # Fallbacks: the class name has been stable longer than the ID.
    fallback <- rvest::html_element(page, "table.pdf-table-forecast")
    if (!inherits(fallback, "xml_missing")) return(fallback)
    fallback <- rvest::html_element(page, "table#table-3-1")
    if (!inherits(fallback, "xml_missing")) return(fallback)
    NULL
  })
  if (is.null(tbl)) return(NULL)

  # Header row: first <td> is an empty corner, then one <th> per period.
  headers <- rvest::html_elements(tbl, "thead th") |> rvest::html_text(trim = TRUE)
  if (length(headers) == 0) return(NULL)

  # GDP row: the <tr> whose <th scope="row"> text is "Gross domestic product".
  gdp_row <- rvest::html_elements(tbl, "tbody tr") |>
    purrr::keep(function(r) {
      th <- rvest::html_element(r, "th[scope='row']")
      !inherits(th, "xml_missing") && trimws(rvest::html_text(th)) == "Gross domestic product"
    })
  if (length(gdp_row) == 0) return(NULL)

  raw_vals <- rvest::html_elements(gdp_row[[1]], "td") |>
    rvest::html_text(trim = TRUE)
  # RBA uses &minus; (U+2212) — normalise to ASCII before parsing.
  vals <- suppressWarnings(as.numeric(gsub("\u2212", "-", raw_vals)))

  if (length(vals) != length(headers)) return(NULL)
  tibble::tibble(column_label = headers, gdp_yoy = vals)
}

# Fetch the RBA YoY GDP forecast for a given target quarter. Returns a tibble
# row (target_quarter, somp_release, yoy_forecast_pct, source_url) or NULL.
fetch_somp_forecast <- function(target_quarter) {
  rel <- somp_release_for_target(target_quarter)
  if (is.null(rel)) return(NULL)

  url <- somp_outlook_url(rel$year, rel$mon)
  parsed <- somp_parse_table(url)
  if (is.null(parsed)) {
    message(sprintf("[somp] could not fetch/parse %s for %s", url, target_quarter))
    return(NULL)
  }

  match <- parsed |> filter(column_label == rel$col)
  if (nrow(match) == 0 || is.na(match$gdp_yoy[1])) {
    message(sprintf("[somp] %s has no column '%s'", url, rel$col))
    return(NULL)
  }

  # Map month name → ISO numeric month for consistent YYYY-MM storage.
  mon_iso <- c(feb = "02", may = "05", aug = "08", nov = "11")[[rel$mon]]
  tibble::tibble(
    target_quarter   = target_quarter,
    somp_release     = sprintf("%d-%s", rel$year, mon_iso),
    yoy_forecast_pct = match$gdp_yoy[1],
    source_url       = url
  )
}

# Top-level: ensure the cache CSV has rows for all requested target quarters.
# For each target_quarter without a cached entry, attempt a fetch. Writes the
# updated cache and returns it.
ensure_somp_cache <- function(target_quarters, cache_path) {
  cache <- if (file.exists(cache_path)) {
    suppressWarnings(read_csv(cache_path, show_col_types = FALSE,
                              col_types = cols(.default = "c")))
  } else {
    tibble::tibble(
      target_quarter = character(),
      somp_release = character(),
      yoy_forecast_pct = character(),
      source_url = character()
    )
  }
  cache$yoy_forecast_pct <- suppressWarnings(as.numeric(cache$yoy_forecast_pct))

  missing <- setdiff(unique(target_quarters), cache$target_quarter)
  if (length(missing) == 0) return(cache)

  new_rows <- purrr::map_dfr(missing, fetch_somp_forecast)
  if (nrow(new_rows) == 0) return(cache)

  cache <- bind_rows(cache, new_rows) |> arrange(target_quarter)
  write_csv(cache, cache_path)
  cache
}

# Panel Expansion — Research & Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Acquire candidate new indicators, assemble an expanded panel, and backtest it offline to decide — with evidence — which new variables (if any) and which factor count improve the AU GDP nowcast, **without touching any production code until the evidence is in.**

**Architecture:** A fully sandboxed research track under `pipeline/experimental/`. Data acquisition writes raw CSVs to a sandbox; an expanded panel + metadata are assembled in the sandbox; a thin experimental runner `source()`s the existing backtest harness and overrides two in-memory globals (`component_metadata`, the master object) so the **production scripts, seed, and committed `data/` are never modified**. The output is a decision document — not a production change.

**Tech Stack:** R (pinned via `renv`), existing `nowcasting`-package DFM harness (`05`/`06`/`09`), `readabs` (ABS), FRED, RBA CSV downloads, `pdftools`/`pdfminer` for NAB PDFs, `rvest`/regex for FCAI HTML, `seasonal` (X-13ARIMA-SEATS) for self-SA.

**Design reference (the "spec"):** `docs/candidate-variables-2026-06-03.md` (annotated) + `docs/backtest-recommendation-2026-04-17.md` (baseline metrics). Diagnosis recap: the model over-forecast Q1 2026 (+0.77% vs actual **+0.30%**, level 695,945) because the labour/hard-activity-dominated panel was deaf to soft + commodity signals; the fix under test is an evidence-gated panel expansion (commodity/ToT + real-activity, no financial block).

---

## Karpathy guardrails (apply to every task)

- **No production touch until Phase 5.** The sandbox NEVER writes to `pipeline/*.R`, `pipeline/seed/`, `pipeline/nab_business_confidence_raw.csv`, or `data/`. It writes only under `pipeline/experimental/` and `.cache/` (gitignored).
- **Simplicity first.** Each fetcher/parser is the minimum to produce one tidy `date,value` CSV. No config frameworks, no abstractions used once.
- **Surgical.** Reuse the existing harness via `source()` + global override. Do **not** edit `09`/`05`/`06` to "make them parameterised."
- **Goal-driven.** Every variable's inclusion is gated on a measured backtest improvement (Phase 4). "It seems useful" is not a reason to keep it.

## Acceptance gates (the whole point)

Variables ship to production (Phase 5) **only if**, on the expanded-panel backtest vs the 13-series r=3 baseline:
1. The expanded panel does not worsen post-COVID **QoQ RMSE** (baseline 0.42pp) or **hit rate** (baseline 93.8%), **and**
2. The block earns its keep on the **panel ladder** (Task 3.2): the cheap **free block** is kept if `full`/`free_only` beats baseline; the high-maintenance **scraped block (NAB×2 + FCAI)** is kept only if `full` beats `free_only`; **oil** is kept only if `free_only` beats `free_no_oil`, **and**
3. The expanded panel nowcasts **2026 Q1 closer to the realised +0.30%** than the baseline does.

If a block/variable fails, it is dropped from the production recommendation — recorded, not shipped. (No per-variable drop-one ablation: it's expensive and only block-level cost decisions matter here.)

---

## File structure (all new files are sandbox-only)

```
pipeline/experimental/
  README.md                      # what this dir is, how to run, sandbox rules
  fetch/
    fetch_rba_commodity.R        # → data_raw/commodity_prices.csv
    fetch_fred_extra.R           # → data_raw/aud_usd.csv, data_raw/oil_brent.csv
    fetch_abs_extra.R            # → data_raw/inventories.csv, data_raw/arrivals.csv
    scrape_nab_survey.R          # → data_raw/nab_conditions.csv, data_raw/nab_capacity.csv
    scrape_fcai_vehicles.R       # → data_raw/motor_vehicles.csv  (self-SA)
  data_raw/                      # one tidy date,value CSV per candidate series
  seed/
    component_metadata_expanded.rds   # production rows + new indicator rows
  data/
    master_expanded.rds          # production master $wide + new columns + realised Q1-2026 actual
  run_expanded_sweep.R           # sources 09, overrides globals, runs r=2/3/4 + ablation + Q1 held-out
  backtest_output/               # experimental results (mirrors .cache/backtest_output layout)
  tests/
    test_parsers.R               # parser unit tests on captured fixtures
    fixtures/                    # saved sample PDFs / HTML for deterministic tests
```

---

## Phase 0 — Environment + reproduce the baseline (no new logic)

### Task 0.1: Restore the R environment

**Files:** none created.

- [ ] **Step 1:** Run: `cd pipeline && Rscript -e 'renv::restore()'`
  Expected: completes; `Rscript -e 'library(nowcasting); library(readabs)'` prints no error.
- [ ] **Step 2: Commit** — nothing to commit (environment only). Skip.

### Task 0.2: Regenerate the base master dataset via existing ingestion

**Files:** writes `.cache/processed/master_dataset_complete.rds` (gitignored cache; `.cache` currently holds only `vintage_tracking.csv`).

- [ ] **Step 1:** Run: `cd pipeline && Rscript run_complete_nowcast.R`
  Expected: prints "Saved to: .cache/processed/master_dataset_complete.rds"; produces a 2026 Q1 nowcast ≈ +0.77% (sanity: matches the shipped vintage).
- [ ] **Step 2: Verify the master shape**
  Run: `cd pipeline && Rscript -e 'm<-readRDS(".cache/processed/master_dataset_complete.rds"); cat(ncol(m$wide)-1,"indicators\n"); print(tail(m$wide$date))'`
  Expected: 13 indicators; dates run to ~2026-04/05.

### Task 0.3: Reproduce the baseline backtest (the control)

**Files:** writes `.cache/backtest_output/` (gitignored).

- [ ] **Step 1:** Run: `cd pipeline && Rscript run_backtest_sweep.R` (≈2–3h).
- [ ] **Step 2: Verify against the recorded baseline**
  Open `.cache/backtest_output/comparison.md`. Confirm r=3 post-COVID **QoQ RMSE ≈ 0.42pp**, **hit rate ≈ 93.8%**, matching `docs/backtest-recommendation-2026-04-17.md`. If materially different, STOP — the environment/data drifted; resolve before proceeding (do not build on a moving baseline).
- [ ] **Step 3:** Copy the baseline for side-by-side comparison:
  `cp -r .cache/backtest_output pipeline/experimental/backtest_output_baseline` (after Phase 1 creates the dir).

### Task 0.4: Record the realised 2026 Q1 actual for held-out scoring

**Files:** Create `pipeline/experimental/data/realised_q1_2026.txt`

- [ ] **Step 1:** Write the realised ABS print so later tasks score against it:
```
quarter,level,qoq_pct,yoy_pct,source
2026 Q1,695945,0.30,2.50,"ABS 5206.0 March qtr 2026 (released 2026-06-03)"
```
- [ ] **Step 2: Commit**
```bash
git add pipeline/experimental/data/realised_q1_2026.txt
git commit -m "research: record realised 2026 Q1 GDP actual for held-out scoring"
```

---

## Phase 1 — Data acquisition (sandbox; external reads only)

> Each series produces a tidy CSV `date,value` (date = first of month `YYYY-MM-01`, or quarter-start for quarterly) under `pipeline/experimental/data_raw/`. Each fetcher prints coverage (first/last date, n obs) on completion. Sub-tracks 1A/1B/1C are independent and may be executed in parallel.

### Sub-track 1A — Free series (commodity, FX, oil, ABS real-activity)

#### Task 1A.1: RBA Commodity Price Index (A$) → `commodity_prices`

**Files:** Create `pipeline/experimental/fetch/fetch_rba_commodity.R`; Test: `pipeline/experimental/tests/test_parsers.R`

- [ ] **Step 1: Save a fixture** — download the RBA I2 table once for a deterministic test:
  Run: `cd pipeline && curl -sL 'https://www.rba.gov.au/statistics/tables/csv/i2-data.csv' -o experimental/tests/fixtures/rba_i2.csv`
  Expected: a CSV with a header block then dated rows; find the column titled like "Index of Commodity Prices; All items; A$ ... (monthly)".
- [ ] **Step 2: Write the failing test**
```r
# in tests/test_parsers.R
test_that("rba commodity parser yields monthly index", {
  out <- parse_rba_commodity("tests/fixtures/rba_i2.csv")
  expect_named(out, c("date", "value"))
  expect_true(all(diff(out$date) > 0))         # sorted, monthly
  expect_gt(nrow(out), 200)                      # history back to ~1980s
  expect_true(is.numeric(out$value))
})
```
- [ ] **Step 3: Run test → FAIL** (`parse_rba_commodity` not found):
  `cd pipeline && Rscript -e 'library(testthat); source("experimental/fetch/fetch_rba_commodity.R"); test_file("experimental/tests/test_parsers.R")'`
- [ ] **Step 4: Implement**
```r
# fetch_rba_commodity.R
library(readr); library(dplyr); library(lubridate); library(stringr)

parse_rba_commodity <- function(path) {
  raw <- read_lines(path)
  # RBA CSVs have a metadata preamble; the data header row contains "Series ID".
  hdr <- which(str_detect(raw, regex("Series ID", ignore_case = TRUE)))[1]
  df  <- read_csv(path, skip = hdr - 1, show_col_types = FALSE)
  # Title row sits a few lines above the Series ID row; pick the A$ all-items monthly col.
  col <- names(df)[str_detect(names(df), regex("A\\$", ignore_case = TRUE))][1]
  if (is.na(col)) stop("RBA I2: A$ commodity column not found; inspect header names")
  tibble(date = floor_date(dmy(df[[1]]), "month"), value = as.numeric(df[[col]])) |>
    filter(!is.na(date), !is.na(value)) |> arrange(date)
}

fetch_rba_commodity <- function(dest = "experimental/data_raw/commodity_prices.csv") {
  url <- "https://www.rba.gov.au/statistics/tables/csv/i2-data.csv"
  tmp <- tempfile(fileext = ".csv"); download.file(url, tmp, quiet = TRUE)
  out <- parse_rba_commodity(tmp)
  write_csv(out, dest)
  message(sprintf("commodity_prices: %d obs, %s → %s",
                  nrow(out), min(out$date), max(out$date)))
  out
}
```
  **Note (karpathy — surface confusion):** RBA occasionally renames I2 columns. Step 1's fixture inspection must confirm the exact A$ all-items monthly column name; adjust the `str_detect` if the heuristic misfires. Do not silently pick the wrong column.
- [ ] **Step 5: Run test → PASS.**
- [ ] **Step 6: Fetch live** `cd pipeline && Rscript -e 'source("experimental/fetch/fetch_rba_commodity.R"); fetch_rba_commodity()'` → confirm coverage line.
- [ ] **Step 7: Commit** `git add pipeline/experimental/fetch/fetch_rba_commodity.R pipeline/experimental/tests && git commit -m "research(fetch): RBA commodity price index"`

#### Task 1A.2: FRED AUD/USD + oil → `aud_usd`, `oil_brent`

**Files:** Create `pipeline/experimental/fetch/fetch_fred_extra.R` (mirror the existing `03b_fetch_fred_data.R` request pattern — reuse its User-Agent/HTTP-1.1 handling that the git log shows was needed on the runner).

- [ ] **Step 1: Read** `03b_fetch_fred_data.R` to copy its exact fetch helper (User-Agent, `httr::GET`, timeout). Do not reinvent it.
- [ ] **Step 2: Implement** two calls using that helper: `DEXUSAL` (US$/A$, daily → month-average) and `DCOILBRENTEU` (daily → month-average). Write `aud_usd.csv`, `oil_brent.csv`.
```r
# fetch_fred_extra.R  (pseudostructure — fill the helper from 03b)
source("03b_fetch_fred_data.R")   # reuse fetch_fred_series(series_id) if exported
monthly_avg <- function(df) df |>
  dplyr::mutate(date = lubridate::floor_date(date, "month")) |>
  dplyr::group_by(date) |> dplyr::summarise(value = mean(value, na.rm = TRUE), .groups = "drop")
fetch_fred_extra <- function() {
  for (s in list(c("DEXUSAL","aud_usd"), c("DCOILBRENTEU","oil_brent"))) {
    out <- monthly_avg(fetch_fred_series(s[[1]]))
    readr::write_csv(out, file.path("experimental/data_raw", paste0(s[[2]], ".csv")))
    message(sprintf("%s: %d obs, %s → %s", s[[2]], nrow(out), min(out$date), max(out$date)))
  }
}
```
  **Note:** if `03b` does not expose a reusable function, copy its minimal request body into a local `fetch_fred_series()` here (sandbox) rather than editing `03b`.
- [ ] **Step 3: Verify** both CSVs exist with monthly dates to ~2026-05 and numeric values.
- [ ] **Step 4: Commit** `... && git commit -m "research(fetch): FRED AUD/USD + Brent oil"`

#### Task 1A.3: ABS inventories (5676.0) + arrivals (3401.0, SA) → `inventories`, `arrivals`

**Files:** Create `pipeline/experimental/fetch/fetch_abs_extra.R` (uses `readabs`, same as `03_data_ingestion.R`).

- [ ] **Step 1: Discover the exact series IDs (don't assume).**
  Run: `cd pipeline && Rscript -e 'library(readabs); print(search_abs_series("5676")[, c("series","series_id","unit")][1:40,])'` (and `"3401"`). Identify: inventories = **Inventories, chain volume, seasonally adjusted** (5676.0); arrivals = **Short-term Visitor Arrivals, seasonally adjusted** (3401.0). Record the two `series_id`s.
  **Karpathy note:** arrivals MUST be the **seasonally adjusted** series (user requirement — strong seasonality, education-driven services-export signal). Verify the chosen series title contains "Seasonally Adjusted".
- [ ] **Step 2: Implement** a thin wrapper over `read_abs_series(id)` that returns `date,value` and writes the two CSVs. Frequencies differ: inventories quarterly, arrivals monthly — keep native frequency (the panel assembler handles mixed frequency).
- [ ] **Step 3: Verify** inventories has quarterly dates, arrivals monthly to ~2026-03/04; both numeric; print coverage.
- [ ] **Step 4: Commit** `... && git commit -m "research(fetch): ABS inventories (5676) + short-term arrivals SA (3401)"`

### Sub-track 1B — NAB business survey scraper (conditions + capacity)

> Grounded by recon: headline **conditions** + **capacity utilisation** are clean selectable text in the monthly PDF "Survey Details" bullets; the **quarterly PDF Data Appendix** is a clean numeric table (5 months + 5 quarters). Backfill = chain quarterlies + monthly bullets from ~2017 on NAB hosting + Wayback tail. URLs are not templatable → discover links from listing pages.

#### Task 1B.1: Monthly-bullet parser (with fixtures)

**Files:** Create `pipeline/experimental/fetch/scrape_nab_survey.R`; fixtures from recon: download a known monthly PDF to `tests/fixtures/nab_monthly_mar2026.pdf`.

- [ ] **Step 1: Save fixture**
  `curl -sL 'https://news.nab.com.au/content/dam/nab-news/documents/economics/202603%20NAB%20Monthly%20Business%20Survey%20March.pdf' -o experimental/tests/fixtures/nab_monthly_mar2026.pdf`
- [ ] **Step 2: Failing test** (expected values from recon: conditions +6, capacity 83.1%):
```r
test_that("nab monthly parser reads conditions + capacity", {
  v <- parse_nab_monthly("tests/fixtures/nab_monthly_mar2026.pdf")
  expect_equal(v$conditions, 6)
  expect_equal(v$capacity, 83.1, tolerance = 0.05)
})
```
- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Implement** using `pdftools::pdf_text` + tolerant regex over the bullets:
```r
library(pdftools); library(stringr)
parse_nab_monthly <- function(path) {
  txt <- paste(pdf_text(path), collapse = "\n")
  cond <- str_match(txt, regex("conditions[^.\\n]*?([+-]?\\d+)\\s*(?:index )?points?", ignore_case = TRUE))[,2]
  cap  <- str_match(txt, regex("capacity utilisation[^.\\n]*?(\\d{2}\\.\\d)\\s*%?", ignore_case = TRUE))[,2]
  list(conditions = as.numeric(cond), capacity = as.numeric(cap))
}
```
  **Karpathy note:** wording varies month to month ("remained at", "rose to", "fell to"). The test fixture proves March; add 1–2 more fixtures (a "rose to"/"fell to" month) before trusting the regex for backfill.
- [ ] **Step 5: Run → PASS. Commit.**

#### Task 1B.2: Quarterly-appendix parser (structured backfill)

- [ ] **Step 1: Save fixture** `curl -sL 'https://business.nab.com.au/content/dam/nab-business/document/NAB-Quarterly-Business-Survey-Q1-2025.pdf' -o experimental/tests/fixtures/nab_quarterly_q1_2025.pdf`
- [ ] **Step 2: Failing test** — assert the appendix yields the monthly capacity/conditions rows (recon-verified e.g. 2025m3: capacity 82.9, conditions 4).
- [ ] **Step 3: Implement** `parse_nab_quarterly(path)` → long tibble `date,series,value` for conditions + capacity, parsing the "QuarterlyMonthly … " appendix block. Return the **monthly** columns (national).
- [ ] **Step 4: Run → PASS. Commit.**

#### Task 1B.3: Backfill assembly + coverage report

- [ ] **Step 1:** Build a link-discovery helper: GET the listing `https://business.nab.com.au/tag/business-survey`, extract monthly + quarterly release page URLs, resolve each PDF link (never template the filename).
- [ ] **Step 2:** Assemble `nab_conditions.csv` + `nab_capacity.csv` by merging: quarterly-appendix monthlies (priority, cleanest) ⊕ monthly-bullet values, dedup by date, sorted. Reach: ~2017→present on NAB hosting.
- [ ] **Step 3: Wayback tail** — for pre-2017 months, query `http://archive.org/wayback/available?url=<landing>` per month; parse where captures exist. **Explicitly log the earliest date reached and every gap** (karpathy: no silent truncation). Decide coverage sufficiency in Phase 2 (the DFM needs enough overlap with the estimation sample; document how far back we got).
- [ ] **Step 4: Verify** both CSVs: monotonic dates, plausible ranges (conditions ~[-40,30], capacity ~[70,86]); print first/last/n and gap list.
- [ ] **Step 5: Commit** `git commit -m "research(fetch): NAB conditions + capacity backfill + monthly parser"`

### Sub-track 1C — FCAI vehicle sales (raw scrape + ABS splice + self-SA)

> Grounded by recon: monthly total + YoY are clean body text in FCAI releases; pre-2018 SA history is free in ABS 9314.0 legacy XLSX; FCAI publishes raw only → self-SA the post-2018 raw with X-13.

#### Task 1C.1: ABS 9314 legacy SA history

- [ ] **Step 1:** Download the frozen ABS 9314.0 Table 1 XLSX (SA total) from `https://www.abs.gov.au/statistics/industry/tourism-and-transport/sales-new-motor-vehicles/latest-release` (downloads tab). Save fixture.
- [ ] **Step 2:** Parse the **Seasonally Adjusted, Total vehicles** series → `date,value` (monthly, ~1994→Dec 2017). Verify last obs is Dec-2017.

#### Task 1C.2: FCAI monthly raw parser (with fixture)

- [ ] **Step 1: Save fixture** — a known release page, e.g. `curl -sL 'https://www.fcai.com.au/electrified-vehicle-sales-hit-46-per-cent-in-may/' -o experimental/tests/fixtures/fcai_may2026.html`
- [ ] **Step 2: Failing test** — assert parser extracts the month total (recon example: 100,206) and YoY (−4.8%) from body text.
- [ ] **Step 3: Implement** `parse_fcai_release(html)` with a tolerant regex over the prose:
```r
library(rvest); library(stringr)
parse_fcai_release <- function(path) {
  txt <- html_text2(read_html(path))
  m <- str_match(txt, regex("([\\d,]{4,})\\s+new vehicles?.*?([\\d.]+)\\s*per cent", ignore_case = TRUE))
  list(units = as.numeric(str_remove_all(m[,2], ",")), yoy_pct = as.numeric(m[,3]))
}
```
  **Karpathy note:** wording varies ("purchased X new vehicles" vs "X vehicles were delivered"); add a second fixture month and keep the regex tolerant. Poll the listing for the date→release mapping, never construct the slug.
- [ ] **Step 4: Run → PASS. Commit.**

#### Task 1C.3: Backfill, splice, self-SA → `motor_vehicles.csv`

- [ ] **Step 1:** Walk the FCAI listing pagination (`?sf_paged=1..~51`), parse each release's raw monthly total → raw series 2018→present. Log earliest reached + gaps.
- [ ] **Step 2: Splice** ABS-SA (pre-2018) + FCAI-raw (2018→present). Because pre-2018 is SA and post is raw, **seasonally adjust the post-2018 raw** with `seasonal::seas()` (X-13), then level-align the two segments at the 2017/2018 boundary (ratio-splice). Output one SA monthly `motor_vehicles.csv`.
- [ ] **Step 3: Verify** continuity across the splice (no step discontinuity > a few %), monotonic dates, coverage to latest month.
- [ ] **Step 4: Commit** `git commit -m "research(fetch): FCAI vehicle sales (ABS-SA splice + self-SA raw)"`

---

## Phase 2 — Expanded panel + metadata assembly (sandbox)

### Task 2.1: Build the expanded component metadata

**Files:** Create `pipeline/experimental/seed/component_metadata_expanded.rds` (built from the production seed + new rows). **Does not overwrite `seed/component_metadata.rds`.**

- [ ] **Step 1: Implement** a build script that reads the production seed, appends one `$indicators` row per new series with the now-documented trans codes, and saves to the sandbox path:
```r
md <- readRDS("seed/component_metadata.rds")
new <- tibble::tribble(
  ~indicator_id,      ~indicator_name,              ~component_id, ~frequency,  ~typical_lag_days, ~abs_series_id, ~trans_code, ~trans_rationale,
  "commodity_prices", "RBA Commodity Price Index",  "X_ext",       "monthly",   21,   NA, 1L, "trending index; MoM % stationary",
  "aud_usd",          "AUD/USD",                    "X_ext",       "monthly",    1,   NA, 2L, "rate; first diff stationary",
  "oil_brent",        "Brent oil (A$/USD proxy)",   "X_ext",       "monthly",    5,   NA, 1L, "trending price; MoM % stationary",
  "inventories",      "Business inventories CVM SA", "I_inv",       "quarterly", 65,   NA, 1L, "level; QoQ % stationary (confirm ADF)",
  "arrivals",         "Short-term arrivals SA",     "X_ext",       "monthly",   35,   NA, 1L, "trending count; MoM % stationary",
  "nab_conditions",   "NAB business conditions",    "B_bus",       "monthly",   10,   NA, 2L, "net balance; first diff (matches bus_conf)",
  "nab_capacity",     "NAB capacity utilisation",   "B_bus",       "monthly",   10,   NA, 2L, "% level; first diff",
  "motor_vehicles",   "New vehicle sales SA",       "C_hh",        "monthly",    5,   NA, 1L, "trending count; MoM % stationary"
)
md$indicators <- dplyr::bind_rows(md$indicators, new)
saveRDS(md, "experimental/seed/component_metadata_expanded.rds")
```
  **Karpathy note:** `component_id` values must match existing groups in `md$components`; Step 2 verifies. `abs_series_id` stays `NA` for all new rows (they're injected as columns directly, like the existing FRED/NAB series), so `05`'s ingestion loop skips them and reads only their `trans_code`/`frequency`.
- [ ] **Step 2: Verify** all 8 new `component_id`s exist in `md$components$component_id`; every new row has a non-NA `trans_code` and `frequency`. Fix mismatches.
- [ ] **Step 3: Commit.**

### Task 2.2: Build the expanded master panel

**Files:** Create `pipeline/experimental/data/master_expanded.rds`.

- [ ] **Step 1: Implement** — start from the base master `$wide`, left-join each `data_raw/*.csv` as a new column keyed on `date`, preserving the existing object structure (`$wide`, plus whatever `$long`/metadata fields the base carries — inspect first, replicate exactly). Monthly series align on month; quarterly (inventories) align on quarter-start months with `NA` elsewhere (the Kalman filter handles the ragged/mixed frequency, as it already does for `gdp_quarterly` and services trade).
- [ ] **Step 2: Inject the realised 2026 Q1 GDP actual** into the expanded master's `gdp_quarterly` (level 695,945 at 2026-03-01) so Phase 3's held-out test can score it. Sandbox only.
- [ ] **Step 3: Data-quality checks** — print per-column coverage (first/last/n_missing); assert no new column is entirely NA over 2015–2025; assert no look-ahead (each series' last date ≤ its plausible release lag from `typical_lag_days`). Log series whose history is too short to contribute (e.g. if NAB backfill only reached 2017, note it).
- [ ] **Step 4: Commit.**

---

## Phase 3 — Experimental backtest + factor sweep (sandbox runner)

### Task 3.1: Write the experimental sweep runner

**Files:** Create `pipeline/experimental/run_expanded_sweep.R`.

- [ ] **Step 1: Implement** — source the production harness, override the two globals in memory, run r=2/3/4 on the expanded panel into a sandbox output dir:
```r
setwd("pipeline")                          # harness expects pipeline/ as cwd
source("09_backtest_model.R")              # sets component_metadata from the production seed
component_metadata <<- readRDS("experimental/seed/component_metadata_expanded.rds")  # OVERRIDE
master <- readRDS("experimental/data/master_expanded.rds")

out_root <- "experimental/backtest_output"; dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
for (r in c(2, 3, 4)) {
  config  <- configure_dfm(n_factors = r, var_order = 1)
  results <- run_backtest(master, config, "2020-01-01", "2026-03-31", "quarterly", verbose = TRUE)
  save_backtest_results(results, file.path(out_root, sprintf("r%d", r)))
  generate_backtest_report(results, file.path(out_root, sprintf("r%d/report.md", r)))
}
```
  **Karpathy note (verify the override took effect):** the estimation prints "Per-series trans codes:" (`05:257`). Confirm that line lists all 21 indicators including `commodity_prices`/`nab_conditions` on the first r=2 run. If it still shows 13, the global override didn't bind — stop and fix (do not proceed on a silently-baseline run).
- [ ] **Step 2: Run** `cd pipeline && Rscript experimental/run_expanded_sweep.R` (note: r=4 may now be feasible with ~21 indicators — the rank-deficiency that killed it at 13 may lift; if it still fails, log the error and keep r=2/3).
- [ ] **Step 3: Verify** `experimental/backtest_output/r3/report.md` exists with metrics; the trans-code line showed 21 series. **Commit** the runner (not the gitignored outputs).

### Task 3.2: Panel-ladder comparison (block-level value, not per-variable)

**Files:** Create `pipeline/experimental/panel_ladder.R`.

**Rationale:** per-variable drop-one is expensive and only block-level cost decisions matter. Compare four panels instead: `baseline` (13), `full` (13+8), `free_only` (13 + commodity/AUD/oil/inventories/arrivals), `free_no_oil` (13 + the 4 free minus oil). `full vs free_only` = is the high-maintenance scraped block (NAB×2+FCAI) worth building; `free_only vs free_no_oil` = does oil help.

- [ ] **Step 1: Implement** a helper `bt_subset(master, keep_cols, r)` that runs `run_backtest` on `master` restricted to `gdp_quarterly` + `keep_cols` and returns post-COVID QoQ RMSE + hit rate + the 2026 Q1 forecast.
- [ ] **Step 2: Compute compute-cheaply** — run all four panels at **r=2 first** (~12 min each) to rank, then re-confirm the chosen panel(s) at **r=3** (~145 min each). Do NOT run the full ladder at r=3.
- [ ] **Step 3: Write** `experimental/backtest_output/panel_ladder.csv` with columns `panel, n_indicators, r, qoq_rmse, hit_rate, q1_2026_qoq`.
- [ ] **Step 4: Verify** all four panels present at r=2 and the chosen panel at r=3. **Commit** the script.

### Task 3.3: Held-out 2026 Q1 scoring

- [ ] **Step 1: Implement** — extract each panel's 2026 Q1 forecast from `results$backtest_results` (baseline, free-only, full, winning-r), compare to realised **+0.30% / 695,945**, write `experimental/backtest_output/q1_2026_holdout.csv` (`panel, qoq_pred, level_pred, qoq_err, level_err`).
- [ ] **Step 2: Verify** the baseline row reproduces ≈ +0.77% (sanity vs the shipped vintage); expanded rows are present. **Commit.**

---

## Phase 4 — Decision document (the deliverable)

### Task 4.1: Write the recommendation

**Files:** Create `docs/backtest-recommendation-2026-06-<dd>.md` (supersedes the 2026-04-17 doc; does not delete it).

- [ ] **Step 1: Assemble** the panel-ladder table (baseline / free_no_oil / free_only / full) and the Q1 held-out table. For each **block** (free, oil, scraped), state KEEP/DROP against the three acceptance gates. State the winning factor count (r=2/3/4) with evidence. State the headline: did the expanded panel pull Q1 toward +0.30%, and by how much?
- [ ] **Step 2: Write the go/no-go** for production integration: the exact list of variables that survived, the factor count to adopt, and any that failed (recorded, not shipped). If nothing beats baseline, say so plainly — that is a valid, valuable result (n=1 miss may not be fixable by these variables).
- [ ] **Step 3: Commit** `git add docs/backtest-recommendation-2026-06-*.md && git commit -m "research: panel-expansion backtest recommendation"`
- [ ] **Step 4: Update memory** — record the decision outcome in `model_upgrade_plan.md` (survived variables, factor count, Q1 held-out result).

---

## Phase 5 — Production integration (DEFERRED — not executed by this plan)

**Gated on Phase 4's go decision. A separate plan will be written then.** For visibility, that follow-up plan would touch (and only then):
- `pipeline/seed/component_metadata.rds` — add the surviving indicator rows (via a script like `update_trans_codes.R`).
- `pipeline/03b_fetch_fred_data.R` / a new `03d_*` — promote the surviving fetchers into the production ingestion chain; merge new columns in `03c` before `master_dataset_complete.rds` is saved.
- NAB conditions/capacity + FCAI: extend `pipeline/nab_business_confidence_raw.csv` schema (or add new raw CSVs) and update the **user-owned scheduled tasks** (`docs/nab-update-task.md` + a new FCAI task) for monthly updates.
- `pipeline/05_estimate_model.R` — only if the factor count changes from r=3.
- `pipeline/04_emit_json.R` — surface any new indicator on the site; **and** the queued empirical-CI work (replace the hardcoded ±0.7%/±1.4% bands with backtest-RMSE-derived bands) as a related follow-up.
- Re-run the full pipeline; confirm the live nowcast and the site build.

---

## Self-review notes

- **Spec coverage:** every candidate in `docs/candidate-variables-2026-06-03.md` (commodity, AUD/USD, oil, inventories, arrivals-SA, NAB conditions, NAB capacity, motor vehicles) has an acquisition task (Phase 1) + metadata row (2.1) + a place in the panel ladder (3.2, by block). Westpac-MI = correctly excluded. Cross-cutting items: services-trade staleness = no action (no source — recorded); factor re-sweep = Task 3.1; validation gate = Phase 4.
- **No production touch before Phase 5:** all writes are under `pipeline/experimental/` or `.cache/`. Phase 0 runs existing code read-only (cache outputs only).
- **Transform codes** consistent with `05:243` semantics (1/2/7) across 2.1.
- **Known soft spots flagged inline (not hidden):** RBA column rename risk (1A.1), NAB/FCAI wording variance needing extra fixtures (1B/1C), backfill depth uncertainty with explicit gap logging (1B.3/1C.3), r=4 feasibility unknown (3.1), global-override verification (3.1).

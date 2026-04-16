# Nowcast pipeline

R pipeline that produces the JSON artifacts consumed by the website at [nowcast.wlsn.me](https://nowcast.wlsn.me).

## Run locally

From the repo root:

```bash
Rscript -e 'setwd("pipeline"); source("run_complete_nowcast.R")'
```

Or from inside `pipeline/`:

```bash
Rscript run_complete_nowcast.R
```

Outputs go to `../data/` (the repo-level `data/` directory consumed by Next.js).

## Dependencies

Pinned via `renv` (Task 13). Run `renv::restore()` once to install.

## Cache

Raw ABS/FRED data is cached under `.cache/` (gitignored). Safe to delete — will be refetched on next run.

## Entry point

`run_complete_nowcast.R` is the canonical entry point. It orchestrates:

1. Data fetch (ABS via `readabs`, FRED via CSV, NAB from `nab_business_confidence_raw.csv`)
2. Master dataset assembly
3. Vintage accuracy check (compares prior nowcasts against newly-released actuals)
4. DFM estimation (3-factor EM algorithm)
5. Nowcast generation + vintage snapshot save
6. JSON emission for the website (added in Task 14)

## Files

- `run_complete_nowcast.R` — top-level orchestrator
- `03_data_ingestion.R` — ABS fetcher via `readabs`
- `03b_fetch_fred_data.R` — FRED fetcher for OECD Consumer Confidence
- `03c_nab_business_confidence.R` — NAB CSV reader + freshness check
- `04_release_calendar.R` — ABS release-schedule metadata
- `05_estimate_model.R` — DFM estimation via the `nowcasting` package
- `06_generate_nowcast.R` — Kalman filter → nowcast
- `08_vintage_tracking.R` — vintage snapshot persistence + accuracy log
- `seed/component_metadata.rds` — indicator/component definitions (checked into the repo)
- `nab_business_confidence_raw.csv` — monthly NAB index values, updated by James's external Claude scheduled task

## Legacy code removed during migration

`install_nowcasting.R`, `run_backtest.R`, `run_nowcast.R`, `01_setup_nowcast.R`, the `archive/` directory, and assorted `test_*.R` / `fix_*.R` / `find_*.R` session scripts were dropped when this pipeline was migrated from `james-mess/code/project_nowcast/`. Their full history remains in the `james-mess` repository if ever needed.

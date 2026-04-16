# nowcasting

Australian GDP nowcast website at **[nowcast.wlsn.me](https://nowcast.wlsn.me)**.

A weekly-updated single-page dashboard showing a Dynamic Factor Model nowcast of Australian GDP, the underlying high-frequency indicators, and the model's track record.

## How it works

```
Mondays 07:00 AEST  →  GH Actions runs pipeline/run_complete_nowcast.R
                   →  Emits JSON to data/
                   →  Commits to main
                   →  Triggers deploy workflow
                   →  Next.js static build published to GitHub Pages
                   →  nowcast.wlsn.me serves the fresh nowcast
```

The R pipeline and the website communicate only via JSON files under `data/`. Site and pipeline can be developed, deployed, and moved independently.

## Local development

```bash
# Site (Next.js 15, Tailwind v4, Recharts)
npm install
npm run dev            # localhost:3000, hot-reload
npm run build          # static export to out/
npm run test           # unit tests (vitest)
npm run test:e2e       # Playwright smoke test

# Pipeline (R, pinned via renv)
cd pipeline
Rscript -e 'renv::restore()'   # one-off: install pinned packages
Rscript run_complete_nowcast.R # fetches data, estimates DFM, emits JSON
```

## Repository layout

```
nowcasting/
├── src/                          # Next.js app
│   ├── app/                      # Pages + layout
│   ├── components/               # Header, HeadlineCard, charts, etc.
│   └── lib/                      # data loader, types, format helpers, chart theme
├── data/                         # JSON artifacts (committed weekly by CI)
│   ├── latest.json
│   ├── gdp.json
│   ├── nowcasts.json             # vintage history
│   ├── indicators.json           # 12 monthly series
│   └── performance.json
├── pipeline/                     # R nowcast pipeline
│   ├── run_complete_nowcast.R    # entry point
│   ├── 03_data_ingestion.R       # ABS via readabs
│   ├── 03b_fetch_fred_data.R     # OECD Consumer Confidence via FRED
│   ├── 03c_nab_business_confidence.R  # NAB CSV reader
│   ├── 04_release_calendar.R     # ABS release schedule
│   ├── 05_estimate_model.R       # DFM via the `nowcasting` package
│   ├── 06_generate_nowcast.R     # Kalman filter → nowcast
│   ├── 08_vintage_tracking.R     # vintage snapshot persistence
│   ├── 04_emit_json.R            # JSON emission for the website
│   ├── seed/component_metadata.rds  # indicator/component definitions
│   ├── nab_business_confidence_raw.csv  # monthly NAB index, updated externally
│   ├── renv.lock                 # pinned R packages
│   └── tests/                    # R smoke tests
├── .github/workflows/
│   ├── nowcast-weekly.yml        # Sundays 21:00 UTC → runs the R pipeline
│   └── deploy.yml                # on push: build Next.js, deploy to Pages
└── docs/
    ├── superpowers/specs/        # design spec
    ├── superpowers/plans/        # implementation plan
    └── nab-update-task.md        # Claude scheduled-task prompt for NAB CSV updates
```

## Data sources

| Indicator group | Count | Source |
|---|---|---|
| Labour | 4 | ABS Labour Force Survey (employment, unemployment rate, participation, hours worked) |
| Consumer | 2 | ABS Retail Trade + OECD Consumer Confidence (via FRED) |
| Business | 2 | ABS Building Approvals + NAB Business Confidence |
| External | 4 | ABS International Trade (goods/services × exports/imports) |
| **Target** | **GDP** | **ABS National Accounts (5206.0) quarterly chain volume** |

NAB Business Confidence doesn't have a free API. It's published monthly and updated into `pipeline/nab_business_confidence_raw.csv` by a **user-owned Claude scheduled task** — see `docs/nab-update-task.md`.

## Model

Component-based Dynamic Factor Model (3 factors, VAR(1), EM estimation via Kalman filter), following the methodology of the NY Fed Staff Nowcast. Backtested 2020-2025 post-COVID, MAE 0.53% of GDP. See the site's Methodology panel for references.

## Phase-1 non-goals

This project deliberately does NOT include:
- A backend, database, or authentication
- Real-time data updates (weekly cron is enough)
- State-level nowcasts
- Comparison against RBA / Treasury / consensus
- Interactive model drill-downs beyond the indicator detail cards
- Mobile-first design optimisation

If any of these are needed, they're Phase 2.

## License

Personal research project. **Not an official forecast.**

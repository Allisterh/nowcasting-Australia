# Nowcast Website — Design Spec

**Date:** 2026-04-16
**Status:** Draft (pending user review)
**Author:** James Wilson + Claude
**Target URL:** `nowcast.wlsn.me`
**Target repo:** `adrasyn/nowcasting` (public)

---

## Summary

Turn the existing R-based Australian GDP nowcasting pipeline (currently at `C:\Users\wilso\Documents\R\james-mess\code\project_nowcast\`) into a polished public website that updates weekly with a fresh nowcast, shows each high-frequency indicator over time, and tracks the historical accuracy of the model.

The pipeline will run entirely in GitHub Actions on a weekly cron (Mondays 07:00 AEST), emit JSON data files committed back to the repo, and trigger a Next.js static site deploy to GitHub Pages. The model itself is unchanged — this project wraps the working pipeline in automation and a public interface, not a rebuild.

---

## Goals

- Public, shareable URL with a professional single-page dashboard.
- Weekly automated nowcast with zero manual intervention (except the monthly NAB Business Confidence update, handled separately via a user-owned Claude scheduled task).
- Visualise the headline nowcast, the 13 underlying indicators, the model's vintage evolution, and historical accuracy.
- Match the visual language of the sibling project `fuelimports.wlsn.me`, re-skinned with James's personal `jw_pal` colour scheme.
- Zero operating cost (GitHub Pages + GitHub Actions free tier on a public repo).

## Non-goals (Phase 1)

- No model changes — same 3-factor EM Dynamic Factor Model, same 13 indicators.
- No backend, no database, no auth, no CMS.
- No writeups, blog, or commentary — just the dashboard.
- No comparison vs RBA / Treasury / consensus forecasts.
- No mobile-first design tuning — responsive enough to work on phone, not optimised for it.
- No accessibility audit beyond semantic HTML and sensible contrast.
- No backtest regeneration in CI. Backtests are a one-off research artifact and run locally when the research question requires it.
- No NAB Business Confidence scraper. Handled via the external monthly Claude scheduled task.

---

## Architecture

One repo (`adrasyn/nowcasting`) containing both the R pipeline and the Next.js site, decoupled via JSON files committed to `public/data/`.

```
┌─────────────────────────────────────────────────────────────┐
│  Mondays 07:00 AEST (21:00 UTC Sunday)                      │
│                                                             │
│  GH Actions: nowcast-weekly.yml                             │
│    1. Checkout repo                                         │
│    2. setup-r + restore package cache (renv)                │
│    3. Run pipeline/run_complete_nowcast.R                   │
│    4. Pipeline emits JSON files to public/data/             │
│    5. Commit + push to main                                 │
│                           │                                 │
│                           ▼                                 │
│  GH Actions: deploy.yml (triggered by push to public/data/) │
│    1. npm run build (Next.js static export)                 │
│    2. Deploy out/ → gh-pages branch                         │
│                           │                                 │
│                           ▼                                 │
│                    nowcast.wlsn.me                          │
└─────────────────────────────────────────────────────────────┘
```

**Separation of concerns:** the R pipeline and the website communicate only via the JSON files. If the R run ever needs to move to a different runner (local, Fly, another CI), only `nowcast-weekly.yml` changes. The website, JSON contract, and deploy workflow are untouched.

**Why GitHub Actions (cloud) and not local scheduling:** after weighing the trade-offs, the user prioritises "hands-off, works while I'm travelling" over "familiar local setup". The one-time CI setup cost is bounded; ongoing automation benefit is permanent. The interactive-charts decision means R only emits JSON, not PNGs, which removes the font/render toolchain from the CI surface area.

---

## Repository Layout

```
nowcasting/
├── .github/workflows/
│   ├── nowcast-weekly.yml        # Cron: runs R pipeline, commits JSON
│   └── deploy.yml                # On push: builds Next.js, deploys
├── pipeline/                     # All R code
│   ├── R/                        # Helper functions (data utilities only)
│   ├── scripts/                  # Numbered runners (cleaned up from legacy)
│   │   ├── 01_fetch_data.R       # ABS + FRED + NAB CSV ingestion
│   │   ├── 02_estimate_model.R   # DFM estimation
│   │   ├── 03_generate_nowcast.R # Produce nowcast + confidence intervals
│   │   └── 04_emit_json.R        # NEW — write JSON files for the site
│   ├── run_complete_nowcast.R    # Canonical entry point (also used locally)
│   ├── nab_business_confidence_raw.csv  # Updated monthly via external task
│   ├── renv.lock                 # Pinned package versions
│   └── README.md                 # How to run locally + how CI runs it
├── public/data/                  # JSON consumed by the site (committed)
│   ├── latest.json
│   ├── gdp.json
│   ├── nowcasts.json
│   ├── indicators.json
│   └── performance.json
├── src/                          # Next.js 15 app
│   ├── app/
│   ├── components/
│   └── lib/
├── docs/
│   ├── superpowers/specs/        # This spec lives here
│   └── nab-update-task.md        # Prompt for the monthly Claude task
├── package.json
├── tailwind.config.ts
├── next.config.ts
└── README.md
```

**Notes:**
- `pipeline/` is fully self-contained — `cd pipeline && Rscript run_complete_nowcast.R` produces the same JSON locally as it does in CI.
- JSON files are committed to the repo. Next.js reads them at build time (static generation) — no runtime fetches.
- `renv.lock` pins R packages so the cloud run uses exactly the versions James used locally.
- Raw ABS/FRED cache (large, binary) is **gitignored** under `pipeline/.cache/` — regenerated each run.

---

## R Pipeline Changes

The existing 7-script pipeline (`code/project_nowcast/` in `james-mess`) is copied into `pipeline/` as the starting point. Changes:

### 1. New script: `04_emit_json.R`
Reads the existing `.rds` artifacts (`latest_nowcast.rds`, `master_dataset_complete.rds`, historical nowcast snapshots) and serialises to the five JSON files in `public/data/`. No model logic — pure format translation at the end of the pipeline.

### 2. Package pinning via `renv`
One-off setup: `renv::init()` → `renv::snapshot()` locally → commit `renv.lock`. CI calls `renv::restore()`. Makes the cloud run version-for-version identical to James's local R.

### 3. Cleanup pass
Consolidate duplicate / archived scripts from the legacy location. Preserve `run_complete_nowcast.R` as the user's familiar entry point — everything the user sources today must still source the same way, just with internals tidied. Drop `install_nowcasting.R`, `run_backtest.R`, and archived scripts that aren't called from the weekly path. The `nowcasting` package install must be handled via `renv` (it's a CRAN-archived package; `renv` supports this via recorded source).

### 4. Cache layer
`readabs` and `fredr` write to `pipeline/.cache/` (gitignored). In CI, `actions/cache` keyed on `week-number + year` so ABS/FRED aren't hit twice the same week if the run is re-triggered.

### 5. Failure telemetry
Workflow wraps the R run in a try/catch. On failure, opens a GitHub Issue titled `Weekly nowcast failed YYYY-MM-DD` with the last ~50 lines of log. Site continues to serve last-good JSON with a staleness banner.

### 6. No font rendering in CI
All visual styling happens in the browser. The pipeline never touches `ragg` / Liberation Serif / Aptos / Fira Code in the cloud. (The user may still generate PNGs locally for Twitter; those outputs are unrelated to the website.)

---

## External Dependency: NAB Business Confidence

NAB Business Confidence is the only indicator without a reliable free API. It's published on the 2nd Tuesday of each month for the prior month.

**This project does not scrape it.** Instead:

- **The contract:** `pipeline/nab_business_confidence_raw.csv` is the single source of truth. The R pipeline reads from it.
- **The updater:** a **user-owned Claude scheduled task** runs monthly (post the 2nd Tuesday), uses Chrome MCP to open the user's preferred source (e.g. `investing.com/economic-calendar/nab-business-confidence-217`), extracts the latest value, `git pull`s the repo, appends to the CSV, commits, pushes. This task is defined outside this project; its prompt is checked into the repo at `docs/nab-update-task.md` for reproducibility.
- **Degradation:** if the CSV is stale past the 2nd Tuesday + buffer, the pipeline still produces a nowcast using the last-known NAB value and auto-opens a GitHub Issue `Update NAB Business Confidence for <month>` as a fallback prompt.

Rationale: NAB data is one number per month. Fighting Cloudflare on an aggregator site or parsing NAB's PDF press releases has a worse reliability profile than a user-owned monthly task running in a real browser with real session cookies.

---

## JSON Data Contract

Five files in `public/data/`. Each is independently loadable; each chart component pulls only what it needs.

### `latest.json` — hero card / headline
```json
{
  "generated_at": "2026-04-20T21:00:00Z",
  "target_quarter": "2026 Q1",
  "data_through": "2026-04",
  "nowcast": {
    "gdp_chain_volume_millions": 694649,
    "qoq_growth_pct": 0.13,
    "yoy_growth_pct": 2.69,
    "ci_68_low": 690200, "ci_68_high": 699100,
    "ci_95_low": 685800, "ci_95_high": 703500
  },
  "latest_actual": {
    "quarter": "2025 Q4",
    "gdp_chain_volume_millions": 693772
  }
}
```

### `gdp.json` — long historical GDP actuals
```json
{
  "series": [
    { "quarter": "2010 Q1", "value": 345678, "qoq_pct": 0.4, "yoy_pct": 2.1 }
  ]
}
```

### `nowcasts.json` — every weekly nowcast ever made
Used for vintage evolution chart and performance tracking.
```json
{
  "vintages": [
    {
      "run_date": "2026-04-15",
      "target_quarter": "2026 Q1",
      "point": 694649,
      "ci_68_low": 690200, "ci_68_high": 699100,
      "ci_95_low": 685800, "ci_95_high": 703500,
      "data_through": "2026-04"
    }
  ]
}
```

### `indicators.json` — 13 monthly indicator series
```json
{
  "indicators": [
    {
      "id": "employment",
      "name": "Employment",
      "group": "Labour",
      "unit": "persons",
      "source": "ABS Labour Force Survey",
      "series": [
        { "date": "2020-01", "value": 12850000 }
      ]
    }
  ]
}
```
Groups: `Labour`, `Consumer`, `Business`, `External`.

### `performance.json` — accuracy stats for the scorecard
```json
{
  "mae_millions": 3481,
  "mae_pct": 0.53,
  "rmse_millions": 4200,
  "hit_rate_direction": 0.82,
  "errors": [
    {
      "target_quarter": "2025 Q3",
      "final_nowcast": 687900,
      "actual": 688317,
      "error_millions": -417,
      "error_pct": -0.06
    }
  ]
}
```

**Versioning:** adding fields is backward-compatible — the site reads defensively. Removing or renaming fields is a breaking change requiring coordinated updates to both R and JS.

---

## Site Structure

Single-page scroll on `nowcast.wlsn.me`. Top to bottom:

1. **Header** — title, one-sentence description, "last updated" stamp.
2. **HeadlineCard** (reads `latest.json`) — target quarter, QoQ %, YoY %, chain volume $M, sparkline of last 8 quarters with current point highlighted.
3. **GdpHistoryChart** (reads `gdp.json` + `latest.json`) — long-run quarterly GDP. Solid line for actuals, dashed continuation for the nowcast segment, confidence band behind the nowcast segment.
4. **VintageChart** (reads `nowcasts.json`) — "How the nowcast for each quarter evolved". X axis: run date. Y axis: nowcast value. One line per target quarter, coloured along the `jw_pal` ramp (older quarters teal, newer quarters green). Final actual plotted as a dotted horizontal line per quarter.
5. **IndicatorGrid** (reads `indicators.json`) — 13 mini sparklines in a 3- or 4-column grid, grouped by category (Labour / Consumer / Business / External). Hover or click reveals a larger expanded card with full series and metadata.
6. **PerformanceSection** (reads `performance.json`) — scorecard tiles (MAE, RMSE, hit rate) and a table of the last 8 quarters showing nowcast vs actual vs error with green/red directional cells.
7. **MethodologyPanel** — collapsible. Short prose on the DFM approach, indicator list, NY Fed lineage, links to methodology references and the GitHub repo.
8. **Footer** — "Not an official forecast", user signature (`Chart: 𝕏 @jameswilson`), source code link, methodology link.

### Design language

Inherits `fuelimports.wlsn.me` aesthetic, re-skinned with `jw_pal`.

- **Typography:** Instrument Serif (Google Fonts) for section headings, Inter (Google Fonts) for body + labels.
- **Primary colour:** `#034159` (dark teal) — data marks, text accents, heading underlines.
- **Accent colour:** `#0CF25D` (bright green) — used sparingly for "current" highlights (current nowcast point, "this week" marker).
- **Sequential scale:** the `jw_pal` ramp from `#034159` → `#0CF25D` — used for vintage colouring and any sequential encoding.
- **Chrome:** light-grey dashed gridlines, 10px axis labels in `#6b7280`, no shadows, no rounded corners, 1.5px borders, white background, dense information layout.
- **Chart library:** Recharts (same as fuel-shipments) for consistency and because it composes well with Tailwind.

Chart composition details (exact axes, tooltips, annotations) will be finalised interactively during implementation using the in-browser visual companion. The user has signalled they will iterate on chart design after seeing the first build; this is expected and planned for.

---

## Failure Modes

| Failure | Behaviour | User-facing signal |
|---|---|---|
| R pipeline fails in CI | Workflow opens GH Issue with log tail; no new JSON committed | Site serves last-good data; banner `"Last updated N days ago — currently stale"` appears if >10 days old |
| ABS/FRED API down on cron day | Pipeline retries once, then emits JSON marking indicators as `data_through: <last-good-month>` | Site shows the old `data_through` date; no crash |
| NAB CSV stale past 2nd Tue + buffer | Pipeline proceeds with last-known NAB value; auto-opens GH Issue | None on the public site (fallback is silent) |
| Deploy workflow fails | Previous deployment stays live; GH Issue opened | None on the public site |
| Data schema drift breaks site | Build fails loudly in `deploy.yml`; previous site stays live | None on the public site; GH Issue filed |

---

## Testing

Light, appropriate to the research/hobby nature of the project.

- **R smoke test** (runs on PR): executes `run_complete_nowcast.R` with a cached test-data fixture, asserts the five JSON files are written and contain expected top-level keys. Does not validate model output numerically.
- **Site e2e test** (Playwright, runs on PR): loads the deployed page, asserts `HeadlineCard` renders a non-empty GDP number and that the first chart renders an SVG. Catches "site is blank" regressions.
- **No DFM unit tests.** The model is research code, already backtested (MAE 0.53% post-COVID), not under active iteration.

---

## Deployment & DNS

- GitHub Pages with custom domain `nowcast.wlsn.me`.
- CNAME record at the user's DNS provider: `nowcast` → `adrasyn.github.io`.
- GitHub provisions TLS via Let's Encrypt automatically.
- Existing `fuelimports.wlsn.me` configuration is untouched. GitHub routes by `Host` header per-repo, so multiple subdomains sharing the same CNAME target is fine.

**Order-of-operations for domain setup:**
1. Add DNS CNAME.
2. Wait for propagation.
3. In `adrasyn/nowcasting` → Settings → Pages, set custom domain to `nowcast.wlsn.me`.
4. Enable "Enforce HTTPS" once the cert is issued.

---

## Phasing

### Phase 1 (this spec)
Deliver `nowcast.wlsn.me` updating weekly with all six site sections live. Scope:
- Repo scaffold + Next.js + Tailwind + Recharts skeleton.
- R pipeline copied to `pipeline/`, cleaned up, pinned via `renv`, extended with `04_emit_json.R`.
- `nowcast-weekly.yml` and `deploy.yml` workflows.
- Site built against placeholder JSON, then switched to real JSON once the pipeline runs green in CI.
- Chart design iterated using the visual companion.
- DNS + custom domain + TLS.
- NAB monthly-update prompt drafted and stored at `docs/nab-update-task.md`.
- Phase 1 is done when a Monday cron completes, commits fresh JSON, deploys, and the URL serves the new nowcast.

### Phase 2 (not in this spec)
Only after Phase 1 is live and stable through multiple cycles. Candidate follow-ups:
- Data-release-triggered updates (e.g. kick a partial run when ABS Labour Force drops).
- State-level nowcast if state-level high-frequency data becomes available.
- Interactive indicator drilldowns (dedicated per-indicator views).
- RSS / email alert on significant nowcast moves.
- A real NAB scraper if the monthly Claude task proves unreliable.

---

## Open Questions / Known Risks

1. **`nowcasting` R package install in CI.** The package is CRAN-archived. `renv::restore()` should handle this via its recorded source URL, but this needs to be verified on the first CI run. Mitigation if broken: use `remotes::install_github("nmecsys/nowcasting")` in a setup step, then let `renv` manage the rest.
2. **`readabs` system dependencies.** On Ubuntu runners, may need `libcurl4-openssl-dev`, `libssl-dev`, `libxml2-dev`. `r-lib/actions/setup-r-dependencies` detects most of these automatically.
3. **Historical vintage backfill.** `nowcasts.json` needs every weekly vintage ever produced. The user has outputs from Feb-Apr 2026 already; earlier dates must be synthesised from the existing `.rds` artifacts or accepted as starting from Feb 2026.
4. **First cron failure handling.** The first live cron is the riskiest. A manual-dispatch workflow trigger (`workflow_dispatch`) should be enabled so the pipeline can be run on demand during setup without waiting for the Monday schedule.

---

## Implementation Notes (forward-looking)

These are not requirements — they're starting assumptions for the implementation plan:
- Use Next.js 15 with `output: 'export'` for static generation, matching `aus-fuel-shipments`.
- Use Tailwind CSS v4 with `@theme` custom properties for the colour tokens, matching `aus-fuel-shipments/src/app/globals.css`.
- Put the `jw_pal` ramp as a Tailwind custom colour family so it's accessible throughout the app.
- Chart components should accept typed JSON shapes (`lib/types.ts`) and render defensively against missing fields.

The implementation plan will decompose this spec into ordered tasks in the next step.

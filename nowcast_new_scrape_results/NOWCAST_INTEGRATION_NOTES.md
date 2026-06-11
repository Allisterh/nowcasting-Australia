# Notes to self — integrating the from_james series into the nowcast model

_Written 2026-06-09. Read this BEFORE wiring these CSVs into the nowcasting model. The
scale/units and date-convention traps below will silently corrupt the model if missed._

## What these files are

Six Australian survey/sentiment series regenerated from investing.com (Fusion Media)
calendar PDF exports, by `extract_from_james.py`. They **supersede** the older sparse
Wayback-scraped versions. Source PDFs: `from_james/*.pdf`. Full background:
`docs/superpowers/specs/2026-06-09-from-james-pdf-ingestion-design.md` and the project
memory `from-james-pdf-ingestion.md`.

## Files to bring across (and why)

| file | what | bring? |
|---|---|---|
| `data/aig_pmi.csv`, `aig_pci.csv`, `aig_psi.csv` | AiG Manufacturing / Construction / Services | yes |
| `data/nab_cond.csv`, `nab_conf.csv` | NAB Business Conditions / Confidence | yes |
| `data/wmi_sent.csv` | Westpac–MI Consumer Sentiment (index level) | yes |
| `data/wmi_sent_pct.csv` | Westpac MoM % change (alt representation) | optional |
| `data/provenance_from_james.csv` | every value → source PDF + **release date** | yes — needed for vintage/lag |
| `data/*_review.csv` | flagged observations (advisory, not removed) | yes — eyeball before trusting flagged months |
| `extract_from_james.py`, `westpac_anchors.csv` | the regenerator + anchor table | yes — to refresh later |

## ⚠️ Scale / units — the #1 thing to get right

Each series is `date,value`. The **scales differ and are not what older code may assume**:

| series | scale | neutral | notes |
|---|---|---|---|
| `aig_pmi` / `aig_pci` / `aig_psi` | **−100 … +100 net balance** | **0** | NOT the old 0–100 diffusion. Pre-2023 history was converted from the old 50=neutral scale via `(old−50)×2`. Do **not** apply any "50 = neutral / >50 = expansion" logic. |
| `nab_cond` / `nab_conf` | net balance (~−40…+40) | 0 | native, no transform; can be negative |
| `wmi_sent` | **index level** (~65…125) | **100** | above 100 = optimism. Mostly reconstructed from MoM %. |
| `wmi_sent_pct` | MoM % change | 0 | different unit; only if you prefer a % representation |

If the model standardizes (z-scores) each series independently, the absolute scale matters
less — but anything that hard-codes a threshold (e.g. "PMI > 50") or mixes raw levels will
break. Treat AiG as a 0-centered balance now.

## ⚠️ Date convention — reference month, not release date

`date` is `YYYY-MM-01` = the survey's **reference month** (the month the data describes),
**not** when it was published. There is a publication lag:
- **AiG / NAB**: released ~1st business day of the *following* month (sometimes end of the
  same month). So the May value is knowable ~early June.
- **Westpac**: released *mid* its own reference month (e.g. the June reading lands ~mid-June).

For a **real-time / vintage-correct** nowcast you must align on availability, not reference
month. `provenance_from_james.csv` has the exact **release_date** per observation — use it to
build the as-of timeline. (Caveat: the stored value is investing.com's "Actual" = first print;
treat it as first-release, revisions not tracked.)

## Coverage, gaps, and confidence (feed these into weighting / start dates)

- **wmi_sent**: spans 1988-05 → 2026-06 but **2008+ is solid**; **1988–2007 is reconstructed
  from sparse anchors** (newspaper-sourced 2001–07 cluster + Nov-1990 low) with up to ~8.6 pts
  of between-anchor drift. **Jan-2008 is a 1-month hole**; nothing before 1988-05. Consider
  starting the sentiment series ~2008 for the model, or down-weighting the reconstructed era.
- **aig_psi (Services)**: **frozen at 2022-11** (AiG discontinued it). It will never update —
  don't let a live model expect new prints.
- **AiG methodology break (early 2023)**: the old→new splice is linear/approximate. Any
  transform that straddles it (YoY, long-window stats) carries model risk near the break.
  Breaks are flagged in `aig_*_review.csv` (`chain_break` at the break month is expected).
- **`*_review.csv`** lists `dup_disagree` (source relistings — check these specific months),
  `chain_break` (mostly methodology break / survey gaps / NAB ±2-3 revision noise). The flagged
  values ARE present in the main series; flags are advisory.

## ⚠️ Inconsistency with the OLD NAB files (do not mix blindly)

Only **nab_cond** and **nab_conf** were regenerated (now back to 1997). The other NAB
sub-series still come from the old Wayback scrape and only go back to ~2012:
`data/nab_trade.csv`, `nab_profit.csv`, `nab_emp.csv`, `nab_forward.csv`, `nab_stocks.csv`,
`nab_cu.csv`, and the wide `data/nab_monthly.csv`. **`nab_monthly.csv`'s cond/conf columns
are now stale/shorter than the new standalone files.** If the model uses NAB sub-series
together, either align start dates or backfill the sub-series separately before trusting a
joined NAB block. **On arrival, verify spans** (e.g. `python -c "import csv,glob;[print(f, sum(1 for _ in open(f))-1) for f in glob.glob('data/nab_*.csv')]"`).

## Still missing (not in this batch)

- **S&P / Judo Manufacturing & Services PMI** (`pmi_mfg`, `pmi_svcs`) — never sourced.
- The 6 NAB sub-series above remain on the old short scrape.
- Westpac pre-1988 and Jan-2008.

## Refresh / re-run

The pipeline is idempotent: re-export the PDFs into `from_james/` and run
`.venv\Scripts\python.exe extract_from_james.py` (Windows; pdfplumber + the project venv).
For ongoing nowcasting you'll eventually want a live fetcher rather than manual PDF exports.
To tighten Westpac's reconstructed era, add more rows to `westpac_anchors.csv`
(`date,level,source`) and re-run — drift shrinks between anchors.

## Suggested integration order

1. Verify file spans/units on arrival (don't trust this note's numbers after a move).
2. Decide reference-month vs release-date alignment (use provenance for real-time).
3. Pick a sentiment start date (recommend ~2008 unless the reconstructed era is explicitly wanted).
4. Decide AiG-break handling (probably fine post-standardization; avoid raw cross-break transforms).
5. Reconcile the NAB block (new cond/conf vs old sub-series start dates).
6. Wire into the model; sanity-check that no code assumes AiG 0–100 / 50=neutral.

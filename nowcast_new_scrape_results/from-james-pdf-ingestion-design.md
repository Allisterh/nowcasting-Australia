# from_james PDF ingestion — design

_Date: 2026-06-09_

## Purpose

James supplied six investing.com (Fusion Media) economic-calendar PDF exports in
`from_james/` containing the long-history data the Wayback scrape couldn't reach.
This project ingests those PDFs and **regenerates** the affected series as the new
source of record, replacing the sparse Wayback-scraped CSVs.

## Decisions (locked with user)

1. **AiG unified scale:** output on the new **−100/+100 net-balance** scale (0 = neutral).
   AiG now publishes natively on this scale, so there is no downstream-units surprise.
2. **Westpac:** the PDF reports **month-over-month % change**, not the index level.
   Reconstruct the index **level** series by chaining the % changes, re-anchored at
   every known level.
3. **Merge mode:** **PDFs are authoritative for all output values** — regenerate each
   series purely from the PDFs. The old scraped CSVs are **not** used as a source and
   **not** used for cross-validation (dropped at user's request).
   - **One scoped exception:** Westpac level reconstruction may use scraped levels — and
     any *additional* historical levels scraped for this purpose — purely as drift
     **anchors** (never copied into the output as values). See Transforms.

## Scope

Five series are regenerated from this batch. The remaining NAB sub-series
(trade, profit, emp, forward, stocks, cu) and S&P/Judo PMI are **not** in this drop and
are left untouched.

| PDF | → series | span in PDF | transform |
|---|---|---|---|
| AiG Manufacturing | `aig_pmi` | 2001 → 2026 | scale-splice to −100/+100 |
| AiG Construction | `aig_pci` | 2005 → 2026 | scale-splice to −100/+100 |
| AiG Services | `aig_psi` | 2003 → Dec 2022 (discontinued) | convert all to −100/+100 |
| NAB Business Conditions | `nab_cond` | 1997 → 2026 | none (already net balance) |
| NAB Business Confidence | `nab_conf` | 1997 → 2026 | none |
| Westpac Consumer Sentiment | `wmi_sent` | 1984 → 2026 (MoM %) | reconstruct levels |

## Source format

Each PDF has a history table with rows of the form:

```
Release date · (RefMonth) · Time · Actual · [Forecast] · Previous
Jun 03, 2026 (May) 00:00 -22.4 -27.5      <- Actual = -22.4
Apr 05, 2023 (Mar) 00:00 5.6 -4.0 -6.4    <- Actual = 5.6 (forecast 4.0, prev 6.4)
```

- **Actual** is always the first numeric token after the time — the value we want.
- Trailing numbers vary (0/2/3 of Forecast/Previous present).
- Westpac values carry a `%` suffix.
- A page-1 "Latest Release" summary line repeats the newest row but **has no time**.

## Architecture

One script `extract_from_james.py`, composed of small testable units:

- `pdf_text(path)` — extract text per page (suppress the FontBBox warnings these PDFs emit).
- `parse_rows(text)` — regex → raw row dicts. **Require a `HH:MM` time** to accept a row
  (drops the page-1 summary line). First numeric after time = Actual; handle optional `%`.
- `assign_ref_month(rows)` — per-file reference-month assignment (see below).
- `transform_aig(value, ref_month, break_date)` — old→new scale splice.
- `reconstruct_westpac_levels(pct_rows, anchors)` — chaining + re-anchor.
- `validate_series(series_id, rows)` — ref-month + Previous-chain checks (see Validation).
- `write_series(series_id, points)` — write `data/<series>.csv` ascending, `date=YYYY-MM-01`.
- `main()` — orchestrate, write backups, provenance, review files, and report.

## Reference-month assignment (the date-inconsistency problem)

Two row patterns: explicit `(May)` parens (ground truth) and ~80/file with no paren.
Release→reference lag differs by source: AiG/NAB publish the **prior** month
(release early-month → ref = month − 1; release end-of-month → ref = same month);
Westpac publishes the **current** month mid-month (offset 0).

**Approach — learn the rule per file.** From rows that *have* parens, compute each
`offset = releaseMonth − refMonth` and its relation to release-day, deriving the file's
rule (AiG/NAB: `day ≤ 15 → offset 1, else 0`; Westpac: `offset 0`). Apply that rule to
the no-paren rows. This is robust to **gaps** because it uses the release date alone, not
sequence position (a naive month-by-month decrement slides on missing months).
Year boundaries handled (`Feb 2024 (Dec)` → Dec 2023).

**Validate after assignment:** ref months should be unique and monotonic, and the
`Previous` column should chain to the next-older `Actual`. Any collision / gap /
chain-break → `data/<series>_review.csv`, not silently merged. Duplicate listings that
agree are de-duped; disagreements are flagged.

## Transforms

- **AiG scale splice.** Detect the single clean old→new transition per file
  (Manufacturing: last old `44.7` Nov-2022 → first new `−6.4` Feb-2023). Verify it is a
  single clean break (no interleaving of positive-old and negative-new) before applying.
  Convert old-era rows with **`new = (old − 50) × 2`** (50→0, 60→+20, 32.4→−35.2);
  new-era rows pass through unchanged. Services is entirely old-scale (ends Dec 2022) →
  all converted.
- **Westpac levels.** Backward chain `level[m−1] = level[m] / (1 + pct[m]/100)`,
  **re-anchored** at every known level. Anchors:
  - the 4 from the user's June-2026 report (Jun-24 83.6, Jun-25 92.6, May-26 83.0, Jun-26 80.6),
  - the 12 scraped 2012–2022 levels (anchors only, not output values),
  - **additional historical levels scraped best-effort** to anchor the long unanchored
    stretch (1984–2011), e.g. Wayback Westpac–MI reports, RBA statistical tables, or
    Westpac economics archives.

  Drift accrues only *within* a between-anchor segment; report max per-segment drift and
  **flag any era that remains unanchored** (likely the earliest years) as lower-confidence.
  Also write raw `data/wmi_sent_pct.csv`.
- **NAB.** Pass-through (already net balance).

## Outputs & safety

- Back up current CSVs to `data/_pre_james_backup/` before overwriting.
- `data/<series>.csv` — regenerated, ascending, `date,value`.
- `data/<series>_review.csv` — flagged anomalies.
- `data/wmi_sent_pct.csv` — raw Westpac MoM %.
- `data/provenance_from_james.csv` — each value → source PDF + release date.
- `FROM_JAMES_REPORT.md` — extraction stats, explicit-vs-inferred ref-month counts,
  anomalies, and Westpac drift / unanchored-era report.

## Validation (no scraped cross-check)

The old scraped CSVs are not used for validation. The checks that remain catch
**extraction bugs** and use only the PDF data itself:

1. **Ref-month uniqueness / monotonicity** — no two rows map to the same month; no
   impossible ordering. Structural, no tolerance. Violations → `*_review.csv`.
2. **`Previous`-column chain** — each row's `Previous` should match the next-older row's
   `Actual`. Advisory only, with a tolerance of **1.0** index points: smaller gaps are
   normal publisher revisions; a larger break signals a month-misalignment. Flagged → report.
3. **AiG clean-break check** — confirm the old→new scale transition is a single clean
   boundary (no interleaving of positive-old and negative-new) before splicing.
4. **Westpac anchors** — reconstructed levels must hit every anchor exactly; report max
   per-segment drift and any unanchored era.

## Testing

Test-first on the tricky units: `assign_ref_month` (explicit, inferred, gap, year-boundary,
duplicate cases drawn from the real PDFs), `transform_aig` (boundary + conversion math),
`reconstruct_westpac_levels` (hits anchors exactly, bounded drift).

## Out of scope

- NAB trade/profit/emp/forward/stocks/cu (not in this drop).
- S&P / Judo Manufacturing & Services PMI (James could not locate the data).
- The latent `fill_missing_data.write_series` provenance bug (separate issue).

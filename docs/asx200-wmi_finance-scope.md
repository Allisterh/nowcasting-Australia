# Scope: asx200 & wmi_finance — the RBA-selected series v2 is missing

<!-- POINT-IN-TIME -->
> **Point-in-time record — 2026-06-12. Not current state.**
> This document describes what was true when it was written. The model, panel and
> calibration have changed since; several numbers here are known to be superseded.
> For current state see `README.md`, and for the 2026-08 fidelity review and its
> corrections log see `docs/reviews/2026-08-01-v2-intention-and-bug-review.md`.


Follow-up to the Bucket-B NO-GO (`nowcasting_v2/BUCKET-B-RESULTS.md`). Both are in the
RBA's own published targeted-predictor list (`mai_tp_list.csv`) but **absent from the
RBA's redistributable data** (`mai_panel.csv` carries them as empty columns — licensed).
So neither gets a free-history shortcut; both must be sourced from scratch, and **history
is the make-or-break** (the `twi` lesson: a 2023+ series is untestable).

Branch: `bucket-b-panel-research`. No cutover / merge / push.

---

## asx200 — SOURCED + TESTED → NO-GO (on 2010+ data)

**Source.** ASX historical market statistics
(`asx.com.au/about/market-statistics/historical-market-statistics`) — end-of-month
S&P/ASX 200 price index. James downloaded the historic (2010-01 … 2026-05, 197 months).

**Cleaning.** The export's `Month` column is stored four different ways — full name
(`May`), `Mon-YY` (`Oct-10`), `Mon'YY` (`Apr'15`), and some with non-UTF8 garbage bytes
(`Jun-10���`); prices have thousands-commas (`"8,091.90"`) and stray bytes (`�4648.9`).
`clean_asx200_source()` (in `R/fetch/fetch_asx200.R`) parses robustly using the always-
clean `Year` column + the month NAME only (latin1 read, strip non-alpha for the month,
strip non-numeric for the value). Verified: 197/197 rows parsed, no gaps, spot-checks
correct. Raw preserved at `data_raw/asx200_source.csv`; clean at `data_raw/asx200.csv`.

**Live updates.** The page IS reachable from the host, but it carries multiple
tables/columns (All Ords, ASX 200, company counts). A naive parse grabs the WRONG one
(returned 8965 for May-2026 vs the correct 8731.7 ≈ All Ords). `fetch_asx200_latest()` is
left as a flagged PROTOTYPE and auto-append is DISABLED; ongoing monthly updates should
use the manual/Cowork channel (how the historic was sourced) until the correct column is
targeted with structural HTML parsing.

**Result. Stationary (ADF −11.94 / KPSS 0.034, clean), but Wald = 0.617 (p=0.89)** —
far below every selection threshold (α.05 7.82 / α.10 6.25 / α.20 4.64). So asx200 is
never selected into the MAI at any α, and (per the Bucket-B mechanism proof) the nowcast
is unchanged. **NO-GO on the 2010+ data we have.**

**Nuance — how did the RBA include it, given our 0.617?** Two parts.
1. *Data.* The RBA ran selection on licensed/internal feeds (Bloomberg/Refinitiv for the
   index). In their public replication package the series is blanked in BOTH the raw
   `mai_panel.csv` AND the transformed `mai_data_tfs.csv` (verified: 0 non-empty of 535) —
   only the column header and the result name in `mai_tp_list.csv` survive. So the public
   code literally cannot reproduce the asx200 selection; it's a "trust us, it was
   selected" entry.
2. *Sample, not method.* Identical Wald gate, very different sample. The RBA selects on
   ~1978-2022 (44 yr) with asx200 spliced via All Ords to cover 1987, the GFC and COVID —
   exactly the episodes where equities lead GDP. Our free series is 2010-2026 (S&P/ASX 200
   inception 2000; download starts 2010), a calm window with no equity-led downturn except
   COVID (which the selection regression dummies out). Same test → 0.617. The ASX 200's
   GDP-predictive power lives in the crashes, and our post-2010 slice is the one stretch
   that excludes them. Consistent with v2's broader trait (this model class shines in
   downturns). A pre-GFC All-Ords splice (~1992+) could be revisited, but its payoff lands
   outside our 2012+ scoring window, so it wouldn't improve the shipped nowcast.

---

## allords — long-history equity test (1982+) → still NO-GO, but informative

To test the "asx200 needs crash history" nuance, James supplied `allords_monthly.xlsx`
(All Ordinaries, monthly EOM, 1982-02..2026-06, 533 obs — the RBA spliced asx200 from
All Ords pre-2000, so this is the long equity series). Cleaned to `data_raw/allords.csv`.

- **Stationary** (ADF −17.1, KPSS 0.07).
- **Wald = 3.046** vs asx200's 0.617 — the 1987/GFC history ~5x'd it, confirming the
  signal lives in crashes — but STILL below every threshold (α.20 = 4.64). Not selected.
- **Not the GDP vintage.** Re-ran the Wald against the RBA's OWN real-time GDP series
  (`rba_paper/.../rt_dgdp_qtr.csv`, which differs from ours): allords 3.046 → **2.845**
  (basically unchanged; still fails). So the real-time-vs-revised GDP hypothesis is
  REFUTED. The RBA's asx200 ranked 15/30 in their (Wald-sorted) tp_list — comfortably
  selected — and we cannot reproduce that from any free equity series + GDP we can access.
  The gap is most likely their exact (withheld) asx200 series + balanced-panel transform.
- **Force-include test** (`backtest_v2(force_full_selection=)`, bypassing the gate):
  production-11 vs +allords —
  full 0.4535→0.4562 (+0.003), postCOVID 0.3422→0.3683 (+0.026), **OOS8 0.2409→0.1820
  (−0.059)**. So forced in, equities HURT full/postCOVID but HELP the last 8 quarters
  markedly — a recency-vs-robustness tradeoff the univariate gate can't see. Likely the
  2022 rate-driven (not GDP-driven) equity selloff poisons 2022-23. Caveat: OOS8 is 8
  points; the robust windows say worse. Verdict: still don't include, but not noise.

---

## wmi_finance — SCOPED, NOT BUILT (history blocker + collinearity)

**Source.** The Westpac-MI **Consumer Sentiment bulletin PDF** tabulates all five
sub-indices, including family finances — a richer document than the investing.com
headline PDF currently used for `wmi_sent`. Ongoing capture is the same parsing pattern
as the NAB/Westpac scrapers, on the same WAF-blocked channel (→ Cowork/residential IP).

**History — the blocker.** The full historical sub-index series is paywalled (Melbourne
Institute sells it ~$319/issue; that's exactly why it's empty in the RBA's public data).
The free path is harvesting the sub-index from historical bulletin PDFs, but the Westpac
IQ library only reliably reaches ~2017 (≈9 yr). Testable on post-COVID/OOS8, thin for
full-sample — better than `twi` (2023+), worse than `wmi_sent` (2008/1988).

**Collinearity caveat.** `wmi_finance` is a sub-component of the SAME survey as
`wmi_sent`, which v2 already has and already selects. The RBA kept both only because its
selection is univariate (each tested vs GDP alone, not marginal-over-others). So its
*marginal* value on top of `wmi_sent` is probably small.

**Wiring (when built).** `wmi_finance`, tcode `t1`/level (like `wmi_sent`), tgroup S.

**To proceed, needs from James:** the source — the latest bulletin PDF(s) + a back-
catalogue of monthly bulletins (2017+) to harvest the sub-index, or confirmation the
Cowork channel can fetch them.

---

## Recommendation

- **asx200:** done — NO-GO on available data. Keep the cleaned series + fetcher on the
  branch for the record; not worth a panel slot. Optional future: pre-GFC All-Ords
  splice, but low expected payoff for our 2012+ scoring window.
- **wmi_finance:** lowest priority. Thin free history AND likely collinear with the
  `wmi_sent` we already capture. Build only for completeness if desired; needs the
  bulletin-PDF source first.

This closes the "what's in the RBA's model that we're missing" thread: of the 7 missing
series, the genuinely-absent ones (asx200, house_prices, wmi_finance) are either
no-better-on-our-data (asx200), unobtainable free (house_prices), or thin+collinear
(wmi_finance). The 29-series panel stands.

---

## Appendix: v2 vs the RBA final model — full spec comparison

Engine is identical (v2 reuses the RBA `methods/*.R` verbatim; replication validated
22/22). All differences are config/product choices, not math:

**Identical:** DFM/EM estimation, q=1 dynamic factor, univariate-Wald selection (3 monthly
lags k=0:2), COVID IIS (2020Q1-2021Q4 @ α=0.01), U-MIDAS (k=3:5, jt-adjusted) and QA
(k=0:1) nowcast models.

| # | Dimension | RBA | v2 |
|---|---|---|---|
| 1 | **Selection α** | 0.10 | **0.05** headline / 0.20 stress (neither is 0.10) |
| 2 | **Headline nowcast model** | U-MIDAS (k=3:5) primary | QA (flat-weight, k=0:1) headline; U-MIDAS = stress |
| 3 | GDP target | real-time first-prints (→2022) | reconstructed/revised vintage (→2026) |
| 4 | Sample window | 1978–2022 | panel 1965–2026; backtest 2012+ |
| 5 | Transform application | balanced-panel block | per-series on observed span (ragged real-time panel) |
| 6 | Backtest selection | recursive exercise | full-sample selection fixed (pseudo-real-time); emit re-selects live |
| 7 | Data curation | uses AiG, rt, licensed series | excludes AiG (dead) + rt (→ real CPI-deflated MHSI); adds empirical CI bands |

**Most consequential: #1 (α=0.05 vs 0.10).** That single parameter is why v2's panel is
tighter than the RBA's and why several RBA-selected series — and all of Bucket-B's
near-misses (credit_personal/non_res_ba, Wald ~7) — don't make v2's cut. Everything else
is identical math, a deliberate precision-vs-robustness call (#2), or a data constraint.

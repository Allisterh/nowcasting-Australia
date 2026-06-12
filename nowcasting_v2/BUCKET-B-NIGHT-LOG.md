# Bucket-B overnight run — NIGHT LOG

Branch: `bucket-b-panel-research` (off `main`). Started 2026-06-11 (evening, James asleep).
Goal: source the easily-accessible RBA-panel predictors v2 doesn't yet use, test each
marginally (one-at-a-time) against the live 29-series headline config, plus a full-Bucket-B
"fuller-RBA-panel" variant. Keep only series that measurably help. NO push / NO cutover /
NO production edits — research only, awaits James's review.

## Decision rules (autonomous)
- Fail-loud sourcing: confirm every series ID against real downloaded data; drop (don't
  fabricate) any series that can't be sourced cleanly; note every drop here + in the report.
- Stationarity: each new series gets its RBA `tcode`/`tlog` (t2 + log = MoM log-growth),
  then an ADF+KPSS QA gate on the transformed series. Non-stationary → try documented
  alternative, else drop.
- Backtest: ONE combined panel (29 baseline + Bucket-B); marginal tests via `exclude_ids`
  (no per-variant rebuild). Held at the live headline config: model=qa, sel_alpha=0.05,
  dfm_q=1, qa_lag=0:1, exclude=c(AIG,"rt").
- Score 3 windows: post-COVID OOS8, OOS8 (last-8q held-out), full-sample. Keep-rule:
  improves post-COVID OOS8 without materially regressing full-sample (clean all-three
  sweeps starred). Report all numbers regardless; final cut is James's.

## Series sourcing — CONFIRMED IDs (against live data, 2026-06-11)
| id | source | series_id | tcode | tlog | tgroup | last | note |
|----|--------|-----------|-------|------|--------|------|------|
| debit_card | RBA C2 | CDCPTTVSA | t2 | T | F | 2026-04 | Value of purchases SA — mirrors credit_card (C1 CCCCSTPVSA) |
| credit_personal | RBA D2 | DLCACOPN | t2 | T | F | 2026-04 | "Credit; Other personal" (original). No SF-splice successor (personal not reclassified in 2019-07 break) |
| import | ABS 5368.0 | A2718603V | t2 | T | H | 2026-04 | "Debits, Total goods" SA — sibling of export A2718577A |
| hs_ba | ABS 8731.0 | A418431A | t2 | T | H | 2026-04 | Houses, Total Sectors, Number, SA |
| nh_ba | ABS 8731.0 | A421265R | t2 | T | H | 2026-04 | Dwellings excl. houses, Total Sectors, Number, SA |
| alt_add | ABS 8731.0 | A419852T | t2 | T | H | 2026-04 | Total Residential alterations & additions, value, SA |
| non_res_ba | ABS 8731.0 | A2413226R | t2 | T | H | 2026-04 | Total Non-residential, Total Work, Australia, value, SA |
| twi | RBA F11.1 | FXRTWI | t2 | T | F | daily | Trade-weighted Index (daily) → aggregated to monthly mean (covers 2010+; backtest is 2012+) |
| icp | RBA I2 | GRCPAIAD | t2 | T | F | monthly | "Commodity prices – A$" (headline RBA ICP). Future-dated rows (> today) dropped as guard |

## DROPPED (with reason)
- **res_ba** — = total dwelling units (A422070J) = existing `building_app`; collinear, no new info.
- **arrivals** — ABS 3401.0 SA series froze at 2020-03 (SA discontinued post-COVID); only
  Original continues. Original is strongly seasonal → t2+log not cleanly stationary across
  2012-2026. (Also a prior v1 reject.)
- **doe_ads** — low priority; redundant with anz_ads; JSA IVI host was firewalled before.

## Progress
- [x] Harness understood (backtest_v2 exclude_ids mechanism; production config from emit_v2_json.R)
- [x] Series IDs discovered + confirmed (9 keep, 3 drop)
- [x] Fetchers written + data pulled + validated (import sign-bug caught + fixed)
- [x] panel_info rows added
- [x] Stationarity QA gate — 8/9 stationary, alt_add borderline-KPSS (kept, ADF-strong)
- [x] Combined panel built (44 series)
- [x] Backtest sweep @ α=0.05 (baseline + 9 marginal + full) — ALL IDENTICAL to baseline
- [x] Root-caused the null result (Wald selection; see below)
- [x] Follow-up α=0.10/0.20 sweep on the two near-miss series
- [x] Report + charts + recommendation -> BUCKET-B-RESULTS.md

## FINAL VERDICT: NO-GO
None of the 9 Bucket-B series improves the v2 nowcast at the production config.
- α=0.05 (production): no Bucket-B series is Wald-selected -> zero effect (all variants identical).
- α=0.10/0.20: only credit_personal & non_res_ba enter; their marginal effect is within-noise
  (|ΔRMSE|≤0.005 on pc/oos8), and the looser-α model is far worse than production anyway
  (full 0.69-0.75 vs 0.45; OOS8 0.38 vs 0.24). non_res_ba helps full-sample most but does
  nothing for pc/oos8. Strict α=0.05 dominates.
- Confirms v1's "more series ≠ better" now holds for the v2 MAI framework too (was untested).
Keep the 29-series panel as-is. Full writeup + tables + charts in BUCKET-B-RESULTS.md.

## KEY RESULT (α=0.05 headline) — null, and WHY
All 11 variants (incl. full_bucketb with all 9 added) returned byte-identical RMSE
(full 0.4535 / postCOVID 0.3422 / OOS8 0.2409). NOT a bug: the candidate pool grows
correctly (31→32→40) but v2's **univariate Wald targeted-predictor selection** never
admits any Bucket-B series at α=0.05 (threshold χ²(3)=7.815). So none enter the MAI,
hence zero effect. Full Wald table: `cache/bucketb/wald.csv`.

Bucket-B Wald stats (pass @.05=7.815 / .10=6.251 / .20=4.642):
  credit_personal 7.64 (p=.054)  — NEAR MISS, passes @.10 & @.20
  non_res_ba      6.95           — passes @.10 & @.20
  import 3.77 · nh_ba 2.30 · icp 1.84 · alt_add 1.76 · debit_card 1.37 · hs_ba 0.17
                                 — fail even @.20 (genuinely unpredictive of QoQ GDP)
  twi             NA             — too few obs (2023+) to evaluate on full sample
=> Only credit_personal & non_res_ba ever get selected (at looser α). Follow-up sweep
   tests their ACTUAL accuracy impact @ α=0.10 and α=0.20 (where the stress model lives).

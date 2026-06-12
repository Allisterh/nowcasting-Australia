# Bucket-B panel-expansion experiment — RESULTS

- **Branch:** `bucket-b-panel-research` (off `main`). Run overnight 2026-06-11/12.
- **Question:** do any of the easily-accessible RBA-panel predictors v2 doesn't yet use earn a permanent slot in the v2 MAI + U-MIDAS panel?
- **Answer: NO-GO.** None of the 9 candidates improves the nowcast at the production config. Nothing was cut over / merged / pushed — research only.

---

## TL;DR

- At the **production headline config** (model=qa, **α=0.05**, dfm_q=1, qa_lag=0:1), **none of the 9 Bucket-B series is selected** by v2's univariate Wald targeted-predictor gate, so adding them — singly or all together — changes the nowcast by **exactly zero** (all 11 variants byte-identical: full 0.4535 / postCOVID 0.3422 / OOS8 0.2409).
- Only **credit_personal** (Wald 7.64) and **non_res_ba** (6.95) come close; they clear the bar only at looser α (0.10/0.20). The other 7 are genuinely unpredictive of QoQ GDP growth; **twi** can't even be evaluated (2023+ history only).
- When credit_personal / non_res_ba *are* let in (α=0.10/0.20), their marginal effect is **tiny and within-noise** (|ΔRMSE| ≤ 0.005 pp on post-COVID/OOS8) — and the looser-α model they live in is **far worse** than production (full RMSE 0.69–0.75 vs 0.45; OOS8 0.38 vs 0.24). So loosening selection to admit them is a net loss many times larger than their help.
- **Recommendation: keep the 29-series panel as-is.** This confirms the v1 "more series ≠ better" lesson now holds for the v2 MAI framework too (previously untested).

---

## Method (apples-to-apples)

One combined panel (29 baseline + 9 Bucket-B = 38 model series + AIG/rt excluded). Each variant differs ONLY in `exclude_ids`, so estimation math + config are held fixed. Marginal one-at-a-time: baseline = production 29-set; `marg_<id>` = production + that one series; full = production + all 9. Scored on post-COVID (2022+) / full / OOS8 (last 8q) RMSE vs latest-vintage GDP, 57 quarter-ends 2012–2026. Every new series given its RBA `tcode`/`tlog` (t2+log) and cleared an ADF+KPSS stationarity gate before backtesting.

---

## Why α=0.05 was null — the Wald selection

(chart: `bucketb_wald_ranking.png`)

v2 selects targeted predictors by a univariate Wald test of each series against QoQ GDP (3 monthly lags), keeping those above the χ²(df=3) critical value at α. Bucket-B Wald stats:

| series | Wald | p | pass α.05 (7.82) | pass α.10 (6.25) | pass α.20 (4.64) |
|---|---|---|:--:|:--:|:--:|
| **credit_personal** | 7.64 | 0.054 | ✗ (near) | ✓ | ✓ |
| **non_res_ba** | 6.95 | 0.074 | ✗ | ✓ | ✓ |
| import | 3.77 | 0.29 | ✗ | ✗ | ✗ |
| nh_ba | 2.30 | 0.51 | ✗ | ✗ | ✗ |
| icp | 1.84 | 0.61 | ✗ | ✗ | ✗ |
| alt_add | 1.76 | 0.62 | ✗ | ✗ | ✗ |
| debit_card | 1.37 | 0.71 | ✗ | ✗ | ✗ |
| hs_ba | 0.17 | 0.98 | ✗ | ✗ | ✗ |
| twi | n/a | n/a | ✗ | ✗ | ✗ |

> **twi:** too few observations (only 42 months, 2023+) to evaluate on the full sample — never selected at any α.

The production set's 11 selected series all clear α=0.05; no Bucket-B series does.

---

## α=0.10 / 0.20 follow-up — actual impact where credit_personal / non_res_ba ARE selected

(chart: `bucketb_alpha_delta.png`)

ΔRMSE vs that α's OWN baseline (negative = improvement):

| α | variant | post-COVID | full | OOS8 | Δ pc | Δ full | Δ oos |
|---|---|---|---|---|---|---|---|
| 0.10 | baseline (14 sel) | 0.391 | 0.687 | 0.379 | — | — | — |
| 0.10 | +credit_personal | 0.388 | 0.697 | 0.377 | −0.003 | +0.010 | −0.002 |
| 0.10 | +non_res_ba | 0.390 | 0.677 | 0.379 | −0.001 | −0.011 | +0.000 |
| 0.10 | +both | 0.387 | 0.687 | 0.377 | −0.004 | −0.000 | −0.002 |
| 0.20 | baseline (18 sel) | 0.375 | 0.745 | 0.379 | — | — | — |
| 0.20 | +credit_personal | 0.376 | 0.746 | 0.387 | +0.001 | +0.001 | +0.008 |
| 0.20 | +non_res_ba | 0.376 | 0.720 | 0.378 | +0.001 | −0.026 | −0.002 |
| 0.20 | +both | 0.373 | 0.722 | 0.376 | −0.003 | −0.024 | −0.003 |

**Production α=0.05 baseline for reference: full 0.4535 / postCOVID 0.3422 / OOS8 0.2409** — better on every window than ANY α=0.10/0.20 variant above. non_res_ba is the most defensible single addition (best full-sample help, −0.011 / −0.026) but only inside a looser-α model that is already much worse than production, and it does nothing for post-COVID/OOS8. The strict α=0.05 dominates.

---

## RBA cross-check — their own selection rejects all 9

This isn't just our adaptation of the method. The RBA published the list of series their MAI actually keeps (`rba_paper/content/Data/mai_tp_list.csv`) — **30 of the 53 panel series**, selected by the identical Wald gate at the RBA's α=0.10. **None of the 9 Bucket-B candidates is in it:**

> wmi_sent, nab_forward, scrigbag3, emp, aig_pmi, nab_conf, anz_sent, doe_ads, ud, credit_housing, wmi_finance, ft_emp, ue, credit, asx200, fcmygbag10, hours, fcmygbag5, house_prices, nab_trade, anz_ads, aig_pci, export, credit_card, pt_emp, credit_business, nab_stocks, nab_profit, nab_emp, rt

So the RBA — running the same test on their own 1978+ sample at an even *looser* α than ours (0.10 vs 0.05) — also excludes debit_card, credit_personal, import, the approvals disaggregates, twi and icp. Our NO-GO independently reproduces the RBA's own decision; we're not rejecting these by a config quirk.

(Nuance: on *our* shorter sample two were near-misses at α=0.10 — credit_personal 7.64, non_res_ba 6.95 — but the RBA's own selection didn't pick them either.)

## What the RBA's selected model has that v2 doesn't

Flipping the question: of the RBA's 30 selected series, v2 uses 23 and is missing 7.

**No data source in v2 (4):**

- `asx200` — S&P/ASX 200 equity prices. No free CSV (RBA stopped publishing; Yahoo/Stooq need keys / are unstable).
- `house_prices` — ABS RPPI discontinued 2021; CoreLogic paywalled.
- `wmi_finance` — Westpac-MI family-finances sub-index. We scrape `wmi_sent` (headline) but not this sub-index — *realistically gettable with extra parsing of the same release.*
- `doe_ads` — Dept of Employment / JSA Internet Vacancy Index (host firewalled). We use `anz_ads` as the functional job-ads stand-in (itself also in the RBA list).

**In v2's data but deliberately excluded from the model (3):**

- `aig_pmi`, `aig_pci` — AiG PMI/PCI. The RBA selected them, but v2 excludes the AiG block (AiG discontinued the surveys; PSI dead, PMI/PCI have a 2023 methodology break).
- `rt` — old ABS retail. The RBA selected it; v2 swaps in real MHSI (`household_spending`), a deliberate upgrade.

So the genuinely-absent, RBA-uses-it series are **asx200, house_prices, and wmi_finance** (plus doe_ads, ~covered by anz_ads). asx200/house_prices are the catalogued "hard bucket" (no free source); **wmi_finance is the one cleanly worth chasing** — a sub-index of a release we already scrape.

## Dropped during sourcing (with reason)

- **res_ba** — = total dwellings (A422070J) = existing `building_app`; collinear.
- **arrivals** — ABS SA series froze at 2020-03 (SA discontinued post-COVID); Original too seasonal to stationarise across 2012–2026.
- **doe_ads** — low priority; redundant with anz_ads; JSA host firewalled.

---

## If ever revisited

The only live candidates are **credit_personal** and **non_res_ba**. A genuinely long-history **twi** (needs the RBA historical exchange-rate XLS workbooks, out of scope tonight) was never testable here. But at the current production selection config none of this changes the answer: the 29-series panel is not improved.

**Artifacts:** `cache/bucketb/{summary.csv, summary_alpha.csv, wald.csv, stationarity_qa.csv}`; charts `bucketb_wald_ranking.png` + `bucketb_alpha_delta.png`. Trail: `BUCKET-B-NIGHT-LOG.md`.
